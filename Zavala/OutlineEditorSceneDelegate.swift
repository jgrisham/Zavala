//
//  OutlineEditorSceneDelegate.swift
//  Zavala
//
//  Created by Maurice Parker on 3/17/21.
//

import UIKit
import CloudKit
import VinOutlineKit

class OutlineEditorSceneDelegate: UIResponder, UIWindowSceneDelegate {

	weak var scene: UIScene?
	weak var session: UISceneSession?
	var window: UIWindow?
	var editorContainerViewController: EditorContainerViewController!
	
	func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
		self.scene = scene
		self.session = session
		
		guard let editorContainerViewController = window?.rootViewController as? EditorContainerViewController else {
			return
		}

		updateUserInterfaceStyle()
		NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsDidChange), name: UserDefaults.didChangeNotification, object: nil)
		
		self.editorContainerViewController = editorContainerViewController
		self.editorContainerViewController.sceneDelegate = self
		
		#if targetEnvironment(macCatalyst)
		guard let windowScene = scene as? UIWindowScene else { return }
		
		let toolbar = NSToolbar(identifier: "editor")
		toolbar.delegate = editorContainerViewController
		toolbar.displayMode = .iconOnly
		toolbar.allowsUserCustomization = true
		toolbar.autosavesConfiguration = true
		
		if let titlebar = windowScene.titlebar {
			titlebar.toolbar = toolbar
			titlebar.toolbarStyle = .unified
		}
		
		#endif

		let _ = editorContainerViewController.view
		
		Task {
			if let userActivity = session.stateRestorationActivity {
				await editorContainerViewController.handle(userActivity)
				return
			}

			if let userActivity = connectionOptions.userActivities.first {
				await editorContainerViewController.handle(userActivity)
				if let windowFrame = window?.frame {
					window?.frame = CGRect(x: windowFrame.origin.x, y: windowFrame.origin.y, width: 700, height: 600)
				}
				return
			}
			
			if let url = connectionOptions.urlContexts.first?.url, let outlineID = EntityID(url: url) {
				await editorContainerViewController.openOutline(outlineID)
				if let windowFrame = window?.frame {
					window?.frame = CGRect(x: windowFrame.origin.x, y: windowFrame.origin.y, width: 700, height: 600)
				}
			}
			
			closeWindow()
			let activity = NSUserActivity(activityType: NSUserActivity.ActivityType.openQuickly)
			UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil, errorHandler: nil)
		}
	}

	func sceneDidDisconnect(_ scene: UIScene) {
		editorContainerViewController.shutdown()
	}
	
	func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
		return editorContainerViewController.stateRestorationActivity
	}
	
	private func scene(_ scene: UIScene, continue userActivity: NSUserActivity) async {
		Task {
			await editorContainerViewController.handle(userActivity)
		}
	}
	
	func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
		if let url = urlContexts.first?.url, let outlineID = EntityID(url: url) {
		
			if let scene =  UIApplication.shared.connectedScenes.first(where: {
				(($0 as? UIWindowScene)?.keyWindow?.rootViewController as? MainCoordinator)?.selectedOutlines.first?.id == outlineID
			}) {
				
				UIApplication.shared.requestSceneSessionActivation(scene.session, userActivity: nil, options: nil, errorHandler: nil)
				
			} else {
				
				let activity = NSUserActivity(activityType: NSUserActivity.ActivityType.openEditor)
				activity.userInfo = [Pin.UserInfoKeys.pin: Pin.userInfo(outlineID: outlineID)]
				UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil, errorHandler: nil)
				
			}
		}
		
	}
	
	func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith shareMetadata: CKShare.Metadata) {
		Task {
			await Outliner.shared.cloudKitAccount?.userDidAcceptCloudKitShareWith(shareMetadata)
		}
	}
	
	// MARK: API
	
	func closeWindow() {
		guard let session else { return }
		UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
	}
	
	func validateToolbar() {
		#if targetEnvironment(macCatalyst)
		guard let windowScene = scene as? UIWindowScene else { return }
		windowScene.titlebar?.toolbar?.visibleItems?.forEach({ $0.validate() })
		#endif
	}
	
}

private extension OutlineEditorSceneDelegate {
	
	@objc func userDefaultsDidChange() {
		updateUserInterfaceStyle()
	}

}
