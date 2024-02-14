//
//  CreateRowOutsideCommand.swift
//  
//
//  Created by Maurice Parker on 6/30/21.
//

import Foundation

public final class CreateRowOutsideCommand: OutlineCommand {

	var row: Row?
	var afterRow: Row
	var rowStrings: RowStrings?
	
	public init(actionName: String, undoManager: UndoManager, delegate: OutlineCommandDelegate, outline: Outline, afterRow: Row, rowStrings: RowStrings?) {
		self.afterRow = afterRow
		self.rowStrings = rowStrings
		
		super.init(actionName: actionName, undoManager: undoManager, delegate: delegate, outline: outline)
	}
	
	public override func perform() async {
		if row == nil {
			row = Row(outline: outline)
		}
		await outline.createRowsOutside([row!], afterRow: afterRow, rowStrings: rowStrings)
	}
	
	public override func undo() async {
		guard let row else { return }
		await outline.deleteRows([row])
	}
	
}
