//
//  Created by Maurice Parker on 11/9/20.
//

#if canImport(UIKit)
import UIKit
#else
import Foundation
#endif

public protocol OutlineContainer: OutlineProvider {
	var id: EntityID { get }
	var name: String? { get }
	#if canImport(UIKit)
	var image: UIImage? { get }
	#endif
	var itemCount: Int? { get }
	var account: Account? { get }
}

public extension Array where Element == OutlineContainer {
    
    var uniqueAccount: Account? {
        var account: Account? = nil
        for container in self {
            if let account, let containerAccount = container.account {
                if account != containerAccount {
                    return nil
                }
            }
            account = container.account
        }
        return account
    }
    
    var tags: [Tag] {
        return self.compactMap { ($0 as? TagOutlines)?.tag }
    }

    var title: String {
        ListFormatter.localizedString(byJoining: self.compactMap({ $0.name }).sorted())
    }
	
}
