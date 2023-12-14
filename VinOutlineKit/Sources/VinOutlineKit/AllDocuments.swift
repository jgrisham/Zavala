//
//  AccountDocuments.swift
//  
//
//  Created by Maurice Parker on 1/27/21.
//

import UIKit

public final class AllDocuments: Identifiable, DocumentContainer {

	public var id: EntityID
	public var name: String? = VinOutlineKitStringAssets.all
	public var image: UIImage? = UIImage(systemName: "tray")!

	public var itemCount: Int? {
		return account?.documents?.count
	}
	
	public weak var account: Account?
	
	public init(account: Account) {
		self.id = .allDocuments(account.id.accountID)
		self.account = account
	}
	
	public func documents(completion: @escaping (Result<[Document], Error>) -> Void) {
		completion(.success(account?.documents ?? [Document]()))
	}
	
}