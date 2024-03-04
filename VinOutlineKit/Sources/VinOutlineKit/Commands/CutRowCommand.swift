//
//  CutRowCommand.swift
//  
//
//  Created by Maurice Parker on 12/31/20.
//

import Foundation

public final class CutRowCommand: OutlineCommand {
	
	var rows: [Row]
	var afterRows = [Row: Row]()
	
	public init(actionName: String, undoManager: UndoManager, delegate: OutlineCommandDelegate, outline: Outline, rows: [Row]) async {
		self.rows = rows

		var allRows = [Row]()
		
		func cutVisitor(_ visited: Row) async {
			allRows.append(visited)
			for row in await visited.rows { await row.visit(visitor: cutVisitor) }
		}
		for row in rows { await row.visit(visitor: cutVisitor) }
		
		self.rows = allRows
		
		for row in allRows {
			if let rowShadowTableIndex = await row.shadowTableIndex, rowShadowTableIndex > 0, let afterRow = await outline.shadowTable?[rowShadowTableIndex - 1] {
				afterRows[row] = afterRow
			}
		}

		super.init(actionName: actionName, undoManager: undoManager, delegate: delegate, outline: outline)
	}
	
	public override func perform() async {
		await outline.deleteRows(rows)
	}
	
	public override func undo() async {
		for row in rows.sortedByDisplayOrder() {
			await outline.createRows([row], afterRow: afterRows[row])
		}
	}
	
}
