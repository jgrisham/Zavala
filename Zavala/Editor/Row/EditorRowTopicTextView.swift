//
//  EditorRowTopicTextView.swift
//  Zavala
//
//  Created by Maurice Parker on 11/17/20.
//

import UIKit
import VinOutlineKit

protocol EditorRowTopicTextViewDelegate: AnyObject {
	var editorRowTopicTextViewUndoManager: UndoManager? { get }
	var editorRowTopicTextViewInputAccessoryView: UIView? { get }
	func didBecomeActive(_: EditorRowTopicTextView, row: Row)
	func resize(_: EditorRowTopicTextView)
	func scrollEditorToVisible(_: EditorRowTopicTextView, rect: CGRect)
	func moveCursorUp(_: EditorRowTopicTextView, row: Row)
	func moveCursorDown(_: EditorRowTopicTextView, row: Row)
	func textChanged(_: EditorRowTopicTextView, row: Row, isInNotes: Bool, selection: NSRange, rowStrings: RowStrings)
	func deleteRow(_: EditorRowTopicTextView, row: Row, rowStrings: RowStrings)
	func createRow(_: EditorRowTopicTextView, beforeRow: Row)
	func createRow(_: EditorRowTopicTextView, afterRow: Row, rowStrings: RowStrings)
	func splitRow(_: EditorRowTopicTextView, row: Row, topic: NSAttributedString, cursorPosition: Int)
	func editLink(_: EditorRowTopicTextView, _ link: String?, text: String?, range: NSRange)
	func zoomImage(_: EditorRowTopicTextView, _ image: UIImage, rect: CGRect)
}

class EditorRowTopicTextView: EditorRowTextView {
	
	override var editorUndoManager: UndoManager? {
		return editorDelegate?.editorRowTopicTextViewUndoManager
	}
	
	override var keyCommands: [UIKeyCommand]? {
		let controlP = UIKeyCommand(input: "p", modifierFlags: [.control], action: #selector(moveCursorUp(_:)))
		controlP.wantsPriorityOverSystemBehavior = true

		let controlN = UIKeyCommand(input: "n", modifierFlags: [.control], action: #selector(moveCursorDown(_:)))
		controlN.wantsPriorityOverSystemBehavior = true

		let keys = [
			controlP,
			controlN,
			UIKeyCommand(input: "\t", modifierFlags: [.alternate], action: #selector(insertTab(_:))),
			UIKeyCommand(input: "\r", modifierFlags: [.alternate], action: #selector(insertNewline(_:))),
			UIKeyCommand(input: "\r", modifierFlags: [.shift], action: #selector(insertRow(_:))),
			UIKeyCommand(input: "\r", modifierFlags: [.shift, .alternate], action: #selector(split(_:))),
			toggleBoldCommand,
			toggleItalicsCommand,
			editLinkCommand
		]
		
		return keys
	}
	
	weak var editorDelegate: EditorRowTopicTextViewDelegate?
	
	override var rowStrings: RowStrings {
		return RowStrings.topic(cleansedAttributedText)
	}
	
	var cursorIsOnTopLine: Bool {
		guard let cursorRect else { return false }
		let lineStart = closestPosition(to: CGPoint(x: 0, y: cursorRect.midY))
		return lineStart == beginningOfDocument
	}
	
	var cursorIsOnBottomLine: Bool {
		guard let cursorRect else { return false }
		let lineEnd = closestPosition(to: CGPoint(x: bounds.maxX, y: cursorRect.midY))
		return lineEnd == endOfDocument
	}
	
	var cursorIsAtBeginning: Bool {
		return position(from: beginningOfDocument, offset: cursorPosition) == beginningOfDocument
	}
	
	var cursorIsAtEnd: Bool {
		return position(from: beginningOfDocument, offset: cursorPosition) == endOfDocument
	}
	
	override init(frame: CGRect, textContainer: NSTextContainer?) {
		super.init(frame: frame, textContainer: textContainer)
		self.delegate = self
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	@discardableResult
	override func becomeFirstResponder() -> Bool {
		inputAccessoryView = editorDelegate?.editorRowTopicTextViewInputAccessoryView
		let result = super.becomeFirstResponder()
		if result {
			didBecomeActive()
		}
		return result
	}
	
	func didBecomeActive() {
		if let row {
			editorDelegate?.didBecomeActive(self, row: row)
		}
	}
    
    override func textWasChanged() {
        guard let row else { return }
        editorDelegate?.textChanged(self, row: row, isInNotes: false, selection: selectedRange, rowStrings: rowStrings)
    }

	override func resize() {
		editorDelegate?.resize(self)
	}
	
    override func makeCursorVisibleIfNecessary() {
		guard let cursorRect else { return }
        editorDelegate?.scrollEditorToVisible(self, rect: cursorRect)
    }
    
	override func deleteBackward() {
		guard let row else { return }
		if attributedText.length == 0 && row.rowCount == 0 {
			editorDelegate?.deleteRow(self, row: row, rowStrings: rowStrings)
		} else {
			super.deleteBackward()
		}
	}

	@objc func createRow(_ sender: Any) {
		guard let row else { return }
		editorDelegate?.createRow(self, afterRow: row, rowStrings: rowStrings)
	}
	
	@objc func moveCursorUp(_ sender: Any) {
		guard let row else { return }
		editorDelegate?.moveCursorUp(self, row: row)
	}
	
	@objc func moveCursorDown(_ sender: Any) {
		guard let row else { return }
		editorDelegate?.moveCursorDown(self, row: row)
	}
	
	@objc func insertTab(_ sender: Any) {
		insertText("\t")
	}
	
	@objc func insertRow(_ sender: Any) {
		guard let row else { return }
		isSavingTextUnnecessary = true
		editorDelegate?.createRow(self, beforeRow: row)
	}

	@objc func split(_ sender: Any) {
		guard let row else { return }
		
		isSavingTextUnnecessary = true
		
		if cursorPosition == 0 {
			editorDelegate?.createRow(self, beforeRow: row)
		} else {
			editorDelegate?.splitRow(self, row: row, topic: attributedText, cursorPosition: cursorPosition)
		}
	}
	
	@objc override func editLink(_ sender: Any?) {
		let result = findAndSelectLink()
		editorDelegate?.editLink(self, result.0, text: result.1, range: result.2)
	}
	
	override func update(row: Row) {
		// Don't update the row if we are in the middle of entering multistage characters, e.g. Japanese
		guard markedTextRange == nil else { return }
		
		self.row = row
		
		updateTextPreferences()
		
		let cursorRange = selectedTextRange
		
		text = ""
		let fontColor = OutlineFontCache.shared.topicColor(level: row.trueLevel)
		baseAttributes = [NSAttributedString.Key : Any]()
		if row.isComplete ?? false || row.isAnyParentComplete {
			if fontColor.cgColor.alpha > 0.3 {
				baseAttributes[.foregroundColor] = fontColor.withAlphaComponent(0.3)
			} else {
				baseAttributes[.foregroundColor] = fontColor
			}
			accessibilityLabel = .completeAccessibilityLabel
		} else {
			baseAttributes[.foregroundColor] = OutlineFontCache.shared.topicColor(level: row.trueLevel)
			accessibilityLabel = nil
		}
		
		if row.isComplete ?? false {
			baseAttributes[.strikethroughStyle] = 1
			if fontColor.cgColor.alpha > 0.3 {
				baseAttributes[.strikethroughColor] = fontColor.withAlphaComponent(0.3)
			} else {
				baseAttributes[.strikethroughColor] = fontColor
			}
		} else {
			baseAttributes[.strikethroughStyle] = 0
		}
		
		baseAttributes[.font] = OutlineFontCache.shared.topicFont(level: row.trueLevel)
		
		typingAttributes = baseAttributes
		
		var linkAttrs = baseAttributes
		linkAttrs[.underlineStyle] = 1
		linkTextAttributes = linkAttrs
		
        if let topic = row.topic {
            attributedText = topic
        }
        
		addSearchHighlighting(isInNotes: false)
		
		selectedTextRange = cursorRange
    }
	
	override func scrollEditorToVisible(rect: CGRect) {
		editorDelegate?.scrollEditorToVisible(self, rect: rect)
	}
	
}

// MARK: CursorCoordinatesProvider

extension EditorRowTopicTextView: CursorCoordinatesProvider {

	var coordinates: CursorCoordinates? {
		if let row {
			return CursorCoordinates(row: row, isInNotes: false, selection: selectedRange)
		}
		return nil
	}

}

// MARK: UITextViewDelegate

extension EditorRowTopicTextView: UITextViewDelegate {
	
	func textViewDidBeginEditing(_ textView: UITextView) {
		processTextEditingBegin()
	}
	
	func textViewDidEndEditing(_ textView: UITextView) {
        processTextEditingEnding()
	}
	
	func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
		guard let row else { return true }
		
		switch text {
		case "\n":
			editorDelegate?.createRow(self, afterRow: row, rowStrings: rowStrings)
			return false
		default:
			return true
		}
	}
	
    func textViewDidChange(_ textView: UITextView) {
        processTextChanges()
    }
    
	func textView(_ textView: UITextView, shouldInteractWith textAttachment: NSTextAttachment, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
		guard interaction == .invokeDefaultAction,
			  let firstRect = firstRect(for: characterRange),
			  let image = textAttachment.image	else { return true }
		
		let convertedRect = convert(firstRect, to: nil)
		editorDelegate?.zoomImage(self, image, rect: convertedRect)
		return false
	}
	
	func textViewDidChangeSelection(_ textView: UITextView) {
		handleDidChangeSelection()
	}

}
