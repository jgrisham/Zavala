//
//  Created by Maurice Parker on 1/27/21.
//

#if canImport(UIKit)
import UIKit
#else
import Foundation
#endif
public final class AllOutlines: Identifiable, OutlineContainer {

	public var id: EntityID
	public var name: String? = VinOutlineKitStringAssets.all
	#if canImport(UIKit)
	public var image: UIImage? = UIImage(systemName: "tray")!
	#endif

	public var itemCount: Int? {
		return 0
//		return account?.documents?.count
	}

	public var outlines: [Outline] {
		get async {
			return await account?.outlines ?? []
		}
	}

	public weak var account: Account?
	
	public init(account: Account) {
		self.id = .allOutlines(account.id.accountID)
		self.account = account
	}
	
}
