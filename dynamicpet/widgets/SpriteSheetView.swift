//
//  SpriteSheetView.swift
//  dynamicpet
//
//  Created by Angelo on 01/09/2025.
//
import SwiftUI
import os

private let spriteLog = Logger(subsystem: "com.perrello.dynamicpet", category: "Sprite")

struct SpriteSheetConfig: Hashable {
    let cols: Int
    let rows: Int
    let cellPx: CGSize
}

struct SpriteSheetView: View {
    let imagePath: String
    let cfg: SpriteSheetConfig
    let index: Int

    var body: some View {
        guard FileManager.default.fileExists(atPath: imagePath) else {
            spriteLog.error("Sprite not found at \(self.imagePath, privacy: .public)")
            return AnyView(ZStack { Color.red.opacity(0.2); Text("sprite not found").font(.caption2) })
        }
        guard let cg = UIImage(contentsOfFile: imagePath)?.cgImage else {
            spriteLog.error("CGImage failed \(self.imagePath, privacy: .public)")
            return AnyView(ZStack { Color.red.opacity(0.2); Text("bad image").font(.caption2) })
        }
        let expW = Int(cfg.cellPx.width) * cfg.cols
        let expH = Int(cfg.cellPx.height) * cfg.rows
        guard cg.width == expW && cg.height == expH else {
            spriteLog.error("Size mismatch \(cg.width)x\(cg.height) exp \(expW)x\(expH)")
            return AnyView(ZStack { Color.red.opacity(0.2); Text("size mismatch").font(.caption2) })
        }

        let col = index % cfg.cols
        let row = (index / cfg.cols) % cfg.rows
        let rect = CGRect(x: CGFloat(col)*cfg.cellPx.width,
                          y: CGFloat(row)*cfg.cellPx.height,
                          width: cfg.cellPx.width,
                          height: cfg.cellPx.height)

        guard let piece = cg.cropping(to: rect) else {
            spriteLog.error("Crop nil")
            return AnyView(ZStack { Color.red.opacity(0.2); Text("crop nil").font(.caption2) })
        }
        return AnyView(
            Image(uiImage: UIImage(cgImage: piece))
                .renderingMode(.original)
                .interpolation(.none)
                .resizable()
                .clipped()
        )
    }
}
