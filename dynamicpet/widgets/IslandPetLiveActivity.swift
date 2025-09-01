//
//  IslandPetLiveActivity.swift
//  dynamicpet
//
//  Created by Angelo on 01/09/2025.
//
import WidgetKit
import SwiftUI
import ActivityKit

struct PetSpriteView: View {
    let frameIndex: Int
    var body: some View {
        Text(["😺","😸","😻","😼"][frameIndex % 4]) // placeholder
            .font(.system(size: 48))
            .frame(width: 120, height: 120)
    }
}

struct IslandPetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PetAttributes.self) { context in
            // Lock Screen / StandBy
            ZStack {
                PetSpriteView(frameIndex: context.state.frameIndex)
                VStack { Spacer(); Text(context.attributes.name).font(.caption2) }
                    .padding(6)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    PetSpriteView(frameIndex: context.state.frameIndex)
                    Text(context.state.mood).font(.caption)
                }
            } compactLeading: {
                Text("🐾")
            } compactTrailing: {
                Text("\(context.state.frameIndex % 10)")
            } minimal: {
                Text("🐾")
            }
        }
    }
}
