//
//  TagDocuments.swift
//  
//
//  Created by Maurice Parker on 2/2/21.
//

#if canImport(UIKit)
import UIKit
#else
import Foundation
#endif

public final class TagOutlines: Identifiable, OutlineContainer {

	public var id: EntityID
	public var name: String?

	#if canImport(UIKit)
	#if targetEnvironment(macCatalyst)
	public var image: UIImage? = UIImage(systemName: "capsule")!.applyingSymbolConfiguration(.init(pointSize: 12))
	#else
	public var image: UIImage? = UIImage(systemName: "capsule")!.applyingSymbolConfiguration(.init(pointSize: 15))
	#endif
	#endif

	public var itemCount: Int? {
		guard let tag else { return nil }
//		return account?.documents?.filter({ $0.hasTag(tag) }).count
		return 0
	}
	
	public weak var account: Account?
	public weak var tag: Tag?
	
	public var outlines: [Outline] {
		get async {
			guard let tag, let outlines = await account?.outlines else { return [] }
			return outlines.filter { $0.hasTag(tag) }
		}
	}

	public init(account: Account, tag: Tag) {
		self.id = .tagOutlines(account.id.accountID, tag.id)
		self.account = account
		self.tag = tag
		self.name = tag.name
	}
	
}

