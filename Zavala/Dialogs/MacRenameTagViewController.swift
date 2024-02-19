//
//  MacRenameTagViewController.swift
//  Zavala
//
//  Created by Maurice Parker on 10/10/21.
//

import UIKit
import VinOutlineKit

class MacRenameTagViewController: MacFormViewController {
	
	var tagOutlines: TagOutlines?
	
	@IBOutlet weak var tagNameTextField: UITextField!
	@IBOutlet weak var renameButton: UIButton!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		tagNameTextField.delegate = self
		tagNameTextField.text = tagOutlines?.name
		
		renameButton.role = .primary
		NotificationCenter.default.addObserver(self, selector: #selector(textDidChange(_:)), name: UITextField.textDidChangeNotification, object: tagNameTextField)
		updateUI()
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		tagNameTextField.becomeFirstResponder()
	}
	
	@IBAction func submit(_ sender: Any) {
		submitAndDismiss()
	}
	
}

// MARK: UITextFieldDelegate

extension MacRenameTagViewController: UITextFieldDelegate {
	
	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		submitAndDismiss()
		return false
	}
	
}

// MARK: Helpers

private extension MacRenameTagViewController {
	
	@objc func textDidChange(_ note: Notification) {
		updateUI()
	}
	
	func updateUI() {
		renameButton.isEnabled = !(tagNameTextField.text?.isEmpty ?? true)
	}
	
	func submitAndDismiss() {
		guard let tagName = tagNameTextField.text, let tag = tagOutlines?.tag else { return }
		tagOutlines?.account?.renameTag(tag, to: tagName)
		dismiss(animated: true)
	}

}
