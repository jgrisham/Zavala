//
//  Created by Maurice Parker on 9/13/19.
//

import Foundation
import AsyncAlgorithms
import OSLog

open class ManagedResourceFile: NSObject, NSFilePresenter {
	
	private var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VinUtility")

	private var isDirty = false {
		didSet {
			debounceSaveToDisk()
		}
	}
	
	private var isLoading = false
	private let fileURL: URL
	private let operationQueue: OperationQueue
	private var saveTask: Task<(), Never>?
	private var saveChannel = AsyncChannel<(() -> Void)>()
	private var lastModificationDate: Date?

	public var presentedItemURL: URL? {
		return fileURL
	}
	
	public var presentedItemOperationQueue: OperationQueue {
		return operationQueue
	}
	
	public init(fileURL: URL) {
		
		self.fileURL = fileURL
		
		operationQueue = OperationQueue()
		operationQueue.qualityOfService = .userInteractive
		operationQueue.maxConcurrentOperationCount = 1
	
		super.init()
		
		NSFileCoordinator.addFilePresenter(self)
		
		startSaveTask()
	}
	
	public func presentedItemDidChange() {
		guard !isDirty else { return }
		Task {
			await load()
		}
	}
	
	public func savePresentedItemChanges(completionHandler: @escaping (Error?) -> Void) {
		Task {
			await saveIfNecessary()
			completionHandler(nil)
		}
	}
	
	public func relinquishPresentedItem(toReader reader: @escaping ((() -> Void)?) -> Void) {
		stopSaveTask()
		reader() {
			self.startSaveTask()
		}
	}
	
	public func relinquishPresentedItem(toWriter writer: @escaping ((() -> Void)?) -> Void) {
		stopSaveTask()
		writer() {
			self.startSaveTask()
		}
	}
	
	public func markAsDirty() {
		if !isLoading {
			isDirty = true
		}
	}
	
	public func load() async {
		isLoading = true
		await loadFile()
		isLoading = false
	}
	
	public func saveIfNecessary() async {
		if isDirty {
			isDirty = false
			await saveFile()
		}
	}

	public func delete() {
		suspend()
		deleteFile()
	}

	public func resume() {
		NSFileCoordinator.addFilePresenter(self)
	}
	
	public func suspend() {
		NSFileCoordinator.removeFilePresenter(self)
	}
	
	open func fileDidLoad(data: Data) async {
		fatalError("Function not implemented")
	}
	
	open func fileWillSave() async -> Data? {
		fatalError("Function not implemented")
	}

}

// MARK: Helpers

private extension ManagedResourceFile {
	
	func startSaveTask() {
		saveTask = Task {
			for await save in saveChannel.debounce(for: .seconds(5.0)) {
				if !Task.isCancelled {
					save()
				}
			}
		}
	}
	
	func stopSaveTask() {
		saveTask?.cancel()
		saveTask = nil
	}
	
	func debounceSaveToDisk() {
		Task {
			await saveChannel.send({ [weak self] in
				guard let self else { return }
				Task {
					await self.saveIfNecessary()
				}
			})
		}
	}
	
	func restartActivityMonitoring() {
		stopSaveTask()
		startSaveTask()
	}

	func loadFile() async {
		var fileData: Data? = nil
		let errorPointer: NSErrorPointer = nil
		let fileCoordinator = NSFileCoordinator(filePresenter: self)
		
		fileCoordinator.coordinate(readingItemAt: fileURL, options: [], error: errorPointer, byAccessor: { readURL in
			do {
				let resourceValues = try readURL.resourceValues(forKeys: [.contentModificationDateKey])
				if lastModificationDate != resourceValues.contentModificationDate {
					lastModificationDate = resourceValues.contentModificationDate
					fileData = try Data(contentsOf: readURL)
				}
			} catch {
				logger.error("Account read from disk failed: \(error.localizedDescription, privacy: .public)")
			}
		})
		
		if let error = errorPointer?.pointee {
			logger.error("Account read from disk coordination failed: \(error.localizedDescription, privacy: .public)")
		}
		
		guard let fileData else { return }
		
		await fileDidLoad(data: fileData)
	}
	
	func saveFile() async {
		guard let fileData = await fileWillSave() else { return }
		
		let errorPointer: NSErrorPointer = nil
		let fileCoordinator = NSFileCoordinator(filePresenter: self)
		
		fileCoordinator.coordinate(writingItemAt: fileURL, options: [], error: errorPointer, byAccessor: { writeURL in
			do {
				try fileData.write(to: writeURL)
				let resourceValues = try writeURL.resourceValues(forKeys: [.contentModificationDateKey])
				lastModificationDate = resourceValues.contentModificationDate
			} catch let error as NSError {
				logger.error("Save to disk failed: \(error.localizedDescription, privacy: .public)")
			}
		})
		
		if let error = errorPointer?.pointee {
			logger.error("Save to disk coordination failed: \(error.localizedDescription, privacy: .public)")
		}
	}
	
	func deleteFile() {
		let errorPointer: NSErrorPointer = nil
		let fileCoordinator = NSFileCoordinator(filePresenter: self)
		
		fileCoordinator.coordinate(writingItemAt: fileURL, options: [.forDeleting], error: errorPointer, byAccessor: { writeURL in
			do {
				if FileManager.default.fileExists(atPath: writeURL.path) {
					try FileManager.default.removeItem(atPath: writeURL.path)
				}
			} catch let error as NSError {
				logger.error("Delete from disk failed: \(error.localizedDescription, privacy: .public)")
			}
		})
		
		if let error = errorPointer?.pointee {
			logger.error("Delete from disk coordination failed: \(error.localizedDescription, privacy: .public)")
		}
	}

}
