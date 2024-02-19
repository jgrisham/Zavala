//
//  Created by Maurice Parker on 11/16/22.
//

import UIKit
import VinOutlineKit

class CopyOutlineLinkActivity: UIActivity {
	
	private let outlines: [Outline]
	
	init(outlines: [Outline]) {
		self.outlines = outlines
	}
	
	override var activityTitle: String? {
		if outlines.count > 1 {
			return .copyOutlineLinksControlLabel
		} else {
			return .copyOutlineLinkControlLabel
		}
	}
	
	override var activityType: UIActivity.ActivityType? {
		UIActivity.ActivityType(rawValue: "io.vincode.Zavala.copyOutlineLink")
	}
	
	override var activityImage: UIImage? {
		.link
	}
	
	override class var activityCategory: UIActivity.Category {
		.action
	}
	
	override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
		true
	}
	
	override func prepare(withActivityItems activityItems: [Any]) {
		
	}
	
	override func perform() {
		UIPasteboard.general.strings = outlines.compactMap { $0.id.url?.absoluteString }
		activityDidFinish(true)
	}
}
