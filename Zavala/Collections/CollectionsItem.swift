//
//  CollectionsItem.swift
//  Zavala
//
//  Created by Maurice Parker on 11/14/20.
//

import UIKit
import VinOutlineKit

final class CollectionsItem: NSObject, NSCopying, Identifiable {
	
	enum ID: Hashable {
		case header(CollectionsSection)
		case search
		case outlineContainer(EntityID)
		
		var accountType: AccountType? {
			if case .header(let section) = self {
				switch section {
				case .localAccount:
					return AccountType.local
				case .cloudKitAccount:
					return AccountType.cloudKit
				default:
					break
				}
			}
			return nil
		}
		
		var name: String? {
			return accountType?.name
		}
		
	}
	
	let id: CollectionsItem.ID
	
	var entityID: EntityID? {
		if case .outlineContainer(let entityID) = id {
			return entityID
		}
		return nil
	}
	
	init(id: ID) {
		self.id = id
	}
	
	static func searchItem() -> CollectionsItem {
		return CollectionsItem(id: .search)
	}
	
	static func item(id: ID) -> CollectionsItem {
		return CollectionsItem(id: id)
	}
	
	static func item(_ container: OutlineContainer) -> CollectionsItem {
		let id = CollectionsItem.ID.outlineContainer(container.id)
		return CollectionsItem(id: id)
	}

	override func isEqual(_ object: Any?) -> Bool {
		guard let other = object as? CollectionsItem else { return false }
		if self === other { return true }
		return id == other.id
	}
	
	override var hash: Int {
		var hasher = Hasher()
		hasher.combine(id)
		return hasher.finalize()
	}
	
	func copy(with zone: NSZone? = nil) -> Any {
		return self
	}
	
}

extension Array where Element == CollectionsItem {
	
	func toContainers() async -> [OutlineContainer] {
		var containers = [OutlineContainer]()
		
		for item in self {
			if case .outlineContainer(let entityID) = item.id, let container = await Outliner.shared.findOutlineContainer(entityID) {
				containers.append(container)
			}
		}
		
		return containers
	}
	
}
