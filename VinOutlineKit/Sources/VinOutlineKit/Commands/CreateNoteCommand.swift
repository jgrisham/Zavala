//
//  CreateNoteCommand.swift
//
//  Created by Maurice Parker on 12/13/20.
//

import Foundation

public final class CreateNoteCommand: OutlineCommand {

	var rows: [Row]
	var oldRowStrings: RowStrings?
	var newRowStrings: RowStrings?
	
	var noteCreatedRows: [Row]?

	public init(actionName: String, undoManager: UndoManager, delegate: OutlineCommandDelegate, outline: Outline, rows: [Row], rowStrings: RowStrings?) async {
		self.rows = rows

		if rows.count == 1, let row = rows.first {
			self.oldRowStrings = await row.rowStrings
			self.newRowStrings = rowStrings
		}

		super.init(actionName: actionName, undoManager: undoManager, delegate: delegate, outline: outline)
	}
	
	public override func perform() async {
		noteCreatedRows = await outline.createNotes(rows: rows, rowStrings: newRowStrings)
	}
	
	public override func undo() async {
		await outline.deleteNotes(rows: noteCreatedRows ?? [Row](), rowStrings: oldRowStrings)
	}
	
}
