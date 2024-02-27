//
//  CollectionsViewController+Drop.swift
//  Zavala
//
//  Created by Maurice Parker on 12/3/20.
//

import UIKit
import VinOutlineKit

extension CollectionsViewController: UICollectionViewDropDelegate {
	
	func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
		guard !(session.items.first?.localObject is Outline) else { return true }
		return session.hasItemsConforming(toTypeIdentifiers: [DataRepresentation.opml.typeIdentifier])
	}
	
	func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
		guard let destinationIndexPath,
			  let item = dataSource.itemIdentifier(for: destinationIndexPath),
			  let entityID = item.entityID,
			  let container = outlineContainersDictionary[entityID] else {
			return UICollectionViewDropProposal(operation: .cancel)
		}
		
		guard session.localDragSession != nil else {
			return UICollectionViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)
		}
		
		let sourceAccount = (session.localDragSession?.localContext as? Outline)?.account
		let destinationAccount = container.account
		
		if sourceAccount == destinationAccount {
			if let tag = (container as? TagOutlines)?.tag {
				if let outline = session.localDragSession?.localContext as? Outline, outline.hasTag(tag) {
					return UICollectionViewDropProposal(operation: .cancel)
				}
			}
			return UICollectionViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)
		} else {
			return UICollectionViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
		}
		
	}
	
	func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
		guard let dragItem = coordinator.items.first?.dragItem,
			  let destinationIndexPath = coordinator.destinationIndexPath,
			  let item = dataSource.itemIdentifier(for: destinationIndexPath),
			  let entityID = item.entityID,
			  let container = outlineContainersDictionary[entityID] else { return }
		
		// Dragging an OPML file into the Collections View
		guard let outline = dragItem.localObject as? Outline else {
			for dropItem in coordinator.items {
				let provider = dropItem.dragItem.itemProvider
				provider.loadDataRepresentation(forTypeIdentifier: DataRepresentation.opml.typeIdentifier) { (opmlData, error) in
					guard let opmlData else { return }
					Task {
                        var tags: [Tag]? = nil
                        if let tag = (container as? TagOutlines)?.tag {
                            tags = [tag]
                        }
						if let outline = try? await container.account?.importOPML(opmlData, tags: tags) {
							OutlineIndexer.updateIndex(for: outline)
						}
					}
				}
			}
			return
		}

		// Local copy between accounts
		guard outline.account == container.account else {
			Task {
				await outline.load()
				
				var tagNames = [String]()
				for tag in await outline.tags {
					outline.deleteTag(tag)
					await outline.account?.deleteTag(tag)
					tagNames.append(tag.name)
				}
				
				await outline.account?.deleteOutline(outline)
				if let containerAccount = container.account {
					outline.reassignAccount(containerAccount.id.accountID)
					await containerAccount.createOutline(outline)
				}
				
				for tagName in tagNames {
					if let tag = await container.account?.createTag(name: tagName) {
						outline.createTag(tag)
					}
				}
				
				outline.deleteAllBacklinks()
				
				await outline.forceSave()
				await outline.unload()
			}
			return
		}
		
		// Adding a tag by dragging a outline to it
		guard let tag = (container as? TagOutlines)?.tag else {
			return
		}
		
		outline.createTag(tag)
	}
	
	
}
