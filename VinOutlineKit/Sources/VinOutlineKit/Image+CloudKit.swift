//
//  Image+CloudKit.swift
//  
//
//  Created by Maurice Parker on 3/15/23.
//

import Foundation
import CloudKit
import VinCloudKit

extension Image: VCKModel {
	
	struct CloudKitRecord {
		static let recordType = "Image"
		struct Fields {
			static let row = "row"
			static let isInNotes = "isInNotes"
			static let offset = "offset"
			static let asset = "asset"
		}
	}
	   
    public var cloudKitRecordID: CKRecord.ID {
        guard let zoneID = outline?.zoneID else { fatalError("Missing Outline in Image.") }
        return CKRecord.ID(recordName: id.description, zoneID: zoneID)
    }
    
    public func apply(_ record: CKRecord) -> Bool {
		if let metaData = cloudKitMetaData,
		   let recordChangeTag = CKRecord(metaData)?.recordChangeTag,
		   record.recordChangeTag == recordChangeTag {
			return false
		}

		cloudKitMetaData = record.metadata

		var updated = false
		
		let serverIsInNotes = record[Image.CloudKitRecord.Fields.isInNotes] as? Bool
		let mergedIsInNotes = merge(client: isInNotes, ancestor: ancestorIsInNotes, server: serverIsInNotes)!
		if mergedIsInNotes != isInNotes {
			updated = true
			isInNotes = mergedIsInNotes
		}
		
		let serverOffset = record[Image.CloudKitRecord.Fields.offset] as? Int
		let mergedOffset = merge(client: offset, ancestor: ancestorOffset, server: serverOffset)!
		if mergedOffset != offset {
			updated = true
			offset = mergedOffset
		}

		let mergedData: Data
		if let ckAsset = record[Image.CloudKitRecord.Fields.asset] as? CKAsset,
		   let fileURL = ckAsset.fileURL,
		   let fileData = try? Data(contentsOf: fileURL) {
			mergedData = merge(client: data, ancestor: ancestorData, server: fileData)!
		} else {
			mergedData = merge(client: data, ancestor: ancestorData, server: nil)!
		}
		if mergedData != data {
			updated = true
			data = mergedData
		}

        clearSyncData()
		
		return updated
	}
    
    public func apply(_ error: CKError) {
		guard let record = error.serverRecord else { return }
		cloudKitMetaData = record.metadata
		
		serverIsInNotes = record[Image.CloudKitRecord.Fields.isInNotes] as? Bool
		serverOffset = record[Image.CloudKitRecord.Fields.offset] as? Int
		
		if let ckAsset = record[Image.CloudKitRecord.Fields.asset] as? CKAsset,
		   let fileURL = ckAsset.fileURL,
		   let fileData = try? Data(contentsOf: fileURL) {
			serverData = merge(client: data, ancestor: ancestorData, server: fileData)
		} else {
			serverData = nil
		}

		isCloudKitMerging = true
	}
    
    public func buildRecord() async -> CKRecord {
		guard let zoneID = outline?.zoneID else {
			fatalError("There is not a Zone ID for this object.")
		}

		let record: CKRecord = {
			if let syncMetaData = cloudKitMetaData, let record = CKRecord(syncMetaData) {
				return record
			} else {
				let recordID = CKRecord.ID(recordName: id.description, zoneID: zoneID)
				return CKRecord(recordType: Image.CloudKitRecord.recordType, recordID: recordID)
			}
		}()
		
		let rowID = EntityID.row(id.accountID, id.documentUUID, id.rowUUID)
		let rowRecordID = CKRecord.ID(recordName: rowID.description, zoneID: zoneID)
		record.parent = CKRecord.Reference(recordID: rowRecordID, action: .none)
		record[Image.CloudKitRecord.Fields.row] = CKRecord.Reference(recordID: rowRecordID, action: .deleteSelf)
		
		let recordIsInNotes = merge(client: isInNotes, ancestor: ancestorIsInNotes, server: serverIsInNotes)
		record[Image.CloudKitRecord.Fields.isInNotes] = recordIsInNotes
		
		let recordOffset = merge(client: offset, ancestor: ancestorOffset, server: serverOffset)
		record[Image.CloudKitRecord.Fields.offset] = recordOffset

		let recordData = merge(client: data, ancestor: ancestorData, server: serverData)!
		let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent(id.imageUUID).appendingPathExtension("png")
		do {
			try recordData.write(to: imageURL)
			record[Image.CloudKitRecord.Fields.asset] = CKAsset(fileURL: imageURL)
			tempCloudKitDataURL = imageURL
		} catch {
			self.logger.error("Unable to write temp file for CloudKit asset data.")
		}

        return record
    }
    
    public func clearSyncData() {
		isCloudKitMerging = false
		
		ancestorIsInNotes = nil
		serverIsInNotes = nil
		
		ancestorOffset = nil
		serverOffset = nil
		
		ancestorData = nil
		serverData = nil

        if let tempCloudKitDataURL {
            try? FileManager.default.removeItem(at: tempCloudKitDataURL)
        }
    }
    
}
