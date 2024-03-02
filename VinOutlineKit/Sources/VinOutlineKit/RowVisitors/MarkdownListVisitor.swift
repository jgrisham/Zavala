//
//  MarkdownListVisitor.swift
//  
//
//  Created by Maurice Parker on 4/14/21.
//

import Foundation

class MarkdownListVisitor {
	
	var indentLevel = 0
	var markdown = String()
	
	func visitor(_ visited: Row) async {
		markdown.append(String(repeating: "\t", count: indentLevel))
		
		if visited.isComplete ?? false {
			markdown.append("* ~~\(visited.topicMarkdown(representation: .markdown) ?? "")~~")
		} else {
			markdown.append("* \(visited.topicMarkdown(representation: .markdown) ?? "")")
		}
		
		if let noteMarkdown = visited.noteMarkdown(representation: .markdown), !noteMarkdown.isEmpty {
			markdown.append("\n\n")
			let paragraphs = noteMarkdown.components(separatedBy: "\n\n")
			for paragraph in paragraphs {
				markdown.append(String(repeating: "\t", count: indentLevel))
				markdown.append("  \(paragraph)\n\n")
			}
		}
		
		indentLevel = indentLevel + 1
		for row in visited.rows {
			markdown.append("\n")
			await row.visit(visitor: self.visitor)
		}
		indentLevel = indentLevel - 1
	}
	
}
