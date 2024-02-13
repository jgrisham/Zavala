//
//  DocumentsActivityItemsConfiguration.swift
//  Zavala
//
//  Created by Maurice Parker on 11/27/22.
//

import UIKit
import CloudKit
import UniformTypeIdentifiers
import LinkPresentation
import VinOutlineKit

protocol DocumentsActivityItemsConfigurationDelegate: AnyObject {
	var selectedDocuments: [Document] { get }
}

class DocumentsActivityItemsConfiguration: NSObject {
	
	private weak var delegate: DocumentsActivityItemsConfigurationDelegate?
	private var heldDocuments: [Document]?
	
	var selectedDocuments: [Document] {
		return heldDocuments ?? delegate?.selectedDocuments ?? []
	}
	
	init(delegate: DocumentsActivityItemsConfigurationDelegate) {
		self.delegate = delegate
	}
	
	init(selectedDocuments: [Document]) {
		heldDocuments = selectedDocuments
	}
}

extension DocumentsActivityItemsConfiguration: UIActivityItemsConfigurationReading {
	
	@objc var applicationActivitiesForActivityItemsConfiguration: [UIActivity]? {
		guard !selectedDocuments.isEmpty else {
			return nil
		}
		
		return [CopyDocumentLinkActivity(documents: selectedDocuments)]
	}
	
	var itemProvidersForActivityItemsConfiguration: [NSItemProvider] {
		guard !selectedDocuments.isEmpty else {
			return [NSItemProvider]()
		}
		
		let itemProviders: [NSItemProvider] = selectedDocuments.compactMap { document in
			let itemProvider = NSItemProvider()
			
			itemProvider.registerDataRepresentation(for: UTType.utf8PlainText, visibility: .all) { completion in
				Task {
					let data = await document.formattedPlainText.data(using: .utf8)
					completion(data, nil)
				}
				return nil
			}
			
			Task {
				if document.isCloudKit, let container = await AccountManager.shared.cloudKitAccount?.cloudKitContainer {
					let sharingOptions = CKAllowedSharingOptions(allowedParticipantPermissionOptions: .readWrite, allowedParticipantAccessOptions: .any)

					if let shareRecord = document.shareRecord {
						itemProvider.registerCKShare(shareRecord, container: container, allowedSharingOptions: sharingOptions)
					} else {
						itemProvider.registerCKShare(container: container, allowedSharingOptions: sharingOptions) {
							let share = try await AccountManager.shared.cloudKitAccount!.generateCKShare(for: document)
							Task {
								await AccountManager.shared.sync()
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
		guard !selectedDocuments.isEmpty, at < selectedDocuments.count else {
			return nil
		}

		switch key {
		case .title:
			return selectedDocuments[at].title
		case .linkPresentationMetadata:
			let iconView = UIImageView(image: .outline)
			iconView.backgroundColor = .accentColor
			iconView.tintColor = .label
			iconView.contentMode = .scaleAspectFit
			iconView.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
			let metadata = LPLinkMetadata()
			metadata.title = selectedDocuments[at].title
			metadata.iconProvider = NSItemProvider(object: iconView.asImage())
			return metadata
		default:
			return nil
		}
	}

}
