//
//  PackManager.swift
//  dynamicpet
//
//  Created by Angelo on 01/09/2025.
//
import Foundation
import UIKit

enum PackManager {
    
    // MARK: - Index I/O
    private static func ensureRoot() throws { // ensures root folder exists
        try FileManager.default.createDirectory(at: SharedStore.packsRoot, withIntermediateDirectories: true)
    }

    private static func readIndex() -> PackIndex {
        (try? Data(contentsOf: SharedStore.indexURL))
            .flatMap { try? JSONDecoder().decode(PackIndex.self, from: $0) } ?? PackIndex()
    }
    
    private static func addToIndex(manifest: PetManifest, variant: PetManifest.Variant) -> PackMeta {
        var index = readIndex()
        let meta = PackMeta(
            id: manifest.id,
            name: manifest.name,
            filename: variant.sprite,
            cols: variant.cols, rows: variant.rows,
            cellW: variant.cellPx.w, cellH: variant.cellPx.h,
            scale: variant.scale,
            fps: manifest.fps
        )
        index.upsert(meta)
        
        // Zet nieuwe pack meteen actief TODO
//        index.activePackId = manifest.id
        writeIndex(index)
        return meta
    }

    private static func writeIndex(_ idx: PackIndex) { //TODO
        do {
            try ensureRoot()
            let data = try JSONEncoder().encode(idx)
            try data.write(to: SharedStore.indexURL, options: [.atomic])
        } catch {
            print("❌ writeIndex failed:", error)
        }
        _ = SharedStore.defaults.synchronize() // sim-flush
    }
    
    private static func getPackageInformationFromHost(url: URL) async throws -> (data: Data, manifest: PetManifest) {
        let (data, _) = try await URLSession.shared.data(from: url)
        let manifest = try JSONDecoder().decode(PetManifest.self, from: data)
        return (data, manifest)
    }
    
    private static func getSpritesheetFromHost(manifestUrl: URL, sprite: String) async throws -> Data {
        let spriteURL = manifestUrl
            .deletingLastPathComponent()
            .appendingPathComponent(sprite)
        let (png, _) = try await URLSession.shared.data(from: spriteURL)
        return png;
    }
    
    private static func validateSprite(spriteDestination: URL, spriteVariant: PetManifest.Variant) {
        if let cg = UIImage(contentsOfFile: spriteDestination.path)?.cgImage {
            let expW = spriteVariant.cols * spriteVariant.cellPx.w
            let expH = spriteVariant.rows * spriteVariant.cellPx.h
            if cg.width != expW || cg.height != expH {
                print("⚠️ size mismatch: \(cg.width)x\(cg.height) expected \(expW)x\(expH)") //TODO throw
            }
        }
    }

    // MARK: - Public API
    static func list() -> PackIndex {
        readIndex()
    }

    static func setActive(meta: PackMeta) {
        var index = readIndex()
        index.activePackId = meta.id
        writeIndex(index)
    }

    static func remove(id: String) {
        var idx = readIndex()
        let dir = SharedStore.packDir(id)
        try? FileManager.default.removeItem(at: dir)
        idx.remove(id: id)
        writeIndex(idx)
    }

    /// Installeer vanuit manifest-URL. Schrijft naar .../Packs/<id>/
    static func install(from targetUrl: URL) async throws -> PackMeta {
        try ensureRoot()
        
        let (data, manifest) = try await getPackageInformationFromHost(url: targetUrl)

        //find highest quality variant in the manifest
        let spriteVariant = manifest.variants.first(where: { $0.scale == 3 }) ?? manifest.variants[0] //TODO
        
        // Create folder
        let packDirectory = SharedStore.packDir(manifest.id)
        try? FileManager.default.createDirectory(at: packDirectory, withIntermediateDirectories: true)

        // Sprite
        let png = try await getSpritesheetFromHost(manifestUrl: targetUrl, sprite: spriteVariant.sprite)
        let spriteDestination = packDirectory.appendingPathComponent(spriteVariant.sprite)
        try png.write(to: spriteDestination, options: [.atomic])

        // Manifest lokaal
        try data.write(to: packDirectory.appendingPathComponent("manifest.json"), options: [.atomic])

        // Validatie
        validateSprite(spriteDestination: spriteDestination, spriteVariant: spriteVariant)

        // Index bijwerken
        return addToIndex(manifest: manifest, variant: spriteVariant)
    }
    
    static func settle() async {
        try? await Task.sleep(nanoseconds: 150_000_000) // 150 ms TODO - hebben we dit nodig want blegh
    }
}
