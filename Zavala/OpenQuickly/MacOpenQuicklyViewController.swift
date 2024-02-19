//
//  MacOpenQuicklyViewController.swift
//  Zavala
//
//  Created by Maurice Parker on 3/19/21.
//

import UIKit
import VinOutlineKit

class MacOpenQuicklyViewController: UIViewController {

	@IBOutlet weak var searchTextField: SearchTextField!
	@IBOutlet weak var openButton: UIButton!
	
	weak var sceneDelegate: MacOpenQuicklySceneDelegate?

	override var keyCommands: [UIKeyCommand]? {
		[
			UIKeyCommand(action: #selector(arrowUp(_:)), input: UIKeyCommand.inputUpArrow),
			UIKeyCommand(action: #selector(arrowDown(_:)), input: UIKeyCommand.inputDownArrow),
			UIKeyCommand(action: #selector(cancel(_:)), input: UIKeyCommand.inputEscape)
		]
	}

	private var collectionsViewController: MacOpenQuicklyCollectionsViewController? {
		return children.first(where: { $0 is MacOpenQuicklyCollectionsViewController }) as? MacOpenQuicklyCollectionsViewController
	}
	
	private var listViewController: MacOpenQuicklyListViewController? {
		return children.first(where: { $0 is MacOpenQuicklyListViewController }) as? MacOpenQuicklyListViewController
	}

	private var selectedOutlineID: EntityID?

    override func viewDidLoad() {
        super.viewDidLoad()
		
		collectionsViewController?.delegate = self
		listViewController?.delegate = self

		searchTextField.delegate = self
		searchTextField.layer.borderWidth = 1
		searchTextField.layer.borderColor = UIColor.systemGray2.cgColor
		searchTextField.layer.cornerRadius = 3
		
		searchTextField.itemSelectionHandler = { [weak self] (filteredResults: [SearchTextFieldItem], index: Int) in
			guard let self, let outlineID = filteredResults[index].associatedObject as? EntityID else {
				return
			}
			self.openOutline(outlineID)
		}

		Task {
			let searchItems = await Outliner.shared.activeOutlines.map { SearchTextFieldItem(title: $0.title ?? "", associatedObject: $0.id) }
			searchTextField.filterItems(searchItems)
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		#if targetEnvironment(macCatalyst)
		appDelegate.appKitPlugin?.configureOpenQuickly(view.window?.nsWindow)
		#endif
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
			self.searchTextField.becomeFirstResponder()
		}
	}
	
	@objc func arrowUp(_ sender: Any) {
		searchTextField.selectAbove()
	}

	@objc func arrowDown(_ sender: Any) {
		searchTextField.selectBelow()
	}

	@IBAction func newOutline(_ sender: Any) {
		sceneDelegate?.closeWindow()
		let activity = NSUserActivity(activityType: NSUserActivity.ActivityType.newOutline)
		UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil, errorHandler: nil)
	}
	
	@IBAction func cancel(_ sender: Any) {
		sceneDelegate?.closeWindow()
	}
	
	@IBAction func submit(_ sender: Any) {
		guard let outlineID = selectedOutlineID else { return }
		openOutline(outlineID)
	}
	
}

// MARK: UITextFieldDelegate

extension MacOpenQuicklyViewController: UITextFieldDelegate {
	
	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		searchTextField.activateSelection()
		return false
	}
	
}

// MARK: MacOpenQuicklyCollectionsDelegate

extension MacOpenQuicklyViewController: MacOpenQuicklyCollectionsDelegate {
	
	func outlineContainerSelectionsDidChange(_: MacOpenQuicklyCollectionsViewController, outlineContainers: [OutlineContainer]) {
		listViewController?.setOutlineContainers(outlineContainers)
	}
	
}

// MARK: MacOpenQuicklyListDelegate

extension MacOpenQuicklyViewController: MacOpenQuicklyListDelegate {
	
	func outlineSelectionDidChange(_: MacOpenQuicklyListViewController, outlineID: EntityID?) {
		selectedOutlineID = outlineID
		updateUI()
	}
	
	func openOutline(_: MacOpenQuicklyListViewController, outlineID: EntityID) {
		openOutline(outlineID)
	}
	
}

// MARK: Helpers

private extension MacOpenQuicklyViewController {
	
	func updateUI() {
		openButton.isEnabled = selectedOutlineID != nil
	}
	
	func openOutline(_ outlineID: EntityID) {
		self.sceneDelegate?.closeWindow()
		let activity = NSUserActivity(activityType: NSUserActivity.ActivityType.openEditor)
		activity.userInfo = [Pin.UserInfoKeys.pin: Pin.userInfo(outlineID: outlineID)]
		UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil, errorHandler: nil)
	}
	
}
