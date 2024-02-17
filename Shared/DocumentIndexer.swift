//
//  DocumentIndexer.swift
//  Zavala
//
//  Created by Maurice Parker on 3/10/21.
//

import Foundation
import MobileCoreServices
import VinOutlineKit
import CoreSpotlight

class DocumentIndexer {
	
	init() {
		NotificationCenter.default.addObserver(self, selector: #selector(documentDidChangeBySync(_:)), name: .DocumentDidChangeBySync, object: nil)
	}
	
	static func updateIndex(forDocument document: Document) {
		Task {
			let searchableItem = await makeSearchableItem(forDocument: document)
			try? await CSSearchableIndex.default().indexSearchableItems([searchableItem])
		}
	}
	
	static func makeSearchableItem(forDocument document: Document) async -> CSSearchableItem {
		let attributeSet = await makeSearchableItemAttributes(forDocument: document)
		let identifier = attributeSet.relatedUniqueIdentifier
		return CSSearchableItem(uniqueIdentifier: identifier, domainIdentifier: "io.vincode", attributeSet: attributeSet)
	}
	
}

// MARK: Helpers

private extension DocumentIndexer {
	
	static func makeSearchableItemAttributes(forDocument document: Document) async -> CSSearchableItemAttributeSet {
		let attributeSet = CSSearchableItemAttributeSet(contentType: UTType.text)
		attributeSet.title = document.title ?? ""
		if let keywords = await document.tags?.map({ $0.name }) {
			attributeSet.keywords = keywords
		}
		attributeSet.relatedUniqueIdentifier = document.id.description
		attributeSet.textContent = await document.textContent
		attributeSet.contentModificationDate = document.updated
		return attributeSet
	}
	
	@objc func documentDidChangeBySync(_ note: Notification) {
		guard let document = note.object as? Document else { return }
		Self.updateIndex(forDocument: document)
	}
	
}
