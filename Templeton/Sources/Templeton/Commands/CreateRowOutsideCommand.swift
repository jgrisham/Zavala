//
//  CreateRowOutsideCommand.swift
//  
//
//  Created by Maurice Parker on 6/30/21.
//

import Foundation
import RSCore

public final class CreateRowOutsideCommand: OutlineCommand {
	public var undoActionName: String
	public var redoActionName: String
	public var undoManager: UndoManager
	public weak var delegate: OutlineCommandDelegate?
	public var cursorCoordinates: CursorCoordinates?
	
	public var newCursorIndex: Int?

	public var outline: Outline
	var row: Row?
	var afterRow: Row
	var rowStrings: RowStrings?
	
	public init(undoManager: UndoManager, delegate: OutlineCommandDelegate, outline: Outline, afterRow: Row, rowStrings: RowStrings?) {
		self.undoManager = undoManager
		self.delegate = delegate
		self.outline = outline
		self.afterRow = afterRow
		self.rowStrings = rowStrings
		undoActionName = L10n.addRowOutside
		redoActionName = L10n.addRowOutside
	}
	
	public func perform() {
		saveCursorCoordinates()
		if row == nil {
			row = Row(outline: outline)
		}
		newCursorIndex = outline.createRowsOutside([row!], afterRow: afterRow, rowStrings: rowStrings)
		registerUndo()
	}
	
	public func undo() {
		guard let row else { return }
		outline.deleteRows([row])
		registerRedo()
		restoreCursorPosition()
	}
	
}
