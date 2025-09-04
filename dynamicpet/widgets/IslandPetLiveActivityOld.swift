//
//  IslandPetLiveActivity.swift
//  dynamicpet

import WidgetKit
import SwiftUI
import ActivityKit
import os

private let petLog = Logger(subsystem: "com.perrello.dynamicpet", category: "PetWidget")

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
private extension Array {
    subscript(safe i: Index) -> Element? { indices.contains(i) ? self[i] : nil }
}
private extension Date {
    var flooredToSecond: Date {
        let t = timeIntervalSince1970
        return Date(timeIntervalSince1970: floor(t))
    }
}

/// Kies `count` indices evenredig uit `0..<total` (stabiel, zonder dubbels).
/// Deze variant centreert binnen de bakjes (minder links-gewogen).
private func spacedIndices(total: Int, count: Int) -> [Int] {
    guard total > 0, count > 0 else { return [] }
    let step = Double(total) / Double(count)
    var out: [Int] = []
    var seen = Set<Int>()
    for k in 0..<count {
        let idx = min(Int(floor((Double(k) + 0.5) * step)), total - 1)
        if seen.insert(idx).inserted { out.append(idx) }
    }
    // Vul aan als afgeronde deling toch gaten liet
    var i = 0
    while out.count < count && i < total {
        if seen.insert(i).inserted { out.append(i) }
        i += 1
    }
    return out
}

/// Optionele column-major → row-major mapping voor een spritesheet.
private func mappedIndex(_ n: Int, cols: Int, rows: Int, columnMajor: Bool) -> Int {
    guard columnMajor else { return n }
    let col = n / rows
    let row = n % rows
    return row * cols + col
}

/// Schaal helper: duration-space (0..duration) -> Blink1Hz-space (0..2)
@inline(__always)
private func toBlinkSpace(_ t: Double, duration: Double) -> Double {
    guard duration > 0 else { return 0 }
    return (t.truncatingRemainder(dividingBy: duration)) * (2.0 / duration)
}

// MARK: - Timer-mask bouwstenen

/// 1 Hz blink label (1s aan / 1s uit), met secondes exact in het midden.
/// Gebruik je eigen blinker-font (met ligatures).
private struct Blink1Hz: View {
    // Op hele seconde uitlijnen om zweven te voorkomen
    static let ref = Date().flooredToSecond - 60
    var offset: TimeInterval = 0
    var fontName: String = "Custom-Regular"

    var body: some View {
        GeometryReader { geo in
            let s = max(geo.size.width, geo.size.height)
            Text(Blink1Hz.ref - offset, style: .timer)
                .font(.custom(fontName, size: s))
                .frame(width: s * 9, height: s)
                .multilineTextAlignment(.trailing)
                .offset(x: -s * 8) // secondes midden
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// Venster binnen een loop van `duration` seconden; overlap in echte seconden.
private struct WindowMaskScaled: View {
    var start: TimeInterval      // in 0..duration
    var length: TimeInterval     // duur (seconden)
    var epsilon: TimeInterval    // 0.02–0.06 s (seconden)
    var duration: TimeInterval

    var body: some View {
        // clamp & overlap in *echte* seconden
        let baseLen = max(0.0, length)
        let d = min(duration, max(0.0, baseLen + 2 * max(0.0, epsilon)))
        // centreer venster binnen slot + extra overlap
        let s = start + max(0, (baseLen - (baseLen - 2 * max(0.0, epsilon))) / 2.0)

        // schaal naar blink-space (0..2)
        let sBlink = toBlinkSpace(s, duration: duration)
        let dBlink = min(1.0, max(0.0, d * (2.0 / duration))) // mask-combinator verwacht 0..1

        Blink1Hz(offset: sBlink)
            .mask(Blink1Hz(offset: sBlink + (1.0 - dBlink)))
            .accessibilityHidden(true)
        
    }
}

// MARK: - Sprite-animatie met duration-geschaalde timer-masks

/// Robuuste, glitch-vrije animatie gedreven door 1 Hz timer-masks.
/// - Parameters:
///   - duration: totale duur van de loop in seconden (bijv. 2, 3.5, 6)
///   - fps: gewenste *effectieve* frames per seconde
private struct SpriteTimerAnimation: View {
    let imagePath: String
    let cfg: SpriteSheetConfig
    var size: CGFloat = 120
    var duration: Double = 18.0
    var fps: Double = 1.0
    var columnMajorSheet: Bool = true
    var allowedFrames: [Int]? = nil   // <--- nieuw

    var body: some View {
        let totalFrames = max(cfg.cols * cfg.rows, 1)

        // kies alle frames óf de subset die jij opgeeft
        let baseFrames: [Int]
        if let allowed = allowedFrames, !allowed.isEmpty {
            baseFrames = allowed.filter { $0 >= 0 && $0 < totalFrames }
        } else {
            baseFrames = Array(0..<totalFrames)
        }

        // hoeveel stappen passen er in de loopduur?
        let desiredCount = max(1, Int(round(fps * max(duration, 0.0001))))
        let framesCount = min(desiredCount, baseFrames.count)

        // verdeel indices gelijkmatig
        let frames = spacedIndices(total: baseFrames.count, count: framesCount)
            .map { baseFrames[$0] }

        // slotduur is precies 1/fps
        let slot = 1.0 / max(fps, 0.0001)
        let epsilon = min(0.06, min(0.35 * slot, 0.49 * slot))

        return ZStack {
            ForEach(Array(frames.enumerated()), id: \.offset) { (k, raw) in
                let idx = mappedIndex(raw,
                                      cols: cfg.cols,
                                      rows: cfg.rows,
                                      columnMajor: columnMajorSheet)
                SpriteSheetView(imagePath: imagePath,
                                cfg: cfg,
                                index: idx,
                                desiredSizePt: CGSize(width: size, height: size))
                    .mask(
                        WindowMaskScaled(
                            start: Double(k) * slot,
                            length: slot,
                            epsilon: epsilon,
                            duration: duration
                        )
                        .frame(width: size, height: size)
                    )
            }
        }
        .frame(width: size, height: size)
    }
}


// MARK: - Gedeelde config loader

private func currentSpritePathAndCfg()
-> (path: String, cfg: SpriteSheetConfig, fps: Double, packID: String, petName: String)
{
    let d = SharedStore.defaults

    // 1) Bepaal actieve pack-id
    var packID = d.string(forKey: "currentPackID")
    if packID == nil,
       let data = try? Data(contentsOf: SharedStore.indexURL),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        packID = obj["activePackId"] as? String
    }
    let id = packID ?? "default-pack"

    // 2) Lees manifest van de pack
    let packDir = SharedStore.packDir(id)
    let manifestURL = packDir.appendingPathComponent("manifest.json")
    let manifestData = (try? Data(contentsOf: manifestURL)) ?? Data()
    let manifest = (try? JSONDecoder().decode(PetManifest.self, from: manifestData))
    // kies variant (bijv. scale 3 of fallback)
    let variant = manifest?.variants.first(where: { $0.scale == 3 }) ?? manifest?.variants.first

    // 3) Bouw pad naar echte sprite in de pack
    let spritePath = variant.map { packDir.appendingPathComponent($0.sprite).path }
                    ?? SharedStore.containerURL.appendingPathComponent("missing.png").path

    // 4) Stel cfg + fps samen
    let cfg = SpriteSheetConfig(
        cols: variant?.cols ?? 6,
        rows: variant?.rows ?? 3,
        cellPx: .init(width: CGFloat(variant?.cellPx.w ?? 480),
                      height: CGFloat(variant?.cellPx.h ?? 480))
    )
    let fps = 1.0
    let petName = manifest?.name ?? "Pet"
    return (spritePath, cfg, fps, id, petName)
}


// MARK: - Widget

struct IslandPetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PetAttributes.self) { context in
            // Lock screen live activity (expanded inline)
            let pack = currentSpritePathAndCfg()
            VStack(spacing: 6) {
                SpriteTimerAnimation(
                    imagePath: pack.path,
                    cfg: pack.cfg,
                    size: 140,
                    duration: 4.0,
                    fps: 1.0,
                    columnMajorSheet: false
                )
                Text(context.state.mood).font(.caption2)
            }
            .padding(8)

        } dynamicIsland: { context in
            let pack = currentSpritePathAndCfg()

            return DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.center) {
                    let loopDuration: Double = 4.0
                    let targetFPS: Double  = 1.0

                    HStack(spacing: 8) {
                        SpriteTimerAnimation(
                            imagePath: pack.path,
                            cfg: pack.cfg,
                            size: 120,
                            duration: loopDuration,
                            fps: targetFPS,
                            columnMajorSheet: true, // zet true als je sheet column-major is
                            allowedFrames: [0,1,2,3]
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(context.state.mood).font(.caption)
                            Text(Date.now, style: .timer)
                                .monospacedDigit()
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

            } compactLeading: {
                let pack = currentSpritePathAndCfg()
                SpriteTimerAnimation(imagePath: pack.path, cfg: pack.cfg, size: 22, duration: 4.0, fps: 1.0, allowedFrames: [0,1,2,3])

            } compactTrailing: {
                EmptyView()

            } minimal: {
                let pack = currentSpritePathAndCfg()
                SpriteTimerAnimation(imagePath: pack.path, cfg: pack.cfg, size: 18, duration: 4.0, fps: 1.0, allowedFrames: [0,1,2,3])
            }
        }
    }
}
