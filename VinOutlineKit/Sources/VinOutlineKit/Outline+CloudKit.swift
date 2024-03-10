//
//  Outline+Cloudkit.swift
//  
//
//  Created by Maurice Parker on 3/15/23.
//

import Foundation
import CloudKit
import OrderedCollections
import VinCloudKit

extension Outline: VCKModel {
	
	struct CloudKitRecord {
		static let recordType = "Outline"
		struct Fields {
			static let title = "title"
			static let autoLinkingEnabled = "autoLinkingEnabled"
			static let checkSpellingWhileTyping = "checkSpellingWhileTyping"
			static let correctSpellingAutomatically = "correctSpellingAutomatically"
			static let ownerName = "ownerName"
			static let ownerEmail = "ownerEmail"
			static let ownerURL = "ownerURL"
			static let created = "created"
			static let updated = "updated"
			static let tagNames = "tagNames"
			static let rowOrder = "rowOrder"
			static let outlineLinks = "documentLinks"
			static let outlineBacklinks = "documentBacklinks"
			static let hasAltLinks = "hasAltLinks"
			static let disambiguator = "disambiguator"
		}
	}
    
    public var cloudKitRecordID: CKRecord.ID {
        return CKRecord.ID(recordName: id.description, zoneID: zoneID!)
    }
    
	public var cloudKitShareRecord: CKShare? {
		get {
			if let cloudKitShareRecordData {
				return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKShare.self, from: cloudKitShareRecordData)
			} else {
				return nil
			}
		}
		set {
			if let newValue {
				cloudKitShareRecordData = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: false)
			} else {
				cloudKitShareRecordData = nil
			}

		}
	}
	
	func beginCloudKitBatchRequest() {
		batchCloudKitRequests += 1
	}
	
	func requestCloudKitUpdateForSelf() {
		requestCloudKitUpdate(for: id)
	}
	
	func requestCloudKitUpdate(for entityID: EntityID) {
		Task {
			guard let cloudKitManager = await account?.cloudKitManager else { return }
			if batchCloudKitRequests > 0 {
				cloudKitRequestsIDs.insert(entityID)
			} else {
				guard let zoneID else { return }
				cloudKitManager.addRequest(CloudKitActionRequest(zoneID: zoneID, id: entityID))
			}
		}
	}

	func requestCloudKitUpdates(for entityIDs: [EntityID]) {
		for id in entityIDs {
			requestCloudKitUpdate(for: id)
		}
	}

	func endCloudKitBatchRequest() {
		Task {
			batchCloudKitRequests = batchCloudKitRequests - 1
			guard batchCloudKitRequests == 0, let cloudKitManager = await account?.cloudKitManager, let zoneID else { return }

			let requests = cloudKitRequestsIDs.map { CloudKitActionRequest(zoneID: zoneID, id: $0) }
			cloudKitManager.addRequests(Set(requests))
			
			cloudKitRequestsIDs = Set<EntityID>()
		}
	}

	func apply(_ update: CloudKitOutlineUpdate) async {
		var updatedRowIDs = Set<String>()
		
		if let record = update.saveOutlineRecord {
			let outlineUpdatedRows = await apply(record)
			updatedRowIDs.formUnion(outlineUpdatedRows)
		}
		
		if keyedRows == nil {
			keyedRows = [String: Row]()
		}
		
		for deleteRecordID in update.deleteRowRecordIDs {
			keyedRows?.removeValue(forKey: deleteRecordID.rowUUID)
		}
		
		for saveRecord in update.saveRowRecords {
			guard let entityID = EntityID(description: saveRecord.recordID.recordName) else { continue }

			var row: Row
			if let existingRow = keyedRows?[entityID.rowUUID] {
				row = existingRow
			} else {
				row = Row(outline: self, id: entityID.rowUUID)
			}

			if row.apply(saveRecord) {
				updatedRowIDs.insert(row.id)
			}
			
			keyedRows?[entityID.rowUUID] = row
		}
		
		for deleteRecordID in update.deleteImageRecordIDs {
			if let row = keyedRows?[deleteRecordID.rowUUID] {
				if row.findImage(id: deleteRecordID) != nil {
					row.deleteImage(id: deleteRecordID)
					updatedRowIDs.insert(deleteRecordID.rowUUID)
				}
			}
		}
		
		for saveRecord in update.saveImageRecords {
			guard let entityID = EntityID(description: saveRecord.recordID.recordName),
				  let row = keyedRows?[entityID.rowUUID] else { continue }
			
			var image: Image
			if let existingImage = row.findImage(id: entityID) {
				image = existingImage
			} else {
				image = Image(outline: self, id: entityID)
			}
			
			if image.apply(saveRecord) {
				updatedRowIDs.insert(row.id)
				row.saveImage(image)
			}
		}
		
		if !updatedRowIDs.isEmpty || !update.deleteRowRecordIDs.isEmpty  {
			rowsFile?.markAsDirty()
			outlineDidChangeBySync()
		}
		
		guard isBeingViewed else { return }

		var reloadRows = [Row]()
		
		func reloadVisitor(_ visited: Row) {
			reloadRows.append(visited)
			visited.rows.forEach { $0.visit(visitor: reloadVisitor) }
		}

		for updatedRowID in updatedRowIDs {
			if let updatedRow = keyedRows?[updatedRowID] {
				reloadRows.append(updatedRow)
				updatedRow.rows.forEach { $0.visit(visitor: reloadVisitor(_:)) }
			}
		}
		
		var changes = rebuildShadowTable()
		let reloadIndexes = reloadRows.compactMap { $0.shadowTableIndex }
		changes.append(OutlineElementChanges(section: adjustedRowsSection, reloads: Set(reloadIndexes)))
		
		if !changes.isEmpty {
			outlineElementsDidChange(changes)
		}
	}
	
	public func apply(_ record: CKRecord) async -> [String] {
		guard let account else { return [] }
		
		if let shareReference = record.share {
			cloudKitShareRecordName = shareReference.recordID.recordName
		} else {
			cloudKitShareRecordName = nil
		}

		if let metaData = cloudKitMetaData,
		   let recordChangeTag = CKRecord(metaData)?.recordChangeTag,
		   record.recordChangeTag == recordChangeTag {
			return []
		}

		cloudKitMetaData = record.metadata
		
        let serverTitle = record[Outline.CloudKitRecord.Fields.title] as? String
		if title != serverTitle {
			title = serverTitle
			if isBeingViewed {
				outlineElementsDidChange(OutlineElementChanges(section: .title, reloads: Set([0])))
			}
		}

        disambiguator = record[Outline.CloudKitRecord.Fields.disambiguator] as? Int

		created = record[Outline.CloudKitRecord.Fields.created] as? Date
        updated = record[Outline.CloudKitRecord.Fields.updated] as? Date
		autoLinkingEnabled = record[Outline.CloudKitRecord.Fields.autoLinkingEnabled] as? Bool
		checkSpellingWhileTyping = record[Outline.CloudKitRecord.Fields.checkSpellingWhileTyping] as? Bool
		correctSpellingAutomatically = record[Outline.CloudKitRecord.Fields.correctSpellingAutomatically] as? Bool

        ownerName = record[Outline.CloudKitRecord.Fields.ownerName] as? String
        ownerEmail = record[Outline.CloudKitRecord.Fields.ownerEmail] as? String
        ownerURL = record[Outline.CloudKitRecord.Fields.ownerURL] as? String

		let updatedRowIDs = applyRowOrder(record)
		await applyTags(record, account)
		applyOutlineLinks(record)
		applyOutlineBacklinks(record)
        
        let serverHasAltLinks = record[Outline.CloudKitRecord.Fields.hasAltLinks] as? Bool
        hasAltLinks = merge(client: hasAltLinks, ancestor: ancestorHasAltLinks, server: serverHasAltLinks)

        clearSyncData()
        
		return updatedRowIDs
	}
	
    public func apply(_ error: CKError) async {
        guard let record = error.serverRecord, let account else { return }
		cloudKitMetaData = record.metadata
		
        serverTitle = record[Outline.CloudKitRecord.Fields.title] as? String
        serverDisambiguator = record[Outline.CloudKitRecord.Fields.disambiguator] as? Int
        serverCreated = record[Outline.CloudKitRecord.Fields.created] as? Date
        serverUpdated = record[Outline.CloudKitRecord.Fields.updated] as? Date
		serverAutolinkingEnabled = record[Outline.CloudKitRecord.Fields.autoLinkingEnabled] as? Bool
        serverOwnerName = record[Outline.CloudKitRecord.Fields.ownerName] as? String
        serverOwnerEmail = record[Outline.CloudKitRecord.Fields.ownerEmail] as? String
        serverOwnerURL = record[Outline.CloudKitRecord.Fields.ownerURL] as? String

        if let errorRowOrder = record[Outline.CloudKitRecord.Fields.rowOrder] as? [String] {
            serverRowOrder = OrderedSet(errorRowOrder)
        } else {
            serverRowOrder = nil
        }

        let errorTagNames = record[Outline.CloudKitRecord.Fields.tagNames] as? [String] ?? [String]()
		var errorTags = [Tag]()
		for errorTagName in errorTagNames {
			errorTags.append(await account.createTag(name: errorTagName))
		}
        serverTagIDs = errorTags.map({ $0.id })
        
        let errorOutlineLinks = record[Outline.CloudKitRecord.Fields.outlineLinks] as? [String] ?? [String]()
        serverOutlineLinks = errorOutlineLinks.compactMap { EntityID(description: $0) }

        let errorOutlineBacklinks = record[Outline.CloudKitRecord.Fields.outlineBacklinks] as? [String] ?? [String]()
        serverOutlineBacklinks = errorOutlineBacklinks.compactMap { EntityID(description: $0) }
        
        hasAltLinks = record[Outline.CloudKitRecord.Fields.hasAltLinks] as? Bool

		isCloudKitMerging = true
	}
    
    public func buildRecord() async -> CKRecord {
        let record: CKRecord = {
            if let syncMetaData = cloudKitMetaData, let record = CKRecord(syncMetaData) {
                return record
            } else {
                return CKRecord(recordType: Outline.CloudKitRecord.recordType, recordID: cloudKitRecordID)
            }
        }()

        let recordTitle = merge(client: title, ancestor: ancestorTitle, server: serverTitle)
        record[Outline.CloudKitRecord.Fields.title] = recordTitle

        let recordDisambiguator = merge(client: disambiguator, ancestor: ancestorDisambiguator, server: serverDisambiguator)
        record[Outline.CloudKitRecord.Fields.disambiguator] = recordDisambiguator

        let recordCreated = merge(client: created, ancestor: ancestorCreated, server: serverCreated)
        record[Outline.CloudKitRecord.Fields.created] = recordCreated

        let recordUpdated = merge(client: updated, ancestor: ancestorUpdated, server: serverUpdated)
        record[Outline.CloudKitRecord.Fields.updated] = recordUpdated

		let recordAutoLinkingEnabled = merge(client: autoLinkingEnabled, ancestor: ancestorAutoLinkingEnabled, server: serverAutolinkingEnabled)
		record[Outline.CloudKitRecord.Fields.autoLinkingEnabled] = recordAutoLinkingEnabled

		let recordCheckSpellingWhileTyping = merge(client: checkSpellingWhileTyping, ancestor: ancestorCheckSpellingWhileTyping, server: serverCheckSpellingWhileTyping)
		record[Outline.CloudKitRecord.Fields.checkSpellingWhileTyping] = recordCheckSpellingWhileTyping

		let recordCorrectSpellingAutomatically = merge(client: correctSpellingAutomatically, ancestor: ancestorCorrectSpellingAutomatically, server: serverCorrectSpellingAutomatically)
		record[Outline.CloudKitRecord.Fields.correctSpellingAutomatically] = recordCorrectSpellingAutomatically

        let recordOwnerName = merge(client: ownerName, ancestor: ancestorOwnerName, server: serverOwnerName)
        record[Outline.CloudKitRecord.Fields.ownerName] = recordOwnerName

        let recordOwnerEmail = merge(client: ownerEmail, ancestor: ancestorOwnerEmail, server: serverOwnerEmail)
        record[Outline.CloudKitRecord.Fields.ownerEmail] = recordOwnerEmail

        let recordOwnerURL = merge(client: ownerURL, ancestor: ancestorOwnerURL, server: serverOwnerURL)
        record[Outline.CloudKitRecord.Fields.ownerURL] = recordOwnerURL

        let recordRowOrder = merge(client: rowOrder, ancestor: ancestorRowOrder, server: serverRowOrder)
        record[Outline.CloudKitRecord.Fields.rowOrder] = Array(recordRowOrder)

        if let recordTagIDs = merge(client: tagIDs, ancestor: ancestorTagIDs, server: serverTagIDs) {
            var recordTags = [Tag]()
			for recordTagID in recordTagIDs {
				if let tag = await account!.findTag(tagID: recordTagID) {
					recordTags.append(tag)
				}
			}
            record[Outline.CloudKitRecord.Fields.tagNames] = recordTags.map { $0.name }
        }

        if let recordOutlineLinks = merge(client: outlineLinks, ancestor: ancestorOutlineLinks, server: serverOutlineLinks) {
            record[Outline.CloudKitRecord.Fields.outlineLinks] = recordOutlineLinks.map { $0.description }
        }

        if let recordOutlineBacklinks = merge(client: outlineBacklinks, ancestor: ancestorOutlineBacklinks, server: serverOutlineBacklinks) {
            record[Outline.CloudKitRecord.Fields.outlineBacklinks] = recordOutlineBacklinks.map { $0.description }
        }

        let recordHasAltLinks = merge(client: hasAltLinks, ancestor: ancestorHasAltLinks, server: serverHasAltLinks)
        record[Outline.CloudKitRecord.Fields.hasAltLinks] = recordHasAltLinks

        return record
    }
    
    public func clearSyncData() {
		isCloudKitMerging = false

		ancestorTitle = nil
        serverTitle = nil

        ancestorDisambiguator = nil
        serverDisambiguator = nil

        ancestorCreated = nil
        serverCreated = nil

        ancestorUpdated = nil
        serverUpdated = nil
		
		ancestorAutoLinkingEnabled = nil
		serverAutolinkingEnabled = nil

		ancestorCheckSpellingWhileTyping = nil
		serverCheckSpellingWhileTyping = nil
		
		ancestorCorrectSpellingAutomatically = nil
		serverCorrectSpellingAutomatically = nil
		
        ancestorOwnerName = nil
        serverOwnerName = nil

        ancestorOwnerEmail = nil
        serverOwnerEmail = nil

        ancestorOwnerURL = nil
        serverOwnerURL = nil

        ancestorRowOrder = nil
        serverRowOrder = nil
        
        ancestorTagIDs = nil
        serverTagIDs = nil

        ancestorOutlineLinks = nil
        serverOutlineLinks = nil

        ancestorOutlineBacklinks = nil
        serverOutlineBacklinks = nil

        ancestorHasAltLinks = nil
        serverHasAltLinks = nil
    }
    
}

// MARK: Helpers

private extension Outline {
	
	func applyRowOrder(_ record: CKRecord) -> [String] {
		var updatedRowIDs = [String]()

		if let serverRowOrder = record[Outline.CloudKitRecord.Fields.rowOrder] as? [String] {
			let serverRowOrderedSet = OrderedSet(serverRowOrder)
			
			//  We only count newly added children as updated for reloading so that they can indent or outdent
			let rowDiff = serverRowOrderedSet.difference(from: rowOrder ?? OrderedSet<String>())
			for change in rowDiff {
				switch change {
				case .insert(_, let newRowID, _):
					updatedRowIDs.append(newRowID)
				default:
					break
				}
			}
			
			rowOrder = serverRowOrderedSet
		} else {
			rowOrder = OrderedSet<String>()
		}
		
		return updatedRowIDs
	}
	

	mutating func applyTags(_ record: CKRecord, _ account: Account) async {
		let serverTagNames = record[Outline.CloudKitRecord.Fields.tagNames] as? [String] ?? []
		var serverTags = [Tag]()
		for name in serverTagNames {
			serverTags.append(await account.createTag(name: name))
		}
		let serverTagIDs = serverTags.map({ $0.id })
		
		let oldTagNames = await tags.map { $0.name }
		let oldTagIDs = tagIDs
		
		tagIDs = serverTagIDs

		if isBeingViewed && isSearching == .notSearching {
			updateTagUI(tagIDs ?? [], oldTagIDs ?? [])
		}
				
		let tagNamesToDelete = Set(oldTagNames).subtracting(serverTagNames)
		for tagNameToDelete in tagNamesToDelete {
			await account.deleteTag(name: tagNameToDelete)
		}
	}
	
	func updateTagUI(_ tagIDs: [String], _ oldTagIDs: [String]) {
		var moves = Set<OutlineElementChanges.Move>()
		var inserts = Set<Int>()
		var deletes = Set<Int>()
		
		let tagDiff = tagIDs.difference(from: oldTagIDs).inferringMoves()
		for change in tagDiff {
			switch change {
			case .insert(let offset, _, let associated):
				if let associated {
					moves.insert(OutlineElementChanges.Move(associated, offset))
				} else {
					inserts.insert(offset)
				}
			case .remove(let offset, _, let associated):
				if let associated {
					moves.insert(OutlineElementChanges.Move(offset, associated))
				} else {
					deletes.insert(offset)
				}
			}
		}
		
		let changes = OutlineElementChanges(section: .tags, deletes: deletes, inserts: inserts, moves: moves)
		outlineElementsDidChange(changes)
	}
	
	mutating func applyDocumentLinks(_ record: CKRecord) {
		if let serverOutlineLinkDescs = record[Outline.CloudKitRecord.Fields.outlineLinks] as? [String] {
			outlineLinks = serverOutlineLinkDescs.compactMap { EntityID(description: $0) }
		} else {
			outlineLinks = [EntityID]()
		}
	}
	
	mutating func applyDocumentBacklinks(_ record: CKRecord) {
		let serverOutlineBacklinkDescs = record[Outline.CloudKitRecord.Fields.outlineBacklinks] as? [String] ?? []
		let serverOutlineBacklinks = serverOutlineBacklinkDescs.compactMap { EntityID(description: $0) }
		let outlineBacklinksDiff = serverOutlineBacklinks.difference(from: outlineBacklinks ?? [])
		
		for change in outlineBacklinksDiff {
			switch change {
			case .insert(_, let outlineBacklink, _):
				createBacklink(outlineBacklink, updateCloudKit: false)
			case .remove(_, let outlineBacklink, _):
				deleteBacklink(outlineBacklink, updateCloudKit: false)
			}
		}
	}
	
	func outlineDidChangeBySync() {
		NotificationCenter.default.post(name: .OutlineDidChangeBySync, object: self, userInfo: nil)
	}

}
