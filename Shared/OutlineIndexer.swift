//
//  Created by Maurice Parker on 3/10/21.
//

import Foundation
import MobileCoreServices
import VinOutlineKit
import CoreSpotlight

class OutlineIndexer {
	
	init() {
		NotificationCenter.default.addObserver(self, selector: #selector(outlineDidChangeBySync(_:)), name: .OutlineDidChangeBySync, object: nil)
	}
	
	static func updateIndex(for outline: Outline) {
		Task {
			let searchableItem = await makeSearchableItem(forOutline: outline)
			try? await CSSearchableIndex.default().indexSearchableItems([searchableItem])
		}
	}
	
	static func makeSearchableItem(forOutline outline: Outline) async -> CSSearchableItem {
		let attributeSet = await makeSearchableItemAttributes(forOutline: outline)
		let identifier = attributeSet.relatedUniqueIdentifier
		return CSSearchableItem(uniqueIdentifier: identifier, domainIdentifier: "io.vincode", attributeSet: attributeSet)
	}
	
}

// MARK: Helpers

private extension OutlineIndexer {
	
	static func makeSearchableItemAttributes(forOutline outline: Outline) async -> CSSearchableItemAttributeSet {
		let attributeSet = CSSearchableItemAttributeSet(contentType: UTType.text)
		attributeSet.title = outline.title ?? ""
		attributeSet.keywords = await outline.tags.map({ $0.name })
		attributeSet.relatedUniqueIdentifier = outline.id.description
		attributeSet.textContent = await outline.textContent()
		attributeSet.contentModificationDate = outline.updated
		return attributeSet
	}
	
	@objc func outlineDidChangeBySync(_ note: Notification) {
		guard let outline = note.object as? Outline else { return }
		Self.updateIndex(for: outline)
	}
	
}
