//
//  AppAssets.swift
//  Manhattan
//
//  Created by Maurice Parker on 11/12/20.
//

import UIKit

struct AppAssets {
	
	static var accent: UIColor = {
		return UIColor(named: "AccentColor")!
	}()
	
	static var createEntity: UIImage = {
		return UIImage(systemName: "square.and.pencil")!
	}()

	static var disclosure: UIImage = {
		return UIImage(systemName: "chevron.right")!.applyingSymbolConfiguration(.init(pointSize: 9, weight: .heavy))!
	}()

	static var favoriteSelected: UIImage = {
		return UIImage(systemName: "star.fill")!
	}()

	static var favoriteUnselected: UIImage = {
		return UIImage(systemName: "star")!
	}()

	static var getInfoEntity: UIImage = {
		return UIImage(systemName: "info.circle")!
	}()

	static var importEntity: UIImage = {
		return UIImage(systemName: "square.and.arrow.down")!
	}()

	static var removeEntity: UIImage = {
		return UIImage(systemName: "trash")!
	}()

}
