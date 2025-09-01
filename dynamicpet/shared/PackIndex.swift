//
//  PackIndex.swift
//  dynamicpet
//
//  Created by Angelo on 01/09/2025.
//

import Foundation

struct PackMeta: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let filename: String
    let cols: Int
    let rows: Int
    let cellW: Int
    let cellH: Int
    let scale: Int         // 2 of 3
    let fps: Double
}

struct PackIndex: Codable {
    var installed: [PackMeta] = []
    var activePackId: String? = nil

    mutating func upsert(_ meta: PackMeta) {
        if let i = installed.firstIndex(where: { $0.id == meta.id }) { installed[i] = meta }
        else { installed.append(meta) }
    }

    mutating func remove(id: String) {
        installed.removeAll { $0.id == id }
        if activePackId == id { activePackId = nil }
    }

    func meta(for id: String?) -> PackMeta? {
        guard let id else { return nil }
        return installed.first(where: { $0.id == id })
    }
}
