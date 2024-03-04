//
//  PasteRowCommand.swift
//
//  Created by Maurice Parker on 12/31/20.
//

import Foundation

public final class PasteRowCommand: OutlineCommand {
	
	var rowGroups: [RowGroup]
	var rows: [Row]
	var afterRow: Row?
	
	public init(actionName: String, undoManager: UndoManager,
				delegate: OutlineCommandDelegate,
				outline: Outline,
				rowGroups: [RowGroup],
				afterRow: Row?) {
		
		self.rowGroups = rowGroups
		self.rows = [Row]()
		self.afterRow = afterRow
		
		super.init(actionName: actionName, undoManager: undoManager, delegate: delegate, outline: outline)
	}
	
	public override func perform() async {
		var newRows = [Row]()
		for rowGroup in rowGroups {
			let newRow = rowGroup.attach(to: outline)
			newRows.append(newRow)
		}
		rows = newRows
			
		await outline.createRows(rows, afterRow: afterRow)
	}
	
	public override func undo() async {
		var allRows = [Row]()
		
		func deleteVisitor(_ visited: Row) async {
			allRows.append(visited)
			for row in await visited.rows { await row.visit(visitor: deleteVisitor) }
		}
		for row in rows { await row.visit(visitor: deleteVisitor) }
			
		await outline.deleteRows(allRows)
	}
	
}
