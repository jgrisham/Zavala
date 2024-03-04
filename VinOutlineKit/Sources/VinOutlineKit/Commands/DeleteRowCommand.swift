//
//  DeleteRowCommand.swift
//
//  Created by Maurice Parker on 11/28/20.
//

import Foundation

public final class DeleteRowCommand: OutlineCommand {

	var rows: [Row]
	var rowStrings: RowStrings?
	var afterRows = [Row: Row]()
	
	public init(actionName: String, undoManager: UndoManager, delegate: OutlineCommandDelegate, outline: Outline, rows: [Row], rowStrings: RowStrings?) async {
		self.rows = rows

		var allRows = Set<Row>()
		
		func deleteVisitor(_ visited: Row) async {
			allRows.insert(visited)
			for row in await visited.rows { await row.visit(visitor: deleteVisitor) }
		}
		for row in rows { await row.visit(visitor: deleteVisitor) }
		
		self.rows = Array(allRows)

		for row in allRows {
			if let rowShadowTableIndex = await row.shadowTableIndex, rowShadowTableIndex > 0, let afterRow = await outline.shadowTable?[rowShadowTableIndex - 1] {
				afterRows[row] = await afterRow.ancestorSibling(row)
			}
		}

		self.rowStrings = rowStrings

		super.init(actionName: actionName, undoManager: undoManager, delegate: delegate, outline: outline)
	}
	
	public override func perform() async {
		await outline.deleteRows(rows, rowStrings: rowStrings)
	}
	
	public override func undo() async {
		for row in rows.sortedByDisplayOrder() {
			await outline.createRows([row], afterRow: afterRows[row])
		}
	}
	
}
