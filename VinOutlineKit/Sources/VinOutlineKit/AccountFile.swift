//
//  AccountFile.swift
//  
//
//  Created by Maurice Parker on 11/6/20.
//

import Foundation
import OSLog
import VinUtility

final class AccountFile: ManagedResourceFile {

	public static let filenameComponent = "account.plist"
	private let accountType: AccountType
	private weak var outliner: Outliner?
	
	public init(fileURL: URL, accountType: AccountType, outliner: Outliner) {
		self.accountType = accountType
		self.outliner = outliner
		super.init(fileURL: fileURL)
	}
	
	public override func fileDidLoad(data: Data) async {
		await outliner?.loadAccountFileData(data, accountType: accountType)
	}
	
	public override func fileWillSave() async -> Data? {
		return await outliner?.buildAccountFileData(accountType: accountType)
	}
	
}
