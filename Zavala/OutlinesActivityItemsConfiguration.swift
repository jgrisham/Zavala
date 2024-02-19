//
//  Created by Maurice Parker on 11/27/22.
//

import UIKit
import CloudKit
import UniformTypeIdentifiers
import LinkPresentation
import VinOutlineKit

protocol OutlinesActivityItemsConfigurationDelegate: AnyObject {
	var selectedOutlines: [Outline] { get }
}

class OutlinesActivityItemsConfiguration: NSObject {
	
	private weak var delegate: OutlinesActivityItemsConfigurationDelegate?
	private var heldOutlines: [Outline]?
	
	var selectedOutlines: [Outline] {
		return heldOutlines ?? delegate?.selectedOutlines ?? []
	}
	
	init(delegate: OutlinesActivityItemsConfigurationDelegate) {
		self.delegate = delegate
	}
	
	init(selectedOutlines: [Outline]) {
		heldOutlines = selectedOutlines
	}
}

extension OutlinesActivityItemsConfiguration: UIActivityItemsConfigurationReading {
	
	@objc var applicationActivitiesForActivityItemsConfiguration: [UIActivity]? {
		guard !selectedOutlines.isEmpty else {
			return nil
		}
		
		return [CopyOutlineLinkActivity(outlines: selectedOutlines)]
	}
	
	var itemProvidersForActivityItemsConfiguration: [NSItemProvider] {
		guard !selectedOutlines.isEmpty else {
			return [NSItemProvider]()
		}
		
		let itemProviders: [NSItemProvider] = selectedOutlines.compactMap { outline in
			let itemProvider = NSItemProvider()
			
			itemProvider.registerDataRepresentation(for: UTType.utf8PlainText, visibility: .all) { completion in
				Task {
					let data = await outline.markdownList().data(using: .utf8)
					completion(data, nil)
				}
				return nil
			}
			
			Task {
				if outline.isCloudKit, let container = await Outliner.shared.cloudKitAccount?.cloudKitContainer {
					let sharingOptions = CKAllowedSharingOptions(allowedParticipantPermissionOptions: .readWrite, allowedParticipantAccessOptions: .any)

					if let shareRecord = outline.cloudKitShareRecord {
						itemProvider.registerCKShare(shareRecord, container: container, allowedSharingOptions: sharingOptions)
					} else {
						itemProvider.registerCKShare(container: container, allowedSharingOptions: sharingOptions) {
							let share = try await Outliner.shared.cloudKitAccount!.generateCKShare(for: outline)
							Task {
								await Outliner.shared.sync()
							}
							return share
						}
					}
				}
			}
			
			return itemProvider
		}
		
		return itemProviders
	}
	
	func activityItemsConfigurationMetadataForItem(at: Int, key: UIActivityItemsConfigurationMetadataKey) -> Any? {
		guard !selectedOutlines.isEmpty, at < selectedOutlines.count else {
			return nil
		}

		switch key {
		case .title:
			return selectedOutlines[at].title
		case .linkPresentationMetadata:
			let iconView = UIImageView(image: .outline)
			iconView.backgroundColor = .accentColor
			iconView.tintColor = .label
			iconView.contentMode = .scaleAspectFit
			iconView.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
			let metadata = LPLinkMetadata()
			metadata.title = selectedOutlines[at].title
			metadata.iconProvider = NSItemProvider(object: iconView.asImage())
			return metadata
		default:
			return nil
		}
	}

}
