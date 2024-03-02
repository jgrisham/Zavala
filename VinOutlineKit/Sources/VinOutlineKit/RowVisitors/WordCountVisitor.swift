//
//  Created by Maurice Parker on 1/3/24.
//

import Foundation

class WordCountVisitor {

	var count = 0
	
	func visitor(_ visited: Row) async {
		if let topic = visited.topic?.string {
			count = count + topic.split(separator: " ", omittingEmptySubsequences: true).count
		}
		
		if let note = visited.note?.string {
			count = count + note.split(separator: " ", omittingEmptySubsequences: true).count
		}

		for row in visited.rows { await row.visit(visitor: self.visitor) }
	}
	
}
