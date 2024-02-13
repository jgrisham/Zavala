//
//  ImagesFile.swift
//
//  Created by Maurice Parker on 7/31/21.
//

import Foundation
import OSLog
import VinUtility

final class ImagesFile: ManagedResourceFile {
	
	private weak var outline: Outline?
	
	init?(outline: Outline) async {
		self.outline = outline

		guard let account = await outline.account else {
			return nil
		}

		let fileURL = account.folder.appendingPathComponent("\(outline.id.documentUUID)_images.plist")
		super.init(fileURL: fileURL)
	}
	
	public override func fileDidLoad(data: Data) async {
		outline?.loadImageFileData(data)
	}
	
	public override func fileWillSave() async -> Data? {
		return outline?.buildImageFileData()
	}
	
}
