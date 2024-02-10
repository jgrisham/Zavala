//
//  AccountManager.swift
//  
//
//  Created by Maurice Parker on 11/6/20.
//

import Foundation
import OSLog

public extension Notification.Name {
	static let AccountManagerAccountsDidChange = Notification.Name(rawValue: "AccountManagerAccountsDidChange")
}

public actor AccountManager {
	
	public static var shared: AccountManager!
	
	public var localAccount: Account {
		return accountsDictionary[AccountType.local.rawValue]!
	}

	public var cloudKitAccount: Account? {
		return accountsDictionary[AccountType.cloudKit.rawValue]
	}

	public var isSyncAvailable: Bool {
		return cloudKitAccount?.cloudKitManager?.isSyncAvailable ?? false
	}
	
	public var accounts: [Account] {
		return accountsDictionary.values.map { $0 }
	}

	public var activeAccounts: [Account] {
		return Array(accountsDictionary.values.filter { $0.isActive })
	}

	public var sortedActiveAccounts: [Account] {
		return sort(activeAccounts)
	}
	
	public var documents: [Document] {
		return accounts.reduce(into: [Document]()) { $0.append(contentsOf: $1.documents ?? [Document]() ) }
	}
	
	public var activeDocuments: [Document] {
		return activeAccounts.reduce(into: [Document]()) { $0.append(contentsOf: $1.documents ?? [Document]() ) }
	}
	
	var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VinOutlineKit")

	var accountsDictionary = [Int: Account]()

	let accountsFolder: URL
	let localAccountFolder: URL
	let localAccountFile: URL
	let cloudKitAccountFolder: URL
	let cloudKitAccountFile: URL

	private var accountFiles = [Int: AccountFile]()
	private var notificationsTask: Task<(), Never>?
	
	public init(accountsFolderPath: String) {
		self.accountsFolder = URL(fileURLWithPath: accountsFolderPath, isDirectory: true)
		self.localAccountFolder = accountsFolder.appendingPathComponent(AccountType.local.folderName)
		self.localAccountFile = localAccountFolder.appendingPathComponent(AccountFile.filenameComponent)
		self.cloudKitAccountFolder = accountsFolder.appendingPathComponent(AccountType.cloudKit.folderName)
		self.cloudKitAccountFile = cloudKitAccountFolder.appendingPathComponent(AccountFile.filenameComponent)
	}

	// MARK: API
	
	public func startUp(errorHandler: ErrorHandler) async {
		// The local account must always exist, even if it's empty.
		if FileManager.default.fileExists(atPath: localAccountFile.path) {
			initializeFile(accountType: .local)
		} else {
			do {
				try FileManager.default.createDirectory(atPath: localAccountFolder.path, withIntermediateDirectories: true, attributes: nil)
			} catch {
				assertionFailure("Could not create folder for local account.")
				abort()
			}
			
			let localAccount = Account(accountType: .local)
			accountsDictionary[AccountType.local.rawValue] = localAccount
			initializeFile(accountType: .local)
		}
		
		if FileManager.default.fileExists(atPath: cloudKitAccountFile.path) {
			initializeFile(accountType: .cloudKit)
			cloudKitAccount?.initializeCloudKit(firstTime: false, errorHandler: errorHandler)
		}
		
		notificationsTask = Task {
			await withTaskGroup(of: Void.self) { group in
				
				group.addTask { [weak self] in
					for await note in NotificationCenter.default.notifications(named: .AccountMetadataDidChange) {
						let account = note.object as! Account
						await self?.markAsDirty(account)
					}
				}

				group.addTask { [weak self] in
					for await note in NotificationCenter.default.notifications(named: .AccountTagsDidChange) {
						let account = note.object as! Account
						await self?.markAsDirty(account)
					}
				}

				group.addTask { [weak self] in
					for await note in NotificationCenter.default.notifications(named: .AccountDocumentsDidChange) {
						let account = note.object as! Account
						await self?.markAsDirty(account)
					}
				}

				group.addTask { [weak self] in
					for await note in NotificationCenter.default.notifications(named: .DocumentTitleDidChange) {
						guard let document = note.object as? Document, let account = document.account else { return }
						await self?.markAsDirty(account)

						if let outline = document.outline {
							account.fixAltLinks(excluding: outline)
						}

						account.disambiguate(document: document)					}
				}

				group.addTask { [weak self] in
					for await note in NotificationCenter.default.notifications(named: .AccountDocumentsDidChange) {
						guard let account = (note.object as? Document)?.account else { return }
						await self?.markAsDirty(account)
					}
				}

			}
		}

	}
	
	public func createCloudKitAccount(errorHandler: ErrorHandler) {
		do {
			try FileManager.default.createDirectory(atPath: cloudKitAccountFolder.path, withIntermediateDirectories: true, attributes: nil)
		} catch {
			assertionFailure("Could not create folder for CloudKit account.")
			abort()
		}
		
		let cloudKitAccount = Account(accountType: .cloudKit)
		accountsDictionary[AccountType.cloudKit.rawValue] = cloudKitAccount
		initializeFile(accountType: .cloudKit)
		accountManagerAccountsDidChange()

		cloudKitAccount.initializeCloudKit(firstTime: true, errorHandler: errorHandler)
	}
	
	public func deleteCloudKitAccount() {
		guard let cloudKitAccount else { return }
		
		// Send out all the document delete events for this account to clean up the search index
		cloudKitAccount.documents?.forEach { $0.documentDidDelete() }
		
		accountsDictionary[AccountType.cloudKit.rawValue] = nil
		accountFiles[AccountType.cloudKit.rawValue] = nil

		try? FileManager.default.removeItem(atPath: cloudKitAccountFolder.path)

		accountManagerAccountsDidChange()

		cloudKitAccount.cloudKitManager?.accountDidDelete(account: cloudKitAccount)
	}
	
	public func findAccount(accountType: AccountType) -> Account? {
		return accountsDictionary[accountType.rawValue]
	}

	public func findAccount(accountID: Int) -> Account? {
		guard let account = accountsDictionary[accountID] else { return nil }
		return account.isActive ? account : nil
	}
	
	public func findDocumentContainer(_ entityID: EntityID) -> DocumentContainer? {
		switch entityID {
		case .search(let searchText):
			return Search(searchText: searchText)
		case .allDocuments(let accountID), .recentDocuments(let accountID), .tagDocuments(let accountID, _):
			return findAccount(accountID: accountID)?.findDocumentContainer(entityID)
		default:
			return nil
		}
	}
	
	public func findDocumentContainers(_ entityIDs: [EntityID]) -> [DocumentContainer] {
		var containers = [DocumentContainer]()
		for entityID in entityIDs {
			if let container = findDocumentContainer(entityID) {
				containers.append(container)
			}
		}
		return containers
	}
	
	public func findDocument(_ entityID: EntityID) -> Document? {
		switch entityID {
		case .document(let accountID, let documentUUID):
			return findAccount(accountID: accountID)?.findDocument(documentUUID: documentUUID)
		case .row(let accountID, let documentUUID, _):
			return findAccount(accountID: accountID)?.findDocument(documentUUID: documentUUID)
		default:
			return nil
		}
	}
	
	public func receiveRemoteNotification(userInfo: [AnyHashable : Any]) async {
		await cloudKitAccount?.cloudKitManager?.receiveRemoteNotification(userInfo: userInfo)
	}
	
	public func sync() async {
		await cloudKitAccount?.cloudKitManager?.sync()
	}
	
	public func resume() {
		accountFiles.values.forEach { $0.resume() }
		activeDocuments.forEach { $0.resume() }
		Task {
			await cloudKitAccount?.cloudKitManager?.resume()
		}
	}
	
	public func suspend() {
		accountFiles.values.forEach {
			$0.saveIfNecessary()
			$0.suspend()
		}

		activeDocuments.forEach {
			$0.save()
			$0.suspend()
		}

		Task {
			await cloudKitAccount?.cloudKitManager?.suspend()
		}
	}
	
}

// MARK: Helpers

private extension AccountManager {
	
	func accountManagerAccountsDidChange() {
		NotificationCenter.default.post(name: .AccountManagerAccountsDidChange, object: self, userInfo: nil)
	}

	func sort(_ accounts: [Account]) -> [Account] {
		return accounts.sorted { (account1, account2) -> Bool in
			if account1.type == .local {
				return true
			}
			if account2.type == .local {
				return false
			}
			return (account1.name as NSString).localizedStandardCompare(account2.name) == .orderedAscending
		}
	}
	
	func initializeFile(accountType: AccountType) {
		let file: URL
		if accountType == .local {
			file = localAccountFile
		} else {
			file = cloudKitAccountFile
		}
		
		let managedFile = AccountFile(fileURL: file, accountType: accountType, accountManager: self)
		managedFile.load()
		accountFiles[accountType.rawValue] = managedFile
	}

	func markAsDirty(_ account: Account) {
		let accountFile = accountFiles[account.type.rawValue]!
		accountFile.markAsDirty()
	}
	
}
