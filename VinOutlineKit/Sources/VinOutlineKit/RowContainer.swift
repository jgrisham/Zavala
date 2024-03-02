//
//  RowContainer.swift
//  
//
//  Created by Maurice Parker on 11/22/20.
//

import Foundation
import VinXML

public protocol RowContainer {
	var outline: Outline? { get async }
	var rows: [Row] { get async }
	var rowCount: Int { get async }

	func containsRow(_: Row) async -> Bool
	func insertRow(_: Row, at: Int) async
	func removeRow(_: Row) async
	func appendRow(_: Row) async
	func firstIndexOfRow(_: Row) async -> Int?
}

public extension RowContainer {
	
	func importRows(outline: Outline, rowNodes: [VinXML.XMLNode], images: [String:  Data]?) async {
		for rowNode in rowNodes {
			let topicMarkdown = rowNode.attributes["text"]
			let noteMarkdown = rowNode.attributes["_note"]
			
			let row = Row(outline: outline)
			await row.importRow(topicMarkdown: topicMarkdown, noteMarkdown: noteMarkdown, images: images)

			if rowNode.attributes["_status"] == "checked" {
				row.isComplete = true
			}
			
			await appendRow(row)
			
			if let rowNodes = rowNode["outline"] {
				await row.importRows(outline: outline, rowNodes: rowNodes, images: images)
			}
		}
	}
	
}
