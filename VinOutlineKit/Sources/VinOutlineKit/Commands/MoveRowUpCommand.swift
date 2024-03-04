//
//  MoveRowUpCommand.swift
//  
//
//  Created by Maurice Parker on 6/29/21.
//

import Foundation

public final class MoveRowUpCommand: OutlineCommand {
	
	var rows: [Row]

	var oldRowStrings: RowStrings?
	var newRowStrings: RowStrings?
	
	public init(actionName: String, undoManager: UndoManager, delegate: OutlineCommandDelegate, outline: Outline, rows: [Row], rowStrings: RowStrings?) async {
		self.rows = rows
		
		if rows.count == 1, let row = rows.first {
			self.oldRowStrings = await row.rowStrings
			self.newRowStrings = rowStrings
		}

		super.init(actionName: actionName, undoManager: undoManager, delegate: delegate, outline: outline)
	}
	
	public override func perform() async {
		await outline.moveRowsUp(rows, rowStrings: newRowStrings)
		registerUndo()
	}
	
	public override func undo() async {
		await outline.moveRowsDown(rows, rowStrings: oldRowStrings)
	}
	
}
