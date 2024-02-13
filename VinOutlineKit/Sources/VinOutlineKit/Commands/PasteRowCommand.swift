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
	
	public override func perform() {
		Task {
			saveCursorCoordinates()
			
			var newRows = [Row]()
			for rowGroup in rowGroups {
				let newRow = rowGroup.attach(to: outline)
				newRows.append(newRow)
			}
			rows = newRows
			
			await outline.createRows(rows, afterRow: afterRow)
			registerUndo()
		}
	}
	
	public override func undo() {
		Task {
			var allRows = [Row]()
			
			func deleteVisitor(_ visited: Row) {
				allRows.append(visited)
				visited.rows.forEach { $0.visit(visitor: deleteVisitor) }
			}
			rows.forEach { $0.visit(visitor: deleteVisitor(_:)) }
			
			await outline.deleteRows(allRows)
			registerRedo()
			restoreCursorPosition()
		}
	}
	
}
