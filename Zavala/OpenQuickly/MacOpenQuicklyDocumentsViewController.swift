//
//  MacOpenQuicklyListViewController.swift
//  Zavala
//
//  Created by Maurice Parker on 3/20/21.
//

import UIKit
import VinOutlineKit
import VinUtility

protocol MacOpenQuicklyListDelegate: AnyObject {
	func outlineSelectionDidChange(_: MacOpenQuicklyListViewController, outlineID: EntityID?)
	func openOutline(_: MacOpenQuicklyListViewController, outlineID: EntityID)
}

final class OutlineItem: NSObject, NSCopying, Identifiable {

		let id: EntityID

		init(id: EntityID) {
				self.id = id
		}

		static func item(_ outline: Outline) -> OutlineItem {
				return OutlineItem(id: outline.id)
		}

		override func isEqual(_ object: Any?) -> Bool {
				guard let other = object as? OutlineItem else { return false }
				if self === other { return true }
				return id == other.id
		}

		override var hash: Int {
				var hasher = Hasher()
				hasher.combine(id)
				return hasher.finalize()
		}

		func copy(with zone: NSZone? = nil) -> Any {
				return self
		}

}

class MacOpenQuicklyListViewController: UICollectionViewController {

	weak var delegate: MacOpenQuicklyListDelegate?
	private var outlineContainers: [OutlineContainer]?
	private var outlineDictionary = [EntityID: Outline]()

	private var dataSource: UICollectionViewDiffableDataSource<Int, OutlineItem>!

    override func viewDidLoad() {
        super.viewDidLoad()

		collectionView.layer.borderWidth = 1
		collectionView.layer.borderColor = UIColor.systemGray2.cgColor
		collectionView.layer.cornerRadius = 3
		
		collectionView.collectionViewLayout = createLayout()
		configureDataSource()
		
		Task {
			await rebuildOutlinesDictionary()
			applySnapshot()
		}
	}

	func setOutlineContainers(_ outlineContainers: [OutlineContainer]) {
		self.outlineContainers = outlineContainers
		collectionView.deselectAll()
		applySnapshot()
	}
	
	// MARK: UICollectionView
	
	private func createLayout() -> UICollectionViewLayout {
		let layout = UICollectionViewCompositionalLayout() { (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
			var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
			configuration.showsSeparators = false
			return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
		}
		return layout
	}
	
	private func configureDataSource() {
		let rowRegistration = UICollectionView.CellRegistration<ConsistentCollectionViewListCell, OutlineItem> { [weak self] (cell, indexPath, item) in
			guard let self, let outline = outlineDictionary[item.id] else { return }
			
			var contentConfiguration = UIListContentConfiguration.subtitleCell()
			cell.insetBackground = true

			let title = (outline.title?.isEmpty ?? true) ? .noTitleLabel : outline.title!

			if outline.isCollaborating {
				let attrText = NSMutableAttributedString(string: "\(title) ")
				let shareAttachement = NSTextAttachment(image: .collaborating)
				attrText.append(NSAttributedString(attachment: shareAttachement))
				contentConfiguration.attributedText = attrText
			} else {
				contentConfiguration.text = title
			}
			
			cell.contentConfiguration = contentConfiguration
			
			let singleTap = UITapGestureRecognizer(target: self, action: #selector(self.selectOutline(gesture:)))
			cell.addGestureRecognizer(singleTap)
			
			if self.traitCollection.userInterfaceIdiom == .mac {
				let doubleTap = UITapGestureRecognizer(target: self, action: #selector(self.openDocumentInNewWindow(gesture:)))
				doubleTap.numberOfTapsRequired = 2
				cell.addGestureRecognizer(doubleTap)
			}
		}
		
		dataSource = UICollectionViewDiffableDataSource<Int, OutlineItem>(collectionView: collectionView) { (collectionView, indexPath, item) -> UICollectionViewCell in
			return collectionView.dequeueConfiguredReusableCell(using: rowRegistration, for: indexPath, item: item)
		}
	}

	@objc private func selectOutline(gesture: UITapGestureRecognizer) {
		guard let cell = gesture.view as? UICollectionViewCell,
			  let indexPath = collectionView.indexPath(for: cell),
			  let item = dataSource.itemIdentifier(for: indexPath) else { return }

		collectionView.deselectAll()
		collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
		delegate?.outlineSelectionDidChange(self, outlineID: item.id)
	}
	
	@objc func openDocumentInNewWindow(gesture: UITapGestureRecognizer) {
		guard let cell = gesture.view as? UICollectionViewCell,
			  let indexPath = collectionView.indexPath(for: cell),
			  let item = dataSource.itemIdentifier(for: indexPath) else { return }

		delegate?.openOutline(self, outlineID: item.id)
	}
	
	func applySnapshot() {
		guard let outlineContainers else {
			let snapshot = NSDiffableDataSourceSectionSnapshot<OutlineItem>()
			self.dataSource.apply(snapshot, to: 0, animatingDifferences: false)
			return
		}
		
		let tags = outlineContainers.tags
		let selectionContainers: [OutlineProvider]
		if !tags.isEmpty {
			selectionContainers = [TagsOutlines(tags: tags)]
		} else {
			selectionContainers = outlineContainers
		}
	
		Task {
			let outlines = await withTaskGroup(of: [Outline].self, returning: Set<Outline>.self) { taskGroup in
				for container in selectionContainers {
					taskGroup.addTask {
						return (try? await container.outlines) ?? []
					}
				}
				
				var outlines = Set<Outline>()
				for await containerOutlines in taskGroup {
					outlines.formUnion(containerOutlines)
				}				
				return outlines
			}
			
			let sortedOutlines = outlines.sorted(by: { ($0.title ?? "").caseInsensitiveCompare($1.title ?? "") == .orderedAscending })
			let items = sortedOutlines.map { OutlineItem.item($0) }
			var snapshot = NSDiffableDataSourceSectionSnapshot<OutlineItem>()
			snapshot.append(items)

			Task { @MainActor in
				dataSource.apply(snapshot, to: 0, animatingDifferences: false)
			}
		}
	}
	
	func rebuildOutlinesDictionary() async {
		var outlineDictionary = [EntityID: Outline]()
		
		let outlines = await Outliner.shared.outlines
		for outline in outlines {
			outlineDictionary[outline.id] = outline
		}
		
		self.outlineDictionary = outlineDictionary
	}

}
