//
//  CloudKitOutlineUpdate.swift
//  
//
//  Created by Maurice Parker on 2/20/21.
//

import Foundation
import CloudKit

class CloudKitOutlineUpdate {
	
	var outlineID: EntityID
	var zoneID: CKRecordZone.ID
	var isDelete = false
	
	var saveOutlineRecord: CKRecord?
	var deleteRowRecordIDs = [EntityID]()
	var saveRowRecords = [CKRecord]()
	var deleteImageRecordIDs = [EntityID]()
	var saveImageRecords = [CKRecord]()

	init(outlineID: EntityID, zoneID: CKRecordZone.ID) {
		self.outlineID = outlineID
		self.zoneID = zoneID
	}
	
}
