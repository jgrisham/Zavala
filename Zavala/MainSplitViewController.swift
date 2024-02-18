//
//  MainSplitViewController.swift
//  Zavala
//
//  Created by Maurice Parker on 11/10/20.
//

import UIKit
import CoreSpotlight
import SafariServices
import VinOutlineKit
import VinUtility

protocol MainControllerIdentifiable {
	var mainControllerIdentifer: MainControllerIdentifier { get }
}

enum MainControllerIdentifier {
	case none
	case collections
	case documents
	case editor
}

class MainSplitViewController: UISplitViewController, MainCoordinator {
	
	struct UserInfoKeys {
		static let goBackwardStack = "goBackwardStack"
		static let goForwardStack = "goForwardStack"
		static let collectionsWidth = "collectionsWidth"
		static let documentsWidth = "documentsWidth"
	}
	
	weak var sceneDelegate: SceneDelegate?

	var stateRestorationActivity: NSUserActivity {
		let activity = activityManager.stateRestorationActivity
		var userInfo = activity.userInfo == nil ? [AnyHashable: Any]() : activity.userInfo

		userInfo![UserInfoKeys.goBackwardStack] = goBackwardStack.map { $0.userInfo }
		userInfo![UserInfoKeys.goForwardStack] = goForwardStack.map { $0.userInfo }

		if traitCollection.userInterfaceIdiom == .mac {
			userInfo![UserInfoKeys.collectionsWidth] = primaryColumnWidth
			userInfo![UserInfoKeys.documentsWidth] = supplementaryColumnWidth
		}

		activity.userInfo = userInfo
		return activity
	}
	
	var selectedDocuments: [Document] {
		return documentsViewController?.selectedDocuments ?? []
	}
	
	var isExportAndPrintUnavailable: Bool {
		guard let outlines = selectedOutlines else { return true }
		return outlines.count < 1
	}

	var isDeleteEntityUnavailable: Bool {
		return (editorViewController?.isOutlineFunctionsUnavailable ?? true) &&
			(editorViewController?.isDeleteCurrentRowUnavailable ?? true) 
	}

	var selectedDocumentContainers: [DocumentContainer]? {
		return collectionsViewController?.selectedDocumentContainers
	}
    
    var selectedTags: [Tag]? {
        return collectionsViewController?.selectedTags
    }
	
	var selectedOutlines: [Outline]? {
		return documentsViewController?.selectedDocuments.compactMap({ $0.outline })
	}

	var editorViewController: EditorViewController? {
		viewController(for: .secondary) as? EditorViewController
	}
	
	var isGoBackwardOneUnavailable: Bool {
		return goBackwardStack.isEmpty
	}
	
	var isGoForwardOneUnavailable: Bool {
		return goForwardStack.isEmpty
	}
    
    private let activityManager = ActivityManager()
	
	private var collectionsViewController: CollectionsViewController? {
		return viewController(for: .primary) as? CollectionsViewController
	}
	
	private var documentsViewController: DocumentsViewController? {
		viewController(for: .supplementary) as? DocumentsViewController
	}
	
	private var lastMainControllerToAppear = MainControllerIdentifier.none
	
	private var lastPin: Pin?
	private var goBackwardStack = [Pin]()
	private var goForwardStack = [Pin]()

	override func viewDidLoad() {
        super.viewDidLoad()
		primaryBackgroundStyle = .sidebar

		if traitCollection.userInterfaceIdiom == .mac {
			if preferredPrimaryColumnWidth < 1 {
				preferredPrimaryColumnWidth = 200
			}
			if preferredSupplementaryColumnWidth < 1 {
				preferredSupplementaryColumnWidth = 300
			}
			presentsWithGesture = false
		}

		delegate = self
    }
	
	// MARK: Notifications
	
	@objc func accountDocumentsDidChange(_ note: Notification) {
		Task {
			await cleanUpNavigationStacks()
		}
	}

	@objc func activeAccountsDidChange(_ note: Notification) {
		Task {
			await cleanUpNavigationStacks()
		}
	}

	// MARK: API
	
	func startUp() async {
		collectionsViewController?.navigationController?.delegate = self
		collectionsViewController?.delegate = self
		documentsViewController?.navigationController?.delegate = self
		documentsViewController?.delegate = self
		await collectionsViewController?.startUp()
		editorViewController?.delegate = self
		
		NotificationCenter.default.addObserver(self, selector: #selector(accountDocumentsDidChange(_:)), name: .AccountDocumentsDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(activeAccountsDidChange(_:)), name: .ActiveAccountsDidChange, object: nil)
	}
	
	func handle(_ activity: NSUserActivity, isNavigationBranch: Bool) async {
		guard let userInfo = activity.userInfo else { return }
		await handle(userInfo, isNavigationBranch: isNavigationBranch)
	}

	func handle(_ userInfo: [AnyHashable: Any], isNavigationBranch: Bool) async {
		if let searchIdentifier = userInfo[CSSearchableItemActivityIdentifier] as? String, let documentID = EntityID(description: searchIdentifier) {
			await handleDocument(documentID, isNavigationBranch: isNavigationBranch)
			return
		}
		
		if let goBackwardStackUserInfos = userInfo[UserInfoKeys.goBackwardStack] as? [Any] {
			var pins = [Pin]()
			
			for goBackwardStackUserInfo in goBackwardStackUserInfos {
				pins.append(await Pin(userInfo: goBackwardStackUserInfo))
			}
			
			goBackwardStack = pins
		}

		if let goForwardStackUserInfos = userInfo[UserInfoKeys.goForwardStack] as? [Any] {
			var pins = [Pin]()
			
			for goForwardStackUserInfo in goForwardStackUserInfos {
				pins.append(await Pin(userInfo: goForwardStackUserInfo))
			}
			
			goForwardStack = pins
		}

		await cleanUpNavigationStacks()
		
		if let collectionsWidth = userInfo[UserInfoKeys.collectionsWidth] as? CGFloat {
			preferredPrimaryColumnWidth = collectionsWidth
		}
		
		if let documentsWidth = userInfo[UserInfoKeys.documentsWidth] as? CGFloat {
			preferredSupplementaryColumnWidth = documentsWidth
		}

		let pin = await Pin(userInfo: userInfo[Pin.UserInfoKeys.pin])
		
		let documentContainers = pin.containers
		guard !(documentContainers?.isEmpty ?? true) else {
			return
		}
		
		await collectionsViewController?.selectDocumentContainers(documentContainers, isNavigationBranch: isNavigationBranch, animated: false)
		lastMainControllerToAppear = .documents

		guard let document = pin.document else {
			return
		}
		
		handleSelectDocument(document, isNavigationBranch: isNavigationBranch)
	}
	
	func handleDocument(_ documentID: EntityID, isNavigationBranch: Bool) async {
		guard let account = await AccountManager.shared.findAccount(accountID: documentID.accountID),
			  let document = await account.findDocument(documentID) else { return }
		
		if let collectionsTags = selectedTags, document.hasAnyTag(collectionsTags) {
			self.handleSelectDocument(document, isNavigationBranch: isNavigationBranch)
		} else if document.tagCount == 1, let tag = await document.tags?.first {
			await collectionsViewController?.selectDocumentContainers([TagDocuments(account: account, tag: tag)], isNavigationBranch: true, animated: false)
			handleSelectDocument(document, isNavigationBranch: isNavigationBranch)
		} else {
			await collectionsViewController?.selectDocumentContainers([AllDocuments(account: account)], isNavigationBranch: true, animated: false)
			handleSelectDocument(document, isNavigationBranch: isNavigationBranch)
		}
	}
	
	func handlePin(_ pin: Pin) async {
		let documentContainers = pin.containers
		await collectionsViewController?.selectDocumentContainers(documentContainers, isNavigationBranch: true, animated: false)
		documentsViewController?.selectDocument(pin.document, isNavigationBranch: true, animated: false)
	}
	
	func importOPMLs(urls: [URL]) {
		Task {
			await selectDefaultDocumentContainerIfNecessary()
			await documentsViewController?.importOPMLs(urls: urls)
		}
	}
	
	func showOpenQuickly() {
		if traitCollection.userInterfaceIdiom == .mac {
		
			let openQuicklyViewController = UIStoryboard.openQuickly.instantiateController(ofType: MainOpenQuicklyViewController.self)
			openQuicklyViewController.preferredContentSize = CGSize(width: 300, height: 60)
			openQuicklyViewController.delegate = self
			present(openQuicklyViewController, animated: true)
		
		} else {

			let outlineGetInfoNavViewController = UIStoryboard.openQuickly.instantiateViewController(withIdentifier: "OpenQuicklyViewControllerNav") as! UINavigationController
			outlineGetInfoNavViewController.preferredContentSize = CGSize(width: 400, height: 100)
			outlineGetInfoNavViewController.modalPresentationStyle = .formSheet
			let outlineGetInfoViewController = outlineGetInfoNavViewController.topViewController as! OpenQuicklyViewController
			outlineGetInfoViewController.delegate = self
			present(outlineGetInfoNavViewController, animated: true)
			
		}
	}
	
	func goBackwardOne() {
		goBackward(to: 0)
	}
	
	func goForwardOne() {
		goForward(to: 0)
	}
	
	func share() {
		documentsViewController?.share()
	}
	
	func manageSharing() async {
		await documentsViewController?.manageSharing()
	}
	
	func validateToolbar() {
		self.sceneDelegate?.validateToolbar()
	}
	
	// MARK: Actions
	
	override func delete(_ sender: Any?) {
		guard editorViewController?.isDeleteCurrentRowUnavailable ?? true else {
			editorViewController?.deleteCurrentRows()
			return
		}
		
		guard editorViewController?.isOutlineFunctionsUnavailable ?? true else {
			documentsViewController?.deleteCurrentDocuments()
			return
		}
	}
	
	override func selectAll(_ sender: Any?) {
		documentsViewController?.selectAllDocuments()
	}

	override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
		switch action {
		case .selectAll:
			return !(editorViewController?.isInEditMode ?? false)
		case .delete:
			guard !(editorViewController?.isInEditMode ?? false) else {
				return false
			}
			return !(editorViewController?.isDeleteCurrentRowUnavailable ?? true) || !(editorViewController?.isOutlineFunctionsUnavailable ?? true)
		default:
			return super.canPerformAction(action, withSender: sender)
		}
	}
	
	@objc func sync() {
		Task {
			await AccountManager.shared.sync()
		}
	}
	
	@objc func createOutline() {
		Task {
			await selectDefaultDocumentContainerIfNecessary()
			await documentsViewController?.createOutline(animated: false)
		}
	}
	
	@objc func importOPML() {
		Task {
			await selectDefaultDocumentContainerIfNecessary()
			documentsViewController?.importOPML()
		}
	}
	
	@objc func toggleSidebar() {
		UIView.animate(withDuration: 0.25) {
			self.preferredDisplayMode = self.displayMode == .twoBesideSecondary ? .secondaryOnly : .twoBesideSecondary
		}
	}

	@objc func insertImage(_ sender: Any?) {
		insertImage()
	}

	@objc func goBackwardOne(_ sender: Any?) {
		goBackward(to: 0)
	}

	@objc func goForwardOne(_ sender: Any?) {
		goForward(to: 0)
	}

	@objc func link(_ sender: Any?) {
		link()
	}

	@objc func createOrDeleteNotes(_ sender: Any?) {
		createOrDeleteNotes()
	}

	@objc func toggleOutlineFilter(_ sender: Any?) {
		toggleCompletedFilter()
	}

	@objc func outlineToggleBoldface(_ sender: Any?) {
		outlineToggleBoldface()
	}

	@objc func outlineToggleItalics(_ sender: Any?) {
		outlineToggleItalics()
	}

	@objc func expandAllInOutline(_ sender: Any?) {
		expandAllInOutline()
	}

	@objc func collapseAllInOutline(_ sender: Any?) {
		collapseAllInOutline()
	}

	@objc func moveRowsRight(_ sender: Any?) {
		moveRowsRight()
	}

	@objc func moveRowsLeft(_ sender: Any?) {
		moveRowsLeft()
	}

	@objc func moveRowsUp(_ sender: Any?) {
		moveRowsUp()
	}

	@objc func moveRowsDown(_ sender: Any?) {
		moveRowsDown()
	}

	@objc func toggleFocus(_ sender: Any?) {
		toggleFocus()
	}

	@objc func toggleOutlineHideNotes(_ sender: Any?) {
		toggleNotesFilter()
	}

	@objc func printDocs(_ sender: Any?) {
		printDocs()
	}

	@objc func printLists(_ sender: Any?) {
		printLists()
	}

	@objc func outlineGetInfo(_ sender: Any?) {
		showGetInfo()
	}

	func beginDocumentSearch() {
		collectionsViewController?.beginDocumentSearch()
	}
	
	// MARK: Validations
	
	override func validate(_ command: UICommand) {
		switch command.action {
		case .delete:
			if isDeleteEntityUnavailable {
				command.attributes = .disabled
			}
		default:
			break
		}
	}
	
}

// MARK: CollectionsDelegate

extension MainSplitViewController: CollectionsDelegate {
	
	func documentContainerSelectionsDidChange(_: CollectionsViewController,
											  documentContainers: [DocumentContainer],
											  isNavigationBranch: Bool,
											  animated: Bool) async {
		
		// The window might not be quite available at launch, so put a slight delay in to help it get there
		DispatchQueue.main.async {
			self.view.window?.windowScene?.title = documentContainers.title
		}
		
		if isNavigationBranch, let lastPin {
			goBackwardStack.insert(lastPin, at: 0)
			goBackwardStack = Array(goBackwardStack.prefix(10))
			self.lastPin = nil
			goForwardStack.removeAll()
		}

        if let accountID = documentContainers.first?.account?.id.accountID {
			AppDefaults.shared.lastSelectedAccountID = accountID
		}
		
        if !documentContainers.isEmpty {
            activityManager.selectingDocumentContainers(documentContainers)
			
			// In theory, we shouldn't need to do anything with the supplementary view when we aren't
			// navigating because we should be using navigation buttons and already be looking at the
			// editor view.
			if isNavigationBranch {
				if animated {
					show(.supplementary)
				} else {
					UIView.performWithoutAnimation {
						show(.supplementary)
					}
				}
			}
		} else {
			activityManager.invalidateSelectDocumentContainers()
		}
		
		await documentsViewController?.setDocumentContainers(documentContainers, isNavigationBranch: isNavigationBranch)
	}

	func showSettings(_: CollectionsViewController) {
		showSettings()
	}
	
	func importOPML(_: CollectionsViewController) {
		importOPML()
	}
	
	func createOutline(_: CollectionsViewController) {
		createOutline()
	}

}

// MARK: DocumentsDelegate

extension MainSplitViewController: DocumentsDelegate {
	
	func documentSelectionDidChange(_: DocumentsViewController,
									documentContainers: [DocumentContainer],
									documents: [Document],
									isNew: Bool,
									isNavigationBranch: Bool,
									animated: Bool) {
		
		Task {
			// Don't overlay the Document Container title if we are just switching Document Containers
			if !documents.isEmpty {
				view.window?.windowScene?.title = documents.title
			}
			
			guard documents.count == 1, let document = documents.first else {
				activityManager.invalidateSelectDocument()
				editorViewController?.edit(nil, isNew: isNew)
				if documents.isEmpty {
					editorViewController?.showMessage(.noSelectionLabel)
				} else {
					editorViewController?.showMessage(.multipleSelectionsLabel)
				}
				return
			}
			
			// This prevents the same document from entering the backward stack more than once in a row.
			// If the first item on the backward stack equals the new document and there is nothing stored
			// in the last pin, we know they clicked on a document twice without one between.
			if let first = goBackwardStack.first, first.document == document && lastPin == nil{
				goBackwardStack.removeFirst()
			}
			
			if isNavigationBranch, let lastPin, lastPin.document != document {
				goBackwardStack.insert(lastPin, at: 0)
				goBackwardStack = Array(goBackwardStack.prefix(10))
				self.lastPin = nil
				goForwardStack.removeAll()
			}
			
			await activityManager.selectingDocument(documentContainers, document)
			
			if animated {
				show(.secondary)
			} else {
				UIView.performWithoutAnimation {
					self.show(.secondary)
				}
			}
			
			lastPin = Pin(containers: documentContainers, document: document)
			
			if let search = documentContainers.first as? Search {
				if search.searchText.isEmpty {
					editorViewController?.edit(nil, isNew: isNew)
				} else {
					editorViewController?.edit(document.outline, isNew: isNew, searchText: search.searchText)
					pinWasVisited(Pin(containers: documentContainers, document: document))
				}
			} else {
				editorViewController?.edit(document.outline, isNew: isNew)
				pinWasVisited(Pin(containers: documentContainers, document: document))
			}
		}
	}

	func showGetInfo(_: DocumentsViewController, outline: Outline) {
		showGetInfo(outline: outline)
	}
	
	func exportPDFDocs(_: DocumentsViewController, outlines: [Outline]) {
		Task {
			await exportPDFDocsForOutlines(outlines)
		}
	}
	
	func exportPDFLists(_: DocumentsViewController, outlines: [Outline]) {
		Task {
			await exportPDFListsForOutlines(outlines)
		}
	}
	
	func exportMarkdownDocs(_: DocumentsViewController, outlines: [Outline]) {
		Task {
			await exportMarkdownDocsForOutlines(outlines)
		}
	}
	
	func exportMarkdownLists(_: DocumentsViewController, outlines: [Outline]) {
		Task {
			await exportMarkdownListsForOutlines(outlines)
		}
	}
	
	func exportOPMLs(_: DocumentsViewController, outlines: [Outline]) {
		Task {
			await exportOPMLsForOutlines(outlines)
		}
	}
	
	func printDocs(_: DocumentsViewController, outlines: [Outline]) {
		printDocsForOutlines(outlines)
	}
	
	func printLists(_: DocumentsViewController, outlines: [Outline]) {
		printListsForOutlines(outlines)
	}
	
}

// MARK: EditorDelegate

extension MainSplitViewController: EditorDelegate {
	
	var editorViewControllerIsGoBackUnavailable: Bool {
		return isGoBackwardOneUnavailable
	}
	
	var editorViewControllerIsGoForwardUnavailable: Bool {
		return isGoForwardOneUnavailable
	}
	
	var editorViewControllerGoBackwardStack: [Pin] {
		return goBackwardStack
	}
	
	var editorViewControllerGoForwardStack: [Pin] {
		return goForwardStack
	}
	
	func goBackward(_: EditorViewController, to: Int) {
		goBackward(to: to)
	}
	
	func goForward(_: EditorViewController, to: Int) {
		goForward(to: to)
	}
	
	func createNewOutline(_: EditorViewController, title: String) async -> Outline? {
		return await documentsViewController?.createOutlineDocument(title: title)?.outline
	}
	
	func validateToolbar(_: EditorViewController) {
		validateToolbar()
	}

	func showGetInfo(_: EditorViewController, outline: Outline) {
		showGetInfo(outline: outline)
	}
	
	func exportPDFDoc(_: EditorViewController, outline: Outline) {
		Task {
			await exportPDFDocsForOutlines([outline])
		}
	}
	
	func exportPDFList(_: EditorViewController, outline: Outline) {
		Task {
			await exportPDFListsForOutlines([outline])
		}
	}
	
	func exportMarkdownDoc(_: EditorViewController, outline: Outline) {
		Task {
			await exportMarkdownDocsForOutlines([outline])
		}
	}
	
	func exportMarkdownList(_: EditorViewController, outline: Outline) {
		Task {
			await exportMarkdownListsForOutlines([outline])
		}
	}
	
	func exportOPML(_: EditorViewController, outline: Outline) {
		Task {
			await exportOPMLsForOutlines([outline])
		}
	}

	func printDoc(_: EditorViewController, outline: Outline) {
		printDocsForOutlines([outline])
	}
	
	func printList(_: EditorViewController, outline: Outline) {
		printListsForOutlines([outline])
	}
	
	func zoomImage(_: EditorViewController, image: UIImage, transitioningDelegate: UIViewControllerTransitioningDelegate) {
		if traitCollection.userInterfaceIdiom == .mac {
			let activity = NSUserActivity(activityType: NSUserActivity.ActivityType.viewImage)
			if let pngData = image.pngData() {
				activity.userInfo = [UIImage.UserInfoKeys.pngData: pngData]
			}
			UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil, errorHandler: nil)
		} else {
			let imageVC = UIStoryboard.image.instantiateController(ofType: ImageViewController.self)
			imageVC.image = image
			imageVC.modalPresentationStyle = .currentContext
			imageVC.transitioningDelegate = transitioningDelegate
			present(imageVC, animated: true)
		}
	}

}

// MARK: UISplitViewControllerDelegate

extension MainSplitViewController: UISplitViewControllerDelegate {
	
	func splitViewController(_ svc: UISplitViewController, topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column) -> UISplitViewController.Column {
		switch proposedTopColumn {
		case .supplementary:
            if let containers = documentsViewController?.documentContainers, !containers.isEmpty {
				return .supplementary
			} else {
				return .primary
			}
		case .secondary:
			if editorViewController?.outline != nil {
				return .secondary
			} else {
                if let containers = documentsViewController?.documentContainers, !containers.isEmpty {
					return .supplementary
				} else {
					return .primary
				}
			}
		default:
			return .primary
		}
	}
	
}

// MARK: UINavigationControllerDelegate

extension MainSplitViewController: UINavigationControllerDelegate {
	
	func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
		if UIApplication.shared.applicationState == .background {
			return
		}
		
		defer {
			if let mainController = viewController as? MainControllerIdentifiable {
				lastMainControllerToAppear = mainController.mainControllerIdentifer
			} else if let mainController = (viewController as? UINavigationController)?.topViewController as? MainControllerIdentifiable {
				lastMainControllerToAppear = mainController.mainControllerIdentifer
			}
		}

		// If we are showing the Feeds and only the feeds start clearing stuff
		if isCollapsed && viewController === collectionsViewController && lastMainControllerToAppear == .documents {
			Task {
				await collectionsViewController?.selectDocumentContainers(nil, isNavigationBranch: false, animated: false)
			}
			return
		}

		if isCollapsed && viewController === documentsViewController && lastMainControllerToAppear == .editor {
			activityManager.invalidateSelectDocument()
			documentsViewController?.selectDocument(nil, isNavigationBranch: false, animated: false)
			return
		}
	}
	
}

// MARK: OpenQuicklyViewControllerDelegate

extension MainSplitViewController: OpenQuicklyViewControllerDelegate {
	
	func quicklyOpenDocument(documentID: EntityID) {
		Task {
			await handleDocument(documentID, isNavigationBranch: true)
		}
	}
	
}

// MARK: Helpers

private extension MainSplitViewController {
	
	func handleSelectDocument(_ document: Document, isNavigationBranch: Bool) {
		// This is done because the restore state navigation used to rely on the fact that
		// the TimeliniewController used a diffable datasource that didn't complete until after
		// some navigation had occurred. Changing this assumption broke state restoration
		// on the iPhone.
		//
		// When DocumentsViewController was rewritten without diffable datasources, was when this
		// assumption was broken. Rather than rewrite how we handle navigation (which would
		// not be easy. CollectionsViewController still uses a diffable datasource), we made it
		// look like it still works the same way by dispatching to the next run loop to occur.
		//
		// Someday this should be refactored. How the UINavigationControllerDelegate works would
		// be the main challenge.
		DispatchQueue.main.async {
			self.documentsViewController?.selectDocument(document, isNavigationBranch: isNavigationBranch, animated: false)
			self.lastMainControllerToAppear = .editor
			self.validateToolbar()
		}
	}
	
	func selectDefaultDocumentContainerIfNecessary() async {
		guard collectionsViewController?.selectedAccount == nil else {
			return
		}

		await selectDefaultDocumentContainer()
	}
	
	func selectDefaultDocumentContainer() async {
		let accountID = AppDefaults.shared.lastSelectedAccountID
		
		let firstActiveAccount = await AccountManager.shared.activeAccounts.first
		guard let account = await AccountManager.shared.findAccount(accountID: accountID) ?? firstActiveAccount else {
			return
		}
		
		let documentContainer = await account.documentContainers[0]
		
		await collectionsViewController?.selectDocumentContainers([documentContainer], isNavigationBranch: true, animated: true)
	}
	
	func cleanUpNavigationStacks() async {
		let allDocumentIDs = await AccountManager.shared.activeDocuments.map { $0.id }
		
		var replacementGoBackwardStack = [Pin]()
		for pin in goBackwardStack {
			if let documentID = pin.document?.id {
				if allDocumentIDs.contains(documentID) {
					replacementGoBackwardStack.append(pin)
				}
			} else {
				replacementGoBackwardStack.append(pin)
			}
		}
		goBackwardStack = replacementGoBackwardStack
		
		var replacementGoForwardStack = [Pin]()
		for pin in goForwardStack {
			if let documentID = pin.document?.id {
				if allDocumentIDs.contains(documentID) {
					replacementGoForwardStack.append(pin)
				}
			} else {
				replacementGoForwardStack.append(pin)
			}
		}
		goForwardStack = replacementGoForwardStack
		
		if let lastPinDocumentID = lastPin?.document?.id, !allDocumentIDs.contains(lastPinDocumentID) {
			self.lastPin = nil
		}
	}
	
	func goBackward(to: Int) {
		guard to < goBackwardStack.count else { return }
		
		if let lastPin {
			goForwardStack.insert(lastPin, at: 0)
		}
		
		for _ in 0..<to {
			let pin = goBackwardStack.removeFirst()
			goForwardStack.insert(pin, at: 0)
		}
		
		let pin = goBackwardStack.removeFirst()
		lastPin = pin
		
		Task {
			await collectionsViewController?.selectDocumentContainers(pin.containers, isNavigationBranch: false, animated: false)
			documentsViewController?.selectDocument(pin.document, isNavigationBranch: false, animated: false)
		}
	}
	
	func goForward(to:  Int) {
		guard to < goForwardStack.count else { return }

		if let lastPin {
			goBackwardStack.insert(lastPin, at: 0)
		}
		
		for _ in 0..<to {
			let pin = goForwardStack.removeFirst()
			goBackwardStack.insert(pin, at: 0)
		}
		
		let pin = goForwardStack.removeFirst()
		
		Task {
			await collectionsViewController?.selectDocumentContainers(pin.containers, isNavigationBranch: false, animated: false)
			documentsViewController?.selectDocument(pin.document, isNavigationBranch: false, animated: false)
		}
	}
	
}

#if targetEnvironment(macCatalyst)

extension MainSplitViewController: NSToolbarDelegate {
	
	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		return [
			.toggleSidebar,
			.primarySidebarTrackingSeparatorItemIdentifier,
			.navigation,
			.flexibleSpace,
			.newOutline,
			.supplementarySidebarTrackingSeparatorItemIdentifier,
			.moveLeft,
			.moveRight,
			.space,
			.insertImage,
			.link,
			.boldface,
			.italic,
			.flexibleSpace,
			.share,
			.space,
			.focus,
			.filter,
		]
	}
	
	func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		return [
			.sync,
			.toggleSidebar,
			.supplementarySidebarTrackingSeparatorItemIdentifier,
			.importOPML,
			.newOutline,
			.navigation,
			.insertImage,
			.link,
			.note,
			.boldface,
			.italic,
			.focus,
			.filter,
			.expandAllInOutline,
			.collapseAllInOutline,
			.moveLeft,
			.moveRight,
			.moveUp,
			.moveDown,
			.printDoc,
			.printList,
			.share,
			.getInfo,
			.space,
			.flexibleSpace
		]
	}
	
	func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
		
		var toolbarItem: NSToolbarItem?
		
		switch itemIdentifier {
		case .sync:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
//			item.checkForUnavailable = { _ in
//				return !AccountManager.shared.isSyncAvailable
//			}
			item.image = .sync.symbolSizedForCatalyst()
			item.label = .syncControlLabel
			item.toolTip = .syncControlLabel
			item.isBordered = true
			item.action = #selector(sync)
			item.target = self
			toolbarItem = item
		case .importOPML:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { _ in
				return false
			}
			item.image = .importDocument.symbolSizedForCatalyst()
			item.label = .importOPMLControlLabel
			item.toolTip = .importOPMLControlLabel
			item.isBordered = true
			item.action = #selector(importOPML as () -> ())
			item.target = self
			toolbarItem = item
		case .newOutline:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { _ in
				return false
			}
			item.image = .createEntity.symbolSizedForCatalyst()
			item.label = .newOutlineControlLabel
			item.toolTip = .newOutlineControlLabel
			item.isBordered = true
			item.action = #selector(createOutline as () -> ())
			item.target = self
			toolbarItem = item
		case .insertImage:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { [weak self] _ in
				return self?.editorViewController?.isInsertImageUnavailable ?? true
			}
			item.image = .insertImage.symbolSizedForCatalyst()
			item.label = .insertImageControlLabel
			item.toolTip = .insertImageControlLabel
			item.isBordered = true
			item.action = #selector(insertImage(_:))
			item.target = self
			toolbarItem = item
		case .navigation:
			let groupItem = NSToolbarItemGroup(itemIdentifier: .navigation)
			groupItem.visibilityPriority = .high
			groupItem.controlRepresentation = .expanded
			groupItem.label = .navigationControlLabel
			
			let goBackwardItem = ValidatingMenuToolbarItem(itemIdentifier: .goBackward)
			
			goBackwardItem.checkForUnavailable = { [weak self] toolbarItem in
				guard let self else { return true }
				var backwardItems = [UIAction]()
				for (index, pin) in self.goBackwardStack.enumerated() {
					backwardItems.append(UIAction(title: pin.document?.title ?? .noTitleLabel) { [weak self] _ in
						DispatchQueue.main.async {
							self?.goBackward(to: index)
						}
					})
				}
				toolbarItem.itemMenu = UIMenu(title: "", children: backwardItems)
				
				return self.isGoBackwardOneUnavailable
			}
			
			goBackwardItem.image = .goBackward.symbolSizedForCatalyst()
			goBackwardItem.label = .goBackwardControlLabel
			goBackwardItem.toolTip = .goBackwardControlLabel
			goBackwardItem.isBordered = true
			goBackwardItem.action = #selector(goBackwardOne(_:))
			goBackwardItem.target = self
			goBackwardItem.showsIndicator = false

			let goForwardItem = ValidatingMenuToolbarItem(itemIdentifier: .goForward)
			
			goForwardItem.checkForUnavailable = { [weak self] toolbarItem in
				guard let self else { return true }
				var forwardItems = [UIAction]()
				for (index, pin) in self.goForwardStack.enumerated() {
					forwardItems.append(UIAction(title: pin.document?.title ?? .noTitleLabel) { [weak self] _ in
						DispatchQueue.main.async {
							self?.goForward(to: index)
						}
					})
				}
				toolbarItem.itemMenu = UIMenu(title: "", children: forwardItems)
				
				return self.isGoForwardOneUnavailable
			}
			
			goForwardItem.image = .goForward.symbolSizedForCatalyst()
			goForwardItem.label = .goForwardControlLabel
			goForwardItem.toolTip = .goForwardControlLabel
			goForwardItem.isBordered = true
			goForwardItem.action = #selector(goForwardOne(_:))
			goForwardItem.target = self
			goForwardItem.showsIndicator = false
			
			groupItem.subitems = [goBackwardItem, goForwardItem]
			
			toolbarItem = groupItem
		case .link:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { [weak self] _ in
				return self?.editorViewController?.isLinkUnavailable ?? true
			}
			item.image = .link.symbolSizedForCatalyst()
			item.label = .linkControlLabel
			item.toolTip = .linkControlLabel
			item.isBordered = true
			item.action = #selector(link(_:))
			item.target = self
			toolbarItem = item
		case .note:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { [weak self] _ in
				if !(self?.editorViewController?.isCreateRowNotesUnavailable ?? true) {
					item.image = .noteAdd.symbolSizedForCatalyst()
					item.label = .addNoteControlLabel
					item.toolTip = .addNoteControlLabel
					return false
				} else if !(self?.editorViewController?.isDeleteRowNotesUnavailable ?? true) {
					item.image = .noteDelete.symbolSizedForCatalyst()
					item.label = .deleteNoteControlLabel
					item.toolTip = .deleteNoteControlLabel
					return false
				} else {
					item.image = .noteAdd.symbolSizedForCatalyst()
					item.label = .addNoteControlLabel
					item.toolTip = .addNoteControlLabel
					return true
				}
			}
			item.image = .noteAdd.symbolSizedForCatalyst()
			item.label = .addNoteControlLabel
			item.toolTip = .addNoteControlLabel
			item.isBordered = true
			item.action = #selector(createOrDeleteNotes(_:))
			item.target = self
			toolbarItem = item
		case .boldface:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { [weak self] _ in
				if self?.editorViewController?.isBoldToggledOn ?? false {
					item.image = .bold.symbolSizedForCatalyst(pointSize: 18.0, color: .systemBlue)
				} else {
					item.image = .bold.symbolSizedForCatalyst(pointSize: 18.0)
				}
				return self?.editorViewController?.isFormatUnavailable ?? true
			}
			item.image = .bold.symbolSizedForCatalyst(pointSize: 18.0)
			item.label = .boldControlLabel
			item.toolTip = .boldControlLabel
			item.isBordered = true
			item.action = #selector(outlineToggleBoldface(_:))
			item.target = self
			toolbarItem = item
		case .italic:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { [weak self] _ in
				if self?.editorViewController?.isItalicToggledOn ?? false {
					item.image = .italic.symbolSizedForCatalyst(pointSize: 18.0, color: .systemBlue)
				} else {
					item.image = .italic.symbolSizedForCatalyst(pointSize: 18.0)
				}
				return self?.editorViewController?.isFormatUnavailable ?? true
			}
			item.image = .italic.symbolSizedForCatalyst(pointSize: 18.0)
			item.label = .italicControlLabel
			item.toolTip = .italicControlLabel
			item.isBordered = true
			item.action = #selector(outlineToggleItalics(_:))
			item.target = self
			toolbarItem = item
		case .expandAllInOutline:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { [weak self] _ in
				return self?.editorViewController?.isExpandAllInOutlineUnavailable ?? true
			}
			item.image = .expandAll.symbolSizedForCatalyst()
			item.label = .expandControlLabel
			item.toolTip = .expandAllInOutlineControlLabel
			item.isBordered = true
			item.action = #selector(expandAllInOutline(_:))
			item.target = self
			toolbarItem = item
		case .collapseAllInOutline:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { [weak self] _ in
				return self?.editorViewController?.isCollapseAllInOutlineUnavailable ?? true
			}
			item.image = .collapseAll.symbolSizedForCatalyst()
			item.label = .collapseControlLabel
			item.toolTip = .collapseAllInOutlineControlLabel
			item.isBordered = true
			item.action = #selector(collapseAllInOutline(_:))
			item.target = self
			toolbarItem = item
		case .moveRight:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { [weak self] _ in
				return self?.editorViewController?.isMoveRowsRightUnavailable ?? true
			}
			item.image = .moveRight.symbolSizedForCatalyst()
			item.label = .moveRightControlLabel
			item.toolTip = .moveRightControlLabel
			item.isBordered = true
			item.action = #selector(moveRowsRight(_:))
			item.target = self
			toolbarItem = item
		case .moveLeft:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { [weak self] _ in
				return self?.editorViewController?.isMoveRowsLeftUnavailable ?? true
			}
			item.image = .moveLeft.symbolSizedForCatalyst()
			item.label = .moveLeftControlLabel
			item.toolTip = .moveLeftControlLabel
			item.isBordered = true
			item.action = #selector(moveRowsLeft(_:))
			item.target = self
			toolbarItem = item
		case .moveUp:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { [weak self] _ in
				return self?.editorViewController?.isMoveRowsUpUnavailable ?? true
			}
			item.image = .moveUp.symbolSizedForCatalyst()
			item.label = .moveUpControlLabel
			item.toolTip = .moveUpControlLabel
			item.isBordered = true
			item.action = #selector(moveRowsUp(_:))
			item.target = self
			toolbarItem = item
		case .moveDown:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { [weak self] _ in
				return self?.editorViewController?.isMoveRowsDownUnavailable ?? true
			}
			item.image = .moveDown.symbolSizedForCatalyst()
			item.label = .moveDownControlLabel
			item.toolTip = .moveDownControlLabel
			item.isBordered = true
			item.action = #selector(moveRowsDown(_:))
			item.target = self
			toolbarItem = item
		case .focus:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { [weak self] _ in
				if self?.editorViewController?.isFocusOutUnavailable ?? true {
					item.image = .focusInactive.symbolSizedForCatalyst(pointSize: 17)
					item.label = .focusInControlLabel
					item.toolTip = .focusInControlLabel
				} else {
					item.image = .focusActive.symbolSizedForCatalyst(pointSize: 17, color: .accentColor)
					item.label = .focusOutControlLabel
					item.toolTip = .focusOutControlLabel
				}
				return self?.editorViewController?.isFocusInUnavailable ?? true && self?.editorViewController?.isFocusOutUnavailable ?? true
			}
			item.image = .focusInactive.symbolSizedForCatalyst()
			item.label = .focusInControlLabel
			item.toolTip = .focusInControlLabel
			item.isBordered = true
			item.action = #selector(toggleFocus(_:))
			item.target = self
			toolbarItem = item
		case .filter:
			let item = ValidatingMenuToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { [weak self] item in
				guard let self else { return false }
				
				if self.editorViewController?.isFilterOn ?? false {
					item.image = .filterActive.symbolSizedForCatalyst(pointSize: 17, color: .accentColor)
				} else {
					item.image = .filterInactive.symbolSizedForCatalyst(pointSize: 17)
				}
				
				let turnFilterOnAction = UIAction() { [weak self] _ in
					DispatchQueue.main.async {
						   self?.toggleFilterOn()
					   }
				}
				
				turnFilterOnAction.title = self.isFilterOn ? .turnFilterOffControlLabel : .turnFilterOnControlLabel
				
				let turnFilterOnMenu = UIMenu(title: "", options: .displayInline, children: [turnFilterOnAction])
				
				let filterCompletedAction = UIAction(title: .filterCompletedControlLabel) { [weak self] _ in
					DispatchQueue.main.async {
						   self?.toggleCompletedFilter()
					   }
				}
				filterCompletedAction.state = self.isCompletedFiltered ? .on : .off
				filterCompletedAction.attributes = self.isFilterOn ? [] : .disabled

				let filterNotesAction = UIAction(title: .filterNotesControlLabel) { [weak self] _ in
					DispatchQueue.main.async {
						   self?.toggleNotesFilter()
					   }
				}
				filterNotesAction.state = self.isNotesFiltered ? .on : .off
				filterNotesAction.attributes = self.isFilterOn ? [] : .disabled

				let filterOptionsMenu = UIMenu(title: "", options: .displayInline, children: [filterCompletedAction, filterNotesAction])

				item.itemMenu = UIMenu(title: "", children: [turnFilterOnMenu, filterOptionsMenu])
				
				return self.editorViewController?.isOutlineFunctionsUnavailable ?? true
			}
			item.image = .filterInactive.symbolSizedForCatalyst()
			item.label = .filterControlLabel
			item.toolTip = .filterControlLabel
			item.isBordered = true
			item.target = self
			item.showsIndicator = false
			toolbarItem = item
		case .printDoc:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { [weak self] _ in
				return self?.editorViewController?.isOutlineFunctionsUnavailable ?? true
			}
			item.image = .printDoc.symbolSizedForCatalyst()
			item.label = .printDocControlLabel
			item.toolTip = .printDocControlLabel
			item.isBordered = true
			item.action = #selector(printDocs(_:))
			item.target = self
			toolbarItem = item
		case .printList:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { [weak self] _ in
				return self?.editorViewController?.isOutlineFunctionsUnavailable ?? true
			}
			item.image = .printList.symbolSizedForCatalyst()
			item.label = .printListControlLabel
			item.toolTip = .printListControlLabel
			item.isBordered = true
			item.action = #selector(printLists(_:))
			item.target = self
			toolbarItem = item
		case .share:
			let item = NSSharingServicePickerToolbarItem(itemIdentifier: .share)
			item.label = .shareControlLabel
			item.toolTip = .shareControlLabel
			item.activityItemsConfiguration = DocumentsActivityItemsConfiguration(delegate: self)
			toolbarItem = item
		case .getInfo:
			let item = ValidatingToolbarItem(itemIdentifier: itemIdentifier)
			item.checkForUnavailable = { [weak self] _ in
				return self?.editorViewController?.isOutlineFunctionsUnavailable ?? true
			}
			item.image = .getInfo.symbolSizedForCatalyst()
			item.label = .getInfoControlLabel
			item.toolTip = .getInfoControlLabel
			item.isBordered = true
			item.action = #selector(outlineGetInfo(_:))
			item.target = self
			toolbarItem = item
		case .toggleSidebar:
			toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
		default:
			toolbarItem = nil
		}
		
		return toolbarItem
	}
}

#endif

