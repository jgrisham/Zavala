//
//  TransientDataVisitor.swift
//  
//
//  Created by Maurice Parker on 11/24/20.
//

import Foundation

class TransientDataVisitor {
	
	let isCompletedFilterOn: Bool
	let isSearching: Outline.SearchState
	var shadowTable = [Row]()
	var addingToShadowTable = true
	
	init(isCompletedFilterOn: Bool, isSearching: Outline.SearchState) {
		self.isCompletedFilterOn = isCompletedFilterOn
		self.isSearching = isSearching
	}
	
	func visitor(_ visited: Row) async {

		var addingToShadowTableSuspended = false
		
		// Add to the Shadow Table if we haven't hit a collapsed entry
		if addingToShadowTable {
			
			let shouldFilter = (isCompletedFilterOn && visited.isComplete ?? false) || (isSearching == .searching && !visited.isPartOfSearchResult)
			
			if shouldFilter {
				visited.shadowTableIndex = nil
			} else {
				visited.shadowTableIndex = shadowTable.count
				shadowTable.append(visited)
			}
			
			if (!visited.isExpanded && isSearching == .notSearching) || shouldFilter {
				addingToShadowTable = false
				addingToShadowTableSuspended = true
			}
			
		} else {
			
			visited.shadowTableIndex = nil
			
		}
		
		// Set all the Headline's children's parent and visit them
		for row in visited.rows {
			row.parent = visited
			await row.visit(visitor: visitor)
		}

		if addingToShadowTableSuspended {
			addingToShadowTable = true
		}
		
	}
	
}
