//
//  SceneDelegate.swift
//  Zavala
//
//  Created by Maurice Parker on 11/5/20.
//

import UIKit
import CloudKit
import VinOutlineKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

	weak var scene: UIScene?
	var window: UIWindow?
	var mainSplitViewController: MainSplitViewController!
	
	func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
		self.scene = scene
		
		guard let mainSplitViewController = window?.rootViewController as? MainSplitViewController else {
			return
		}
		
		updateUserInterfaceStyle()
		NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsDidChange), name: UserDefaults.didChangeNotification, object: nil)
		
		AppDefaults.shared.lastMainWindowWasClosed = false
		
		self.mainSplitViewController = mainSplitViewController
		self.mainSplitViewController.sceneDelegate = self
		self.mainSplitViewController.showsSecondaryOnlyButton = true

		#if targetEnvironment(macCatalyst)
		guard let windowScene = scene as? UIWindowScene else { return }
		
		let toolbar = NSToolbar(identifier: "main")
		toolbar.delegate = mainSplitViewController
		toolbar.displayMode = .iconOnly
		toolbar.allowsUserCustomization = true
		toolbar.autosavesConfiguration = true
		
		if let titlebar = windowScene.titlebar {
			titlebar.titleVisibility = .hidden
			titlebar.toolbar = toolbar
			titlebar.toolbarStyle = .unified
		}

		// If we let the user shrink the window down too small, the collection view will crash itself with a
		// no selector found error on an internal Apple API
		windowScene.sizeRestrictions?.minimumSize = CGSize(width: 800, height: 600)
		
		#endif

		Task {
			await mainSplitViewController.startUp()
			
			if let shareMetadata = connectionOptions.cloudKitShareMetadata {
				await acceptShare(shareMetadata)
				return
			}

			if let userActivity = connectionOptions.userActivities.first ?? session.stateRestorationActivity {
				await mainSplitViewController.handle(userActivity, isNavigationBranch: true)
				return
			}
			
			if let url = connectionOptions.urlContexts.first?.url, let outlineID = EntityID(url: url) {
				await mainSplitViewController.handleOutline(outlineID, isNavigationBranch: true)
				return
			}
			
			if let userInfo = AppDefaults.shared.lastMainWindowState {
				await mainSplitViewController.handle(userInfo, isNavigationBranch: true)
				AppDefaults.shared.lastMainWindowState = nil
			}
		}
	}
	
	func sceneDidDisconnect(_ scene: UIScene) {
		if UIApplication.shared.applicationState == .active {
			if let windows = (scene as? UIWindowScene)?.windows {
				if windows.contains(where: { $0.rootViewController is MainSplitViewController }) {
					AppDefaults.shared.lastMainWindowWasClosed = true
					AppDefaults.shared.lastMainWindowState = mainSplitViewController.stateRestorationActivity.userInfo
				}
			}
		}
	}

	func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
		return mainSplitViewController.stateRestorationActivity
	}
	
	func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
		Task {
			await mainSplitViewController.handle(userActivity, isNavigationBranch: true)
		}
	}
	
	func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
		if let url = urlContexts.first?.url, let outlineID = EntityID(url: url) {
			Task {
				await mainSplitViewController.handleOutline(outlineID, isNavigationBranch: true)
			}
			return
		}
		
		let opmlURLs = urlContexts.filter({ $0.url.pathExtension == DataRepresentation.opml.suffix }).map({ $0.url })
		mainSplitViewController.importOPMLs(urls: opmlURLs)
		
		#if targetEnvironment(macCatalyst)
		DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
			appDelegate.appKitPlugin?.clearRecentDocuments()
		}
		#endif
	}
	
	func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith shareMetadata: CKShare.Metadata) {
		Task {
			await acceptShare(shareMetadata)
		}
	}
	
	// MARK: API
	
	func validateToolbar() {
		#if targetEnvironment(macCatalyst)
		guard let windowScene = scene as? UIWindowScene else { return }
		windowScene.titlebar?.toolbar?.visibleItems?.forEach({ $0.validate() })
		#endif
	}
	
}

private extension SceneDelegate {
	
	@objc func userDefaultsDidChange() {
		updateUserInterfaceStyle()
	}

	func acceptShare(_ shareMetadata: CKShare.Metadata) async {
		await Outliner.shared.cloudKitAccount?.userDidAcceptCloudKitShareWith(shareMetadata)
		if let outlineID = await Outliner.shared.cloudKitAccount?.findOutline(shareRecordID: shareMetadata.share.recordID)?.id {
			await mainSplitViewController.handleOutline(outlineID, isNavigationBranch: true)
		}
	}
	
}
