//
//  StringVisitor.swift
//  
//
//  Created by Maurice Parker on 4/14/21.
//

import Foundation

class StringVisitor {

	var indentLevel = 0
	var string = String()
	
	func visitor(_ visited: Row) async {
		string.append(String(repeating: "\t", count: indentLevel))
		string.append("\(visited.topic?.string ?? "")")
		
		if let notePlainText = visited.note?.string {
			string.append("\n\(notePlainText)")
		}
		
		indentLevel = indentLevel + 1
		for row in visited.rows {
			string.append("\n")
			await row.visit(visitor: self.visitor)
		}
		indentLevel = indentLevel - 1
	}
	
}
