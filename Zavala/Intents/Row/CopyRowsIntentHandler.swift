//
//  CopyRowsIntentHandler.swift
//  Zavala
//
//  Created by Maurice Parker on 10/18/21.
//

import Intents
import VinOutlineKit

class CopyRowsIntentHandler: NSObject, ZavalaIntentHandler, CopyRowsIntentHandling {
	
	func handle(intent: CopyRowsIntent, completion: @escaping (CopyRowsIntentResponse) -> Void) {
		resume()
		
		guard let intentRows = intent.rows,
			  let entityID = intent.entityID?.toEntityID(),
			  let outline = Outliner.shared.findDocument(entityID)?.outline else {
				  suspend()
				  completion(.init(code: .success, userActivity: nil))
				  return
			  }
		
		var outlines = Set<Outline>()
		outline.load()
		outlines.insert(outline)
		
		guard let rowContainer = outline.findRowContainer(entityID: entityID) else {
			outlines.forEach { $0.unload() }
			suspend()
			completion(.init(code: .success, userActivity: nil))
			return
		}
		
		let rows: [Row] = intentRows
			.compactMap { $0.entityID?.toEntityID() }
			.compactMap {
				if let rowOutline = Outliner.shared.findDocument($0)?.outline {
					rowOutline.load()
					outlines.insert(rowOutline)
					return rowOutline.findRow(id: $0.rowUUID)
				}
				return nil
			}
		
		for row in rows {
			let rowGroup = RowGroup(row)
			let attachedRow = rowGroup.attach(to: outline)

			switch intent.destination {
			case .insideAtStart:
				outline.createRowsInsideAtStart([attachedRow], afterRowContainer: rowContainer)
			case .insideAtEnd:
				outline.createRowsInsideAtEnd([attachedRow], afterRowContainer: rowContainer)
			case .outside:
				if let afterRow = rowContainer as? Row {
					outline.createRowsOutside([attachedRow], afterRow: afterRow)
				}
			case .directlyAfter:
				if let afterRow = rowContainer as? Row {
					outline.createRowsDirectlyAfter([attachedRow], afterRow: afterRow)
				}
			default:
				outlines.forEach { $0.unload() }
				suspend()
				completion(.init(code: .failure, userActivity: nil))
				return
			}
		}
		
		outlines.forEach { $0.unload() }
		suspend()
		
		let response = CopyRowsIntentResponse(code: .success, userActivity: nil)
		response.rows = rows.map { IntentRow($0) }
		completion(response)
	}
	
}
