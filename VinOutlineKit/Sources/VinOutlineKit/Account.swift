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
	static let AccountOutlinesDidChange = Notification.Name(rawValue: "AccountOutlinesDidChange")
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
	public private(set) var keyedOutlines: [EntityID: Outline]?

	public private(set) var sharedDatabaseChangeToken: Data?
	public private(set) var zoneChangeTokens: [VCKChangeTokenKey: Data]?
	
	public var outlineContainers: [OutlineContainer] {
		var containers = [OutlineContainer]()
		containers.append(AllOutlines(account: self))

		for tagOutlines in tags?
			.sorted(by: { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending })
			.compactMap({ TagOutlines(account: self, tag: $0) }) ?? [TagOutlines]() {
			containers.append(tagOutlines)
		}
		
		return containers
	}
	
	public var cloudKitContainer: CKContainer? {
		return cloudKitManager?.container
	}
	
	var folder: URL {
		switch type {
		case .local:
			return Outliner.shared.localAccountFolder
		case .cloudKit:
			return Outliner.shared.cloudKitAccountFolder
		}
	}
	var cloudKitManager: CloudKitManager?
	
	private let operationQueue = OperationQueue()

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
		self.outlines = [Outline]()
	}
	
	init(accountCodable: AccountCodable) {
		self.type = accountCodable.type
		self.isActive = accountCodable.isActive
		self.tags = accountCodable.tags
		
		var outlines = [Outline]()
		for documentCodable in accountCodable.documents ?? [] {
			if let outline = documentCodable.outline {
				outlines.append(outline)
			}
		}
		self.outlines = outlines
		
		self.sharedDatabaseChangeToken = accountCodable.sharedDatabaseChangeToken
		self.zoneChangeTokens = accountCodable.zoneChangeTokens
	}
	
	func initializeCloudKit(firstTime: Bool, errorHandler: ErrorHandler) async {
		cloudKitManager = await CloudKitManager(account: self, errorHandler: errorHandler)
		
		for outline in outlines ?? [] {
			cloudKitManager?.addSyncRecordIfNeeded(outline: outline)
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

	public func generateCKShare(for outline: Outline) async throws -> CKShare {
		guard let cloudKitManager else { fatalError() }
		return try await cloudKitManager.generateCKShare(for: outline)
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
	
	public func importOPML(_ url: URL, tags: [Tag]?) async throws -> Outline {
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
	public func importOPML(_ opmlData: Data, tags: [Tag]?, images: [String:  Data]? = nil) async throws -> Outline {
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
		
		var outline = await Outline(account: self, parentID: id, title: title)
		outlines?.append(outline)
		accountOutlinesDidChange()

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
		
		disambiguate(outline: outline)
		
		saveToCloudKit(outline)
		
		await outline.updateAllLinkRelationships()
		await fixAltLinks(excluding: outline)
		
		return outline
	}
	
	public func disambiguate(outline: Outline) {
		guard let outlines else { return }
		
		if let lastCommon = outlines.filter({ $0.title == outlines.title && $0.id != outline.id }).sorted(by: { $0.disambiguator ?? 0 < $1.disambiguator ?? 0 }).last {
			outline.update(disambiguator: (lastCommon.disambiguator ?? 1) + 1)
		}
	}
	
	public func createOutline(title: String? = nil, tags: [Tag]? = nil) async -> Outline {
		let outline = await Outline(account: self, parentID: id, title: title)
		if outlines == nil {
			outlines = [Outline]()
		}
		
		outline.zoneID = cloudKitManager?.outlineZone.zoneID

		outlines!.append(outline)
		accountOutlinesDidChange()

		if let tags {
            for tag in tags {
                outline.createTag(tag)
            }
		}
		
		disambiguate(outline: outline)
		
		saveToCloudKit(outline)
		
		return outline
	}
	
	func apply(_ update: CloudKitOutlineUpdate) async {
		guard !update.isDelete else {
			guard let outline = findOutline(outlineUUID: update.outlineID.outlineUUID) else { return }
			await deleteOutline(outline, updateCloudKit: false)
			return
		}
		
		if var outline = findOutline(outlineUUID: update.outlineID.outlineUUID) {
			await outline.load()
			await outline.apply(update)
			await outline.unload()
		} else {
			guard update.saveOutlineRecord != nil else {
				return
			}
			let outline = await Outline(account: self, id: update.outlineID)
			outline.zoneID = update.zoneID

			await outline.apply(update)
			await outline.forceSave()
			await outline.unload()
			
			if outlines == nil {
				outlines = [Outline]()
			}

			outlines!.append(outline)
			accountOutlinesDidChange()
		}
	}
	
	public func createOutline(_ outline: Outline) async {
		if outlines == nil {
			outlines = [Outline]()
		}
		
		for tag in await outline.tags {
			createTag(tag)
		}
		
		outline.zoneID = cloudKitManager?.outlineZone.zoneID
			
		outlines!.append(outline)
		accountOutlinesDidChange()
		saveToCloudKit(outline)
	}

	public func deleteOutline(_ outline: Outline) async {
		await deleteOutline(outline, updateCloudKit: true)
	}
	
	public func findOutlineContainer(_ entityID: EntityID) -> OutlineContainer? {
		switch entityID {
		case .allOutlines:
			return AllOutlines(account: self)
		case .recentOutlines:
			return nil
		case .tagOutlines(_, let tagID):
			guard let tag = findTag(tagID: tagID) else { return nil }
			return TagOutlines(account: self, tag: tag)
		default:
			fatalError()
		}
	}

	public func findOutline(_ entityID: EntityID) async -> Outline? {
		var outline = keyedOutlines[entityID]
		await outline?.load()
		return outline
	}
	
	public func findOutline(shareRecordID: CKRecord.ID) async -> Outline? {
		var outline = outlines?.first(where: { $0.shareRecordID == shareRecordID })
		await outline?.load()
		return outline
	}
	
	public func findOutline(filename: String) async -> Outline? {
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
		
		var outline = outlines?.filter({ outline in
			return outline.title == title && outline.disambiguator == disambiguator
		}).first
		
		await outline?.load()
		return outline
	}
	
	public func updateOutline(_ outline: Outline) async {
		await outline.unload()
		keyedOutlines[outline.id] = outline
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

		for outline in outlines ?? [Outline]() {
			if outline.hasTag(tag) {
				outline.requestCloudKitUpdateForSelf()
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
		for outline in outlines ?? [Outline]() {
			if outline.hasTag(tag) {
				return
			}
		}
		
		tags?.removeFirst(object: tag)
		accountTagsDidChange()
	}
	
	public func forceDeleteTag(_ tag: Tag) {
		for outline in outlines ?? [Outline]() {
			outline.deleteTag(tag)
		}
		
		tags?.removeFirst(object: tag)
		accountTagsDidChange()
	}
	
	public func findTag(name: String) -> Tag? {
		return tags?.first(where: { $0.name == name })
	}

	func deleteAllOutlines(with zoneID: CKRecordZone.ID) async {
		for outline in outlines ?? [Outline]() {
			if outline.zoneID == zoneID {
				await deleteOutline(outline, updateCloudKit: false)
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
		for outline in outlines?.compactMap({ $0.outline }) ?? [Outline]() {
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
	
	func accountOutlinesDidChange() {
		outlinesDictionaryNeedUpdate = true
		NotificationCenter.default.post(name: .AccountOutlinesDidChange, object: self, userInfo: nil)
	}
	
	func accountTagsDidChange() {
		tagsDictionaryNeedUpdate = true
		NotificationCenter.default.post(name: .AccountTagsDidChange, object: self, userInfo: nil)
	}

	func activeAccountsDidChange() {
		NotificationCenter.default.post(name: .ActiveAccountsDidChange, object: self, userInfo: nil)
	}
	
	func rebuildOutlinesDictionary() {
		var idDictionary = [String: Outline]()
		
		for outline in outlines ?? [Outline]() {
			idDictionary[outline.id.outlineUUID] = outline
		}
		
		_idToOutlinesDictionary = idDictionary
		outlinesDictionaryNeedUpdate = false
	}

	func rebuildTagsDictionary() {
		var idDictionary = [String: Tag]()
		
		for tag in tags ?? [Tag]() {
			idDictionary[tag.id] = tag
		}
		
		_idToTagsDictionary = idDictionary
		tagsDictionaryNeedUpdate = false
	}
	
	func deleteOutline(_ outline: Outline, updateCloudKit: Bool) async {
		outlines?.removeAll(where: { $0.id == outline.id})
		accountOutlinesDidChange()
		
		if updateCloudKit {
			deleteFromCloudKit(outline)
		}

		for tag in await outline.tags {
			deleteTag(tag)
		}

		await outline.delete()
	}
	
	func saveToCloudKit(_ outline: Outline) {
		guard let cloudKitManager, let zoneID = outline.zoneID else { return }
		
		var requests = Set<CloudKitActionRequest>()
		requests.insert(CloudKitActionRequest(zoneID: zoneID, id: outline.id))
		
		if let rows = outline.keyedRows?.values {
			for row in rows {
				requests.insert(CloudKitActionRequest(zoneID: zoneID, id: row.entityID))
			}
		}
		
		if let rowImages = outline.images?.values {
			for rowImage in rowImages {
				for image in rowImage {
					requests.insert(CloudKitActionRequest(zoneID: zoneID, id: image.id))
				}
			}
			if let rowImages = outline.images?.values {
				for images in rowImages {
					for image in images {
						requests.insert(CloudKitActionRequest(zoneID: zoneID, id: image.id))
					}
				}
			}
		}
		
		cloudKitManager.addRequests(requests)
	}
	
	func deleteFromCloudKit(_ outline: Outline) {
		guard let cloudKitManager, let zoneID = outline.zoneID else { return }
		var requests = Set<CloudKitActionRequest>()
		requests.insert(CloudKitActionRequest(zoneID: zoneID, id: outline.id))
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
