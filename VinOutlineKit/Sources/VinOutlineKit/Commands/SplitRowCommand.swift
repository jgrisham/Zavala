//
//  SplitRowCommand.swift
//
//  Created by Maurice Parker on 12/5/20.
//

import Foundation

public final class SplitRowCommand: OutlineCommand {

	var newRow: Row?
	var row: Row
	var topic: NSAttributedString
	var cursorPosition: Int
	
	public init(actionName: String,
				undoManager: UndoManager,
				delegate: OutlineCommandDelegate,
				outline: Outline,
				row: Row,
				topic: NSAttributedString,
				cursorPosition: Int) {
		self.row = row
		self.topic = topic
		self.cursorPosition = cursorPosition

		super.init(actionName: actionName, undoManager: undoManager, delegate: delegate, outline: outline)
	}
	
	public override func perform() async {
		if newRow == nil {
			newRow = Row(outline: outline)
		}
		await outline.splitRow(newRow: newRow!, row: row, topic: topic, cursorPosition: cursorPosition)
	}
	
	public override func undo() async {
		guard let newHeadline = newRow else { return }
		await outline.joinRows(topRow: row, bottomRow: newHeadline)
	}
	
}
