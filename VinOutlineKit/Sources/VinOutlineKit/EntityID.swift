//
//  EntityID.swift
//  
//
//  Created by Maurice Parker on 11/10/20.
//

import Foundation

public enum EntityID: CustomStringConvertible, Hashable, Equatable, Codable {
	case account(Int)
	case outline(Int, String) // Account, Outline
	case row(Int, String, String) // Account, Outline, Row
	case image(Int, String, String, String) // Account, Outline, Row, Image
	case allOutlines(Int) // Account
	case recentOutlines(Int) // Account
	case tagOutlines(Int, String) // Account, Tag
	case search(String) // Search String

	public var accountID: Int {
		switch self {
		case .account(let accountID):
			return accountID
		case .outline(let accountID, _):
			return accountID
		case .row(let accountID, _, _):
			return accountID
		case .image(let accountID, _, _, _):
			return accountID
		case .allOutlines(let accountID):
			return accountID
		case .recentOutlines(let accountID):
			return accountID
		case .tagOutlines(let accountID, _):
			return accountID
		default:
			fatalError()
		}
	}

	public var outlineUUID: String {
		switch self {
		case .outline(_, let outlineID):
			return outlineID
		case .row(_, let outlineID, _):
			return outlineID
		case .image(_, let outlineID, _, _):
			return outlineID
		default:
			fatalError()
		}
	}
	
	public var rowUUID: String {
		switch self {
		case .row(_, _, let rowID):
			return rowID
		case .image(_, _, let rowID, _):
			return rowID
		default:
			fatalError()
		}
	}
	
	public var imageUUID: String {
		switch self {
		case .image(_, _, _, let imageID):
			return imageID
		default:
			fatalError()
		}
	}
	
	public var description: String {
		switch self {
		case .account(let id):
			return "account:\(id)"
		case .outline(let accountID, let outlineID):
			return "document:\(accountID)_\(outlineID)"
		case .row(let accountID, let outlineID, let rowID):
			return "row:\(accountID)_\(outlineID)_\(rowID)"
		case .image(let accountID, let outlineID, let rowID, let imageID):
			return "image:\(accountID)_\(outlineID)_\(rowID)_\(imageID)"
		case .search(let searchText):
			return "search:\(searchText)"
		case .allOutlines(let id):
			return "allOutlines:\(id)"
		case .recentOutlines(let id):
			return "recentOutlines:\(id)"
		case .tagOutlines(let accountID, let tagID):
			return "tagOutlines:\(accountID)_\(tagID)"
		}
	}
	
	public var userInfo: [AnyHashable: AnyHashable] {
		switch self {
		case .account(let accountID):
			return [
				"type": "account",
				"accountID": accountID
			]
		case .outline(let accountID, let outlineID):
			return [
				"type": "document",
				"accountID": accountID,
				"documentID": outlineID
			]
		case .row(let accountID, let outlineID, let rowID):
			return [
				"type": "row",
				"accountID": accountID,
				"documentID": outlineID,
				"rowID": rowID
			]
		case .image(let accountID, let outlineID, let rowID, let imageID):
			return [
				"type": "image",
				"accountID": accountID,
				"documentID": outlineID,
				"rowID": rowID,
				"imageID": imageID
			]
		case .search(let searchText):
			return [
				"type": "search",
				"searchText": searchText
			]
		case .allOutlines(let accountID):
			return [
				"type": "allOutlines",
				"accountID": accountID
			]
		case .recentOutlines(let accountID):
			return [
				"type": "recentOutlines",
				"accountID": accountID
			]
		case .tagOutlines(let accountID, let tagID):
			return [
				"type": "tagOutlines",
				"accountID": accountID,
				"tagID": tagID
			]
		}
	}

	public var url: URL? {
		switch self {
		case .outline(let acct, let outlineUUID):
			var urlComponents = URLComponents()
			urlComponents.scheme = "zavala"
			urlComponents.host = "document"
			
			var queryItems = [URLQueryItem]()
			queryItems.append(URLQueryItem(name: "accountID", value: String(acct)))
			queryItems.append(URLQueryItem(name: "documentUUID", value: String(outlineUUID)))
			urlComponents.queryItems = queryItems
			
			return urlComponents.url!
		default:
			return nil
		}
	}
	
	public var isAccount: Bool {
		switch self {
		case .account(_):
			return true
		default:
			return false
		}
	}
	
	public var isSystemCollection: Bool {
		switch self {
		case .allOutlines(_):
			return true
		case .recentOutlines(_):
			return true
		default:
			return false
		}
	}
	
	public var isDocument: Bool {
		switch self {
		case .outline(_, _):
			return true
		default:
			return false
		}
	}
	
	private enum CodingKeys: String, CodingKey {
		case type
		case searchText
		case accountID
		case documentID
		case rowID
		case imageID
		case tagID
	}
	
	public init?(description: String) {
		if description.starts(with: "account:") {
			let idString = description.suffix(from: description.index(description.startIndex, offsetBy: 8))
			if let accountID = Int(idString) {
				self = .account(accountID)
				return
			}
		} else if description.starts(with: "document:") {
			let idString = description.suffix(from: description.index(description.startIndex, offsetBy: 9))
			let ids = idString.split(separator: "_")
			if let accountID = Int(ids[0]) {
				self = .outline(accountID, String(ids[1]))
				return
			}
		} else if description.starts(with: "row:") {
			let idString = description.suffix(from: description.index(description.startIndex, offsetBy: 4))
			let ids = idString.split(separator: "_")
			if let accountID = Int(ids[0]) {
				self = .row(accountID, String(ids[1]), String(ids[2]))
				return
			}
		} else if description.starts(with: "image:") {
			let idString = description.suffix(from: description.index(description.startIndex, offsetBy: 6))
			let ids = idString.split(separator: "_")
			if let accountID = Int(ids[0]) {
				self = .image(accountID, String(ids[1]), String(ids[2]), String(ids[3]))
				return
			}
		} else if description.starts(with: "search:") {
			let searchText = description.suffix(from: description.index(description.startIndex, offsetBy: 7))
			self = .search(String(searchText))
			return
		} else if description.starts(with: "allOutlines:") {
			let idString = description.suffix(from: description.index(description.startIndex, offsetBy: 13))
			if let accountID = Int(idString) {
				self = .allOutlines(accountID)
				return
			}
		} else if description.starts(with: "recentOutlines:") {
			let idString = description.suffix(from: description.index(description.startIndex, offsetBy: 16))
			if let accountID = Int(idString) {
				self = .recentOutlines(accountID)
				return
			}
		} else if description.starts(with: "tagOutlines:") {
			let idString = description.suffix(from: description.index(description.startIndex, offsetBy: 13))
			let ids = idString.split(separator: "_")
			if let accountID = Int(ids[0]) {
				self = .tagOutlines(accountID, String(ids[1]))
				return
			}
		}
		return nil
	}
	
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let type = try container.decode(String.self, forKey: .type)
		
		switch type {
		case "account":
			let accountID = try container.decode(Int.self, forKey: .accountID)
			self = .account(accountID)
		case "document":
			let accountID = try container.decode(Int.self, forKey: .accountID)
			let outlineID = try container.decode(String.self, forKey: .documentID)
			self = .outline(accountID, outlineID)
		case "row":
			let accountID = try container.decode(Int.self, forKey: .accountID)
			let outlineID = try container.decode(String.self, forKey: .documentID)
			let rowID = try container.decode(String.self, forKey: .rowID)
			self = .row(accountID, outlineID, rowID)
		case "image":
			let accountID = try container.decode(Int.self, forKey: .accountID)
			let outlineID = try container.decode(String.self, forKey: .documentID)
			let rowID = try container.decode(String.self, forKey: .rowID)
			let imageID = try container.decode(String.self, forKey: .imageID)
			self = .image(accountID, outlineID, rowID, imageID)
		case "search":
			let searchText = try container.decode(String.self, forKey: .searchText)
			self = .search(searchText)
		case "allOutlines":
			let accountID = try container.decode(Int.self, forKey: .accountID)
			self = .allOutlines(accountID)
		case "recentOutlines":
			let accountID = try container.decode(Int.self, forKey: .accountID)
			self = .recentOutlines(accountID)
		case "tagOutlines":
			let accountID = try container.decode(Int.self, forKey: .accountID)
			let tagID = try container.decode(String.self, forKey: .tagID)
			self = .tagOutlines(accountID, tagID)
		default:
			fatalError()
		}
	}
	
	public init?(userInfo: [AnyHashable: AnyHashable]) {
		guard let type = userInfo["type"] as? String else { return nil }
		
		switch type {
		case "account":
			guard let accountID = userInfo["accountID"] as? Int else { return nil }
			self = .account(accountID)
		case "document":
			guard let accountID = userInfo["accountID"] as? Int else { return nil }
			guard let outlineID = userInfo["documentID"] as? String else { return nil }
			self = .outline(accountID, outlineID)
		case "row":
			guard let accountID = userInfo["accountID"] as? Int else { return nil }
			guard let outlineID = userInfo["documentID"] as? String else { return nil }
			guard let rowID = userInfo["rowID"] as? String else { return nil }
			self = .row(accountID, outlineID, rowID)
		case "image":
			guard let accountID = userInfo["accountID"] as? Int else { return nil }
			guard let outlineID = userInfo["documentID"] as? String else { return nil }
			guard let rowID = userInfo["rowID"] as? String else { return nil }
			guard let imageID = userInfo["imageID"] as? String else { return nil }
			self = .image(accountID, outlineID, rowID, imageID)
		case "search":
			guard let searchText = userInfo["searchText"] as? String else { return nil }
			self = .search(searchText)
		case "allOutlines":
			guard let accountID = userInfo["accountID"] as? Int else { return nil }
			self = .allOutlines(accountID)
		case "recentOutlines":
			guard let accountID = userInfo["accountID"] as? Int else { return nil }
			self = .recentOutlines(accountID)
		case "tagOutlines":
			guard let accountID = userInfo["accountID"] as? Int else { return nil }
			guard let tagID = userInfo["tagID"] as? String else { return nil }
			self = .tagOutlines(accountID, tagID)
		default:
			return nil
		}
	}
	
	public init?(url: URL) {
		guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
			  let accountIDString = urlComponents.queryItems?.first(where: { $0.name == "accountID" })?.value,
			  let accountID = Int(accountIDString),
			  let outlineUUID = urlComponents.queryItems?.first(where: { $0.name == "documentUUID" })?.value else {
			return nil
		}
		self = .outline(accountID, outlineUUID)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		switch self {
		case .account(let accountID):
			try container.encode("account", forKey: .type)
			try container.encode(accountID, forKey: .accountID)
		case .outline(let accountID, let outlineID):
			try container.encode("document", forKey: .type)
			try container.encode(accountID, forKey: .accountID)
			try container.encode(outlineID, forKey: .documentID)
		case .row(let accountID, let outlineID, let rowID):
			try container.encode("row", forKey: .type)
			try container.encode(accountID, forKey: .accountID)
			try container.encode(outlineID, forKey: .documentID)
			try container.encode(rowID, forKey: .rowID)
		case .image(let accountID, let outlineID, let rowID, let imageID):
			try container.encode("image", forKey: .type)
			try container.encode(accountID, forKey: .accountID)
			try container.encode(outlineID, forKey: .documentID)
			try container.encode(rowID, forKey: .rowID)
			try container.encode(imageID, forKey: .imageID)
		case .search(let searchText):
			try container.encode("search", forKey: .type)
			try container.encode(searchText, forKey: .searchText)
		case .allOutlines(let accountID):
			try container.encode("allOutlines", forKey: .type)
			try container.encode(accountID, forKey: .accountID)
		case .recentOutlines(let accountID):
			try container.encode("recentOutlines", forKey: .type)
			try container.encode(accountID, forKey: .accountID)
		case .tagOutlines(let accountID, let tagID):
			try container.encode("tagOutlines", forKey: .type)
			try container.encode(accountID, forKey: .accountID)
			try container.encode(tagID, forKey: .tagID)
		}
	}

}
