//
//  OPMLVisitor.swift
//  
//
//  Created by Maurice Parker on 4/14/21.
//

import Foundation
import VinUtility

class OPMLVisitor {
	
	var indentLevel = 0
	var opml = String()
	
	func visitor(_ visited: Row) async {
		let indent = String(repeating: " ", count: (indentLevel + 1) * 2)
		let escapedText = visited.topicMarkdown(representation: .opml)?.escapingXMLCharacters ?? ""
		
		opml.append(indent + "<outline text=\"\(escapedText)\"")
		if let escapedNote = visited.noteMarkdown(representation: .opml)?.escapingXMLCharacters {
			opml.append(" _note=\"\(escapedNote)\"")
		}

		if visited.isComplete ?? false {
			opml.append(" _status=\"checked\"")
		}
		
		if visited.rowCount == 0 {
			opml.append("/>\n")
		} else {
			opml.append(">\n")
			indentLevel = indentLevel + 1
			
			for row in visited.rows {
				await row.visit(visitor: self.visitor)
			}
			
			indentLevel = indentLevel - 1
			opml.append(indent + "</outline>\n")
		}
	}
	
}
