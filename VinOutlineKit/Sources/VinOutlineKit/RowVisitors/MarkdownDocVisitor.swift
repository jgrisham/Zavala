//
//  MarkdownDocVisitor.swift
//  
//
//  Created by Maurice Parker on 4/14/21.
//

import Foundation

class MarkdownDocVisitor {
	
	var indentLevel = 0
	var markdown = String()
	
	var previousRowWasParagraph = false
	
	func visitor(_ visited: Row) async {
		
		func visitChildren() async {
			indentLevel = indentLevel + 1
			for row in visited.rows {
				await row.visit(visitor: self.visitor)
			}
			indentLevel = indentLevel - 1
		}

		if let topicMarkdown = visited.topicMarkdown(representation: .markdown), !topicMarkdown.isEmpty {
			if let noteMarkdown = visited.noteMarkdown(representation: .markdown), !noteMarkdown.isEmpty {
				markdown.append("\n\n")
				markdown.append(String(repeating: "#", count: indentLevel + 2))
				markdown.append(" \(topicMarkdown)")
				markdown.append("\n\n\(noteMarkdown)")
				previousRowWasParagraph = true
				
				await visitChildren()
			} else {
				if previousRowWasParagraph {
					markdown.append("\n")
				}

				let listVisitor = MarkdownListVisitor()
				markdown.append("\n")
				await visited.visit(visitor: listVisitor.visitor)
				markdown.append(listVisitor.markdown)
				
				previousRowWasParagraph = false
			}
		} else {
			if let noteMarkdown = visited.noteMarkdown(representation: .markdown), !noteMarkdown.isEmpty {
				markdown.append("\n\n\(noteMarkdown)")
				previousRowWasParagraph = true
			} else {
				previousRowWasParagraph = false
			}
			
			await visitChildren()
		}
		
	}
	
}
