//
//  CollectionsViewController.swift
//  Zavala
//
//  Created by Maurice Parker on 11/5/20.
//

import UIKit
import UniformTypeIdentifiers
import Combine
import VinOutlineKit
import VinUtility

protocol CollectionsDelegate: AnyObject {
	func documentContainerSelectionsDidChange(_: CollectionsViewController, documentContainers: [DocumentContainer], isNavigationBranch: Bool, animated: Bool) async
	func showSettings(_: CollectionsViewController)
	func importOPML(_: CollectionsViewController)
	func createOutline(_: CollectionsViewController)
}

enum CollectionsSection: Int {
	case search, localAccount, cloudKitAccount
}

class CollectionsViewController: UICollectionViewController, MainControllerIdentifiable {
	var mainControllerIdentifer: MainControllerIdentifier { return .collections }
	
	weak var delegate: CollectionsDelegate?
	
	var selectedAccount: Account? {
        selectedDocumentContainers?.uniqueAccount
	}
	
	var selectedTags: [Tag]? {
        return selectedDocumentContainers?.compactMap { ($0 as? TagDocuments)?.tag }
	}
	
	var selectedDocumentContainers: [DocumentContainer]? {
		guard let selectedIndexPaths = collectionView.indexPathsForSelectedItems else {
			return nil
		}
        
        return selectedIndexPaths.compactMap { indexPath in
            if let entityID = dataSource.itemIdentifier(for: indexPath)?.entityID {
                return documentContainersDictionary[entityID]
            }
            return nil
        }
	}

	var dataSource: UICollectionViewDiffableDataSource<CollectionsSection, CollectionsItem>!
	
	var documentContainersDictionary = [EntityID: DocumentContainer]()
	
	private var applyChangeDebouncer = Debouncer(duration: 0.5)
	private var reloadVisibleDebouncer = Debouncer(duration: 0.5)

	private var addButton: UIButton!
	private var importButton: UIButton!

    private var selectBarButtonItem: UIBarButtonItem!
    private var selectDoneBarButtonItem: UIBarButtonItem!
	
	private let iCloudActivityIndicatorView = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
		super.viewDidLoad()

		if traitCollection.userInterfaceIdiom == .mac {
			navigationController?.setNavigationBarHidden(true, animated: false)
			collectionView.allowsMultipleSelection = true
		} else {
			if traitCollection.userInterfaceIdiom == .pad {
				selectBarButtonItem = UIBarButtonItem(title: .selectControlLabel, style: .plain, target: self, action: #selector(multipleSelect))
				selectDoneBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(multipleSelectDone))

				navigationItem.rightBarButtonItem = selectBarButtonItem
			} else {
				let navButtonGroup = ButtonGroup(hostController: self, containerType: .standard, alignment: .right)
				importButton = navButtonGroup.addButton(label: .importOPMLControlLabel, image: .importDocument, selector: "importOPML:")
				addButton = navButtonGroup.addButton(label: .addControlLabel, image: .createEntity, selector: "createOutline:")
				let navButtonsBarButtonItem = navButtonGroup.buildBarButtonItem()

				navigationItem.rightBarButtonItem = navButtonsBarButtonItem
			}

			collectionView.refreshControl = UIRefreshControl()
			collectionView.alwaysBounceVertical = true
			collectionView.refreshControl!.addTarget(self, action: #selector(sync), for: .valueChanged)
			collectionView.refreshControl!.tintColor = .clear
		}
        
		NotificationCenter.default.addObserver(self, selector: #selector(activeAccountsDidChange(_:)), name: .ActiveAccountsDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(accountDidReload(_:)), name: .AccountDidReload, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(accountMetadataDidChange(_:)), name: .AccountMetadataDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(accountTagsDidChange(_:)), name: .AccountTagsDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(outlineTagsDidChange(_:)), name: .OutlineTagsDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(cloudKitSyncWillBegin(_:)), name: .CloudKitSyncWillBegin, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(cloudKitSyncDidComplete(_:)), name: .CloudKitSyncDidComplete, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(accountDocumentsDidChange(_:)), name: .AccountDocumentsDidChange, object: nil)
	}
	
	// MARK: API
	
	func startUp() async {
		collectionView.remembersLastFocusedIndexPath = true
		collectionView.dragDelegate = self
		collectionView.dropDelegate = self
		collectionView.collectionViewLayout = createLayout()
		configureDataSource()
		await applyInitialSnapshot()
	}
	
	func selectDocumentContainers(_ containers: [DocumentContainer]?, isNavigationBranch: Bool, animated: Bool) async {
        collectionView.deselectAll()
        
        if let containers, containers.count > 1, traitCollection.userInterfaceIdiom == .pad {
            multipleSelect()
        }
        
        if let containers, containers.count == 1, let search = containers.first as? Search {
			DispatchQueue.main.async {
				if let searchCellIndexPath = self.dataSource.indexPath(for: CollectionsItem.searchItem()) {
					if let searchCell = self.collectionView.cellForItem(at: searchCellIndexPath) as? CollectionsSearchCell {
						searchCell.setSearchField(searchText: search.searchText)
					}
				}
			}
		} else {
			clearSearchField()
		}

		await updateSelections(containers, isNavigationBranch: isNavigationBranch, animated: animated)
	}
	
	// MARK: Notifications
	
	@objc func activeAccountsDidChange(_ note: Notification) {
		debounceApplyChangeSnapshot()
	}

	@objc func accountDidReload(_ note: Notification) {
		debounceApplyChangeSnapshot()
		debounceReloadVisible()
		updateSelections()
	}
	
	@objc func accountMetadataDidChange(_ note: Notification) {
		debounceApplyChangeSnapshot()
	}
	
	@objc func accountTagsDidChange(_ note: Notification) {
		debounceApplyChangeSnapshot()
		debounceReloadVisible()
	}

	@objc func outlineTagsDidChange(_ note: Notification) {
		debounceReloadVisible()
	}

	@objc func accountDocumentsDidChange(_ note: Notification) {
		debounceReloadVisible()
	}

	@objc func cloudKitSyncWillBegin(_ note: Notification) {
		// Let any pending UI things like adding the account happen so that we have something to put the spinner on
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
			self.iCloudActivityIndicatorView.startAnimating()
		}
	}
	
	@objc func cloudKitSyncDidComplete(_ note: Notification) {
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
			self.iCloudActivityIndicatorView.stopAnimating()
		}
	}
	
	// MARK: Actions
	
	@objc func sync() {
		Task {
			if await Outliner.shared.isSyncAvailable {
				await Outliner.shared.sync()
			}
		}
		collectionView?.refreshControl?.endRefreshing()
	}
	
	@IBAction func showSettings(_ sender: Any) {
		delegate?.showSettings(self)
	}
	
	@objc func importOPML(_ sender: Any) {
		delegate?.importOPML(self)
	}

    @objc func createOutline(_ sender: Any) {
        delegate?.createOutline(self)
    }
    
    @objc func multipleSelect() {
		Task {
			await selectDocumentContainers(nil, isNavigationBranch: true, animated: true)
			collectionView.allowsMultipleSelection = true
			navigationItem.rightBarButtonItem = selectDoneBarButtonItem
		}
    }

    @objc func multipleSelectDone() {
		Task {
			await selectDocumentContainers(nil, isNavigationBranch: true, animated: true)
			collectionView.allowsMultipleSelection = false
			navigationItem.rightBarButtonItem = selectBarButtonItem
		}
    }

	// MARK: API
	
	func beginDocumentSearch() {
		if let searchCellIndexPath = self.dataSource.indexPath(for: CollectionsItem.searchItem()) {
			if let searchCell = self.collectionView.cellForItem(at: searchCellIndexPath) as? CollectionsSearchCell {
				searchCell.setSearchField(searchText: "")
			}
		}
	}
	
}

// MARK: Collection View

extension CollectionsViewController {
	
	override func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
		// If we don't force the text view to give up focus, we get its additional context menu items
		if let textView = UIResponder.currentFirstResponder as? UITextView {
			textView.resignFirstResponder()
		}
		
		if !(collectionView.indexPathsForSelectedItems?.contains(indexPath) ?? false) {
			collectionView.deselectAll()
		}
		
		let items: [CollectionsItem]
		if let selected = collectionView.indexPathsForSelectedItems, !selected.isEmpty {
			items = selected.compactMap { dataSource.itemIdentifier(for: $0) }
		} else {
			if let item = dataSource.itemIdentifier(for: indexPath) {
				items = [item]
			} else {
				items = [CollectionsItem]()
			}
		}
		
		guard let mainItem = dataSource.itemIdentifier(for: indexPath) else { return nil }
		return makeDocumentContainerContextMenu(mainItem: mainItem, items: items)
	}
    
	override func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
		return false
	}
	
	override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
		if traitCollection.userInterfaceIdiom == .pad {
			if collectionView.allowsMultipleSelection {
				return !(dataSource.itemIdentifier(for: indexPath)?.entityID?.isSystemCollection ?? false)
			}

		}
		return true
	}
		
	override func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        updateSelections()
    }

	override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		clearSearchField()
        updateSelections()
	}
    
    private func updateSelections() {
        guard let selectedIndexes = collectionView.indexPathsForSelectedItems else { return }
        let items = selectedIndexes.compactMap { dataSource.itemIdentifier(for: $0) }
        
		Task {
			let containers = await items.toContainers()
			await delegate?.documentContainerSelectionsDidChange(self, documentContainers: containers, isNavigationBranch: true, animated: true)
		}
    }
    
	private func createLayout() -> UICollectionViewLayout {
		let layout = UICollectionViewCompositionalLayout() { (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
			var configuration = UICollectionLayoutListConfiguration(appearance: .sidebar)
			configuration.showsSeparators = false
			configuration.headerMode = .firstItemInSection
			return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
		}
		return layout
	}
	
	private func configureDataSource() {
		let searchRegistration = UICollectionView.CellRegistration<CollectionsSearchCell, CollectionsItem> { (cell, indexPath, item) in
			var contentConfiguration = CollectionsSearchContentConfiguration(searchText: nil)
			contentConfiguration.delegate = self
			cell.contentConfiguration = contentConfiguration
		}

		let headerRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, CollectionsItem> { [weak self]	(cell, indexPath, item) in
			guard let self else { return }
			
			var contentConfiguration = UIListContentConfiguration.sidebarHeader()
			
			contentConfiguration.text = item.id.name
			if self.traitCollection.userInterfaceIdiom == .mac {
				contentConfiguration.textProperties.font = .preferredFont(forTextStyle: .subheadline)
				contentConfiguration.textProperties.color = .secondaryLabel
			} else {
				contentConfiguration.textProperties.font = .preferredFont(forTextStyle: .title2).with(traits: .traitBold)
				contentConfiguration.textProperties.color = .label
			}
			
			cell.contentConfiguration = contentConfiguration
			cell.accessories = [.outlineDisclosure()]
			
			if item.id.accountType == .cloudKit, let textLayoutGuide = (cell.contentView as? UIListContentView)?.textLayoutGuide {
				self.iCloudActivityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
				
				let trailingAnchorAdjustment: CGFloat
				if self.traitCollection.userInterfaceIdiom == .mac {
					self.iCloudActivityIndicatorView.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
					trailingAnchorAdjustment = 4
				} else {
					trailingAnchorAdjustment = 8
				}
				
				cell.contentView.addSubview(self.iCloudActivityIndicatorView)
				
				NSLayoutConstraint.activate([
					self.iCloudActivityIndicatorView.centerYAnchor.constraint(equalTo: textLayoutGuide.centerYAnchor),
					self.iCloudActivityIndicatorView.leadingAnchor.constraint(equalTo: textLayoutGuide.trailingAnchor, constant: trailingAnchorAdjustment),
				])
			}
		}
		
		let rowRegistration = UICollectionView.CellRegistration<ConsistentCollectionViewListCell, CollectionsItem> { [weak self] (cell, indexPath, item) in
			var contentConfiguration = UIListContentConfiguration.sidebarSubtitleCell()
			
			if case .documentContainer(let entityID) = item.id, let container = self?.documentContainersDictionary[entityID] {
				contentConfiguration.text = container.name
				contentConfiguration.image = container.image
				
				if let count = container.itemCount {
					contentConfiguration.secondaryTextProperties.font = UIFont.preferredFont(forTextStyle: .body)
					contentConfiguration.secondaryText = String(count)
				}
			}

			contentConfiguration.prefersSideBySideTextAndSecondaryText = true
			cell.contentConfiguration = contentConfiguration
		}
		
		dataSource = UICollectionViewDiffableDataSource<CollectionsSection, CollectionsItem>(collectionView: collectionView) { (collectionView, indexPath, item) -> UICollectionViewCell in
			switch item.id {
			case .search:
				return collectionView.dequeueConfiguredReusableCell(using: searchRegistration, for: indexPath, item: item)
			case .header:
				return collectionView.dequeueConfiguredReusableCell(using: headerRegistration, for: indexPath, item: item)
			default:
				return collectionView.dequeueConfiguredReusableCell(using: rowRegistration, for: indexPath, item: item)
			}
		}
	}
	
	private func searchSnapshot() -> NSDiffableDataSourceSectionSnapshot<CollectionsItem> {
		var snapshot = NSDiffableDataSourceSectionSnapshot<CollectionsItem>()
		snapshot.append([CollectionsItem.searchItem()])
		return snapshot
	}
	
	private func localAccountSnapshot() async -> NSDiffableDataSourceSectionSnapshot<CollectionsItem>? {
		guard let localAccount = await Outliner.shared.localAccount else { return nil }
		
		guard await localAccount.isActive else { return nil }
		
		var snapshot = NSDiffableDataSourceSectionSnapshot<CollectionsItem>()
		let header = CollectionsItem.item(id: .header(.localAccount))
		
		let items = await localAccount.documentContainers.map { CollectionsItem.item($0) }
		
		snapshot.append([header])
		snapshot.expand([header])
		snapshot.append(items, to: header)
		return snapshot
	}
	
	private func cloudKitAccountSnapshot() async -> NSDiffableDataSourceSectionSnapshot<CollectionsItem>? {
		guard let cloudKitAccount = await Outliner.shared.cloudKitAccount else { return nil }
		
		var snapshot = NSDiffableDataSourceSectionSnapshot<CollectionsItem>()
		let header = CollectionsItem.item(id: .header(.cloudKitAccount))
		
		let items = await cloudKitAccount.documentContainers.map { CollectionsItem.item($0) }
		
		snapshot.append([header])
		snapshot.expand([header])
		snapshot.append(items, to: header)
		return snapshot
	}
	
	private func applyInitialSnapshot() async {
		if traitCollection.userInterfaceIdiom == .mac {
			applySnapshot(searchSnapshot(), section: .search, animated: false)
		}
		await applyChangeSnapshot()
	}
	
	private func applyChangeSnapshot() async {
		await rebuildContainersDictionary()
		
		if let snapshot = await localAccountSnapshot() {
			applySnapshot(snapshot, section: .localAccount, animated: true)
		} else {
			applySnapshot(NSDiffableDataSourceSectionSnapshot<CollectionsItem>(), section: .localAccount, animated: true)
		}

		if let snapshot = await self.cloudKitAccountSnapshot() {
			applySnapshot(snapshot, section: .cloudKitAccount, animated: true)
		} else {
			applySnapshot(NSDiffableDataSourceSectionSnapshot<CollectionsItem>(), section: .cloudKitAccount, animated: true)
		}
	}
	
	func applySnapshot(_ snapshot: NSDiffableDataSourceSectionSnapshot<CollectionsItem>, section: CollectionsSection, animated: Bool) {
		let selectedItems = collectionView.indexPathsForSelectedItems?.compactMap({ dataSource.itemIdentifier(for: $0) })
		
		dataSource.apply(snapshot, to: section, animatingDifferences: animated) { [weak self] in
			guard let self else { return }

			let selectedIndexPaths = selectedItems?.compactMap { self.dataSource.indexPath(for: $0) } ?? [IndexPath]()
			
			if let selectedItems, !selectedItems.isEmpty, selectedIndexPaths.isEmpty {
				Task {
					await self.delegate?.documentContainerSelectionsDidChange(self, documentContainers: [], isNavigationBranch: false, animated: true)
				}
			} else {
				for selectedIndexPath in selectedIndexPaths {
					self.collectionView.selectItem(at: selectedIndexPath, animated: false, scrollPosition: [])
				}
			}
		}

	}
	
	func updateSelections(_ containers: [DocumentContainer]?, isNavigationBranch: Bool, animated: Bool) async {
        let items = containers?.map { CollectionsItem.item($0) } ?? [CollectionsItem]()
		let indexPaths = items.compactMap { dataSource.indexPath(for: $0) }

		if !indexPaths.isEmpty {
			for indexPath in indexPaths {
				collectionView.selectItem(at: indexPath, animated: animated, scrollPosition: .centeredVertically)
			}
		} else {
			collectionView.deselectAll()
		}
		
		let containers = await items.toContainers()
		await delegate?.documentContainerSelectionsDidChange(self, documentContainers: containers, isNavigationBranch: isNavigationBranch, animated: animated)
	}
	
	func reloadVisible() {
		let visibleIndexPaths = collectionView.indexPathsForVisibleItems
		let items = visibleIndexPaths.compactMap { dataSource.itemIdentifier(for: $0) }
		var snapshot = dataSource.snapshot()
		snapshot.reloadItems(items)
		dataSource.apply(snapshot)
	}
	
}

// MARK: CollectionsSearchCellDelegate

extension CollectionsViewController: CollectionsSearchCellDelegate {

	func collectionsSearchDidBecomeActive() {
		Task {
			await selectDocumentContainers([Search(searchText: "")], isNavigationBranch: false, animated: false)
		}
	}

	func collectionsSearchDidUpdate(searchText: String?) {
		Task {
			if let searchText {
				await selectDocumentContainers([Search(searchText: searchText)], isNavigationBranch: false, animated: true)
			} else {
				await selectDocumentContainers([Search(searchText: "")], isNavigationBranch: false, animated: false)
			}

		}
	}
	
}

// MARK: Helpers

private extension CollectionsViewController {
	
	func clearSearchField() {
		if let searchCellIndexPath = dataSource.indexPath(for: CollectionsItem.searchItem()) {
			if let searchCell = collectionView.cellForItem(at: searchCellIndexPath) as? CollectionsSearchCell {
				searchCell.clearSearchField()
			}
		}
	}
	
	func debounceApplyChangeSnapshot() {
		applyChangeDebouncer.debounce { [weak self] in
			Task {
				await self?.applyChangeSnapshot()
			}
		}
	}
	
	func debounceReloadVisible() {
		reloadVisibleDebouncer.debounce { [weak self] in
			self?.reloadVisible()
		}
	}
	
	func makeDocumentContainerContextMenu(mainItem: CollectionsItem, items: [CollectionsItem]) -> UIContextMenuConfiguration {
		return UIContextMenuConfiguration(identifier: mainItem as NSCopying, previewProvider: nil, actionProvider: { [weak self] suggestedActions in
			guard let self else { return nil }

			let containers: [DocumentContainer] = items.compactMap { item in
				if case .documentContainer(let entityID) = item.id {
					return self.documentContainersDictionary[entityID]
				}
				return nil
			}
			
			var menuItems = [UIMenu]()
			if let renameTagAction = self.renameTagAction(containers: containers) {
				menuItems.append(UIMenu(title: "", options: .displayInline, children: [renameTagAction]))
			}
			if let deleteTagAction = self.deleteTagAction(containers: containers) {
				menuItems.append(UIMenu(title: "", options: .displayInline, children: [deleteTagAction]))
			}
			return UIMenu(title: "", children: menuItems)
		})
	}

	func renameTagAction(containers: [DocumentContainer]) -> UIAction? {
		guard containers.count == 1, let container = containers.first, let tagDocuments = container as? TagDocuments else { return nil }
		
		let action = UIAction(title: .renameControlLabel, image: .rename) { [weak self] action in
			guard let self else { return }
			
			if self.traitCollection.userInterfaceIdiom == .mac {
				let renameTagViewController = UIStoryboard.dialog.instantiateController(ofType: MacRenameTagViewController.self)
				renameTagViewController.preferredContentSize = CGSize(width: 400, height: 80)
				renameTagViewController.tagDocuments = tagDocuments
				self.present(renameTagViewController, animated: true)
			} else {
				let renameTagNavViewController = UIStoryboard.dialog.instantiateViewController(withIdentifier: "RenameTagViewControllerNav") as! UINavigationController
				renameTagNavViewController.preferredContentSize = CGSize(width: 400, height: 100)
				renameTagNavViewController.modalPresentationStyle = .formSheet
				let renameTagViewController = renameTagNavViewController.topViewController as! RenameTagViewController
				renameTagViewController.tagDocuments = tagDocuments
				self.present(renameTagNavViewController, animated: true)
			}
		}
		
		return action
	}

	func deleteTagAction(containers: [DocumentContainer]) -> UIAction? {
		let tagDocuments = containers.compactMap { $0 as? TagDocuments }
		guard tagDocuments.count == containers.count else { return nil}
		
		let action = UIAction(title: .deleteControlLabel, image: .delete, attributes: .destructive) { [weak self] action in
			let deleteAction = UIAlertAction(title: .deleteControlLabel, style: .destructive) { _ in
				for tagDocument in tagDocuments {
					if let tag = tagDocument.tag {
						tagDocument.account?.forceDeleteTag(tag)
					}
				}
			}
			
			let title: String
			let message: String
			if tagDocuments.count == 1, let tag = tagDocuments.first?.tag {
				title = .deleteTagPrompt(tagName: tag.name)
				message = .deleteTagMessage
			} else {
				title = .deleteTagsPrompt(tagCount: tagDocuments.count)
				message = .deleteTagsMessage
			}
			
			let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
			alert.addAction(deleteAction)
			alert.addAction(UIAlertAction(title: .cancelControlLabel, style: .cancel))
			alert.preferredAction = deleteAction
			self?.present(alert, animated: true, completion: nil)
		}
		
		return action
	}

	func rebuildContainersDictionary() async {
		var containersDictionary = [EntityID: DocumentContainer]()
		
		let containers = await Outliner.shared.documentContainers
		for container in containers {
			containersDictionary[container.id] = container
		}
		
		self.documentContainersDictionary = containersDictionary
	}
}
