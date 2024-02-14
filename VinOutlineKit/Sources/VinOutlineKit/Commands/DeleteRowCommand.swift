//
//  DeleteRowCommand.swift
//
//  Created by Maurice Parker on 11/28/20.
//

import Foundation

public final class DeleteRowCommand: OutlineCommand {
	public var newCursorIndex: Int?

	var rows: [Row]
	var rowStrings: RowStrings?
	var afterRows = [Row: Row]()
	
	public init(actionName: String, undoManager: UndoManager, delegate: OutlineCommandDelegate, outline: Outline, rows: [Row], rowStrings: RowStrings?) {
		self.rows = rows

		var allRows = Set<Row>()
		
		func deleteVisitor(_ visited: Row) {
			allRows.insert(visited)
			visited.rows.forEach { $0.visit(visitor: deleteVisitor) }
		}
		rows.forEach { $0.visit(visitor: deleteVisitor(_:)) }
		
		self.rows = Array(allRows)

		for row in allRows {
			if let rowShadowTableIndex = row.shadowTableIndex, rowShadowTableIndex > 0, let afterRow = outline.shadowTable?[rowShadowTableIndex - 1] {
				afterRows[row] = afterRow.ancestorSibling(row)
			}
		}

		self.rowStrings = rowStrings

		super.init(actionName: actionName, undoManager: undoManager, delegate: delegate, outline: outline)
	}
	
	public override func perform() async {
		newCursorIndex = await outline.deleteRows(rows, rowStrings: rowStrings)
	}
	
	public override func undo() async {
		for row in rows.sortedByDisplayOrder() {
			await outline.createRows([row], afterRow: afterRows[row])
		}
	}
	
}
