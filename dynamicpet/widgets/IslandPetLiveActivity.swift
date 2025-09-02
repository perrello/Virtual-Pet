//
//  IslandPetLiveActivity.swift
//  dynamicpet
//
//  Vereenvoudigd
//

import WidgetKit
import SwiftUI
import ActivityKit
import os

private let petLog = Logger(subsystem: "com.perrello.dynamicpet", category: "PetWidget")

// MARK: - Timer-mask bouwstenen

/// 1 Hz blink label (1s aan / 1s uit), met secondes exact in het midden.
/// Gebruik je eigen blinker-font (met ligatures).
private struct Blink1Hz: View {
    static let ref = Date() - 60
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

/// Venster: overlap van 2 blinkers, gecentreerd + kleine overlap tegen gaps.
private struct WindowMask: View {
    var start: TimeInterval      // begin binnen 0..2
    var length: TimeInterval     // duur
    var epsilon: TimeInterval    // 0.02–0.06 s

    var body: some View {
        // centreer venster binnen slot + extra overlap
        let d = min(1.0, length + 2 * epsilon)
        let s = start + max(0, (length - (length - 2 * epsilon)) / 2.0)
        Blink1Hz(offset: s)
            .mask(Blink1Hz(offset: s + (1.0 - d)))
            .accessibilityHidden(true)
    }
}

// MARK: - Helpers

/// Kies `count` indices evenredig uit `0..<total` (stabiel, zonder dubbels).
private func spacedIndices(total: Int, count: Int) -> [Int] {
    guard total > 0, count > 0 else { return [] }
    var out: [Int] = []
    var seen = Set<Int>()
    for k in 0..<count {
        let i = Int((Double(k) * Double(total)) / Double(count))
        if seen.insert(i).inserted { out.append(i) }
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

// MARK: - Sprite-animatie met timer-masks

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
        let desiredCount = max(1, Int(round(fps * duration)))
        let frames = spacedIndices(total: totalFrames, count: min(desiredCount, totalFrames))

        // 2s motor → verdeel gekozen frames gelijkmatig over 0..2
        let slot = 2.0 / Double(max(frames.count, 1))
        // Adaptieve overlap (20–60 ms), schaalt mee met tempo
        let epsilon = min(0.06, max(0.02, slot * 0.35))

        // Bovenstack (1..2s) krijgt eigen mask om de knip op t=1 te verzachten
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
                        WindowMask(start: Double(k) * slot, length: slot, epsilon: epsilon)
                            .frame(width: size, height: size)
                    )
                    .accessibilityHidden(true)
            }
        }
        // Maak alleen het 2e-seconde deel (indices in 1..2s) zichtbaar bovenop:
        // dit volgt hetzelfde principe als de oorspronkelijke "bovenstack".
        .mask(
            ZStack {
                WindowMask(start: 0.0, length: 1.0, epsilon: 0) // 0..1
                WindowMask(start: 1.0, length: 1.0, epsilon: 0.02) // 1..2 met mini-overlap
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

// Kleine helpers
private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
private extension Array {
    subscript(safe i: Index) -> Element? { indices.contains(i) ? self[i] : nil }
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
