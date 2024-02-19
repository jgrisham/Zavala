//
//  Created by Maurice Parker on 11/6/20.
//

import Foundation
import OSLog
import Semaphore

public actor Outliner {
	
	nonisolated(unsafe) public static var shared: Outliner!
	
	public var localAccount: Account? {
		get async {
			return await accountsDictionary[AccountType.local.rawValue]
		}
	}
	
	public var cloudKitAccount: Account? {
		get async {
			return await accountsDictionary[AccountType.cloudKit.rawValue]
		}
	}
	
	public var isSyncAvailable: Bool {
		get async {
			return await cloudKitAccount?.cloudKitManager?.isSyncAvailable ?? false
		}
	}
	
	public var accounts: [Account] {
		get async {
			return await accountsDictionary.values.map { $0 }
		}
	}
	
	public var activeAccounts: [Account] {
		get async {
			var result = [Account]()
			for account in await accounts {
				if await account.isActive {
					result.append(account)
				}
			}
			return result
		}
	}
	
	public var sortedActiveAccounts: [Account] {
		get async {
			return await sort(activeAccounts)
		}
	}
	
	public var outlines: [Outline] {
		get async {
			var result = [Outline]()
			for account in await accounts {
				result.append(contentsOf: await account.outlines ?? [])
			}
			return result
		}
	}
	
	public var activeOutlines: [Outline] {
		get async {
			var result = [Outline]()
			for account in await activeAccounts {
				result.append(contentsOf: await account.outlines ?? [])
			}
			return result
		}
	}
	
	public var outlineContainers: [OutlineContainer] {
		get async {
			var result = [OutlineContainer]()
			for account in await accounts {
				result.append(contentsOf: await account.outlineContainers)
			}
			return result
		}
	}
	
	var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VinOutlineKit")

	// Prevents anyone accessing the accounts before we've initially loaded them
	var accountsDictionarySemaphore = AsyncSemaphore(value: 1)
	var _accountsDictionary = [Int: Account]()
	var accountsDictionary: [Int: Account] {
		get async {
			await accountsDictionarySemaphore.wait()
			defer { accountsDictionarySemaphore.signal() }
			
			return _accountsDictionary
		}
	}
	
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
		await accountsDictionarySemaphore.wait()

		// The local account must always exist, even if it's empty.
		if FileManager.default.fileExists(atPath: localAccountFile.path) {
			await initializeFile(accountType: .local)
		} else {
			do {
				try FileManager.default.createDirectory(atPath: localAccountFolder.path, withIntermediateDirectories: true, attributes: nil)
			} catch {
				assertionFailure("Could not create folder for local account.")
				abort()
			}
			
			let localAccount = Account(accountType: .local)
			_accountsDictionary[AccountType.local.rawValue] = localAccount
			await initializeFile(accountType: .local)
		}
		
		if FileManager.default.fileExists(atPath: cloudKitAccountFile.path) {
			await initializeFile(accountType: .cloudKit)
			await _accountsDictionary[AccountType.cloudKit.rawValue]?.initializeCloudKit(firstTime: false, errorHandler: errorHandler)
		}
		
		accountsDictionarySemaphore.signal()
		
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
					for await note in NotificationCenter.default.notifications(named: .AccountOutlinesDidChange) {
						let account = note.object as! Account
						await self?.markAsDirty(account)
					}
				}

				group.addTask { [weak self] in
					for await note in NotificationCenter.default.notifications(named: .OutlineMetaDataDidChange) {
						guard let outline = note.object as? Outline, let account = outline.account else { return }
						await self?.markAsDirty(account)
					}
				}

				group.addTask { [weak self] in
					for await note in NotificationCenter.default.notifications(named: .OutlineTitleDidChange) {
						guard let outline = note.object as? Outline, let account = outline.account else { return }
						await self?.markAsDirty(account)
						await account.fixAltLinks(excluding: outline)
						await account.disambiguate(outline: outline)					}
				}

			}
			
		}
		
	}
	
	public func createCloudKitAccount(errorHandler: ErrorHandler) async {
		await accountsDictionarySemaphore.wait()
		defer { accountsDictionarySemaphore.signal() }

		do {
			try FileManager.default.createDirectory(atPath: cloudKitAccountFolder.path, withIntermediateDirectories: true, attributes: nil)
		} catch {
			assertionFailure("Could not create folder for CloudKit account.")
			abort()
		}
		
		let cloudKitAccount = Account(accountType: .cloudKit)
		_accountsDictionary[AccountType.cloudKit.rawValue] = cloudKitAccount
		await initializeFile(accountType: .cloudKit)
		
		activeAccountsDidChange()

		await cloudKitAccount.initializeCloudKit(firstTime: true, errorHandler: errorHandler)
	}
	
	public func deleteCloudKitAccount() async {
		guard let cloudKitAccount = await self.cloudKitAccount else { return }

		await accountsDictionarySemaphore.wait()
		defer { accountsDictionarySemaphore.signal() }

		// Send out all the outline delete events for this account to clean up the search index
		await cloudKitAccount.outlines?.forEach { $0.outlineDidDelete() }
		
		accountFiles[AccountType.cloudKit.rawValue]?.suspend()
		
		_accountsDictionary[AccountType.cloudKit.rawValue] = nil
		accountFiles[AccountType.cloudKit.rawValue] = nil

		try? FileManager.default.removeItem(atPath: cloudKitAccountFolder.path)

		activeAccountsDidChange()

		await cloudKitAccount.cloudKitManager?.accountDidDelete(account: cloudKitAccount)
	}
	
	public func findAccount(accountType: AccountType) async -> Account? {
		return await accountsDictionary[accountType.rawValue]
	}

	public func findAccount(accountID: Int) async -> Account? {
		guard let account = await accountsDictionary[accountID] else { return nil }
		return await account.isActive ? account : nil
	}
	
	public func findOutlineContainer(_ entityID: EntityID) async -> OutlineContainer? {
		switch entityID {
		case .search(let searchText):
			return Search(searchText: searchText)
		case .allOutlines(let accountID), .recentOutlines(let accountID), .tagOutlines(let accountID, _):
			return await findAccount(accountID: accountID)?.findOutlineContainer(entityID)
		default:
			return nil
		}
	}
	
	public func findOutlineContainers(_ entityIDs: [EntityID]) async -> [OutlineContainer] {
		var containers = [OutlineContainer]()
		for entityID in entityIDs {
			if let container = await findOutlineContainer(entityID) {
				containers.append(container)
			}
		}
		return containers
	}
	
	public func findOutline(_ entityID: EntityID) async -> Outline? {
		switch entityID {
		case .outline(let accountID, let outlineUUID):
			return await findAccount(accountID: accountID)?.findOutline(outlineUUID: outlineUUID)
		case .row(let accountID, let outlineUUID, _):
			return await findAccount(accountID: accountID)?.findOutline(outlineUUID: outlineUUID)
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
	
	public func resume() async {
		accountFiles.values.forEach { $0.resume() }
		await activeOutlines.forEach { $0.resume() }
		Task {
			await cloudKitAccount?.cloudKitManager?.resume()
		}
	}
	
	public func suspend() async {
		for accountFile in accountFiles.values {
			await accountFile.saveIfNecessary()
			accountFile.suspend()
		}

		for outline in await activeOutlines {
			await outline.save()
			outline.suspend()
		}

		await cloudKitAccount?.cloudKitManager?.suspend()
	}
	
}

// MARK: Helpers

private extension Outliner {
	
	func activeAccountsDidChange() {
		NotificationCenter.default.post(name: .ActiveAccountsDidChange, object: self, userInfo: nil)
	}

	func sort(_ accounts: [Account]) -> [Account] {
		return accounts.sorted { (account1, account2) -> Bool in
			if account1.type == .local {
				return true
			}
			return false
		}
	}
	
	func initializeFile(accountType: AccountType) async {
		let file: URL
		if accountType == .local {
			file = localAccountFile
		} else {
			file = cloudKitAccountFile
		}
		
		let managedFile = AccountFile(fileURL: file, accountType: accountType, outliner: self)
		await managedFile.load()
		accountFiles[accountType.rawValue] = managedFile
	}

	func markAsDirty(_ account: Account) {
		let accountFile = accountFiles[account.type.rawValue]!
		accountFile.markAsDirty()
	}
	
}
