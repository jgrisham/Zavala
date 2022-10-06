//
//  PreferencesWindowController.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 8/1/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import AppKit

private struct PreferencesToolbarItemSpec {

	let identifier: NSToolbarItem.Identifier
	let name: String
	let image: NSImage?
	
	init(identifierRawValue: String, name: String, image: NSImage?) {
		self.identifier = NSToolbarItem.Identifier(identifierRawValue)
		self.name = name
		self.image = image
	}
}

private struct ToolbarItemIdentifier {
	static let General = "General"
	static let Font = "Font"
}

class PreferencesWindowController : NSWindowController, NSToolbarDelegate {
	
	private let windowWidth = CGFloat(450.0) // Width is constant for all views; only the height changes
	private var viewControllers = [String: NSViewController]()
	private let toolbarItemSpecs: [PreferencesToolbarItemSpec] = {
		var specs = [PreferencesToolbarItemSpec]()
		specs += [PreferencesToolbarItemSpec(identifierRawValue: ToolbarItemIdentifier.General,
											 name: L10n.general,
											 image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)!)]
		specs += [PreferencesToolbarItemSpec(identifierRawValue: ToolbarItemIdentifier.Font,
											 name: L10n.fontsAndColors,
											 image: NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)!)]
		return specs
	}()

	override func windowDidLoad() {
		let toolbar = NSToolbar(identifier: NSToolbar.Identifier("PreferencesToolbar"))
		toolbar.delegate = self
		toolbar.autosavesConfiguration = false
		toolbar.allowsUserCustomization = false
		toolbar.displayMode = .iconAndLabel
		toolbar.selectedItemIdentifier = toolbarItemSpecs.first!.identifier

		window?.showsToolbarButton = false
		window?.toolbar = toolbar
		
		updateAppearance()
		switchToViewAtIndex(0)

		window?.center()
		
		NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsDidChange), name: UserDefaults.didChangeNotification, object: nil)
	}

	// MARK: Actions

	@objc func toolbarItemClicked(_ sender: Any?) {
		guard let toolbarItem = sender as? NSToolbarItem else {
			return
		}
		switchToView(identifier: toolbarItem.itemIdentifier.rawValue)
	}

	// MARK: NSToolbarDelegate

	func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {

		guard let toolbarItemSpec = toolbarItemSpecs.first(where: { $0.identifier.rawValue == itemIdentifier.rawValue }) else {
			return nil
		}

		let toolbarItem = NSToolbarItem(itemIdentifier: toolbarItemSpec.identifier)
		toolbarItem.action = #selector(toolbarItemClicked(_:))
		toolbarItem.target = self
		toolbarItem.label = toolbarItemSpec.name
		toolbarItem.paletteLabel = toolbarItem.label
		toolbarItem.image = toolbarItemSpec.image

		return toolbarItem
	}

	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		return toolbarItemSpecs.map { $0.identifier }
	}

	func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		return toolbarDefaultItemIdentifiers(toolbar)
	}

	func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		return toolbarDefaultItemIdentifiers(toolbar)
	}
}

private extension PreferencesWindowController {

	var currentView: NSView? {
		return window?.contentView?.subviews.first
	}
	
	@objc func userDefaultsDidChange() {
		updateAppearance()
	}
	
	func updateAppearance() {
		switch AppDefaults.shared.userInterfaceColorPalette {
		case .light:
			window?.appearance = NSAppearance(named: .aqua)
		case .dark:
			window?.appearance = NSAppearance(named: .darkAqua)
		default:
			window?.appearance = nil
		}
	}

	func toolbarItemSpec(for identifier: String) -> PreferencesToolbarItemSpec? {
		return toolbarItemSpecs.first(where: { $0.identifier.rawValue == identifier })
	}

	func switchToViewAtIndex(_ index: Int) {
		let identifier = toolbarItemSpecs[index].identifier
		switchToView(identifier: identifier.rawValue)
	}

	func switchToView(identifier: String) {
		guard let toolbarItemSpec = toolbarItemSpec(for: identifier) else {
			assertionFailure("Preferences window: no toolbarItemSpec matching \(identifier).")
			return
		}

		guard let newViewController = viewController(identifier: identifier) else {
			assertionFailure("Preferences window: no view controller matching \(identifier).")
			return
		}
		
		if newViewController.view == currentView {
			return
		}

		newViewController.view.nextResponder = newViewController
		newViewController.nextResponder = window!.contentView

		window!.title = toolbarItemSpec.name

		resizeWindow(toFitView: newViewController.view)

		if let currentView {
			window!.contentView?.replaceSubview(currentView, with: newViewController.view)
		}
		else {
			window!.contentView?.addSubview(newViewController.view)
		}

		window!.makeFirstResponder(newViewController.view)
	}

	func viewController(identifier: String) -> NSViewController? {
		if let cachedViewController = viewControllers[identifier] {
			return cachedViewController
		}

		let bundle = Bundle(for: type(of: self))
		let storyboard = NSStoryboard(name: NSStoryboard.Name("Preferences"), bundle: bundle)
		guard let viewController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(identifier)) as? NSViewController else {
			assertionFailure("Unknown preferences view controller: \(identifier)")
			return nil
		}

		viewControllers[identifier] = viewController
		return viewController
	}

	func resizeWindow(toFitView view: NSView) {
		let viewFrame = view.frame
		let windowFrame = window!.frame
		let contentViewFrame = window!.contentView!.frame
		
		let deltaHeight = NSHeight(contentViewFrame) - NSHeight(viewFrame)
		let heightForWindow = NSHeight(windowFrame) - deltaHeight
		let windowOriginY = NSMinY(windowFrame) + deltaHeight
		
		var updatedWindowFrame = windowFrame
		updatedWindowFrame.size.height = heightForWindow
		updatedWindowFrame.origin.y = windowOriginY
		updatedWindowFrame.size.width = windowWidth //NSWidth(viewFrame)
		
		var updatedViewFrame = viewFrame
		updatedViewFrame.origin = NSZeroPoint
		updatedViewFrame.size.width = windowWidth
		if viewFrame != updatedViewFrame {
			view.frame = updatedViewFrame
		}
		
		if windowFrame != updatedWindowFrame {
			window!.contentView?.alphaValue = 0.0
			window!.setFrame(updatedWindowFrame, display: true, animate: true)
			window!.contentView?.alphaValue = 1.0
		}
	}
}
