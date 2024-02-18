//
//  File.swift
//  
//
//  Created by Maurice Parker on 2/7/24.
//

import Foundation
import VinCloudKit

public extension AccountManager {
	
	func loadAccountFileData(_ data: Data, accountType: AccountType) async {
		let decoder = PropertyListDecoder()
		let accountCodable: AccountCodable
		do {
			accountCodable = try decoder.decode(AccountCodable.self, from: data)
		} catch {
			logger.error("Account read deserialization failed: \(error.localizedDescription, privacy: .public)")
			return
		}
		
		let account = accountCodable.toAccount()
		
		let initialLoad = _accountsDictionary[accountType.rawValue] == nil
		_accountsDictionary[accountType.rawValue] = account
		
		for document in await account.documents ?? [] {
			var mutableDocument = document
			mutableDocument.account = account
		}
		
		if !initialLoad {
			await account.accountDidReload()
		}
	}
	
	func buildAccountFileData(accountType: AccountType) async -> Data? {
		guard let account = _accountsDictionary[accountType.rawValue] else { return nil }
		
		let accountCodable = await AccountCodable(account: account)
		
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .binary
		
		let accountData: Data
		do {
			accountData = try encoder.encode(accountCodable)
		} catch {
			logger.error("Account read serialization failed: \(error.localizedDescription, privacy: .public)")
			return nil
		}
		
		return accountData
	}
	
}

struct AccountCodable: Codable {
	let type: AccountType
	var isActive: Bool
	
	var tags: [Tag]?
	var documents: [DocumentCodable]?

	var sharedDatabaseChangeToken: Data?
	var zoneChangeTokens: [VCKChangeTokenKey: Data]?

	enum CodingKeys: String, CodingKey {
		case type = "type"
		case isActive = "isActive"
		case tags = "tags"
		case documents = "documents"
		case sharedDatabaseChangeToken = "sharedDatabaseChangeToken"
		case zoneChangeTokens = "zoneChangeTokens"
	}
	
	init(account: Account) async {
		self.type = account.type
		self.isActive = await account.isActive
		self.tags = await account.tags
		
		var documentCodables = [DocumentCodable]()
		for document in await account.documents ?? [] {
			if let outline = document.outline {
				documentCodables.append(.outline(outline))
			}
		}
		
		self.documents = documentCodables
		self.sharedDatabaseChangeToken = await account.sharedDatabaseChangeToken
		self.zoneChangeTokens = await account.zoneChangeTokens
	}
	
	func toAccount() -> Account {
		return Account(accountType: type)
	}
	
}

public enum DocumentCodable: Equatable, Hashable, Codable {
	case outline(Outline)
	
	private enum CodingKeys: String, CodingKey {
		case type
		case outline
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let type = try container.decode(String.self, forKey: .type)
		
		switch type {
		case "outline":
			let outline = try container.decode(Outline.self, forKey: .outline)
			self = .outline(outline)
		default:
			fatalError()
		}
	}
	
	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		switch self {
		case .outline(let outline):
			try container.encode("outline", forKey: .type)
			try container.encode(outline, forKey: .outline)
		}
	}
}
