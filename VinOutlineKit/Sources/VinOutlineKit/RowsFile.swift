//
//  RowsFile.swift
//  
//
//  Created by Maurice Parker on 11/15/20.
//

import Foundation
import OSLog
import OrderedCollections
import VinUtility


final class RowsFile: ManagedResourceFile {
	
	private weak var outline: Outline?
	
	init?(outline: Outline) async {
		self.outline = outline

		guard let account = outline.account else {
			return nil
		}

		let fileURL = await account.folder.appendingPathComponent("\(outline.id.outlineUUID).plist")
		super.init(fileURL: fileURL)
	}
	
	public override func fileDidLoad(data: Data) async {
		outline?.loadRowFileData(data)
	}
	
	public override func fileWillSave() async -> Data? {
		return outline?.buildRowFileData()
	}
	
}
