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
	
	public let containers: [DocumentContainer]?
	public let document: Document?
	
	public var userInfo: [AnyHashable: AnyHashable] {
		let containerIDs = containers?.map({ $0.id })
		let documentID = document?.id
		return Self.userInfo(containerIDs: containerIDs, documentID: documentID)
	}
	
	public init(containers: [DocumentContainer]? = nil, document: Document? = nil) {
        self.containers = containers
		self.document = document
	}

	public init(userInfo: Any?) async {
		guard let userInfo = userInfo as? [AnyHashable: AnyHashable] else {
			self.containers = nil
			self.document = nil
			return
		}
		
		if let userInfos = userInfo["containerIDs"] as? [[AnyHashable : AnyHashable]] {
            let containerIDs = userInfos.compactMap { EntityID(userInfo: $0) }
			containers = await AccountManager.shared.findDocumentContainers(containerIDs)
		} else {
			self.containers = nil
		}
		
		if let userInfo = userInfo["documentID"] as? [AnyHashable : AnyHashable] {
			if let documentID = EntityID(userInfo: userInfo) {
				self.document = await AccountManager.shared.findDocument(documentID)
			} else {
				self.document = nil
			}
		} else {
			self.document = nil
		}
	}
	
	public static func userInfo(containerIDs: [EntityID]? = nil, documentID: EntityID? = nil) -> [AnyHashable: AnyHashable] {
		var userInfo = [AnyHashable: AnyHashable]()
		if let containerIDs {
			userInfo["containerIDs"] = containerIDs.map { $0.userInfo }
		}
		if let documentID {
			userInfo["documentID"] = documentID.userInfo
		}
		return userInfo
	}
	
	public static func == (lhs: Pin, rhs: Pin) -> Bool {
		guard lhs.document == rhs.document else {
			return false
		}
		
		let lhsContainerIDs = lhs.containers?.map { $0.id }
		let rhsContainerIDs = rhs.containers?.map { $0.id }
		
		return lhsContainerIDs == rhsContainerIDs
	}

}
