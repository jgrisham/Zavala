//
//  AccountDocuments.swift
//  
//
//  Created by Maurice Parker on 1/27/21.
//

#if canImport(UIKit)
import UIKit
#else
import Foundation
#endif
public final class AllDocuments: Identifiable, DocumentContainer {

	public var id: EntityID
	public var name: String? = VinOutlineKitStringAssets.all
	#if canImport(UIKit)
	public var image: UIImage? = UIImage(systemName: "tray")!
	#endif

	public var itemCount: Int? {
		return 0
//		return account?.documents?.count
	}

	public var documents: [Document] {
		get async {
			return await account?.documents ?? []
		}
	}

	public weak var account: Account?
	
	public init(account: Account) {
		self.id = .allDocuments(account.id.accountID)
		self.account = account
	}
	
}
