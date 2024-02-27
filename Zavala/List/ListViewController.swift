//
//  Created by Maurice Parker on 11/9/20.
//

import UIKit
import UniformTypeIdentifiers
import CoreSpotlight
import Semaphore
import VinOutlineKit
import VinUtility

protocol ListDelegate: AnyObject  {
	func outlineSelectionDidChange(_: ListViewController, outlineContainers: [OutlineContainer], outlines: [Outline], isNew: Bool, isNavigationBranch: Bool, animated: Bool)
	func showGetInfo(_: ListViewController, outline: Outline)
	func exportPDFDocs(_: ListViewController, outlines: [Outline])
	func exportPDFLists(_: ListViewController, outlines: [Outline])
	func exportMarkdownDocs(_: ListViewController, outlines: [Outline])
	func exportMarkdownLists(_: ListViewController, outlines: [Outline])
	func exportOPMLs(_: ListViewController, outlines: [Outline])
	func printDocs(_: ListViewController, outlines: [Outline])
	func printLists(_: ListViewController, outlines: [Outline])
}

class ListViewController: UICollectionViewController, MainControllerIdentifiable, OutlinesActivityItemsConfigurationDelegate {

	var mainControllerIdentifer: MainControllerIdentifier { return .list }

	weak var delegate: ListDelegate?

	var selectedOutlines: [Outline] {
		guard let indexPaths = collectionView.indexPathsForSelectedItems else { return [] }
		return indexPaths.sorted().map { outlines[$0.row] }
	}
	
	var outlines = [Outline]()

	override var canBecomeFirstResponder: Bool { return true }

	private(set) var outlineContainers: [OutlineContainer]?
	private var heldOutlineContainers: [OutlineContainer]?

	private let searchController = UISearchController(searchResultsController: nil)

	private var navButtonsBarButtonItem: UIBarButtonItem!
	private var addButton: UIButton!
	private var importButton: UIButton!

	private let loadOutlinesSemaphore = AsyncSemaphore(value: 1)
	private var loadOutlinesDebouncer = Debouncer(duration: 0.5)
	
	private var lastClick: TimeInterval = Date().timeIntervalSince1970
	private var lastIndexPath: IndexPath? = nil

	private var rowRegistration: UICollectionView.CellRegistration<ConsistentCollectionViewListCell, Outline>!
	
	private var relativeFormatter: RelativeDateTimeFormatter = {
		let relativeDateTimeFormatter = RelativeDateTimeFormatter()
		relativeDateTimeFormatter.dateTimeStyle = .named
		relativeDateTimeFormatter.unitsStyle = .full
		relativeDateTimeFormatter.formattingContext = .beginningOfSentence
		return relativeDateTimeFormatter
	}()
	
	override func viewDidLoad() {
		super.viewDidLoad()

		if traitCollection.userInterfaceIdiom == .mac {
			navigationController?.setNavigationBarHidden(true, animated: false)
			collectionView.allowsMultipleSelection = true
			collectionView.contentInset = UIEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
		} else {
			let navButtonGroup = ButtonGroup(hostController: self, containerType: .standard, alignment: .right)
			importButton = navButtonGroup.addButton(label: .importOPMLControlLabel, image: .importOutline, selector: "importOPML")
			addButton = navButtonGroup.addButton(label: .addControlLabel, image: .createEntity, selector: "createOutline")
			navButtonsBarButtonItem = navButtonGroup.buildBarButtonItem()

			searchController.delegate = self
			searchController.searchResultsUpdater = self
			searchController.obscuresBackgroundDuringPresentation = false
			searchController.searchBar.placeholder = .searchPlaceholder
			navigationItem.searchController = searchController
			definesPresentationContext = true

			navigationItem.rightBarButtonItem = navButtonsBarButtonItem

			collectionView.refreshControl = UIRefreshControl()
			collectionView.alwaysBounceVertical = true
			collectionView.refreshControl!.addTarget(self, action: #selector(sync), for: .valueChanged)
			collectionView.refreshControl!.tintColor = .clear
		}
		
		collectionView.dragDelegate = self
		collectionView.dropDelegate = self
		collectionView.remembersLastFocusedIndexPath = true
		collectionView.collectionViewLayout = createLayout()
		collectionView.reloadData()
		
		rowRegistration = UICollectionView.CellRegistration<ConsistentCollectionViewListCell, Outline> { [weak self] (cell, indexPath, outline) in
			guard let self else { return }
			
			let title = (outline.title?.isEmpty ?? true) ? .noTitleLabel : outline.title!
			
			var contentConfiguration = UIListContentConfiguration.subtitleCell()
			if outline.isCollaborating {
				let attrText = NSMutableAttributedString(string: "\(title) ")
				let shareAttachement = NSTextAttachment(image: .collaborating)
				attrText.append(NSAttributedString(attachment: shareAttachement))
				contentConfiguration.attributedText = attrText
			} else {
				contentConfiguration.text = title
			}

			if let updated = outline.updated {
				contentConfiguration.secondaryTextProperties.font = .preferredFont(forTextStyle: .body)
				contentConfiguration.secondaryText = self.relativeFormatter.localizedString(for: updated, relativeTo: Date())
			}

			contentConfiguration.prefersSideBySideTextAndSecondaryText = true
			
			if self.traitCollection.userInterfaceIdiom == .mac {
				cell.insetBackground = true
				contentConfiguration.textProperties.font = .preferredFont(forTextStyle: .body)
				contentConfiguration.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
			}
			
			cell.contentConfiguration = contentConfiguration
			cell.setNeedsUpdateConfiguration()
		}
		
		NotificationCenter.default.addObserver(self, selector: #selector(accountOutlinesDidChange(_:)), name: .AccountOutlinesDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(outlineTagsDidChange(_:)), name: .OutlineTagsDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(outlineTitleDidChange(_:)), name: .OutlineTitleDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(outlineUpdatedDidChange(_:)), name: .OutlineUpdatedDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(outlineSharingDidChange(_:)), name: .OutlineSharingDidChange, object: nil)
		
		scheduleReconfigureAll()
	}
	
	override func viewDidAppear(_ animated: Bool) {
		updateUI()
	}
	
	// MARK: API
	
	func setOutlineContainers(_ outlineContainers: [OutlineContainer], isNavigationBranch: Bool) async {
		func updateContainer() async {
			self.outlineContainers = outlineContainers
			updateUI()
			collectionView.deselectAll()
			await loadOutlines(animated: false, isNavigationBranch: isNavigationBranch)
		}
		
		if outlineContainers.count == 1, outlineContainers.first is Search {
			await updateContainer()
		} else {
			heldOutlineContainers = nil
			searchController.searchBar.text = ""
			searchController.dismiss(animated: false)
			await updateContainer()
		}
	}

	func selectOutline(_ outline: Outline?, isNew: Bool = false, isNavigationBranch: Bool = true, animated: Bool) {
		guard let outlineContainers else { return }

		collectionView.deselectAll()

		if let outline, let index = outlines.firstIndex(of: outline) {
			collectionView.selectItem(at: IndexPath(row: index, section: 0), animated: true, scrollPosition: .centeredVertically)
			delegate?.outlineSelectionDidChange(self, outlineContainers: outlineContainers, outlines: [outline], isNew: isNew, isNavigationBranch: isNavigationBranch, animated: animated)
		} else {
			delegate?.outlineSelectionDidChange(self, outlineContainers: outlineContainers, outlines: [], isNew: isNew, isNavigationBranch: isNavigationBranch, animated: animated)
		}
	}
	
	func selectAllOutlines() {
		guard let outlineContainers else { return }

		for i in 0..<collectionView.numberOfItems(inSection: 0) {
			collectionView.selectItem(at: IndexPath(row: i, section: 0), animated: false, scrollPosition: [])
		}
		
		delegate?.outlineSelectionDidChange(self, outlineContainers: outlineContainers, outlines: outlines, isNew: false, isNavigationBranch: false, animated: true)
	}
	
	func deleteCurrentOutlines() {
		deleteOutlines(selectedOutlines)
	}
	
	func importOPMLs(urls: [URL]) async {
		guard let outlineContainers,
			  let account = outlineContainers.uniqueAccount else { return }

		var outline: Outline?
		for url in urls {
			do {
				let tags = outlineContainers.compactMap { ($0 as? TagOutlines)?.tag }
				outline = try await account.importOPML(url, tags: tags)
				OutlineIndexer.updateIndex(for: outline!)
			} catch {
				self.presentError(title: .importFailedTitle, message: error.localizedDescription)
			}
		}
		
		if let outline {
			Task {
				await loadOutlines(animated: true)
				selectOutline(outline, animated: true)
			}
		}
	}
	
	func createOutline(animated: Bool) async {
		guard let outline = await createOutline(title: "") else { return }
		Task {
			await loadOutlines(animated: animated)
			selectOutline(outline, isNew: true, animated: true)
		}
	}

	func createOutline(title: String) async -> Outline? {
		guard let outlineContainers,
			  let account = outlineContainers.uniqueAccount else { return nil }

        let outline = await account.createOutline(title: title, tags: outlineContainers.tags)
		
		let defaults = AppDefaults.shared
		outline.update(checkSpellingWhileTyping: defaults.checkSpellingWhileTyping,
					   correctSpellingAutomatically: defaults.correctSpellingAutomatically,
					   autoLinkingEnabled: defaults.autoLinkingEnabled,
					   ownerName: defaults.ownerName,
					   ownerEmail: defaults.ownerEmail,
					   ownerURL: defaults.ownerURL)
		return outline
	}
	
	func share() {
		guard let indexPath = collectionView.indexPathsForSelectedItems?.first,
			  let cell = collectionView.cellForItem(at: indexPath) else { return }
		
		let controller = UIActivityViewController(activityItemsConfiguration: OutlinesActivityItemsConfiguration(selectedOutlines: selectedOutlines))
		controller.popoverPresentationController?.sourceView = cell
		self.present(controller, animated: true)
	}
	
	func manageSharing() async {
		guard let outline = selectedOutlines.first,
			  let shareRecord = outline.cloudKitShareRecord,
			  let container = await Outliner.shared.cloudKitAccount?.cloudKitContainer,
			  let indexPath = collectionView.indexPathsForSelectedItems?.first,
			  let cell = collectionView.cellForItem(at: indexPath) else {
			return
		}

		let controller = UICloudSharingController(share: shareRecord, container: container)
		controller.popoverPresentationController?.sourceView = cell
		controller.delegate = self
		self.present(controller, animated: true)
	}
	
	// MARK: Notifications
	
	@objc func accountOutlinesDidChange(_ note: Notification) {
		debounceLoadOutlines()
	}
	
	@objc func outlineTagsDidChange(_ note: Notification) {
		debounceLoadOutlines()
	}
	
	@objc func outlineTitleDidChange(_ note: Notification) {
		guard let outline = note.object as? Outline else { return }
		Task { @MainActor in
			reload(outline: outline)
			await loadOutlines(animated: true)
		}
	}
	
	@objc func outlineUpdatedDidChange(_ note: Notification) {
		guard let outline = note.object as? Outline else { return }
		Task { @MainActor in
			reload(outline: outline)
		}
	}
	
	@objc func outlineSharingDidChange(_ note: Notification) {
		guard let outline = note.object as? Outline else { return }
		Task { @MainActor in
			reload(outline: outline)
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
	
	@objc func createOutline() {
		Task {
			await createOutline(animated: true)
		}
	}

	@objc func importOPML() {
		let opmlType = UTType(exportedAs: DataRepresentation.opml.typeIdentifier)
		let docPicker = UIDocumentPickerViewController(forOpeningContentTypes: [opmlType, .xml])
		docPicker.delegate = self
		docPicker.modalPresentationStyle = .formSheet
		docPicker.allowsMultipleSelection = true
		self.present(docPicker, animated: true)
	}

}

// MARK: UIDocumentPickerDelegate

extension ListViewController: UIDocumentPickerDelegate {
	
	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
		Task {
			await importOPMLs(urls: urls)
		}
	}
	
}

// MARK: UICloudSharingControllerDelegate

extension ListViewController: UICloudSharingControllerDelegate {
	
	func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
	}
	
	func itemTitle(for csc: UICloudSharingController) -> String? {
		return nil
	}
	
	func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
		Task {
			try await Task.sleep(for: .seconds(2))
			await Outliner.shared.sync()
		}
	}
	
}

// MARK: Collection View

extension ListViewController {
	
	override func numberOfSections(in collectionView: UICollectionView) -> Int {
		return 1
	}
	
	override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return outlines.count
	}
		
	override func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
		// If we don't force the text view to give up focus, we get its additional context menu items
		if let textView = UIResponder.currentFirstResponder as? UITextView {
			textView.resignFirstResponder()
		}
		
		if !(collectionView.indexPathsForSelectedItems?.contains(indexPath) ?? false) {
			collectionView.deselectAll()
		}
		
		let allRowIDs: [GenericRowIdentifier]
		if let selected = collectionView.indexPathsForSelectedItems, !selected.isEmpty {
			allRowIDs = selected.sorted().compactMap { GenericRowIdentifier(indexPath: $0)}
		} else {
			allRowIDs = [GenericRowIdentifier(indexPath: indexPath)]
		}
		
		return makeOutlineContextMenu(mainRowID: GenericRowIdentifier(indexPath: indexPath), allRowIDs: allRowIDs)
	}
	
	override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		return collectionView.dequeueConfiguredReusableCell(using: rowRegistration, for: indexPath, item: outlines[indexPath.row])
	}

	override func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
		return false
	}
	
	override func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
		guard let outlineContainers else { return }
		
		guard let selectedIndexPaths = collectionView.indexPathsForSelectedItems else {
			delegate?.outlineSelectionDidChange(self, outlineContainers: outlineContainers, outlines: [], isNew: false, isNavigationBranch: false, animated: true)
			return
		}
		
		let selectedOutlines = selectedIndexPaths.map { outlines[$0.row] }
		delegate?.outlineSelectionDidChange(self, outlineContainers: outlineContainers, outlines: selectedOutlines, isNew: false, isNavigationBranch: true, animated: true)
	}
	
	override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		guard let outlineContainers else { return }

		// We have to figure out double clicks for ourselves
		#if targetEnvironment(macCatalyst)
		let now: TimeInterval = Date().timeIntervalSince1970
		if now - lastClick < 0.3 && lastIndexPath?.row == indexPath.row {
			openOutlineInNewWindow(indexPath: indexPath)
		}
		lastClick = now
		lastIndexPath = indexPath
		#endif
		
		guard let selectedIndexPaths = collectionView.indexPathsForSelectedItems else {
			delegate?.outlineSelectionDidChange(self, outlineContainers: outlineContainers, outlines: [], isNew: false, isNavigationBranch: false, animated: true)
			return
		}
		
		let selectedOutlines = selectedIndexPaths.map { outlines[$0.row] }
		delegate?.outlineSelectionDidChange(self, outlineContainers: outlineContainers, outlines: selectedOutlines, isNew: false, isNavigationBranch: true, animated: true)
	}
	
	private func createLayout() -> UICollectionViewLayout {
		let layout = UICollectionViewCompositionalLayout() { [weak self] (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
			let isMac = layoutEnvironment.traitCollection.userInterfaceIdiom == .mac
			var configuration = UICollectionLayoutListConfiguration(appearance: isMac ? .plain : .sidebar)
			configuration.showsSeparators = false

			configuration.trailingSwipeActionsConfigurationProvider = { indexPath in
				guard let self else { return nil }
				return UISwipeActionsConfiguration(actions: [self.deleteContextualAction(indexPath: indexPath)])
			}

			return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
		}
		return layout
	}
	
	func openOutlineInNewWindow(indexPath: IndexPath) {
		collectionView.deselectAll()
		let outline = outlines[indexPath.row]
		
		let activity = NSUserActivity(activityType: NSUserActivity.ActivityType.openEditor)
		activity.userInfo = [Pin.UserInfoKeys.pin: Pin(outline: outline).userInfo]
		UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil, errorHandler: nil)
	}
	
	func reload(outline: Outline) {
		let selectedIndexPaths = self.collectionView.indexPathsForSelectedItems
		if let index = outlines.firstIndex(of: outline) {
			collectionView.reloadItems(at: [IndexPath(row: index, section: 0)])
		}
		if let selectedItem = selectedIndexPaths?.first {
			collectionView.selectItem(at: selectedItem, animated: false, scrollPosition: [])
		}
	}
	
	func loadOutlines(animated: Bool, isNavigationBranch: Bool = false) async {
		guard let outlineContainers else {
			return
		}
		
		await loadOutlinesSemaphore.wait()
		defer { loadOutlinesSemaphore.signal() }

		let tags = outlineContainers.tags
		var selectionContainers: [OutlineProvider]
		if !tags.isEmpty {
			selectionContainers = [TagsOutlines(tags: tags)]
		} else {
			selectionContainers = outlineContainers
		}
		
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

		guard animated else {
			self.outlines = sortedOutlines
			self.collectionView.reloadData()
			self.delegate?.outlineSelectionDidChange(self, outlineContainers: outlineContainers, outlines: [], isNew: false, isNavigationBranch: isNavigationBranch, animated: true)
			return
		}
		
		let prevSelectedDoc = self.collectionView.indexPathsForSelectedItems?.map({ self.outlines[$0.row] }).first

		let diff = sortedOutlines.difference(from: self.outlines).inferringMoves()
		self.outlines = sortedOutlines

		self.collectionView.performBatchUpdates {
			for change in diff {
				switch change {
				case .insert(let offset, _, let associated):
					if let associated {
						self.collectionView.moveItem(at: IndexPath(row: associated, section: 0), to: IndexPath(row: offset, section: 0))
					} else {
						self.collectionView.insertItems(at: [IndexPath(row: offset, section: 0)])
					}
				case .remove(let offset, _, let associated):
					if let associated {
						self.collectionView.moveItem(at: IndexPath(row: offset, section: 0), to: IndexPath(row: associated, section: 0))
					} else {
						self.collectionView.deleteItems(at: [IndexPath(row: offset, section: 0)])
					}
				}
			}
		}
		
		if let prevSelectedDoc, let index = self.outlines.firstIndex(of: prevSelectedDoc) {
			let indexPath = IndexPath(row: index, section: 0)
			self.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
			self.collectionView.scrollToItem(at: indexPath, at: [], animated: true)
		} else {
			self.delegate?.outlineSelectionDidChange(self, outlineContainers: outlineContainers, outlines: [], isNew: false, isNavigationBranch: isNavigationBranch, animated: true)
		}
	}
	
	private func reconfigureAll() {
		let indexPaths = (0..<outlines.count).map { IndexPath(row: $0, section: 0) }
		collectionView.reconfigureItems(at: indexPaths)
	}
	
	private func scheduleReconfigureAll() {
		DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
			self?.reconfigureAll()
			self?.scheduleReconfigureAll()
		}
	}
	
}

// MARK: UISearchControllerDelegate

extension ListViewController: UISearchControllerDelegate {

	func willPresentSearchController(_ searchController: UISearchController) {
		heldOutlineContainers = outlineContainers
		Task {
			await setOutlineContainers([Search(searchText: "")], isNavigationBranch: false)
		}
	}

	func didDismissSearchController(_ searchController: UISearchController) {
		if let heldOutlineContainers {
			Task {
				await setOutlineContainers(heldOutlineContainers, isNavigationBranch: false)
				self.heldOutlineContainers = nil
			}
		}
	}

}

// MARK: UISearchResultsUpdating

extension ListViewController: UISearchResultsUpdating {

	func updateSearchResults(for searchController: UISearchController) {
		guard heldOutlineContainers != nil else { return }
		
		Task {
			await setOutlineContainers([Search(searchText: searchController.searchBar.text!)], isNavigationBranch: false)
		}
	}

}

// MARK: Helpers

private extension ListViewController {
	
	func debounceLoadOutlines() {
		loadOutlinesDebouncer.debounce { [weak self] in
			Task { @MainActor in
				await self?.loadOutlines(animated: true)
			}
		}
	}
	
	func updateUI() {
		guard isViewLoaded else { return }
		let title = outlineContainers?.title ?? ""
		navigationItem.title = title
		
		var defaultAccount: Account? = nil
		if let containers = outlineContainers {
			if containers.count == 1, let onlyContainer = containers.first {
				defaultAccount = onlyContainer.account
			}
		}
		
		if traitCollection.userInterfaceIdiom != .mac {
			if defaultAccount == nil {
				navigationItem.rightBarButtonItem = nil
			} else {
				navigationItem.rightBarButtonItem = navButtonsBarButtonItem
			}
		}
	}
	
	func makeOutlineContextMenu(mainRowID: GenericRowIdentifier, allRowIDs: [GenericRowIdentifier]) -> UIContextMenuConfiguration {
		return UIContextMenuConfiguration(identifier: mainRowID as NSCopying, previewProvider: nil, actionProvider: { [weak self] suggestedActions in
			guard let self else { return UIMenu() }
			let outlines = allRowIDs.map { self.outlines[$0.indexPath.row] }
			
			var menuItems = [UIMenuElement]()

			if outlines.count == 1, let outline = outlines.first {
				menuItems.append(self.showGetInfoAction(outline: outline))
			}
			
			menuItems.append(self.duplicateAction(outlines: outlines))

			var shareMenuItems = [UIMenuElement]()

			if let cell = self.collectionView.cellForItem(at: allRowIDs.first!.indexPath) {
				shareMenuItems.append(self.shareAction(outlines: outlines, sourceView: cell))
			}
			
			if outlines.count == 1,
			   let outline = outlines.first,
			   outlines.first!.isCollaborating,
			   let cell = self.collectionView.cellForItem(at: allRowIDs.first!.indexPath),
			   let action = manageSharingAction(outline: outline, sourceView: cell) {
				shareMenuItems.append(action)
			}

			var exportActions = [UIAction]()
			exportActions.append(self.exportPDFDocsOutlineAction(outlines: outlines))
			exportActions.append(self.exportPDFListsOutlineAction(outlines: outlines))
			exportActions.append(self.exportMarkdownDocsOutlineAction(outlines: outlines))
			exportActions.append(self.exportMarkdownListsOutlineAction(outlines: outlines))
			exportActions.append(self.exportOPMLsAction(outlines: outlines))
			let exportMenu = UIMenu(title: .exportControlLabel, image: .export, children: exportActions)
			shareMenuItems.append(exportMenu)

			var printActions = [UIAction]()
			printActions.append(self.printDocsAction(outlines: outlines))
			printActions.append(self.printListsAction(outlines: outlines))
			let printMenu = UIMenu(title: .printControlLabel, image: .printDoc, children: printActions)
			shareMenuItems.append(printMenu)

			menuItems.append(UIMenu(title: "", options: .displayInline, children: shareMenuItems))
			
			menuItems.append(UIMenu(title: "", options: .displayInline, children: [self.deleteOutlinesAction(outlines: outlines)]))
			
			return UIMenu(title: "", children: menuItems)
		})
	}

	func showGetInfoAction(outline: Outline) -> UIAction {
		let action = UIAction(title: .getInfoControlLabel, image: .getInfo) { [weak self] action in
			guard let self else { return }
			self.delegate?.showGetInfo(self, outline: outline)
		}
		return action
	}
	
	func duplicateAction(outlines: [Outline]) -> UIAction {
		let action = UIAction(title: .duplicateControlLabel, image: .duplicate) { action in
            for outline in outlines {
				Task {
					await outline.load()
					let newOutline = await outline.duplicate()
					await outline.account?.createOutline(newOutline)
					await newOutline.forceSave()
					await newOutline.unload()
					await outline.unload()
				}
            }
		}
		return action
	}
	
	func shareAction(outlines: [Outline], sourceView: UIView) -> UIAction {
		let action = UIAction(title: .shareEllipsisControlLabel, image: .share) { action in
			let controller = UIActivityViewController(activityItemsConfiguration: OutlinesActivityItemsConfiguration(selectedOutlines: outlines))
			controller.popoverPresentationController?.sourceView = sourceView
			self.present(controller, animated: true)
		}
		return action
	}
	
	func manageSharingAction(outline: Outline, sourceView: UIView) -> UIAction? {
		guard let shareRecord = outline.cloudKitShareRecord else {
			return nil
		}

		let action = UIAction(title: .manageSharingEllipsisControlLabel, image: .collaborating) { [weak self] action in
			Task {
				guard let self, let container = await Outliner.shared.cloudKitAccount?.cloudKitContainer else { return }
				let controller = UICloudSharingController(share: shareRecord, container: container)
				controller.popoverPresentationController?.sourceView = sourceView
				controller.delegate = self
				self.present(controller, animated: true)
			}
		}
		return action
	}

	func exportPDFDocsOutlineAction(outlines: [Outline]) -> UIAction {
		let action = UIAction(title: .exportPDFDocEllipsisControlLabel) { [weak self] action in
			guard let self else { return }
			self.delegate?.exportPDFDocs(self, outlines: outlines)
		}
		return action
	}
	
	func exportPDFListsOutlineAction(outlines: [Outline]) -> UIAction {
        let action = UIAction(title: .exportPDFListEllipsisControlLabel) { [weak self] action in
			guard let self else { return }
			self.delegate?.exportPDFLists(self, outlines: outlines)
		}
		return action
	}
	
	func exportMarkdownDocsOutlineAction(outlines: [Outline]) -> UIAction {
        let action = UIAction(title: .exportMarkdownDocEllipsisControlLabel) { [weak self] action in
			guard let self else { return }
			self.delegate?.exportMarkdownDocs(self, outlines: outlines)
		}
		return action
	}
	
	func exportMarkdownListsOutlineAction(outlines: [Outline]) -> UIAction {
        let action = UIAction(title: .exportMarkdownListEllipsisControlLabel) { [weak self] action in
			guard let self else { return }
			self.delegate?.exportMarkdownLists(self, outlines: outlines)
		}
		return action
	}
	
	func exportOPMLsAction(outlines: [Outline]) -> UIAction {
        let action = UIAction(title: .exportOPMLEllipsisControlLabel) { [weak self] action in
			guard let self else { return }
			self.delegate?.exportOPMLs(self, outlines: outlines)
		}
		return action
	}
	
	func printDocsAction(outlines: [Outline]) -> UIAction {
		let action = UIAction(title: .printDocEllipsisControlLabel) { [weak self] action in
			guard let self else { return }
			self.delegate?.printDocs(self, outlines: outlines)
		}
		return action
	}
	
	func printListsAction(outlines: [Outline]) -> UIAction {
		let action = UIAction(title: .printListControlEllipsisLabel) { [weak self] action in
			guard let self else { return }
			self.delegate?.printLists(self, outlines: outlines)
		}
		return action
	}
	
	func deleteContextualAction(indexPath: IndexPath) -> UIContextualAction {
		return UIContextualAction(style: .destructive, title: .deleteControlLabel) { [weak self] _, _, completion in
			guard let self else { return }
			let outline = self.outlines[indexPath.row]
			self.deleteOutlines([outline], completion: completion)
		}
	}
	
	func deleteOutlinesAction(outlines: [Outline]) -> UIAction {
		let action = UIAction(title: .deleteControlLabel, image: .delete, attributes: .destructive) { [weak self] action in
			self?.deleteOutlines(outlines)
		}
		
		return action
	}
	
	#warning("Convert this syntax.")
	func deleteOutlines(_ outlines: [Outline], completion: ((Bool) -> Void)? = nil) {
		func delete() {
			let deselect = selectedOutlines.filter({ outlines.contains($0) }).isEmpty
			if deselect, let outlineContainers = self.outlineContainers {
				self.delegate?.outlineSelectionDidChange(self, outlineContainers: outlineContainers, outlines: [], isNew: false, isNavigationBranch: true, animated: true)
			}
			for outlines in outlines {
				Task {
					await outlines.account?.deleteOutline(outlines)
				}
			}
		}

		// We insta-delete anytime we don't have any outline content
		guard !outlines.filter({ !$0.isEmpty }).isEmpty else {
			delete()
			return
		}
		
		let deleteAction = UIAlertAction(title: .deleteControlLabel, style: .destructive) { _ in
			delete()
		}
		
		let cancelAction = UIAlertAction(title: .cancelControlLabel, style: .cancel) { _ in
			completion?(true)
		}
		
        let title: String
        let message: String
        if outlines.count > 1 {
			title = .deleteOutlinesPrompt(outlineCount: outlines.count)
            message = .deleteOutlinesMessage
        } else {
			title = .deleteOutlinePrompt(outlineName: outlines.first?.title ?? "")
            message = .deleteOutlineMessage
        }
        
		let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
		alert.addAction(deleteAction)
		alert.addAction(cancelAction)
		alert.preferredAction = deleteAction
		
		present(alert, animated: true, completion: nil)
	}
	
}
