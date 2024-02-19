//
//  IndexRequestHandler.swift
//  SpotlightIndexExtension
//
//  Created by Maurice Parker on 3/10/21.
//

import Foundation
import OSLog
import CoreSpotlight
import VinOutlineKit

class IndexRequestHandler: CSIndexExtensionRequestHandler {
	
	var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Zavala")

    override func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
		Task {
			self.logger.info("IndexRequestHandler starting...")
			
			await self.resume()

			await withTaskGroup(of: Void.self) { taskGroup in
				for outline in await Outliner.shared.outlines {
					autoreleasepool {
						taskGroup.addTask {
							let searchableItem = await OutlineIndexer.makeSearchableItem(forOutline: outline)
							await withCheckedContinuation { continuation in
								searchableIndex.indexSearchableItems([searchableItem]) { _ in
									continuation.resume()
								}
							}
						}
					}
				}
			}
			
			await self.suspend()
			self.logger.info("IndexRequestHandler done.")
			acknowledgementHandler()
		}
    }
    
	override func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
		Task {
			self.logger.info("IndexRequestHandler starting...")
			
			await self.resume()

			await withTaskGroup(of: Void.self) { taskGroup in
				for description in identifiers {
					if let entityID = EntityID(description: description), let outline = await Outliner.shared.findOutline(entityID) {
						autoreleasepool {
							taskGroup.addTask {
								let searchableItem = await OutlineIndexer.makeSearchableItem(forOutline: outline)
								await withCheckedContinuation { continuation in
									searchableIndex.indexSearchableItems([searchableItem]) { _ in
										continuation.resume()
									}
								}
							}
						}
					}
				}
			}
			
			await self.suspend()
			self.logger.info("IndexRequestHandler done.")
			acknowledgementHandler()
		}
	}
	
}

// MARK: ErrorHandler

extension IndexRequestHandler: ErrorHandler {
	
	func presentError(_ error: Error, title: String) {
		self.logger.error("IndexRequestHandler failed with error: \(error.localizedDescription, privacy: .public)")
	}
	
}

// MARK: Helpers

private extension IndexRequestHandler {
	
	func resume() async {
		if Outliner.shared == nil {
			let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as! String
			let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
			let documentAccountsFolderPath = containerURL!.appendingPathComponent("Accounts").path
			Outliner.shared = Outliner(accountsFolderPath: documentAccountsFolderPath)
			await Outliner.shared.startUp(errorHandler: self)
		} else {
			await Outliner.shared.resume()
		}
	}
	
	func suspend() async {
		await Outliner.shared.suspend()
	}
	
}
