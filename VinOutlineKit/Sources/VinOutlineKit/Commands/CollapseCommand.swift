//
//  CollapseCommand.swift
//  
//
//  Created by Maurice Parker on 12/28/20.
//

import Foundation

public final class CollapseCommand: OutlineCommand {
	
	var rows: [Row]
	var collapsedRows: [Row]?
	
	public init(actionName: String, undoManager: UndoManager, delegate: OutlineCommandDelegate, outline: Outline, rows: [Row]) {
		self.rows = rows
		
		super.init(actionName: actionName, undoManager: undoManager, delegate: delegate, outline: outline)
	}
	
	override public func perform() async {
		collapsedRows = await outline.collapse(rows: rows)
	}
	
	override public func undo() async {
		guard let expandedRows = collapsedRows else { return }
		await outline.expand(rows: expandedRows)
	}
	
}
