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
			
			let visitedIsComplete = await visited.isComplete ?? false
			let visitedIsPartOfSearchResult = await visited.isPartOfSearchResult
			let shouldFilter = (isCompletedFilterOn && visitedIsComplete) || (isSearching == .searching && !visitedIsPartOfSearchResult)
			
			if shouldFilter {
				await visited.update(shadowTableIndex: nil)
			} else {
				await visited.update(shadowTableIndex: shadowTable.count)
				shadowTable.append(visited)
			}
			
			if await (!visited.isExpanded && isSearching == .notSearching) || shouldFilter {
				addingToShadowTable = false
				addingToShadowTableSuspended = true
			}
			
		} else {
			
			await visited.update(shadowTableIndex: nil)

		}
		
		// Set all the Headline's children's parent and visit them
		for row in await visited.rows {
			await row.update(parent: visited)
			await row.visit(visitor: visitor)
		}

		if addingToShadowTableSuspended {
			addingToShadowTable = true
		}
		
	}
	
}
