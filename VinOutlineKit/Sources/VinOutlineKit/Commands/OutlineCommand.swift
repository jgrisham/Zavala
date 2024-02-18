//
//  OutlineCommand.swift
//
//  Created by Maurice Parker on 11/27/20.
//

import Foundation
import VinUtility

public protocol OutlineCommandDelegate: AnyObject {
	var currentCoordinates: CursorCoordinates? { get }
	func restoreCursorPosition(_: CursorCoordinates)
}

public class OutlineCommand {
	
	var actionName: String
	
	public var undoManager: UndoManager
	weak public var delegate: OutlineCommandDelegate?
	public var cursorCoordinates: CursorCoordinates?
	public var outline: Outline

	init(actionName: String,
		 undoManager: UndoManager,
		 delegate: OutlineCommandDelegate? = nil,
		 outline: Outline,
		 cursorCoordinates: CursorCoordinates? = nil) {
		self.actionName = actionName
		self.undoManager = undoManager
		self.delegate = delegate
		self.outline = outline
		self.cursorCoordinates = cursorCoordinates
	}
	
	public func execute() async {
		registerUndo()
		await saveCursorCoordinates()
		await perform()
	}
	
	func unexecute() {
		registerRedo()
		Task {
			await undo()
			await restoreCursorPosition()
		}
	}
	
	func perform() async {
		fatalError("Perform function not implemented.")
	}
	
	func undo() async {
		fatalError("Undo function not implemented.")
	}
	
	func registerUndo() {
		undoManager.setActionName(actionName)
		undoManager.registerUndo(withTarget: self) { _ in
			self.unexecute()
		}
	}

	func registerRedo() {
		undoManager.setActionName(actionName)
		undoManager.registerUndo(withTarget: self) { _ in
			Task {
				await self.execute()
			}
		}
	}
	
	@MainActor
	func saveCursorCoordinates() {
		let coordinates = delegate?.currentCoordinates
		cursorCoordinates = coordinates
		outline.cursorCoordinates = coordinates
	}
	
	@MainActor
	func restoreCursorPosition() {
		if let cursorCoordinates {
			delegate?.restoreCursorPosition(cursorCoordinates)
		}
	}
	
}
