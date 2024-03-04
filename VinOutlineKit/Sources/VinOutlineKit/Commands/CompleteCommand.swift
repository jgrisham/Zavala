//
//  CompleteCommand.swift
//  
//
//  Created by Maurice Parker on 12/28/20.
//

import Foundation

public final class CompleteCommand: OutlineCommand {
	
	var rows: [Row]
	var completedRows: [Row]?
	
	public var newCursorIndex: Int?
	
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
	
	override public func perform() async {
		let (impacted, newCursorIndex) = await outline.complete(rows: rows, rowStrings: newRowStrings)
		completedRows = impacted
		self.newCursorIndex = newCursorIndex
	}
	
	override public func undo() async {
		guard let completedRows else { return }
		await outline.uncomplete(rows: completedRows, rowStrings: oldRowStrings)
	}
	
}
