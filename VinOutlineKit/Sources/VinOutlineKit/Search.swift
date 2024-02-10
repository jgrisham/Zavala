//
//  Search.swift
//  
//
//  Created by Maurice Parker on 1/12/21.
//

#if canImport(UIKit)
import UIKit
#else
import Foundation
#endif
import CoreSpotlight

public final class Search: Identifiable, DocumentContainer {
	
	public var id: EntityID
	public var name: String? = VinOutlineKitStringAssets.search
	
	#if canImport(UIKit)
	public var image: UIImage?
	#endif
	public var account: Account? = nil

	public var itemCount: Int? {
		return nil
	}
	
	public var searchText: String
	
	private var searchQuery: CSSearchQuery?

	public var documents: [Document] {
		get async throws {
			searchQuery?.cancel()
			
			guard searchText.count > 2 else {
				return []
			}
			
			return try await withCheckedThrowingContinuation { continuation in
				var  foundItems = [CSSearchableItem]()
				
				let queryString = "title == \"*\(searchText)*\"c || textContent == \"*\(searchText)*\"c"
				searchQuery = CSSearchQuery(queryString: queryString, attributes: nil)
				
				searchQuery?.foundItemsHandler = { items in
					foundItems.append(contentsOf: items)
				}
				
				searchQuery?.completionHandler = { error in
					if let error {
						continuation.resume(throwing: error)
					} else {
						let documentIDs = foundItems.compactMap { EntityID(description: $0.uniqueIdentifier) }
						Task {
							var documents = [Document]()
							for documentID in documentIDs {
								if let document = await AccountManager.shared.findDocument(documentID) {
									documents.append(document)
								}
							}
							continuation.resume(returning: documents)
						}
					}
				}
				
				searchQuery?.start()
			}
		}
		
	}


	public init(searchText: String) {
		self.id = .search(searchText)
		self.searchText = searchText
	}
	
	deinit {
		searchQuery?.cancel()
	}
	
}
