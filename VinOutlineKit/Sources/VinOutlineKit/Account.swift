//
//  Account.swift
//  
//
//  Created by Maurice Parker on 11/6/20.
//

#if canImport(UIKit)
import UIKit
#else
import Foundation
#endif
import CloudKit
import VinXML
import VinCloudKit

public extension Notification.Name {
	static let AccountDidReload = Notification.Name(rawValue: "AccountDidReload")
	static let AccountMetadataDidChange = Notification.Name(rawValue: "AccountMetadataDidChange")
	static let AccountDocumentsDidChange = Notification.Name(rawValue: "AccountDocumentsDidChange")
	static let AccountTagsDidChange = Notification.Name(rawValue: "AccountTagsDidChange")
	static let ActiveAccountsDidChange = Notification.Name(rawValue: "ActiveAccountsDidChange")
}

public enum AccountError: LocalizedError {
	case securityScopeError
	case fileReadError
	case opmlParserError
	
	public var errorDescription: String? {
		switch self {
		case .securityScopeError:
			return VinOutlineKitStringAssets.accountErrorScopedResource
		case .fileReadError:
			return VinOutlineKitStringAssets.accountErrorImportRead
		case .opmlParserError:
			return VinOutlineKitStringAssets.accountErrorOPMLParse
		}
	}
}

public actor Account: Identifiable, Equatable {

	nonisolated public var id: EntityID {
		return EntityID.account(type.rawValue)
	}
	
	public var name: String {
		return type.name
	}
	
	public let type: AccountType
	public var isActive: Bool
	
	public private(set) var tags: [Tag]?
	public private(set) var documents: [Document]?

	public private(set) var sharedDatabaseChangeToken: Data?
	public private(set) var zoneChangeTokens: [VCKChangeTokenKey: Data]?

	enum CodingKeys: String, CodingKey {
		case type = "type"
		case isActive = "isActive"
		case tags = "tags"
		case documents = "documents"
		case sharedDatabaseChangeToken = "sharedDatabaseChangeToken"
		case zoneChangeTokens = "zoneChangeTokens"
	}
	
	public var documentContainers: [DocumentContainer] {
		var containers = [DocumentContainer]()
		containers.append(AllDocuments(account: self))

		for tagDocuments in tags?
			.sorted(by: { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending })
			.compactMap({ TagDocuments(account: self, tag: $0) }) ?? [TagDocuments]() {
			containers.append(tagDocuments)
		}
		
		return containers
	}
	
	public var cloudKitContainer: CKContainer? {
		return cloudKitManager?.container
	}
	
	var folder: URL {
		switch type {
		case .local:
			return AccountManager.shared.localAccountFolder
		case .cloudKit:
			return AccountManager.shared.cloudKitAccountFolder
		}
	}
	var cloudKitManager: CloudKitManager?
	
	private let operationQueue = OperationQueue()

	private var documentsDictionaryNeedUpdate = true
	private var _idToDocumentsDictionary = [String: Document]()
	private var idToDocumentsDictionary: [String: Document] {
		if documentsDictionaryNeedUpdate {
			rebuildDocumentsDictionary()
		}
		return _idToDocumentsDictionary
	}

	private var tagsDictionaryNeedUpdate = true
	private var _idToTagsDictionary = [String: Tag]()
	private var idToTagsDictionary: [String: Tag] {
		if tagsDictionaryNeedUpdate {
			rebuildTagsDictionary()
		}
		return _idToTagsDictionary
	}

	init(accountType: AccountType) {
		self.type = accountType
		self.isActive = true
		self.documents = [Document]()
	}
	
	init(accountCodable: AccountCodable) {
		self.type = accountCodable.type
		self.isActive = accountCodable.isActive
		self.tags = accountCodable.tags
		
		var documents = [Document]()
		for documentCodable in accountCodable.documents ?? [] {
			if let outline = documentCodable.outline {
				documents.append(.outline(outline))
			}
		}
		self.documents = documents
		
		self.sharedDatabaseChangeToken = accountCodable.sharedDatabaseChangeToken
		self.zoneChangeTokens = accountCodable.zoneChangeTokens
	}
	
	func initializeCloudKit(firstTime: Bool, errorHandler: ErrorHandler) async {
		cloudKitManager = await CloudKitManager(account: self, errorHandler: errorHandler)
		
		for document in documents ?? [] {
			cloudKitManager?.addSyncRecordIfNeeded(document: document)
		}
		
		if firstTime {
			Task { 
				await cloudKitManager?.firstTimeSetup()
				await cloudKitManager?.sync()
			}
		}
	}
	
	public func userDidAcceptCloudKitShareWith(_ shareMetadata: CKShare.Metadata) async {
		await cloudKitManager?.userDidAcceptCloudKitShareWith(shareMetadata)
	}

	public func generateCKShare(for document: Document) async throws -> CKShare {
		guard let cloudKitManager else { fatalError() }
		return try await cloudKitManager.generateCKShare(for: document)
	}
	
	public func activate() {
		guard isActive == false else { return }
		isActive = true
		accountMetadataDidChange()
		activeAccountsDidChange()
	}
	
	public func deactivate() {
		guard isActive == true else { return }
		isActive = false
		accountMetadataDidChange()
		activeAccountsDidChange()
	}
	
	public func storeSharedDatabase(changeToken: Data?) {
		sharedDatabaseChangeToken = changeToken
		accountMetadataDidChange()
	}

	func store(changeToken: Data?, key: VCKChangeTokenKey) {
		if zoneChangeTokens == nil {
			zoneChangeTokens = [VCKChangeTokenKey: Data]()
		}
		zoneChangeTokens?[key] = changeToken
		accountMetadataDidChange()
	}
	
	public func importOPML(_ url: URL, tags: [Tag]?) async throws -> Document {
		guard url.startAccessingSecurityScopedResource() else { throw AccountError.securityScopeError }
		defer {
			url.stopAccessingSecurityScopedResource()
		}
		
		var fileData: Data?
		var fileError: NSError? = nil
		NSFileCoordinator().coordinate(readingItemAt: url, error: &fileError) { (url) in
			fileData = try? Data(contentsOf: url)
		}
		
		guard fileError == nil else { throw fileError! }
		guard let opmlData = fileData else { throw AccountError.fileReadError }
		
		return try await importOPML(opmlData, tags: tags)
	}

	@discardableResult
	public func importOPML(_ opmlData: Data, tags: [Tag]?, images: [String:  Data]? = nil) async throws -> Document {
		let opmlString = try convertOPMLAttributeNewlines(opmlData)
		
		guard let opmlNode = try? VinXML.XMLDocument(xml: opmlString, caseSensitive: false)?.root else {
			throw AccountError.opmlParserError
		}
		
		let headNode = opmlNode["head"]?.first
		let bodyNode = opmlNode["body"]?.first
		let rowNodes = bodyNode?["outline"]
		
		var title = headNode?["title"]?.first?.content
		if (title == nil || title!.isEmpty) && rowNodes?.count ?? 0 > 0 {
			title = rowNodes?.first?.attributes["text"]
		}
		if title == nil {
			title = VinOutlineKitStringAssets.noTitle
		}
		
		let outline = await Outline(account: self, parentID: id, title: title)
		let document = Document.outline(outline)
		documents?.append(document)
		accountDocumentsDidChange()

		if let created = headNode?["dateCreated"]?.first?.content {
			outline.created = Date.dateFromRFC822(rfc822String: created)
		}
		if let updated = headNode?["dateModified"]?.first?.content {
			outline.updated = Date.dateFromRFC822(rfc822String: updated)
		}
		
		outline.ownerName = headNode?["ownerName"]?.first?.content
		outline.ownerEmail = headNode?["ownerEmail"]?.first?.content
		outline.ownerURL = headNode?["ownerID"]?.first?.content
		
		if let verticleScrollState = headNode?["vertScrollState"]?.first?.content {
			outline.verticleScrollState = Int(verticleScrollState)
		}
		
		if let autoLinkingEnabled = headNode?["automaticallyChangeLinkTitles"]?.first?.content {
			outline.autoLinkingEnabled = autoLinkingEnabled == "true" ? true : false
		}

		if let checkSpellingWhileTyping = headNode?["checkSpellingWhileTyping"]?.first?.content {
			outline.checkSpellingWhileTyping = checkSpellingWhileTyping == "true" ? true : false
		}

		if let correctSpellingAutomatically = headNode?["correctSpellingAutomatically"]?.first?.content {
			outline.correctSpellingAutomatically = correctSpellingAutomatically == "true" ? true : false
		}

		if let tagNodes = headNode?["tags"]?.first?["tag"] {
			for tagNode in tagNodes {
				if let tagName = tagNode.content {
					let tag = createTag(name: tagName)
					outline.createTag(tag)
				}
			}
		}

		if let expansionState = headNode?["expansionState"]?.first?.content {
			outline.expansionState = expansionState
		}
		
		for tag in tags ?? [Tag]() {
			outline.createTag(tag)
		}

		if let rowNodes {
			await outline.importRows(outline: outline, rowNodes: rowNodes, images: images)
		}
		
		outline.zoneID = cloudKitManager?.outlineZone.zoneID
		
		disambiguate(document: document)
		
		saveToCloudKit(document)
		
		await outline.updateAllLinkRelationships()
		await fixAltLinks(excluding: outline)
		
		await outline.forceSave()
		await outline.unloadRows()

		return document
	}
	
	public func disambiguate(document: Document) {
		guard let documents else { return }
		
		if let lastCommon = documents.filter({ $0.title == document.title && $0.id != document.id }).sorted(by: { $0.disambiguator ?? 0 < $1.disambiguator ?? 0 }).last {
			document.update(disambiguator: (lastCommon.disambiguator ?? 1) + 1)
		}
	}
	
	public func createOutline(title: String? = nil, tags: [Tag]? = nil) async -> Document {
		let outline = await Outline(account: self, parentID: id, title: title)
		if documents == nil {
			documents = [Document]()
		}
		
		outline.zoneID = cloudKitManager?.outlineZone.zoneID
		let document = Document.outline(outline)
		documents!.append(document)
		accountDocumentsDidChange()

		if let tags {
            for tag in tags {
                outline.createTag(tag)
            }
		}
		
		disambiguate(document: document)
		
		saveToCloudKit(document)
		
		return document
	}
	
	func apply(_ update: CloudKitOutlineUpdate) async {
		guard !update.isDelete else {
			guard let document = findDocument(documentUUID: update.documentID.documentUUID) else { return }
			await deleteDocument(document, updateCloudKit: false)
			return
		}
		
		if let document = findDocument(documentUUID: update.documentID.documentUUID) {
			let outline = document.outline!
			await outline.load()
			await outline.apply(update)
			await outline.forceSave()
			await outline.unload()
		} else {
			guard update.saveOutlineRecord != nil else {
				return
			}
			let outline = await Outline(account: self, id: update.documentID)
			outline.zoneID = update.zoneID

			await outline.apply(update)
			await outline.forceSave()
			await outline.unload()
			
			if documents == nil {
				documents = [Document]()
			}
			let document = Document.outline(outline)
			documents!.append(document)
			accountDocumentsDidChange()
		}
	}
	
	public func createDocument(_ document: Document) async {
		if documents == nil {
			documents = [Document]()
		}
		
		for tag in await document.tags ?? [Tag]() {
			createTag(tag)
		}
		
		var mutableDocument = document
		mutableDocument.zoneID = cloudKitManager?.outlineZone.zoneID
			
		documents!.append(mutableDocument)
		accountDocumentsDidChange()
		saveToCloudKit(mutableDocument)
	}

	public func deleteDocument(_ document: Document) async {
		await deleteDocument(document, updateCloudKit: true)
	}
	
	public func findDocumentContainer(_ entityID: EntityID) -> DocumentContainer? {
		switch entityID {
		case .allDocuments:
			return AllDocuments(account: self)
		case .recentDocuments:
			return nil
		case .tagDocuments(_, let tagID):
			guard let tag = findTag(tagID: tagID) else { return nil }
			return TagDocuments(account: self, tag: tag)
		default:
			fatalError()
		}
	}

	public func findDocument(_ entityID: EntityID) -> Document? {
		return findDocument(documentUUID: entityID.documentUUID)
	}
	
	public func findDocument(filename: String) -> Document? {
		var title = filename
		var disambiguator: Int? = nil
		
		if let periodIndex = filename.lastIndex(of: ".") {
			title = String(filename.prefix(upTo: periodIndex))
		}
		
		if let underscoreIndex = filename.lastIndex(of: "-") {
			if underscoreIndex < title.endIndex {
				let disambiguatorIndex = title.index(after: underscoreIndex)
				disambiguator = Int(title.suffix(from: disambiguatorIndex))
			}
			title = String(filename.prefix(upTo: underscoreIndex))
		}

		title = title.replacingOccurrences(of: "_", with: " ")
		
		return documents?.filter({ document in
			return document.title == title && document.disambiguator == disambiguator
		}).first
	}
	
	@discardableResult
	public func createTag(name: String) -> Tag {
		if let tag = tags?.first(where: { $0.name == name }) {
			return tag
		}
		
		let tag = Tag(name: name)
		return createTag(tag)
	}
	
	@discardableResult
	func createTag(_ tag: Tag) -> Tag {
		if let tag = tags?.first(where: { $0 == tag }) {
			return tag
		}

		if tags == nil {
			tags = [Tag]()
		}
		
		tags?.append(tag)
		tags?.sort(by: { $0.name < $1.name })
		accountTagsDidChange()
		
		return tag
	}
	
	public func renameTag(_ tag: Tag, to newTagName: String) {
		tag.name = newTagName
		tags?.sort(by: { $0.name < $1.name })
		accountTagsDidChange()

		for doc in documents ?? [Document]() {
			if doc.hasTag(tag) {
				doc.requestCloudKitUpdateForSelf()
			}
		}
	}
	
	public func deleteTag(name: String) {
		guard let tag = tags?.first(where: { $0.name == name }) else {
			return
		}
		deleteTag(tag)
	}

	public func deleteTag(_ tag: Tag) {
		for doc in documents ?? [Document]() {
			if doc.hasTag(tag) {
				return
			}
		}
		
		tags?.removeFirst(object: tag)
		accountTagsDidChange()
	}
	
	public func forceDeleteTag(_ tag: Tag) {
		for doc in documents ?? [Document]() {
			doc.deleteTag(tag)
		}
		
		tags?.removeFirst(object: tag)
		accountTagsDidChange()
	}
	
	public func findTag(name: String) -> Tag? {
		return tags?.first(where: { $0.name == name })
	}

	func findDocument(documentUUID: String) -> Document? {
		return idToDocumentsDictionary[documentUUID]
	}

	func findDocument(shareRecordID: CKRecord.ID) -> Document? {
		return documents?.first(where: { $0.shareRecordID == shareRecordID })
	}
	
	func deleteAllDocuments(with zoneID: CKRecordZone.ID) async {
		for doc in documents ?? [Document]() {
			if doc.zoneID == zoneID {
				await deleteDocument(doc, updateCloudKit: false)
			}
		}
	}
	
	func findTag(tagID: String) -> Tag? {
		return idToTagsDictionary[tagID]
	}

	func findTags(tagIDs: [String]) -> [Tag] {
		var tags = [Tag]()
		for tagID in tagIDs {
			if let tag = findTag(tagID: tagID) {
				tags.append(tag)
			}
		}
		return tags
	}
	
	func fixAltLinks(excluding: Outline) async {
		for outline in documents?.compactMap({ $0.outline }) ?? [Outline]() {
			if outline != excluding {
				await outline.fixAltLinks()
			}
		}
	}
	
	func accountDidReload() {
		NotificationCenter.default.post(name: .AccountDidReload, object: self, userInfo: nil)
	}
	
	public static func == (lhs: Account, rhs: Account) -> Bool {
		return lhs.id == rhs.id
	}
	
}

// MARK: Helpers

private extension Account {
	
	func accountMetadataDidChange() {
		NotificationCenter.default.post(name: .AccountMetadataDidChange, object: self, userInfo: nil)
	}
	
	func accountDocumentsDidChange() {
		documentsDictionaryNeedUpdate = true
		NotificationCenter.default.post(name: .AccountDocumentsDidChange, object: self, userInfo: nil)
	}
	
	func accountTagsDidChange() {
		tagsDictionaryNeedUpdate = true
		NotificationCenter.default.post(name: .AccountTagsDidChange, object: self, userInfo: nil)
	}

	func activeAccountsDidChange() {
		NotificationCenter.default.post(name: .ActiveAccountsDidChange, object: self, userInfo: nil)
	}
	
	func rebuildDocumentsDictionary() {
		var idDictionary = [String: Document]()
		
		for doc in documents ?? [Document]() {
			idDictionary[doc.id.documentUUID] = doc
		}
		
		_idToDocumentsDictionary = idDictionary
		documentsDictionaryNeedUpdate = false
	}

	func rebuildTagsDictionary() {
		var idDictionary = [String: Tag]()
		
		for tag in tags ?? [Tag]() {
			idDictionary[tag.id] = tag
		}
		
		_idToTagsDictionary = idDictionary
		tagsDictionaryNeedUpdate = false
	}
	
	func deleteDocument(_ document: Document, updateCloudKit: Bool) async {
		documents?.removeAll(where: { $0.id == document.id})
		accountDocumentsDidChange()
		
		if updateCloudKit {
			deleteFromCloudKit(document)
		}

		for tag in await document.tags ?? [Tag]() {
			deleteTag(tag)
		}

		await document.delete()
	}
	
	func saveToCloudKit(_ document: Document) {
		guard let cloudKitManager, let zoneID = document.zoneID else { return }
		
		var requests = Set<CloudKitActionRequest>()
		requests.insert(CloudKitActionRequest(zoneID: zoneID, id: document.id))
		
		switch document {
		case .outline(let outline):
			if let rows = outline.keyedRows?.values {
				for row in rows {
					requests.insert(CloudKitActionRequest(zoneID: zoneID, id: row.entityID))
				}
			}
		}
		
		cloudKitManager.addRequests(requests)
	}
	
	func deleteFromCloudKit(_ document: Document) {
		guard let cloudKitManager, let zoneID = document.zoneID else { return }
		var requests = Set<CloudKitActionRequest>()
		requests.insert(CloudKitActionRequest(zoneID: zoneID, id: document.id))
		cloudKitManager.addRequests(requests)
	}
	
	func convertOPMLAttributeNewlines(_ opmlData: Data) throws -> String {
		guard var opmlString = String(data: opmlData, encoding: .utf8),
			  let regEx = try? NSRegularExpression(pattern: "(text|_note)=\"([^\"]*)\"", options: []) else {
			throw AccountError.opmlParserError
		}
		
		for match in regEx.allMatches(in: opmlString) {
			for rangeIndex in 0..<match.numberOfRanges {
				let matchRange = match.range(at: rangeIndex)
				if let substringRange = Range(matchRange, in: opmlString) {
					opmlString = opmlString.replacingOccurrences(of: "\n", with: "&#10;", range: substringRange)
				}
			}
		}
		
		return opmlString
	}
}
