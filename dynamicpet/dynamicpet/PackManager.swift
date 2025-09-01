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

    private static func ensureRoot() throws {
        try FileManager.default.createDirectory(at: SharedStore.packsRoot, withIntermediateDirectories: true)
    }

    private static func readIndex() -> PackIndex {
        (try? Data(contentsOf: SharedStore.indexURL))
            .flatMap { try? JSONDecoder().decode(PackIndex.self, from: $0) } ?? PackIndex()
    }

    private static func writeIndex(_ idx: PackIndex) {
        do {
            try ensureRoot()
            let data = try JSONEncoder().encode(idx)
            try data.write(to: SharedStore.indexURL, options: [.atomic])
        } catch {
            print("❌ writeIndex failed:", error)
        }
        _ = SharedStore.defaults.synchronize() // sim-flush
    }

    // MARK: - Public API

    static func list() -> PackIndex {
        readIndex()
    }

    static func setActive(id: String?) {
        var idx = readIndex()
        idx.activePackId = id
        writeIndex(idx)
    }

    static func remove(id: String) {
        var idx = readIndex()
        let dir = SharedStore.packDir(id)
        try? FileManager.default.removeItem(at: dir)
        idx.remove(id: id)
        writeIndex(idx)
    }

    /// Installeer vanuit manifest-URL. Schrijft naar .../Packs/<id>/
    static func install(from manifestURL: URL) async throws -> PackMeta {
        try ensureRoot()

        let (data, _) = try await URLSession.shared.data(from: manifestURL)
        let manifest = try JSONDecoder().decode(PetManifest.self, from: data)

        let v = manifest.variants.first(where: { $0.scale == 3 }) ?? manifest.variants[0]
        let dir = SharedStore.packDir(manifest.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Sprite
        let spriteURL = manifestURL.deletingLastPathComponent().appendingPathComponent(v.sprite)
        let (png, _) = try await URLSession.shared.data(from: spriteURL)
        let spriteDest = dir.appendingPathComponent(v.sprite)
        try png.write(to: spriteDest, options: [.atomic])

        // Manifest lokaal
        try data.write(to: dir.appendingPathComponent("manifest.json"), options: [.atomic])

        // Validatie
        if let cg = UIImage(contentsOfFile: spriteDest.path)?.cgImage {
            let expW = v.cols * v.cellPx.w
            let expH = v.rows * v.cellPx.h
            if cg.width != expW || cg.height != expH {
                print("⚠️ size mismatch: \(cg.width)x\(cg.height) expected \(expW)x\(expH)")
            }
        }

        // Index bijwerken
        var idx = readIndex()
        let meta = PackMeta(
            id: manifest.id,
            name: manifest.name,
            filename: v.sprite,
            cols: v.cols, rows: v.rows,
            cellW: v.cellPx.w, cellH: v.cellPx.h,
            scale: v.scale,
            fps: manifest.fps
        )
        idx.upsert(meta)
        // Zet nieuwe pack meteen actief
        idx.activePackId = manifest.id
        writeIndex(idx)

        return meta
    }

    /// Hulp om op app-/UI-kant even te wachten. Handig in de sim.
    static func settle() async {
        try? await Task.sleep(nanoseconds: 150_000_000) // 150 ms
    }
}

extension PackManager {
    static func activate(_ meta: PackMeta) throws {
        // bronnen
        let srcDir = SharedStore.packDir(meta.id)
        let src    = srcDir.appendingPathComponent(meta.filename)

        // doel
        let dest   = SharedStore.containerURL.appendingPathComponent("current-sprite.png")

        // schrijf sprite
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: src, to: dest)

        // cfg + fps
        let cfg = [meta.cols, meta.rows, meta.cellW, meta.cellH]
        let d = SharedStore.defaults
        d.set(cfg,           forKey: "currentCfg")
        d.set(meta.fps,      forKey: "currentFps") // optioneel, handig
        _ = d.synchronize() // simulator flush

        // (optioneel) bewaar activePackId ook in index.json
        var idx = readIndex()
        idx.activePackId = meta.id
        writeIndex(idx)
    }
}
