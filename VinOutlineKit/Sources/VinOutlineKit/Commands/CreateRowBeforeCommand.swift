//
//  CreateRowBeforeCommand.swift
//
//  Created by Maurice Parker on 12/15/20.
//

import Foundation

public final class CreateRowBeforeCommand: OutlineCommand {
	public var newCursorIndex: Int?

	var row: Row
	var beforeRow: Row
	
	public init(actionName: String, undoManager: UndoManager, delegate: OutlineCommandDelegate, outline: Outline, beforeRow: Row) {
		self.row = Row(outline: outline)
		self.beforeRow = beforeRow

		super.init(actionName: actionName, undoManager: undoManager, delegate: delegate, outline: outline)
	}
	
	public override func perform() {
		Task {
			saveCursorCoordinates()
			newCursorIndex = await outline.createRow(row, beforeRow: beforeRow)
			registerUndo()
		}
	}
	
	public override func undo() {
		Task {
			await outline.deleteRows([row])
			registerRedo()
			restoreCursorPosition()
		}
	}
	
}
