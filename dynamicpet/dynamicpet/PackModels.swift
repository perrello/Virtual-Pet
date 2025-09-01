//
//  PackModels.swift
//  dynamicpet
//
//  Created by Angelo on 01/09/2025.
//
import Foundation

struct PetManifest: Codable {
    let id: String
    let name: String
    let variants: [Variant]
    let fps: Double

    struct Variant: Codable {
        let scale: Int
        let cols: Int
        let rows: Int
        let cellPx: Size
        let sprite: String
    }
    struct Size: Codable { let w: Int; let h: Int }
}

