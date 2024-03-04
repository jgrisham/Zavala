//
//  Created by Maurice Parker on 1/26/24.
//

import Foundation

public final class ReplaceSearchResultCommand: OutlineCommand {

	private let coordinates: [SearchResultCoordinates]
	private let replacementText: String
	private var oldRowStrings = [(Row, RowStrings)]()
	private var oldRangeLength: Int?
	
	public init(actionName: String,
				undoManager: UndoManager,
				delegate: OutlineCommandDelegate,
				outline: Outline,
				coordinates: [SearchResultCoordinates],
				replacementText: String) async {

		self.coordinates = coordinates
		self.replacementText = replacementText
		
		for coordinate in coordinates {
			await oldRowStrings.append((coordinate.row, coordinate.row.rowStrings))
		}
		
		if let length = coordinates.first?.range.length {
			oldRangeLength = length
		}
		
		super.init(actionName: actionName, undoManager: undoManager, delegate: delegate, outline: outline)

	}
	
	public override func perform() async {
		await outline.replaceSearchResults(coordinates, with: replacementText)
	}
	
	public override func undo() async {
		for coordinate in coordinates {
			coordinate.range.length = oldRangeLength ?? 0
		}
			
		for (row, rowStrings) in oldRowStrings {
			await outline.updateRow(row, rowStrings: rowStrings, applyChanges: true)
		}
	}
	
}
