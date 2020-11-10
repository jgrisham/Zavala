//
//  AppDelegate.swift
//  Manhattan
//
//  Created by Maurice Parker on 11/5/20.
//

import UIKit
import Templeton

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
	
	var mainSplitViewController: MainSplitViewController? {
		var keyScene: UIScene?
		let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
		
		for windowScene in windowScenes {
			if !windowScene.windows.filter({ $0.isKeyWindow }).isEmpty {
				keyScene = windowScene
			}
		}
		
		return (keyScene?.delegate as? SceneDelegate)?.mainSplitViewController
	}

	func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
		let documentAccountURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
		let documentAccountsFolder = documentAccountURL.appendingPathComponent("Accounts").absoluteString
		let documentAccountsFolderPath = String(documentAccountsFolder.suffix(from: documentAccountsFolder.index(documentAccountsFolder.startIndex, offsetBy: 7)))
		AccountManager.shared = AccountManager(accountsFolderPath: documentAccountsFolderPath)
		return true
	}
	
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		// Override point for customization after application launch.
		return true
	}

	// MARK: UISceneSession Lifecycle

	func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
		return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
	}

	// MARK: Actions

	@objc func newWindow(_ sender: Any?) {
		let userActivity = NSUserActivity(activityType: "io.vincode.Manhattan.create")
		UIApplication.shared.requestSceneSessionActivation(nil, userActivity: userActivity, options: nil, errorHandler: nil)
	}
	
	@objc func createFolder(_ sender: Any?) {
		mainSplitViewController?.createFolder(sender)
	}
	
	@objc func createOutline(_ sender: Any?) {
		mainSplitViewController?.createOutline(sender)
	}
	
	@objc func toggleOutlineIsFavorite(_ sender: Any?) {
		mainSplitViewController?.toggleOutlineIsFavorite(sender)
	}
	
	override func buildMenu(with builder: UIMenuBuilder) {
		super.buildMenu(with: builder)
		guard builder.system == UIMenuSystem.main else { return }
		
		builder.remove(menu: .newScene)

		// File Menu
		let newWindowCommand = UIKeyCommand(title: NSLocalizedString("New Window", comment: "New Window"),
											action: #selector(newWindow(_:)),
											input: "n",
											modifierFlags: [.alternate, .command])
		let newWindowMenu = UIMenu(title: "", options: .displayInline, children: [newWindowCommand])
		builder.insertChild(newWindowMenu, atStartOfMenu: .file)

		let newOutlineCommand = UIKeyCommand(title: NSLocalizedString("New Outline", comment: "New Outline"),
											action: #selector(createOutline(_:)),
											input: "n",
											modifierFlags: [.command])
		let newFolderCommand = UIKeyCommand(title: NSLocalizedString("New Folder", comment: "New Folder"),
											action: #selector(createFolder(_:)),
											input: "n",
											modifierFlags: [.shift, .command])
		let newItemsMenu = UIMenu(title: "", options: .displayInline, children: [newOutlineCommand, newFolderCommand])
		builder.insertChild(newItemsMenu, atStartOfMenu: .file)

	}
	
}

