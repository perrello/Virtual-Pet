//
//  SharedStore.swift
//  dynamicpet
//
//  Created by Angelo on 01/09/2025.
//
import Foundation

enum SharedStore {
    static let groupID = "group.com.perrello.dynamicpet"

    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)!
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: groupID)!
    }

    static var packsRoot: URL {
        containerURL.appendingPathComponent("Packs", isDirectory: true)
    }

    static func packDir(_ id: String) -> URL {
        packsRoot.appendingPathComponent(id, isDirectory: true)
    }

    static var indexURL: URL {
        packsRoot.appendingPathComponent("index.json")
    }
}

