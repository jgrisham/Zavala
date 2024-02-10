//
//  Pin.swift
//
//  Created by Maurice Parker on 11/3/21.
//

import Foundation

public extension Notification.Name {
	static let PinWasVisited = Notification.Name(rawValue: "PinWasVisited")
}

public struct Pin: Equatable {
	
	public struct UserInfoKeys {
		public static let pin = "pin"
	}
	
	public let containerIDs: [EntityID]?
	public let documentID: EntityID?
	
	public var containers: [DocumentContainer] {
		get async {
			if let containerIDs {
				return await AccountManager.shared.findDocumentContainers(containerIDs)
			}

			if let documentID, let container = await AccountManager.shared.findDocumentContainer(.allDocuments(documentID.accountID)) {
				return [container]
			}
		
			return []
		}
	}
	
	public var document: Document? {
		get async {
			guard let documentID else { return nil }
			return await AccountManager.shared.findDocument(documentID)
		}
	}
	
	public var userInfo: [AnyHashable: AnyHashable] {
		var userInfo = [AnyHashable: AnyHashable]()
		if let containerIDs {
            userInfo["containerIDs"] = containerIDs.map { $0.userInfo }
		}
		if let documentID {
			userInfo["documentID"] = documentID.userInfo
		}
		return userInfo
	}
	
	public init(containerIDs: [EntityID]? = nil, documentID: EntityID? = nil) {
		self.containerIDs = containerIDs
		self.documentID = documentID
	}

	public init(containers: [DocumentContainer]? = nil, document: Document? = nil) {
        self.containerIDs = containers?.map { $0.id }
		self.documentID = document?.id
	}

	public init(userInfo: Any?) {
		guard let userInfo = userInfo as? [AnyHashable: AnyHashable] else {
			self.containerIDs = nil
			self.documentID = nil
			return
		}
		
		if let userInfos = userInfo["containerIDs"] as? [[AnyHashable : AnyHashable]] {
            self.containerIDs = userInfos.compactMap { EntityID(userInfo: $0) }
		} else {
			self.containerIDs = nil
		}
		
		if let userInfo = userInfo["documentID"] as? [AnyHashable : AnyHashable] {
			self.documentID = EntityID(userInfo: userInfo)
		} else {
			self.documentID = nil
		}
	}
	
}
