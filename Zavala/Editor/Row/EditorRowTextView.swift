//
//  EditorRowTextView.swift
//  Zavala
//
//  Created by Maurice Parker on 12/7/20.
//

import UIKit
import Templeton
import RSCore

extension Selector {
	static let editLink = #selector(EditorRowTextView.editLink(_:))
}

extension NSAttributedString.Key {
	static let selectedSearchResult: NSAttributedString.Key = .init("selectedSearchResult")
	static let searchResult: NSAttributedString.Key = .init("searchResult")
}

class EditorRowTextView: UITextView {
	
	var row: Row?
	
	var lineHeight: CGFloat {
		if let textRange = textRange(from: beginningOfDocument, to: beginningOfDocument) {
			return firstRect(for: textRange).height
		}
		return 0
	}
	
	var editorUndoManager: UndoManager? {
		fatalError("editorUndoManager has not been implemented")
	}
	
	override var undoManager: UndoManager? {
		guard let textViewUndoManager = super.undoManager, let controllerUndoManager = editorUndoManager else { return nil }
		if stackedUndoManager == nil {
			stackedUndoManager = StackedUndoManger(mainUndoManager: textViewUndoManager, fallBackUndoManager: controllerUndoManager)
		}
		return stackedUndoManager
	}
	
	var isBoldToggledOn: Bool {
		if let symbolicTraits = (typingAttributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits {
			if symbolicTraits.contains(.traitBold) {
				return true
			}
		}
		return false
	}
	
	var isItalicToggledOn: Bool {
		if let symbolicTraits = (typingAttributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits {
			if symbolicTraits.contains(.traitItalic) {
				return true
			}
		}
		return false
	}
		
	var isSelecting: Bool {
		return !(selectedTextRange?.isEmpty ?? true)
	}
    
	var selectedText: String? {
		if let textRange = selectedTextRange {
			return text(in: textRange)
		}
		return nil
	}
	
	var cursorPosition: Int {
		return selectedRange.location
	}
	
	var isTextChanged = false
	
	var rowStrings: RowStrings {
		fatalError("rowStrings has not been implemented")
	}

	var cleansedAttributedText: NSAttributedString {
		let cleanText = NSMutableAttributedString(attributedString: attributedText)
		cleanText.enumerateAttribute(.backgroundColor, in:  NSRange(0..<cleanText.length)) { value, range, stop in
			cleanText.removeAttribute(.backgroundColor, range: range)
		}
		return cleanText
	}
	
    var autosaveWorkItem: DispatchWorkItem?
    var textViewHeight: CGFloat?
    var isSavingTextUnnecessary = false

	let toggleBoldCommand = UIKeyCommand(title: L10n.bold, action: .toggleBoldface, input: "b", modifierFlags: [.command])
	let toggleItalicsCommand = UIKeyCommand(title: L10n.italic, action: .toggleItalics, input: "i", modifierFlags: [.command])
	let editLinkCommand = UIKeyCommand(title: L10n.link, action: .editLink, input: "k", modifierFlags: [.command])

	private var dropInteractionDelegate: EditorRowDropInteractionDelegate!
	private var stackedUndoManager: UndoManager?

	override init(frame: CGRect, textContainer: NSTextContainer?) {
		let textStorage = NSTextStorage()
		let layoutManager = OutlineLayoutManager()
		textStorage.addLayoutManager(layoutManager)
		let textContainer = NSTextContainer()
		layoutManager.addTextContainer(textContainer)
		
		super.init(frame: frame, textContainer: textContainer)

		textStorage.delegate = self
		textDropDelegate = self
		
		self.dropInteractionDelegate = EditorRowDropInteractionDelegate(textView: self)
		self.addInteraction(UIDropInteraction(delegate: dropInteractionDelegate))

		// These gesture recognizers will conflict with context menu preview dragging if not removed.
		if traitCollection.userInterfaceIdiom != .mac {
			gestureRecognizers?.forEach {
				if $0.name == "dragInitiation"
					|| $0.name == "dragExclusionRelationships"
					|| $0.name == "dragFailureRelationships"
					|| $0.name == "com.apple.UIKit.longPressClickDriverPrimary" {
					removeGestureRecognizer($0)
				}
			}
		}

		self.allowsEditingTextAttributes = true
		self.isScrollEnabled = false
		self.textContainer.lineFragmentPadding = 0
		self.textContainerInset = .zero
		self.backgroundColor = .clear
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
 
    override func resignFirstResponder() -> Bool {
		CursorCoordinates.updateLastKnownCoordinates()
        return super.resignFirstResponder()
    }
	
	override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
		switch action {
		case .toggleUnderline:
			return false
		default:
			return super.canPerformAction(action, withSender: sender)
		}
	}
	
	override func buildMenu(with builder: UIMenuBuilder) {
		super.buildMenu(with: builder)
		
		if isSelecting {
			let formattingMenu = UIMenu(title: "", options: .displayInline, children: [toggleBoldCommand, toggleItalicsCommand])
			builder.insertSibling(formattingMenu, afterMenu: .standardEdit)
			
			let editMenu = UIMenu(title: "", options: .displayInline, children: [editLinkCommand])
			builder.insertSibling(editMenu, afterMenu: .standardEdit)
		}
	}
    
    func layoutEditor() {
        fatalError("reloadRow has not been implemented")
    }
    
    func makeCursorVisibleIfNecessary() {
        fatalError("makeCursorVisibleIfNecessary has not been implemented")
    }

    // MARK: API
	
	func saveText() {
        guard isTextChanged else { return }
        
        if isSavingTextUnnecessary {
            isSavingTextUnnecessary = false
        } else {
            textWasChanged()
        }
        
        autosaveWorkItem?.cancel()
        autosaveWorkItem = nil
        isTextChanged = false
	}

    func textWasChanged() {
        fatalError("textChanged has not been implemented")
    }

	func update(row: Row) {
		fatalError("update has not been implemented")
	}
	
	func updateLinkForCurrentSelection(text: String, link: String?, range: NSRange) {
        var attrs = typingAttributes
        attrs.removeValue(forKey: .link)
        let attrText = NSMutableAttributedString(string: text, attributes: attrs)
		
		textStorage.beginEditing()
        textStorage.replaceCharacters(in: range, with: attrText)

        let newRange = NSRange(location: range.location, length: attrText.length)
		if let link = link, let url = URL(string: link) {
			textStorage.addAttribute(.link, value: url, range: newRange)
		} else {
			if newRange.length > 0 {
				textStorage.removeAttribute(.link, range: newRange)
			}
		}
		textStorage.endEditing()

        selectedRange = NSRange(location: range.location + text.count, length: 0)
        
        processTextChanges()
	}
	
	func replaceCharacters(_ range: NSRange, withImage image: UIImage) {
		let attachment = ImageTextAttachment()
		attachment.image = image
		attachment.imageUUID = UUID().uuidString
		let imageAttrText = NSAttributedString(attachment: attachment)

		let savedTypingAttributes = typingAttributes

		textStorage.beginEditing()
		textStorage.replaceCharacters(in: range, with: imageAttrText)
		textStorage.endEditing()

		selectedRange = .init(location: range.location + imageAttrText.length, length: 0)
		typingAttributes = savedTypingAttributes

		processTextChanges()
	}
	
    // MARK: Actions
    
    @objc func editLink(_ sender: Any?) {
        fatalError("editLink has not been implemented")
    }

}

extension EditorRowTextView: UITextDropDelegate {
	
	func textDroppableView(_ textDroppableView: UIView & UITextDroppable, willBecomeEditableForDrop drop: UITextDropRequest) -> UITextDropEditability {
		return .temporary
	}
	
	func textDroppableView(_ textDroppableView: UIView & UITextDroppable, proposalForDrop drop: UITextDropRequest) -> UITextDropProposal {
		guard !drop.dropSession.hasItemsConforming(toTypeIdentifiers: [Row.typeIdentifier]) else {
			return UITextDropProposal(operation: .forbidden)
		}

		return UITextDropProposal(operation: .copy)
	}
	
}

// MARK: NSTextStorageDelegate

extension EditorRowTextView: NSTextStorageDelegate {
	
	func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions, range editedRange: NSRange, changeInLength delta: Int) {
		textStorage.enumerateAttributes(in: editedRange, options: .longestEffectiveRangeNotRequired) { (attributes, range, _) in
			var newAttributes = attributes
			
			var newTypingAttributes = typingAttributes
			newTypingAttributes.removeValue(forKey: .font)
			newAttributes.merge(newTypingAttributes) { old, new in new }
			
			for key in attributes.keys {
				
				if key == .selectedSearchResult {
					newAttributes[.backgroundColor] = UIColor.systemYellow
					if traitCollection.userInterfaceStyle == .dark {
						newAttributes[.foregroundColor] = UIColor.black
					}
				}
				
				if key == .searchResult {
					newAttributes[.backgroundColor] = UIColor.systemGray
				}
				
				if key == .underlineStyle {
					newAttributes[key] = nil
				}

				if key == .font, let oldFont = attributes[key] as? UIFont, let newFont = font {
					let charsInRange = textStorage.attributedSubstring(from: range).string
					if charsInRange.containsEmoji || charsInRange.containsSymbols {
						newAttributes[key] = oldFont.withSize(newFont.pointSize)
					} else {
						let ufd = oldFont.fontDescriptor.withFamily(newFont.familyName).withSymbolicTraits(oldFont.fontDescriptor.symbolicTraits) ?? oldFont.fontDescriptor.withFamily(newFont.familyName)
						let newFont = UIFont(descriptor: ufd, size: newFont.pointSize)
						newAttributes[key] = newFont
					}
				}
				
				if key == .attachment, let nsAttachment = attributes[key] as? NSTextAttachment {
					guard !(nsAttachment is ImageTextAttachment) && !(nsAttachment is MetadataTextAttachment) else { continue }
					if let image = nsAttachment.image {
						let attachment = ImageTextAttachment(data: nil, ofType: nil)
						attachment.image = image
						attachment.imageUUID = UUID().uuidString
						newAttributes[key] = attachment
					} else if let fileContents = nsAttachment.fileWrapper?.regularFileContents {
						let attachment = ImageTextAttachment(data: fileContents, ofType: nsAttachment.fileType)
						attachment.imageUUID = UUID().uuidString
						newAttributes[key] = attachment
					}
				}
			}
			
			textStorage.setAttributes(newAttributes, range: range)
		}
	}
	
}

// MARK: Helpers

extension EditorRowTextView {
    
    func detectData() {
        guard let text = attributedText?.string, !text.isEmpty else { return }
        
        let detector = NSDataDetector(dataTypes: [.url])
        detector.enumerateMatches(in: text) { (range, match) in
            switch match {
            case .url(let url), .email(_, let url):
                var effectiveRange = NSRange()
                if let link = textStorage.attribute(.link, at: range.location, effectiveRange: &effectiveRange) as? URL {
                    if range != effectiveRange || link != url {
                        isTextChanged = true
                        textStorage.removeAttribute(.link, range: effectiveRange)
                        textStorage.addAttribute(.link, value: url, range: range)
                    }
                } else {
                    isTextChanged = true
                    textStorage.addAttribute(.link, value: url, range: range)
                }
            default:
                break
            }
        }
    }
    
    func findAndSelectLink() -> (String?, String?, NSRange) {
        var effectiveRange = NSRange()
        if selectedRange.length == 0 && selectedRange.lowerBound < textStorage.length {
            if let link = textStorage.attribute(.link, at: selectedRange.lowerBound, effectiveRange: &effectiveRange) as? URL {
                let text = textStorage.attributedSubstring(from: effectiveRange).string
                return (link.absoluteString, text, effectiveRange)
            }
        } else {
            for i in selectedRange.lowerBound..<selectedRange.upperBound {
                if let link = textStorage.attribute(.link, at: i, effectiveRange: &effectiveRange) as? URL {
                    let text = textStorage.attributedSubstring(from: effectiveRange).string
                    return (link.absoluteString, text, effectiveRange)
                }
            }
        }
        let text = textStorage.attributedSubstring(from: selectedRange).string
        return (nil, text, selectedRange)
    }
    
    func addSearchHighlighting(isInNotes: Bool) {
        guard let coordinates = row?.searchResultCoordinates else { return }
        for element in coordinates.objectEnumerator() {
            guard let coordinate = element as? SearchResultCoordinates, coordinate.isInNotes == isInNotes else { continue }
            if coordinate.isCurrentResult {
                textStorage.addAttribute(.selectedSearchResult, value: true, range: coordinate.range)
            } else {
                textStorage.addAttribute(.searchResult, value: true, range: coordinate.range)
            }
        }
    }
    
	func processTextEditingBegin() {
		let fittingSize = sizeThatFits(CGSize(width: frame.width, height: CGFloat.greatestFiniteMagnitude))
		textViewHeight = fittingSize.height
	}
	
    func processTextEditingEnding() {
        detectData()
        saveText()
    }

    func processTextChanges() {
        // If we deleted to the beginning of the line, remove any residual links
        if selectedRange.location == 0 && selectedRange.length == 0 {
			typingAttributes[.link] = nil
		}
        
        isTextChanged = true

		// Layout the editor if we change the line height by any amount that is more than just typing
		// in a capital letter (which changes the line height by less than 1 typically)
        let fittingSize = sizeThatFits(CGSize(width: frame.width, height: CGFloat.greatestFiniteMagnitude))
        if let currentHeight = textViewHeight, abs(fittingSize.height - currentHeight) > 2  {
			CursorCoordinates.updateLastKnownCoordinates()
            textViewHeight = fittingSize.height
            layoutEditor()
        }
        
        makeCursorVisibleIfNecessary()
        
        autosaveWorkItem?.cancel()
        autosaveWorkItem = DispatchWorkItem { [weak self] in
            self?.saveText()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: autosaveWorkItem!)
    }

}
