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

private func currentSpritePathAndCfg() -> (path: String, cfg: SpriteSheetConfig, fps: Double) {
    let base = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.groupID)!
    let path = base.appendingPathComponent("current-sprite.png").path

    let d = SharedStore.defaults
    let arr = (d.array(forKey: "currentCfg") as? [Int]) ?? [6,3,480,480]
    let fps = (d.object(forKey: "currentFps") as? Double) ?? 2.0

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
                    .frame(width: 140, height: 140)
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
                }
            } compactLeading: {
                let pack = currentSpritePathAndCfg()
                SpriteSheetView(imagePath: pack.path, cfg: pack.cfg, index: context.state.frameIndex)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } compactTrailing: {
                Text("\(context.state.frameIndex % 10)").font(.caption2)
            } minimal: {
                // KAN ook mini-preview, maar 16pt is krap; jouw keuze:
                SpriteSheetView(imagePath: pack.path, cfg: pack.cfg, index: context.state.frameIndex)
                    .frame(width: 16, height: 16)
            }
        }
    }
}

