//
//  IslandPetLiveActivity.swift
//  dynamicpet
//
//  Created by Angelo on 01/09/2025.
//
import WidgetKit
import SwiftUI
import ActivityKit
import os

private let petLog = Logger(subsystem: "com.perrello.dynamicpet", category: "PetWidget")

// Hulpje: laad pad + cfg + fps uit je App Group
private func currentSpritePathAndCfg() -> (path: String, cfg: SpriteSheetConfig, fps: Double, packID: String, petName: String) {
    let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.groupID)!
    let path = base.appendingPathComponent("current-sprite.png").path

    let d = SharedStore.defaults
    let currentConfig = (d.array(forKey: "currentCfg") as? [Int]) ?? [6, 3, 480, 480]
    var fps = (d.object(forKey: "currentFps") as? Double) ?? 2.0
    //let packID = d.string(forKey: "currentPackID") ?? "default-pack"
    //let petName = d.string(forKey: "currentPetName") ?? "Mochi"

    // defensief: klem 1..2 zoals je build-script ook doet
    fps = max(1.0, min(2.0, fps))

    let cfg = SpriteSheetConfig(
        cols: currentConfig[0], rows: currentConfig[1],
        cellPx: .init(width: CGFloat(currentConfig[2]), height: CGFloat(currentConfig[3]))
    )
    
    // 3) Active pack-id: eerst defaults, anders index.json
     var packID = d.string(forKey: "currentPackID")
     if packID == nil {
         if let data = try? Data(contentsOf: SharedStore.indexURL),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
             packID = obj["activePackId"] as? String
         }
     }
    
    // 4) Pet-naam uit manifest.json (…/Packs/<id>/manifest.json)
    var petName: String? = nil
    if let id = packID {
        let manifestURL = SharedStore.packDir(id).appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: manifestURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            petName = obj["name"] as? String
            // Als je manifest-fps wilt prefereren:
            if let mfps = obj["fps"] as? Double {
                fps = max(1.0, min(2.0, mfps))
            }
        }
    }
    
    
    return (path, cfg, fps, packID ?? "package.com", petName ?? "Pet")
}

struct IslandPetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        
        ActivityConfiguration(for: PetAttributes.self) { context in
            let pack = currentSpritePathAndCfg()
            VStack(spacing: 6) {
                SpriteSheetView(imagePath: pack.path, cfg: pack.cfg, index: context.state.frameIndex)
                    .frame(width: 140, height: 140) // expanded inline view
                Text(context.state.mood).font(.caption2)
            }
            .padding(8)

        } dynamicIsland: { context in
            let pack = currentSpritePathAndCfg()
//            let cols = pack.cfg.cols
//            let rows = pack.cfg.rows
//            let totalFrames = max(cols * rows, 1)
//            let fps: Double = 1.0
//
//            func getFrame(now: Date, start: Date) -> Int {
//                // elapsed in seconden sinds start
//                let elapsed = max(0, now.timeIntervalSince1970 - start.timeIntervalSince1970)
//                let n = Int(elapsed * fps) % totalFrames        // lineaire frame teller
//                petLog.error("FRAME n=\(n) elapsed=\(elapsed)") // tijdelijk .error voor zichtbaarheid
//                return n
//            }

            return DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        // 1 Hz cadans – 'timeline.date' verandert elke tick
                        let now = timeline.date
//                        let test = context.state.frameIndex
//                        
//                        let elapsed = max(0, now.timeIntervalSince(context.state.start))
//                        let frame = Int(floor(elapsed * fps)) % totalFrames
//                        let idx = getFrame(now: now, start: context.state.start)
//                        let _ = petLog.debug("TEST: \(frame) - \(elapsed) - \(context.state.start)")
//                        
                        HStack(alignment: .center, spacing: 8) {
                            SpriteSheetView(
                                imagePath: pack.path,
                                cfg: pack.cfg,
                                index: context.state.frameIndex,
                                desiredSizePt: CGSize(width: 120, height: 120)
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(pack.petName).font(.headline)
                                Text(context.state.mood).font(.caption)
                                Text(pack.packID).font(.caption2)
                                // zichtbare teller (handige sanity check)
                                Text(now, style: .timer)
                                    .monospacedDigit()
                                    .font(.custom("Custom-Regular",size: 18))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer() // duwt alles naar links
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentMargins(.all, 0)
                    }
                }

                // (optioneel) compact/minimal regio's
            } compactLeading: {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
//                    let now = timeline.date
//                    let elapsed = max(0, now.timeIntervalSince(context.state.start))
//                    let frame = Int(floor(elapsed * fps)) % totalFrames
                    SpriteSheetView(
                        imagePath: pack.path,
                        cfg: pack.cfg,
                        index: context.state.frameIndex,
                        desiredSizePt: CGSize(width: 22, height: 22)
                    )
                }
            } compactTrailing: {
//                TimelineView(.periodic(from: .now, by: 1)) { timeline in
//                    let now = timeline.date
//                    let elapsed = max(0, now.timeIntervalSince(context.state.start))
//                    let frame = Int(floor(elapsed * fps)) % totalFrames
//                    SpriteSheetView(
//                        imagePath: pack.path,
//                        cfg: pack.cfg,
//                        index: frame,
//                        desiredSizePt: CGSize(width: 22, height: 22)
//                    )
//                }
            } minimal: {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let now = timeline.date
                    SpriteSheetView(
                        imagePath: pack.path,
                        cfg: pack.cfg,
                        index: context.state.frameIndex,
                        desiredSizePt: CGSize(width: 18, height: 18)
                    )
                }
            }
        }
    }
}
