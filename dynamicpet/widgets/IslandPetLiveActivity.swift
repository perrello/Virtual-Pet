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

    var body: some View {
        let totalFrames = max(cfg.cols * cfg.rows, 1)
        let desiredCount = max(1, Int(round(fps * max(duration, 0.0001))))
        let framesCount = min(desiredCount, totalFrames)
        let frames = spacedIndices(total: totalFrames, count: framesCount)

        // slotduur is precies 1/fps
        let slot = 1.0 / max(fps, 0.0001)
        // Adaptieve overlap (20–60 ms), nooit > ~49% van slot
        let epsilon = min(0.06, min(0.35 * slot, 0.49 * slot))

        return ZStack {
            // Alle frames in één ForEach; we maskeren per frame in zijn eigen slot.
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
                    .accessibilityHidden(true)
            }
        }
        // Maak de hele loopduur zichtbaar, in segmenten van max. 1s
        .mask(
            ZStack {
                let seconds = Int(ceil(max(duration, 0)))
                ForEach(0..<max(seconds, 1), id: \.self) { sec in
                    WindowMaskScaled(
                        start: Double(sec),
                        length: min(1.0, duration - Double(sec)),
                        epsilon: sec == 0 ? 0.0 : 0.02, // mini-overlap tussen seconden
                        duration: duration
                    )
                }
            }
            .frame(width: size, height: size)
        )
        .frame(width: size, height: size)
    }
}

// MARK: - Gedeelde config loader

private func currentSpritePathAndCfg()
-> (path: String, cfg: SpriteSheetConfig, fps: Double, packID: String, petName: String)
{
    let base = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: SharedStore.groupID
    )!
    let path = base.appendingPathComponent("current-sprite.png").path

    let d = SharedStore.defaults
    let arr = (d.array(forKey: "currentCfg") as? [Int]) ?? [6, 3, 480, 480]
    var fps = (d.object(forKey: "currentFps") as? Double) ?? 2.0
    fps = fps.clamped(to: 1.0...2.0)

    let cfg = SpriteSheetConfig(
        cols: arr[safe: 0] ?? 6,
        rows: arr[safe: 1] ?? 3,
        cellPx: .init(width: CGFloat(arr[safe: 2] ?? 480),
                      height: CGFloat(arr[safe: 3] ?? 480))
    )

    // Active pack-id + naam (best-effort)
    var packID = d.string(forKey: "currentPackID")
    if packID == nil,
       let data = try? Data(contentsOf: SharedStore.indexURL),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        packID = obj["activePackId"] as? String
    }

    var petName: String = "Pet"
    if let id = packID {
        let manifestURL = SharedStore.packDir(id).appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: manifestURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            petName = (obj["name"] as? String) ?? petName
            if let mfps = obj["fps"] as? Double {
                fps = mfps.clamped(to: 1.0...2.0)
            }
        }
    }

    return (path, cfg, fps, packID ?? "default-pack", petName)
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
                            columnMajorSheet: false // zet true als je sheet column-major is
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
                SpriteTimerAnimation(imagePath: pack.path, cfg: pack.cfg, size: 22, duration: 4.0, fps: 1.0)

            } compactTrailing: {
                EmptyView()

            } minimal: {
                let pack = currentSpritePathAndCfg()
                SpriteTimerAnimation(imagePath: pack.path, cfg: pack.cfg, size: 18, duration: 4.0, fps: 1.0)
            }
        }
    }
}
