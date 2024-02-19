//
//  RequestReview.swift
//  Zavala
//
//  Created by Maurice Parker on 1/10/24.
//

import UIKit
import StoreKit
import VinOutlineKit
import VinUtility

struct RequestReview {
	
	// Only prompt every 30 days if they have 10 active outlines and the app version is different
	static func request() {
		Task {
			let activeOutlinesCount = await Outliner.shared.activeOutlines.count
			
			if BuildInfo.shared.versionNumber != AppDefaults.shared.lastReviewPromptAppVersion &&
				Date().addingTimeInterval(-2592000) > AppDefaults.shared.lastReviewPromptDate ?? .distantPast &&
				activeOutlinesCount >= 10 {
				
				AppDefaults.shared.lastReviewPromptAppVersion = BuildInfo.shared.versionNumber
				AppDefaults.shared.lastReviewPromptDate = Date()
				
				guard let scene = await UIApplication.shared.foregroundActiveScene else { return }
				await SKStoreReviewController.requestReview(in: scene)
			}
		}
	}
	
}
