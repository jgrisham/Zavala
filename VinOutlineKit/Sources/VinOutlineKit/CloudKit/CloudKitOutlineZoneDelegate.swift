//
//  CloudKitOutlineZoneDelegate.swift
//  
//
//  Created by Maurice Parker on 2/6/21.
//

import Foundation
import CloudKit
import VinCloudKit

class CloudKitOutlineZoneDelegate: VCKZoneDelegate {
	
	weak var account: Account?
	var zoneID: CKRecordZone.ID
	
	init(account: Account, zoneID: CKRecordZone.ID) {
		self.account = account
		self.zoneID = zoneID
	}
	
	func store(changeToken: Data?, key: VCKChangeTokenKey) async {
		await account!.store(changeToken: changeToken, key: key)
	}
	
	func findChangeToken(key: VCKChangeTokenKey) async -> Data? {
		return await account!.zoneChangeTokens?[key]
	}
	
	func cloudKitDidModify(changed: [CKRecord], deleted: [CloudKitRecordKey]) async throws {
		var updates = [EntityID: CloudKitOutlineUpdate]()

		func update(for outlineID: EntityID, zoneID: CKRecordZone.ID) -> CloudKitOutlineUpdate {
			if let update = updates[outlineID] {
				return update
			} else {
				let update = CloudKitOutlineUpdate(outlineID: outlineID, zoneID: zoneID)
				updates[outlineID] = update
				return update
			}
		}

		for deletedRecordKey in deleted {
			if deletedRecordKey.recordType == CKRecord.SystemType.share {
				if let outline = await Outliner.shared.cloudKitAccount?.findOutline(shareRecordID: deletedRecordKey.recordID) {
					Task { @MainActor in
						outline.cloudKitShareRecord = nil
					}
				}
			} else {
				guard let entityID = EntityID(description: deletedRecordKey.recordID.recordName) else { continue }
				switch entityID {
				case .outline:
					update(for: entityID, zoneID: deletedRecordKey.recordID.zoneID).isDelete = true
				case .row(let accountID, let outlineUUID, _):
					let outlineID = EntityID.outline(accountID, outlineUUID)
					update(for: outlineID, zoneID: deletedRecordKey.recordID.zoneID).deleteRowRecordIDs.append(entityID)
				case .image(let accountID, let outlineUUID, _, _):
					let outlineID = EntityID.outline(accountID, outlineUUID)
					update(for: outlineID, zoneID: deletedRecordKey.recordID.zoneID).deleteImageRecordIDs.append(entityID)
				default:
					assertionFailure("Unknown record type: \(deletedRecordKey.recordType)")
				}
			}
		}

		for changedRecord in changed {
			if let shareRecord = changedRecord as? CKShare {
				if let outline = await Outliner.shared.cloudKitAccount?.findOutline(shareRecordID: shareRecord.recordID) {
					Task { @MainActor in
						outline.cloudKitShareRecord = shareRecord
					}
				}
			} else {
				guard let entityID = EntityID(description: changedRecord.recordID.recordName) else { continue }
				switch entityID {
				case .outline:
					update(for: entityID, zoneID: changedRecord.recordID.zoneID).saveOutlineRecord = changedRecord
				case .row(let accountID, let outlineUUID, _):
					let outlineID = EntityID.outline(accountID, outlineUUID)
					update(for: outlineID, zoneID: changedRecord.recordID.zoneID).saveRowRecords.append(changedRecord)
				case .image(let accountID, let outlineUUID, _, _):
					let outlineID = EntityID.outline(accountID, outlineUUID)
					update(for: outlineID, zoneID: changedRecord.recordID.zoneID).saveImageRecords.append(changedRecord)
				default:
					assertionFailure("Unknown record type: \(changedRecord.recordType)")
				}
			}
		}
		
		for update in updates.values {
			Task { @MainActor in
				await account?.apply(update)
			}
		}
		
	}

}
