//
//  NSActivity+.swift
//  Zavala
//
//  Created by Maurice Parker on 3/18/21.
//

import Foundation

extension NSUserActivity {
	struct ActivityType {
		static let newWindow = "io.vincode.Zavala.newWindow"
		static let openEditor = "io.vincode.Zavala.openEditor"
		static let newOutline = "io.vincode.Zavala.newOutline"
		static let openQuickly = "io.vincode.Zavala.openQuickly"
		static let showAbout = "io.vincode.Zavala.showAbout"
		static let showSettings = "io.vincode.Zavala.showSettings"
		static let viewImage = "io.vincode.Zavala.viewImage"

		static let restoration = "io.vincode.Zavala.restoration"
		static let selectingOutlineContainer = "io.vincode.Zavala.selectingOutlineContainer"
		static let selectingOutline = "io.vincode.Zavala.selectingOutline"
	}
}
