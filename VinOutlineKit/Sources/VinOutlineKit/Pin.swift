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
	
	public let containers: [OutlineContainer]?
	public let outline: Outline?
	
	public var userInfo: [AnyHashable: AnyHashable] {
		let containerIDs = containers?.map({ $0.id })
		let outlineID = outline?.id
		return Self.userInfo(containerIDs: containerIDs, outlineID: outlineID)
	}
	
	public init(containers: [OutlineContainer]? = nil, outline: Outline? = nil) {
        self.containers = containers
		self.outline = outline
	}

	public init(userInfo: Any?) async {
		guard let userInfo = userInfo as? [AnyHashable: AnyHashable] else {
			self.containers = nil
			self.outline = nil
			return
		}
		
		if let userInfos = userInfo["containerIDs"] as? [[AnyHashable : AnyHashable]] {
            let containerIDs = userInfos.compactMap { EntityID(userInfo: $0) }
			containers = await Outliner.shared.findOutlineContainers(containerIDs)
		} else {
			self.containers = nil
		}
		
		if let userInfo = userInfo["documentID"] as? [AnyHashable : AnyHashable] {
			if let outlineID = EntityID(userInfo: userInfo) {
				self.outline = await Outliner.shared.findOutline(outlineID)
			} else {
				self.outline = nil
			}
		} else {
			self.outline = nil
		}
	}
	
	public static func userInfo(containerIDs: [EntityID]? = nil, outlineID: EntityID? = nil) -> [AnyHashable: AnyHashable] {
		var userInfo = [AnyHashable: AnyHashable]()
		if let containerIDs {
			userInfo["containerIDs"] = containerIDs.map { $0.userInfo }
		}
		if let outlineID {
			userInfo["documentID"] = outlineID.userInfo
		}
		return userInfo
	}
	
	public static func == (lhs: Pin, rhs: Pin) -> Bool {
		guard lhs.outline == rhs.outline else {
			return false
		}
		
		let lhsContainerIDs = lhs.containers?.map { $0.id }
		let rhsContainerIDs = rhs.containers?.map { $0.id }
		
		return lhsContainerIDs == rhsContainerIDs
	}

}
