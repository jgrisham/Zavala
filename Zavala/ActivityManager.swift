//
//  ActivityManager.swift
//  Zavala
//
//  Created by Maurice Parker on 11/13/20.
//

import UIKit
import CoreSpotlight
import CoreServices
import VinOutlineKit

class ActivityManager {
	
	private var selectOutlineContainerActivity: NSUserActivity?
	private var selectOutlineActivity: NSUserActivity?
    private var selectOutlineContainers: [OutlineContainer]?
    private var selectOutline: Outline?

	var stateRestorationActivity: NSUserActivity {
		if let activity = selectOutlineActivity {
			return activity
		}
		
		if let activity = selectOutlineContainerActivity {
			return activity
		}
		
		let activity = NSUserActivity(activityType: NSUserActivity.ActivityType.restoration)
		activity.persistentIdentifier = UUID().uuidString
		activity.becomeCurrent()
		return activity
	}
	
	init() {
		NotificationCenter.default.addObserver(self, selector: #selector(outlineDidDelete(_:)), name: .OutlineDidDelete, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(outlineTitleDidChange(_:)), name: .OutlineTitleDidChange, object: nil)
	}
    
    func selectingOutlineContainers(_ containers: [OutlineContainer]) {
        self.invalidateSelectOutlineContainers()
        self.selectOutlineContainerActivity = self.makeSelectOutlineContainerActivity(containers)
        self.selectOutlineContainerActivity!.becomeCurrent()
    }
    
    func invalidateSelectOutlineContainers() {
        invalidateSelectOutline()
        selectOutlineContainerActivity?.invalidate()
        selectOutlineContainerActivity = nil
    }

	func selectingOutline(_ outlineContainers: [OutlineContainer]?, _ outline: Outline) async {
		self.invalidateSelectOutline()
		self.selectOutlineActivity = await self.makeSelectOutlineActivity(outlineContainers, outline)
		self.selectOutlineActivity!.becomeCurrent()
        self.selectOutlineContainers = outlineContainers
        self.selectOutline = outline
	}
	
	func invalidateSelectOutline() {
		selectOutlineActivity?.invalidate()
		selectOutlineActivity = nil
        selectOutlineContainers = nil
        selectOutline = nil
	}

}

// MARK: Helpers

private extension ActivityManager {

	@objc func outlineDidDelete(_ note: Notification) {
		guard let outline = note.object as? Outline else { return }
		CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [outline.id.description])
	}
	
	@objc func outlineTitleDidChange(_ note: Notification) {
		guard let outline = note.object as? Outline, outline == selectOutline else { return }
		Task { @MainActor in
			await selectingOutline(selectOutlineContainers, outline)
		}
	}
	
	func makeSelectOutlineContainerActivity(_ outlineContainers: [OutlineContainer]) -> NSUserActivity {
		let activity = NSUserActivity(activityType: NSUserActivity.ActivityType.selectingOutlineContainer)
		
		let title = String.seeOutlinesInPrompt(outlineContainerTitle: outlineContainers.title)
		activity.title = title
		
		activity.userInfo = [Pin.UserInfoKeys.pin: Pin(containers: outlineContainers).userInfo]
		activity.requiredUserInfoKeys = Set(activity.userInfo!.keys.map { $0 as! String })
		
		return activity
	}
	
	func makeSelectOutlineActivity(_ outlineContainers: [OutlineContainer]?, _ outline: Outline) async -> NSUserActivity {
		let activity = NSUserActivity(activityType: NSUserActivity.ActivityType.selectingOutline)

		let title = String.editOutlinePrompt(outlineTitle: outline.title ?? "")
		activity.title = title
		
		activity.userInfo = [Pin.UserInfoKeys.pin: Pin(containers: outlineContainers, outline: outline).userInfo]
		activity.requiredUserInfoKeys = Set(activity.userInfo!.keys.map { $0 as! String })
		
		let keywords = await outline.tags.map({ $0.name })
		activity.keywords = Set(keywords)

		activity.isEligibleForSearch = true
		activity.isEligibleForPrediction = true
		
		if await outline.account?.type == .cloudKit {
			activity.isEligibleForHandoff = true
		}

		activity.persistentIdentifier = outline.id.description
		
		return activity
	}
	
}
