//
//  MoveRowRightCommand.swift
//  
//
//  Created by Maurice Parker on 6/29/21.
//

import Foundation

public final class MoveRowRightCommand: OutlineCommand {
	
	var rows: [Row]
	var moveRightRows: [Row]?
	var oldRowStrings: RowStrings?
	var newRowStrings: RowStrings?
	
	public init(actionName: String, undoManager: UndoManager, delegate: OutlineCommandDelegate, outline: Outline, rows: [Row], rowStrings: RowStrings?) {
		self.rows = rows
		
		if rows.count == 1, let row = rows.first {
			self.oldRowStrings = row.rowStrings
			self.newRowStrings = rowStrings
		}

		super.init(actionName: actionName, undoManager: undoManager, delegate: delegate, outline: outline)
	}
	
	public override func perform() async {
		moveRightRows = await outline.moveRowsRight(rows, rowStrings: newRowStrings)
		registerUndo()
	}
	
	public override func undo() async {
		guard let moveRightRows else { return }
		await outline.moveRowsLeft(moveRightRows, rowStrings: oldRowStrings)
	}
	
}
