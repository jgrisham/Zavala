//
//  TextChangedCommand.swift
//
//  Created by Maurice Parker on 11/28/20.
//

import Foundation

public final class TextChangedCommand: OutlineCommand {
	
	var row: Row
	var oldRowStrings: RowStrings?
	var newRowStrings: RowStrings
	var applyChanges = false
	
	public init(actionName: String,
				undoManager: UndoManager,
				delegate: OutlineCommandDelegate,
				outline: Outline,
				row: Row,
				rowStrings: RowStrings,
				isInNotes: Bool,
				selection: NSRange) {
		self.row = row

		oldRowStrings = row.rowStrings
		newRowStrings = rowStrings
		
		super.init(actionName: actionName, undoManager: undoManager, delegate: delegate, outline: outline)

		cursorCoordinates = CursorCoordinates(row: row, isInNotes: isInNotes, selection: selection)
	}
	
	public override func perform() async {
		await outline.updateRow(row, rowStrings: newRowStrings, applyChanges: applyChanges)
		applyChanges = true
	}
	
	public override func undo() async {
		await outline.updateRow(row, rowStrings: oldRowStrings, applyChanges: applyChanges)
	}
	
}
