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
    /// Pixel-afmetingen van één cel (bijv. 480×480)
    let cellPx: CGSize
}

struct SpriteSheetView: View {
    let imagePath: String
    let cfg: SpriteSheetConfig
    let index: Int
    var desiredSizePt: CGSize? = nil

    @Environment(\.displayScale) private var displayScale

    var body: some View { content() }

    @ViewBuilder
    private func content() -> some View {
        if !FileManager.default.fileExists(atPath: imagePath) {
            errorBox("sprite not found")
                .onAppear { spriteLog.error("Sprite not found at \(self.imagePath, privacy: .public)") }
        }
        else if let cg = UIImage(contentsOfFile: imagePath)?.cgImage {
            let expW = Int(cfg.cellPx.width) * cfg.cols
            let expH = Int(cfg.cellPx.height) * cfg.rows

            if cg.width != expW || cg.height != expH {
                errorBox("size mismatch")
                    .onAppear {
                        spriteLog.error("Size mismatch \(cg.width)x\(cg.height) exp \(expW)x\(expH)")
                    }
            } else {
                spritePiece(cg: cg)
            }
        }
        else {
            errorBox("bad image")
                .onAppear { spriteLog.error("CGImage failed \(self.imagePath, privacy: .public)") }
        }
    }

    @ViewBuilder
    private func spritePiece(cg: CGImage) -> some View {
        let col = index % cfg.cols
        let row = (index / cfg.cols) % cfg.rows
        let rect = CGRect(
            x: CGFloat(col) * cfg.cellPx.width,
            y: CGFloat(row) * cfg.cellPx.height,
            width: cfg.cellPx.width,
            height: cfg.cellPx.height
        )

        if let piece = cg.cropping(to: rect) {
            let naturalPt = CGSize(width: cfg.cellPx.width / displayScale,
                                   height: cfg.cellPx.height / displayScale)
            let pt = desiredSizePt ?? naturalPt

            let smallThreshold: CGFloat = 24
            if max(pt.width, pt.height) <= smallThreshold,
               let ui = rasterizeNearest(piece, targetPx: CGSize(width: pt.width * displayScale,
                                                                 height: pt.height * displayScale)) {
                Image(uiImage: ui)
                    .renderingMode(.original)
                    .interpolation(.none)
                    .antialiased(false)
                    .frame(width: pt.width, height: pt.height)
                    .accessibilityHidden(true)
            } else {
                Image(uiImage: UIImage(cgImage: piece, scale: displayScale, orientation: .up))
                    .renderingMode(.original)
                    .interpolation(.none)
                    .antialiased(false)
                    .resizable()
                    .aspectRatio(cfg.cellPx.width / cfg.cellPx.height, contentMode: .fit)
                    .frame(width: pt.width, height: pt.height)
                    .accessibilityHidden(true)
            }
        } else {
            errorBox("crop nil")
                .onAppear { spriteLog.error("Crop nil") }
        }
    }

    private func rasterizeNearest(_ cg: CGImage, targetPx: CGSize) -> UIImage? {
        let w = max(Int(targetPx.width.rounded()), 1)
        let h = max(Int(targetPx.height.rounded()), 1)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let out = ctx.makeImage() else { return nil }
        return UIImage(cgImage: out, scale: UIScreen.main.scale, orientation: .up)
    }

    @ViewBuilder
    private func errorBox(_ msg: String) -> some View {
        ZStack { Color.red.opacity(0.2); Text(msg).font(.caption2) }
    }
}
