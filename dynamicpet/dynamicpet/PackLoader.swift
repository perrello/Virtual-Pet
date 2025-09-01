//
//  PackLoader.swift
//  dynamicpet
//
//  Created by Angelo on 01/09/2025.
//
import Foundation
import UIKit

enum PackLoader {
    static func install(from manifestURL: URL) async throws
      -> (manifest: PetManifest, spritePath: String, cfg: [Int]) {

        let (data, _) = try await URLSession.shared.data(from: manifestURL)
        let manifest = try JSONDecoder().decode(PetManifest.self, from: data)

        let v = manifest.variants.first(where: { $0.scale == 3 }) ?? manifest.variants[0]

        let base = SharedStore.packDir(manifest.id)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let spriteURL = manifestURL.deletingLastPathComponent().appendingPathComponent(v.sprite)
        let (png, _) = try await URLSession.shared.data(from: spriteURL)
        let dest = base.appendingPathComponent(v.sprite)
        try png.write(to: dest, options: .atomic)

        try data.write(to: base.appendingPathComponent("manifest.json"), options: .atomic)

        // Validatie
        let cg = UIImage(contentsOfFile: dest.path)?.cgImage
        let okW = cg?.width ?? 0, okH = cg?.height ?? 0
        let expW = v.cols * v.cellPx.w, expH = v.rows * v.cellPx.h
        if okW != expW || okH != expH {
            print("⚠️ Sprite size mismatch: image=\(okW)x\(okH) expected=\(expW)x\(expH)")
        }

        let cfg = [v.cols, v.rows, v.cellPx.w, v.cellPx.h]
        let d = SharedStore.defaults
        d.set(manifest.id, forKey: "currentPackID")
        d.set(v.sprite,    forKey: "currentSpriteFilename")
        d.set(cfg,         forKey: "currentCfg")
        d.removeObject(forKey: "currentSpritePath")

        _ = d.synchronize()

        return (manifest, dest.path, cfg)
    }
}
