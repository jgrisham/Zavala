//
//  Created by Maurice Parker on 11/7/21.
//

import Foundation

public final class TagsOutlines: OutlineProvider {
    
    private let tags: [Tag]

	public var outlines: [Outline] {
		get async throws {
			let outlines = await Outliner.shared.activeOutlines
			return outlines.filter { $0.hasAllTags(tags) }
		}
	}

    public init(tags: [Tag]) {
        self.tags = tags
    }
    
}
