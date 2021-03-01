//
//  CloudKitModifyOperation.swift
//  
//
//  Created by Maurice Parker on 2/15/21.
//

import Foundation
import CloudKit

class CloudKitModifyOperation: BaseMainThreadOperation {

	var modifications = [CKRecordZone.ID: ([CKRecord], [CKRecord.ID])]()

	override func run() {
		guard let account = AccountManager.shared.cloudKitAccount,
			  let cloudKitManager = account.cloudKitManager else {
			operationDelegate?.operationDidComplete(self)
			return
		}
		
		var (documentRequests, documentRowRequests) = loadRequests()
		
		guard !documentRequests.isEmpty || !documentRowRequests.isEmpty else {
			operationDelegate?.operationDidComplete(self)
			return
		}
		
		// Document Processing
		
		for documentRequest in documentRequests {
			let id = documentRequest.id.documentUUID
			if let document = account.findDocument(documentUUID: id) {
				addSave(document)
			} else {
				addDeleteDocument(documentRequest)
				documentRowRequests.removeValue(forKey: id)
			}
		}
		
		// Row Processing
		
		for documentUUID in documentRowRequests.keys {
			guard let outline = account.findDocument(documentUUID: documentUUID)?.outline,
				  let documentRowRequest = documentRowRequests[documentUUID],
				  let zoneID = outline.zoneID else { continue }
			
			let outlineRecordID = CKRecord.ID(recordName: outline.id.description, zoneID: zoneID)

			outline.load()
			
			for rowRequest in documentRowRequest {
				if let row = outline.findRow(id: rowRequest.id) {
					addSave(zoneID: zoneID, outlineRecordID: outlineRecordID, row: row)
				} else {
					addDeleteRow(rowRequest)
				}
			}
			
			outline.suspend()
		}
		
		// Send the grouped changes
		
		let group = DispatchGroup()
		
		for zoneID in modifications.keys {
			group.enter()

			let cloudKitZone = cloudKitManager.findZone(zoneID: zoneID)
			let (saves, deletes) = modifications[zoneID]!

			cloudKitZone.modify(recordsToSave: saves, recordIDsToDelete: deletes) { result in
				if case .failure(let error) = result {
					self.error = error
				}
				group.leave()
			}
		}
		
		group.notify(queue: DispatchQueue.main) {
			if self.error == nil {
				self.deleteRequests()
			}
			self.operationDelegate?.operationDidComplete(self)
		}
	}
	
}

extension CloudKitModifyOperation {
	
	private func loadRequests() -> ([CloudKitActionRequest], [String: [CloudKitActionRequest]]) {
		var queuedRequests: Set<CloudKitActionRequest>? = nil
		if let fileData = try? Data(contentsOf: CloudKitActionRequest.actionRequestFile) {
			let decoder = PropertyListDecoder()
			if let decodedRequests = try? decoder.decode(Set<CloudKitActionRequest>.self, from: fileData) {
				queuedRequests = decodedRequests
			}
		}

		var documentRequests = [CloudKitActionRequest]()
		var documentRowRequests = [String: [CloudKitActionRequest]]()
		
		guard !(queuedRequests?.isEmpty ?? true) else { return (documentRequests, documentRowRequests) }
		
		for queuedRequest in queuedRequests! {
			switch queuedRequest.id {
			case .document:
				documentRequests.append(queuedRequest)
			case .row(_, let documentUUID, _):
				if var rowIDs = documentRowRequests[documentUUID] {
					rowIDs.append(queuedRequest)
					documentRowRequests[documentUUID] = rowIDs
				} else {
					var rowIDs = [CloudKitActionRequest]()
					rowIDs.append(queuedRequest)
					documentRowRequests[documentUUID] = rowIDs
				}
			default:
				fatalError()
			}
		}
		
		return (documentRequests, documentRowRequests)
	}
	
	private func deleteRequests() {
		try? FileManager.default.removeItem(at: CloudKitActionRequest.actionRequestFile)
	}
	
	private func addSave(_ document: Document) {
		guard let outline = document.outline, let zoneID = outline.zoneID else { return }
		
		let recordID = CKRecord.ID(recordName: outline.id.description, zoneID: zoneID)
		let record = CKRecord(recordType: CloudKitOutlineZone.CloudKitOutline.recordType, recordID: recordID)
		
		record[CloudKitOutlineZone.CloudKitOutline.Fields.title] = outline.title
		record[CloudKitOutlineZone.CloudKitOutline.Fields.ownerName] = outline.ownerName
		record[CloudKitOutlineZone.CloudKitOutline.Fields.ownerEmail] = outline.ownerEmail
		record[CloudKitOutlineZone.CloudKitOutline.Fields.ownerURL] = outline.ownerURL
		record[CloudKitOutlineZone.CloudKitOutline.Fields.tagNames] = outline.tags.map { $0.name }
		record[CloudKitOutlineZone.CloudKitOutline.Fields.rowOrder] = outline.rowOrder?.map { $0.rowUUID }

		addSave(zoneID, record)
	}
	
	private func addSave(zoneID: CKRecordZone.ID, outlineRecordID: CKRecord.ID, row: Row) {
		guard let textRow = row.textRow else { return }
		
		let recordID = CKRecord.ID(recordName: textRow.id.description, zoneID: zoneID)
		let record = CKRecord(recordType: CloudKitOutlineZone.CloudKitRow.recordType, recordID: recordID)
		
		record.parent = CKRecord.Reference(recordID: outlineRecordID, action: .none)
		record[CloudKitOutlineZone.CloudKitRow.Fields.outline] = CKRecord.Reference(recordID: outlineRecordID, action: .deleteSelf)
		record[CloudKitOutlineZone.CloudKitRow.Fields.subtype] = "text"
		record[CloudKitOutlineZone.CloudKitRow.Fields.topicData] = textRow.topicData
		record[CloudKitOutlineZone.CloudKitRow.Fields.noteData] = textRow.noteData
		record[CloudKitOutlineZone.CloudKitRow.Fields.isComplete] = textRow.isComplete ? "1" : "0"
		record[CloudKitOutlineZone.CloudKitRow.Fields.rowOrder] = textRow.rowOrder.map { $0.rowUUID }

		addSave(zoneID, record)
	}
	
	private func addSave(_ zoneID: CKRecordZone.ID, _ record: CKRecord) {
		if let (saves, deletes) = modifications[zoneID] {
			var mutableSaves = saves
			mutableSaves.append(record)
			modifications[zoneID] = (mutableSaves, deletes)
		} else {
			var saves = [CKRecord]()
			saves.append(record)
			let deletes = [CKRecord.ID]()
			modifications[zoneID] = (saves, deletes)
		}
	}
	
	private func addDeleteDocument(_ request: CloudKitActionRequest) {
		let zoneID = request.zoneID
		let recordID = CKRecord.ID(recordName: request.id.description, zoneID: zoneID)
		addDelete(zoneID, recordID)
	}
	
	private func addDeleteRow(_ request: CloudKitActionRequest) {
		let zoneID = request.zoneID
		let recordID = CKRecord.ID(recordName: request.id.description, zoneID: zoneID)
		addDelete(zoneID, recordID)
	}
	
	private func addDelete(_ zoneID: CKRecordZone.ID, _ recordID: CKRecord.ID) {
		if let (saves, deletes) = modifications[zoneID] {
			var mutableDeletes = deletes
			mutableDeletes.append(recordID)
			modifications[zoneID] = (saves, mutableDeletes)
		} else {
			let saves = [CKRecord]()
			var deletes = [CKRecord.ID]()
			deletes.append(recordID)
			modifications[zoneID] = (saves, deletes)
		}
	}
	
}
