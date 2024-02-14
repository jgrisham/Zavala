//
//  File.swift
//  
//
//  Created by Maurice Parker on 2/1/21.
//

import Foundation

public final class DeleteTagCommand: OutlineCommand {
	
	var tagName: String
	var tag: Tag?
	
	public init(actionName: String, undoManager: UndoManager, delegate: OutlineCommandDelegate, outline: Outline, tagName: String) {
		self.tagName = tagName

		super.init(actionName: actionName, undoManager: undoManager, delegate: delegate, outline: outline)
	}
	
	public override func perform() async {
		guard let tag = outline.account?.findTag(name: tagName) else { return }
		self.tag = tag
		outline.deleteTag(tag)
		outline.account?.deleteTag(tag)
	}
	
	public override func undo() async {
		guard let tag else { return }
		outline.account?.createTag(tag)
		outline.createTag(tag)
	}
	
}
