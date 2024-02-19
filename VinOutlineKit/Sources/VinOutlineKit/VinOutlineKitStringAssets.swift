//
//  VinOutlineKitStringAssets.swift
//  
//
//  Created by Maurice Parker on 10/6/22.
//
import Foundation

struct VinOutlineKitStringAssets {
	
	static var accountOnMyMac = String(localized: "On My Mac", comment: "Local Account Name: On My Mac")
	static var accountOnMyIPad = String(localized: "On My iPad", comment: "Local Account Name: On My iPad")
	static var accountOnMyIPhone = String(localized: "On My iPhone", comment: "Local Account Name: On My iPhone")
	static var accountICloud = String(localized: "iCloud", comment: "iCloud Account Name: iCloud")

	static var noTitle = String(localized: "(No Title)", comment: "OPML Export Title: (No Title)")
	static var all = String(localized: "All", comment: "Collection: Search Outlines")
	static var search = String(localized: "Search", comment: "Collection: Search Outlines")

	static var accountErrorScopedResource =	String(localized: "Unable to access security scoped resource.",
												   comment: "Error Message: Unable to access security scoped resource.")
	
	static var accountErrorImportRead = String(localized: "Unable to read the import file.",
											   comment: "Error Message: Unable to read the import file.")
	static var accountErrorOPMLParse = String(localized: "Unable to process the OPML data.",
											   comment: "Error Message: Unable to read the import file.")
	
	static var rowDeserializationError = String(localized: "Unable to deserialize the row data.",
												comment: "Error Message: Unable to deserialize the row data.")

}
