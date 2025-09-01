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

// Hulpje: laad pad + cfg + fps uit je App Group
private func currentSpritePathAndCfg() -> (path: String, cfg: SpriteSheetConfig, fps: Double) {
    let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.groupID)!
    let path = base.appendingPathComponent("current-sprite.png").path

    let d = SharedStore.defaults
    let arr = (d.array(forKey: "currentCfg") as? [Int]) ?? [6, 3, 480, 480]
    var fps = (d.object(forKey: "currentFps") as? Double) ?? 2.0
    // defensief: klem 1..2 zoals je build-script ook doet
    fps = max(1.0, min(2.0, fps))

    let cfg = SpriteSheetConfig(
        cols: arr[0], rows: arr[1],
        cellPx: .init(width: CGFloat(arr[2]), height: CGFloat(arr[3]))
    )
    return (path, cfg, fps)
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

            return DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 6) {
                        SpriteSheetView(imagePath: pack.path, cfg: pack.cfg, index: context.state.frameIndex)
                            .frame(width: 140, height: 140)
                        Text(context.state.mood).font(.caption)
                    }
                    .contentMargins(.all, 0)
                }
            } compactLeading: {
                // ~22×22 pt; contentMargins(0) om alle padding weg te nemen
                SpriteSheetView(imagePath: pack.path, cfg: pack.cfg, index: context.state.frameIndex)
                    .frame(width: 22, height: 22)
                    .contentMargins(.all, 0)
            } compactTrailing: {
                Text("\(context.state.frameIndex % 10)")
                    .font(.caption2)
            } minimal: {
                // ~16×16 pt; de SpriteSheetView rastert zelf naar exact 16*scale pixels
                SpriteSheetView(imagePath: pack.path, cfg: pack.cfg, index: context.state.frameIndex)
                    .frame(width: 16, height: 16)
                    .contentMargins(.all, 0)
            }
        }
    }
}
