//
//  Created by Maurice Parker on 11/7/21.
//

import Foundation

public protocol OutlineProvider {
	var outlines: [Outline] { get async throws }
}
