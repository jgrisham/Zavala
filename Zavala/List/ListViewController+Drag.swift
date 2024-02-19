//
//  ListViewController+Drag.swift
//  Zavala
//
//  Created by Maurice Parker on 12/2/20.
//

import UIKit
import UniformTypeIdentifiers
import VinOutlineKit

extension ListViewController: UICollectionViewDragDelegate {
	
	func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		let outline = outlines[indexPath.row]
		session.localContext = outline
		
		let itemProvider = NSItemProvider()

		let filename = outline.filename(representation: DataRepresentation.opml)
		itemProvider.suggestedName = filename
		itemProvider.registerFileRepresentation(forTypeIdentifier: DataRepresentation.opml.typeIdentifier, visibility: .all) { (completionHandler) -> Progress? in
			let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
			Task {
				do {
					let opml = await outline.opml()
					try opml.write(to: tempFile, atomically: true, encoding: String.Encoding.utf8)
					completionHandler(tempFile, true, nil)
				} catch {
					completionHandler(nil, false, error)
				}
			}
			return nil
		}

		itemProvider.registerDataRepresentation(for: UTType.utf8PlainText, visibility: .all) { completion in
			Task {
				let data = await outline.markdownList().data(using: .utf8)
				completion(data, nil)
			}
			return nil
		}
		
		let userActivity = NSUserActivity(activityType: NSUserActivity.ActivityType.newWindow)
		var userInfo = [AnyHashable: Any]()
		userInfo[Pin.UserInfoKeys.pin] = Pin(containers: outlineContainers, outline: outline).userInfo
		userActivity.userInfo = userInfo
		itemProvider.registerObject(userActivity, visibility: .all)

		let dragItem = UIDragItem(itemProvider: itemProvider)
		dragItem.localObject = outline
		return [dragItem]
	}
	
}
