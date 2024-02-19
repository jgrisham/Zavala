//
//  RowGroup.swift
//  
//
//  Created by Maurice Parker on 2/26/21.
//

import Foundation
import OrderedCollections

public class RowGroup: Codable {
	
	public var row: Row
	var childRows: [Row]
	var images: [String: [Image]]

	private enum CodingKeys: String, CodingKey {
		case row
		case childRows
		case images
	}
	
	public init(_ row: Row) {
		self.row = row
		self.childRows = [Row]()
		self.images = [String: [Image]]()
		
		self.images[row.id] = row.images
		
		func keyedRowsVisitor(_ visited: Row) {
			self.childRows.append(visited)
			self.images[visited.id] = visited.images
			visited.rows.forEach { $0.visit(visitor: keyedRowsVisitor) }
		}
		row.rows.forEach { $0.visit(visitor: keyedRowsVisitor(_:)) }
	}

	public func attach(to outline: Outline) -> Row {
		var idMap = [String: String]()
		var newChildRows = [Row]()
		var newImages = [String: [Image]]()

		let newRow = row.duplicate(newOutline: outline)
		idMap[row.id] = newRow.id

		for childRow in childRows {
			let newChildRow = childRow.duplicate(newOutline: outline)
			idMap[childRow.id] = newChildRow.id
			newChildRows.append(newChildRow)
		}
		
		for (rowID, images) in images {
			guard let newRowID = idMap[rowID] else { continue }
			newImages[newRowID] = images.map {
                return $0.duplicate(outline: outline, accountID: outline.id.accountID, outlineUUID: outline.id.outlineUUID, rowUUID: newRowID)
			}
		}
		
		if outline.keyedRows == nil {
			outline.keyedRows = [String: Row]()
		}
		
		outline.beginCloudKitBatchRequest()

		for newChildRow in newChildRows {
			var newChildRowRowOrder = [String]()
			for oldRowOrder in newChildRow.rowOrder {
				newChildRowRowOrder.append(idMap[oldRowOrder]!)
			}
			
			newChildRow.rowOrder = OrderedSet(newChildRowRowOrder)
			outline.keyedRows?[newChildRow.id] = newChildRow
			outline.requestCloudKitUpdate(for: newChildRow.entityID)
		}
		
		for (newRowID, newImages) in newImages {
			outline.updateImages(rowID: newRowID, images: newImages)
		}
		
		outline.endCloudKitBatchRequest()
		
		newRow.parent = row.parent
		var newRowRowOrder = [String]()
		for newRowOrder in newRow.rowOrder {
			newRowRowOrder.append(idMap[newRowOrder]!)
		}
		
		newRow.rowOrder = OrderedSet(newRowRowOrder)

		return newRow
	}
	
	public func asData() throws -> Data {
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .binary
		return try encoder.encode(self)
	}
	
	public static func fromData(_ data: Data) throws -> RowGroup {
		let decoder = PropertyListDecoder()
		return try decoder.decode(RowGroup.self, from: data)
	}

}
