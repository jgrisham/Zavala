//
//  CloudKitManager.swift
//  
//
//  Created by Maurice Parker on 2/6/21.
//

#if canImport(UIKit)
import UIKit
#else
import Foundation
#endif
import OSLog
import SystemConfiguration
import CloudKit
import Semaphore
import VinCloudKit
import VinUtility

public extension Notification.Name {
	static let CloudKitSyncWillBegin = Notification.Name(rawValue: "CloudKitSyncWillBegin")
	static let CloudKitSyncDidComplete = Notification.Name(rawValue: "CloudKitSyncDidComplete")
}

public class CloudKitManager {

	class CombinedRequest {
		var outlineRequest: CloudKitActionRequest?
		var rowRequests = [CloudKitActionRequest]()
		var imageRequests = [CloudKitActionRequest]()
	}

	var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VinOutlineKit")

	let outlineZone: CloudKitOutlineZone

	var isSyncAvailable: Bool {
		return !isSyncing && isNetworkAvailable
	}
	
	public let container: CKContainer = {
		let orgID = Bundle.main.object(forInfoDictionaryKey: "OrganizationIdentifier") as! String
		return CKContainer(identifier: "iCloud.\(orgID).Zavala")
	}()

	private weak var errorHandler: ErrorHandler?
	private weak var account: Account?

	#if canImport(UIKit)
	private var sendChangesBackgroundTaskID = UIBackgroundTaskIdentifier.invalid
	#endif

	private var debouncer = Debouncer(duration: 5)
	private var zones = [CKRecordZone.ID: CloudKitOutlineZone]()
	private let requestsSemaphore = AsyncSemaphore(value: 1)
	
	private var isSyncing = false
	private var isNetworkAvailable: Bool {
		var zeroAddress = sockaddr_in()
		zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
		zeroAddress.sin_family = sa_family_t(AF_INET)

		guard let defaultRouteReachability = withUnsafePointer(to: &zeroAddress, {
			 $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				 SCNetworkReachabilityCreateWithAddress(nil, $0)
			 }
		 }) else {
			 return false
		 }

		 var flags: SCNetworkReachabilityFlags = []
		 if !SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags) {
			 return false
		 }

		 let isReachable = flags.contains(.reachable)
		 let needsConnection = flags.contains(.connectionRequired)

		 return (isReachable && !needsConnection)
	}
		
	init(account: Account, errorHandler: ErrorHandler) async {
		self.account = account
		self.outlineZone = CloudKitOutlineZone(container: container)
		outlineZone.delegate = CloudKitOutlineZoneDelegate(account: account, zoneID: self.outlineZone.zoneID)
		self.zones[outlineZone.zoneID] = outlineZone
		self.errorHandler = errorHandler
		await migrateSharedDatabaseChangeToken()
		await outlineZone.migrateChangeToken()
	}
	
	func firstTimeSetup() async {
		do {
			// This will create the record zone if one doesn't exist
			let _ = try await outlineZone.fetchRecordZone()
			try await outlineZone.subscribeToZoneChanges()
			try await subscribeToSharedDatabaseChanges()
		} catch {
			await presentError(error)
		}
	}
	
	func addRequest(_ request: CloudKitActionRequest) {
		var requests = Set<CloudKitActionRequest>()
		requests.insert(request)
		addRequests(requests)
	}
	
	func addRequests(_ requests: Set<CloudKitActionRequest>) {
		Task {
			await requestsSemaphore.wait()
			defer { requestsSemaphore.signal() }

			let queuedRequests: Set<CloudKitActionRequest>
			
			if let fileData = try? Data(contentsOf: CloudKitActionRequest.actionRequestFile) {
				let decoder = PropertyListDecoder()
				if let decodedRequests = try? decoder.decode(Set<CloudKitActionRequest>.self, from: fileData) {
					queuedRequests = decodedRequests
				} else {
					queuedRequests = Set<CloudKitActionRequest>()
				}
			} else {
				queuedRequests = Set<CloudKitActionRequest>()
			}
			
			let mergedRequests = queuedRequests.union(requests)
			CloudKitActionRequest.save(requests: mergedRequests)
			
			debouncer.debounce { [weak self] in
				guard let self, self.isNetworkAvailable else { return }
				Task {
					do {
						try await self.sendChanges(userInitiated: false)
						try await self.fetchAllChanges(userInitiated: false)
					} catch {
						await self.presentError(error)
					}
				}
			}
		}
	}
	
	func receiveRemoteNotification(userInfo: [AnyHashable : Any]) async {
		await requestsSemaphore.wait()
		defer { requestsSemaphore.signal() }

		do {
			if let dbNote = CKDatabaseNotification(fromRemoteNotificationDictionary: userInfo), dbNote.notificationType == .database {
				try await sendChanges(userInitiated: false)
				try await fetchAllChanges(userInitiated: false)
			} else if let zoneNote = CKRecordZoneNotification(fromRemoteNotificationDictionary: userInfo), zoneNote.notificationType == .recordZone {
				guard let zoneId = zoneNote.databaseScope == .private ? outlineZone.zoneID : zoneNote.recordZoneID else {
					return
				}
				try await sendChanges(userInitiated: false)
				try await fetchChanges(userInitiated: false, zoneID: zoneId)
			}
		} catch {
			await presentError(error)
		}
	}
	
	func sync() async {
		await requestsSemaphore.wait()
		defer { requestsSemaphore.signal() }

		guard isNetworkAvailable else {
			return
		}
		
		cloudKitSyncWillBegin()

		do {
			try await sendChanges(userInitiated: true)
			try await fetchAllChanges(userInitiated: true)
		} catch {
			await presentError(error)
		}
		
		cloudKitSyncDidComplete()
	}
	
	func userDidAcceptCloudKitShareWith(_ shareMetadata: CKShare.Metadata) async {
		await requestsSemaphore.wait()
		defer { requestsSemaphore.signal() }
		
		return await withCheckedContinuation { continuation in
			let op = CKAcceptSharesOperation(shareMetadatas: [shareMetadata])
			op.qualityOfService = CloudKitOutlineZone.qualityOfService
			
			op.acceptSharesResultBlock = { [weak self] result in
				guard let self else { return }
				
				switch result {
				case .success:
					let zoneID = shareMetadata.share.recordID.zoneID
					Task {
						self.cloudKitSyncWillBegin()
						do {
							try await self.fetchChanges(userInitiated: true, zoneID: zoneID)
							self.cloudKitSyncDidComplete()
							continuation.resume()
						} catch {
							await self.presentError(error)
							self.cloudKitSyncDidComplete()
							continuation.resume()
						}
					}
				case .failure(let error):
					Task {
						await self.presentError(error)
						continuation.resume()
					}
				}
			}
			
			container.add(op)
		}
	}
	
	func generateCKShare(for outline: Outline) async throws -> CKShare {
		guard let zoneID = outline.zoneID else {
			throw CloudKitOutlineZoneError.unknown
		}
		
		let zone = findZone(zoneID: zoneID)
		return try await zone.generateCKShare(for: outline)
	}
	
	func resume() async {
		await sync()
	}
	
	func suspend() async {
		debouncer.executeNow()
	}
	
	func accountDidDelete(account: Account) async {
		var zoneIDs = Set<CKRecordZone.ID>()

		// If the user deletes all the outlines prior to deleting the account, we
		// won't reset the default zone unless we add it manually.
		zoneIDs.insert(outlineZone.zoneID)
		
		for outline in await account.outlines ?? [Outline]() {
			if let zoneID = outline.zoneID {
				zoneIDs.insert(zoneID)
			}
		}
		
		await storeSharedDatabaseChangeToken(token: nil)
	}
	
	// We need this function because at one time we didn't store the CKShare records locally. We
	// probably need to keep it, becaust we sometimes miss the CKShare when accepting a shared
	// outline. This fixes that problem.
	func addSyncRecordIfNeeded(outline: Outline) {
		guard outline.cloudKitShareRecordName != nil && outline.cloudKitShareRecordData == nil,
			  let zoneID = outline.zoneID,
			  isNetworkAvailable else { return }
		
		let zone = findZone(zoneID: zoneID)

		Task { @MainActor in
			if let shareRecord = try await zone.fetch(externalID: outline.cloudKitShareRecordName!) as? CKShare {
				outline.cloudKitShareRecord = shareRecord
			}
		}
	}
	
}

// MARK: Helpers

private extension CloudKitManager {
	
	@MainActor
	func presentError(_ error: Error) {
		errorHandler?.presentError(error, title: "CloudKit Syncing Error")
	}
	
	func cloudKitSyncWillBegin() {
		NotificationCenter.default.post(name: .CloudKitSyncWillBegin, object: self, userInfo: nil)
	}
	
	func cloudKitSyncDidComplete() {
		NotificationCenter.default.post(name: .CloudKitSyncDidComplete, object: self, userInfo: nil)
	}
	
	func findZone(zoneID: CKRecordZone.ID) -> CloudKitOutlineZone {
		if let zone = zones[zoneID] {
			return zone
		}
		
		let zone = CloudKitOutlineZone(container: container, database: container.sharedCloudDatabase, zoneID: zoneID)
		zone.delegate = CloudKitOutlineZoneDelegate(account: account!, zoneID: zoneID)
		zones[zoneID] = zone
		return zone
	}
	
	@MainActor
	func sendChanges(userInitiated: Bool) async throws {
		isSyncing = true
		
		guard let requests = CloudKitActionRequest.loadRequests(), !requests.isEmpty else {
			logger.info("No pending requests to send.")
			return
		}
		
#if canImport(UIKit)
		let completeProcessing = { [weak self] in
			guard let self else {
				return
			}
			
			self.isSyncing = false
			self.sendChangesBackgroundTaskID = UIBackgroundTaskIdentifier.invalid
			
			Task { @MainActor in
				UIApplication.shared.endBackgroundTask(self.sendChangesBackgroundTaskID)
			}
		}
		
		self.sendChangesBackgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
			self?.logger.info("CloudKit sync processing terminated for running too long.")
		}
#endif
		
		logger.info("Sending \(requests.count) requests.")
		
		let (loadedOutlines, modifications) = await loadOutlinesAndStageModifications(requests: requests)
		
		// Send the grouped changes
		
		let leftOverRequests = try await withThrowingTaskGroup(of: ([EntityID], [EntityID]).self, returning: Set<CloudKitActionRequest>.self) { taskGroup in
			var leftOverRequests = requests
			
			for zoneID in modifications.keys {
				let cloudKitZone = findZone(zoneID: zoneID)
				let (modelsToSave, recordIDsToDelete) = modifications[zoneID]!
				
				let strategy = VCKModifyStrategy.onlyIfServerUnchanged
				
				taskGroup.addTask {
					let (completedSaves, completedDeletes) = try await cloudKitZone.modify(modelsToSave: modelsToSave, recordIDsToDelete: recordIDsToDelete, strategy: strategy)
					await self.updateSyncMetaData(savedRecords: completedSaves)
					
					let savedEntityIDs = completedSaves.compactMap { EntityID(description: $0.recordID.recordName) }
					let deletedEntityIDs = completedDeletes.compactMap { EntityID(description: $0.recordName) }
					
					return (savedEntityIDs, deletedEntityIDs)
				}
				
				do {
					for try await (savedEntityIDs, deletedEntityIDs) in taskGroup {
						leftOverRequests.subtract(savedEntityIDs.map { CloudKitActionRequest(zoneID: zoneID, id: $0) })
						leftOverRequests.subtract(deletedEntityIDs.map { CloudKitActionRequest(zoneID: zoneID, id: $0) })
					}
				} catch {
					if let ckError = error as? CKError, ckError.code == .userDeletedZone {
						await account?.deleteAllOutlines(with: zoneID)
						throw VCKError.userDeletedZone
					} else {
						throw error
					}
				}
			}
			
			return leftOverRequests
		}
		
		for loadedOutline in loadedOutlines {
			await loadedOutline.unload()
		}
		
		self.logger.info("Saving \(leftOverRequests.count) requests.")
		CloudKitActionRequest.save(requests: leftOverRequests)
		
		for mods in modifications.values {
			for save in mods.0 {
				save.clearSyncData()
			}
		}
		
		completeProcessing()
	}
	
	func fetchAllChanges(userInitiated: Bool) async throws {
		isSyncing = true
		var zoneIDs = Set<CKRecordZone.ID>()
		zoneIDs.insert(outlineZone.zoneID)
		
		let changeToken = await sharedDatabaseChangeToken
		
		return try await withCheckedThrowingContinuation { continuation in
			let op = CKFetchDatabaseChangesOperation(previousServerChangeToken: changeToken)
			op.qualityOfService = CloudKitOutlineZone.qualityOfService
			
			op.recordZoneWithIDWasDeletedBlock = { zoneID in
				zoneIDs.insert(zoneID)
			}
			
			op.recordZoneWithIDChangedBlock = { zoneID in
				zoneIDs.insert(zoneID)
			}
			
			op.fetchDatabaseChangesResultBlock = { [weak self] result in
				guard let self else {
					continuation.resume()
					return
				}
				
				switch result {
				case .success((let token, _)):
					let zoneIDs = zoneIDs
					Task {
						await withTaskGroup(of: Void.self) { taskGroup in
							for zoneID in zoneIDs {
								taskGroup.addTask {
									do {
										try await self.fetchChanges(userInitiated: userInitiated, zoneID: zoneID)
									} catch {
										await self.presentError(error)
									}
								}
							}
						}
						
						await self.storeSharedDatabaseChangeToken(token: token)
						self.isSyncing = false
						continuation.resume()
					}
				case .failure(let error):
					continuation.resume(throwing: error)
				}
			}
			
			container.sharedCloudDatabase.add(op)
		}
		
	}
	
	@MainActor
	func fetchChanges(userInitiated: Bool, zoneID: CKRecordZone.ID) async throws {
		let zone = findZone(zoneID: zoneID)
		
		do {
			try await zone.fetchChangesInZone(incremental: false)
		} catch {
			if let ckError = error as? CKError, ckError.code == .userDeletedZone {
				await account?.deleteAllOutlines(with: zoneID)
				throw VCKError.userDeletedZone
			} else {
				throw error
			}
		}
	}
	
	func loadOutlinesAndStageModifications(requests: Set<CloudKitActionRequest>) async -> ([Outline], [CKRecordZone.ID: ([VCKModel], [CKRecord.ID])]) {
		var loadedOutlines = [Outline]()
		var modifications = [CKRecordZone.ID: ([VCKModel], [CKRecord.ID])]()
		
		func addSave(_ zoneID: CKRecordZone.ID, _ model: VCKModel) {
			if let (saves, deletes) = modifications[zoneID] {
				var mutableSaves = saves
				mutableSaves.append(model)
				modifications[zoneID] = (mutableSaves, deletes)
			} else {
				var saves = [VCKModel]()
				saves.append(model)
				let deletes = [CKRecord.ID]()
				modifications[zoneID] = (saves, deletes)
			}
		}
		
		func addDelete(_ request: CloudKitActionRequest) {
			let zoneID = request.zoneID
			let recordID = CKRecord.ID(recordName: request.id.description, zoneID: zoneID)
			addDelete(zoneID, recordID)
		}
		
		func addDelete(_ zoneID: CKRecordZone.ID, _ recordID: CKRecord.ID) {
			if let (saves, deletes) = modifications[zoneID] {
				var mutableDeletes = deletes
				mutableDeletes.append(recordID)
				modifications[zoneID] = (saves, mutableDeletes)
			} else {
				let saves = [VCKModel]()
				var deletes = [CKRecord.ID]()
				deletes.append(recordID)
				modifications[zoneID] = (saves, deletes)
			}
		}
		
		let combinedRequests = combine(requests: requests)
		
		for outlineUUID in combinedRequests.keys {
			guard let combinedRequest = combinedRequests[outlineUUID] else { continue }
			
			// If we don't have an outline, we probably have a delete request to send.
			// We don't have to continue processing since we cascade delete our rows.
			guard let outline = await account?.findOutline(outlineUUID: outlineUUID) else {
				if let outlineRequest = combinedRequest.outlineRequest {
					addDelete(outlineRequest)
				}
				continue
			}
			
			await outline.load()
			loadedOutlines.append(outline)
			
			guard let zoneID = outline.zoneID else { continue }
			
			// This has to be a save for the outline
			if combinedRequest.outlineRequest != nil {
				addSave(zoneID, outline)
			}
			
			// Now process all the rows
			for rowRequest in combinedRequest.rowRequests {
				if let row = outline.findRow(id: rowRequest.id.rowUUID) {
					addSave(zoneID, row)
				} else {
					addDelete(rowRequest)
				}
			}
			
			// Now process all the images
			for imageRequest in combinedRequest.imageRequests {
				// if the row is gone, we don't need to process the images because we cascade our deletes
				if let row = outline.findRow(id: imageRequest.id.rowUUID) {
					if let image = row.findImage(id: imageRequest.id) {
						addSave(zoneID, image)
					} else {
						addDelete(imageRequest)
					}
				}
			}
		}
		
		return (loadedOutlines, modifications)
	}
	
	func combine(requests: Set<CloudKitActionRequest>) -> [String: CombinedRequest] {
		var combinedRequests = [String: CombinedRequest]()
		
		for request in requests {
			switch request.id {
			case .outline(_, let outlineUUID):
				if let combinedRequest = combinedRequests[outlineUUID] {
					combinedRequest.outlineRequest = request
					combinedRequests[outlineUUID] = combinedRequest
				} else {
					let combinedRequest = CombinedRequest()
					combinedRequest.outlineRequest = request
					combinedRequests[outlineUUID] = combinedRequest
				}
			case .row(_, let outlineUUID, _):
				if let combinedRequest = combinedRequests[outlineUUID] {
					combinedRequest.rowRequests.append(request)
					combinedRequests[outlineUUID] = combinedRequest
				} else {
					let combinedRequest = CombinedRequest()
					combinedRequest.rowRequests.append(request)
					combinedRequests[outlineUUID] = combinedRequest
				}
			case .image(_, let outlineUUID, _, _):
				if let combinedRequest = combinedRequests[outlineUUID] {
					combinedRequest.imageRequests.append(request)
					combinedRequests[outlineUUID] = combinedRequest
				} else {
					let combinedRequest = CombinedRequest()
					combinedRequest.imageRequests.append(request)
					combinedRequests[outlineUUID] = combinedRequest
				}
			default:
				fatalError()
			}
		}
		
		return combinedRequests
	}
	
	// Don't update the sync metadata if we just performed a merge. When that happens what is in the cloud
	// is out of sync with what we currently have a record of. We will immediately do a sync after this,
	// where we will get a batch of data to sync. If we store the metadata of any merged records, we won't
	// try to apply the received record changes in the various mode apply() methods.
	func updateSyncMetaData(savedRecords: [CKRecord]) async {
		for savedRecord in savedRecords {
			guard let entityID = EntityID(description: savedRecord.recordID.recordName),
				  let outline = await account?.findOutline(entityID)?.outline else { continue }
			
			switch savedRecord.recordType {
			case "Outline":
				if !outline.isCloudKitMerging {
					outline.cloudKitMetaData = savedRecord.metadata
				}
			case "Row":
				if let row = outline.findRowContainer(entityID: entityID) as? Row, !row.isCloudKitMerging {
					row.cloudKitMetaData = savedRecord.metadata
				}
			case "Image":
				if let image = (outline.findRowContainer(entityID: entityID) as? Row)?.findImage(id: entityID), !image.isCloudKitMerging {
					image.cloudKitMetaData = savedRecord.metadata
				}
			default:
				break
			}
		}
	}
	
	func subscribeToSharedDatabaseChanges() async throws {
		let outlineSubscription = sharedDatabaseSubscription(recordType: Outline.CloudKitRecord.recordType)
		let rowSubscription = sharedDatabaseSubscription(recordType: Row.CloudKitRecord.recordType)
		let imageSubscription = sharedDatabaseSubscription(recordType: Image.CloudKitRecord.recordType)
		
		return try await withCheckedThrowingContinuation { continuation in
			let op = CKModifySubscriptionsOperation(subscriptionsToSave: [outlineSubscription, rowSubscription, imageSubscription], subscriptionIDsToDelete: nil)
			op.qualityOfService = CloudKitOutlineZone.qualityOfService
			
			op.modifySubscriptionsResultBlock = { result in
				switch result {
				case .success:
					continuation.resume()
				case .failure(let error):
					continuation.resume(throwing: error)
				}
			}
			
			container.sharedCloudDatabase.add(op)
		}
	}
	
	func sharedDatabaseSubscription(recordType: String) -> CKDatabaseSubscription {
		let subscription = CKDatabaseSubscription(subscriptionID: "\(recordType)-changes")
		subscription.recordType = recordType
		
		let notificationInfo = CKSubscription.NotificationInfo()
		notificationInfo.shouldSendContentAvailable = true
		subscription.notificationInfo = notificationInfo
		
		return subscription
	}
	
	func migrateSharedDatabaseChangeToken() async {
		if let tokenData = UserDefaults.standard.object(forKey: oldSharedDatabaseChangeTokenKey) as? Data {
			await account?.storeSharedDatabase(changeToken: tokenData)
			UserDefaults.standard.removeObject(forKey: oldSharedDatabaseChangeTokenKey)
		}
	}
	
	var oldSharedDatabaseChangeTokenKey: String {
		return "cloudkit.server.token.sharedDatabase"
	}
	
	var sharedDatabaseChangeToken: CKServerChangeToken? {
		get async {
			guard let tokenData = await account?.sharedDatabaseChangeToken else { return nil }
			return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: tokenData)
		}
	}
	
	func storeSharedDatabaseChangeToken(token: CKServerChangeToken?) async {
		if let token, let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false) {
			await account?.storeSharedDatabase(changeToken: tokenData)
		} else {
			await account?.storeSharedDatabase(changeToken: nil)
		}
	}
	
}
