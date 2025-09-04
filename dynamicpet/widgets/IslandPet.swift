//
//  IslandPet.swift
//  dynamicpet
//
//  Created by Angelo on 04/09/2025.
//
import WidgetKit
import SwiftUI

struct IslandPet : Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PetAttributes.self) { context in
            PetView().id(context.state.start)
        } dynamicIsland: { context in
            return DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    PetView().id(context.state.spriteRevision)
                }
            } compactLeading: {
                PetView().id(context.state.spriteRevision)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                PetView().id(context.state.spriteRevision) 
            }
            
        }
    }
}

struct PetView: View {
    let config = getConfig()
    var body: some View { 
        SpriteSheetView(imagePath: config.imagePath , cfg: config.config, index: 0)
    }
}


func getConfig() -> (imagePath: String, config: SpriteSheetConfig, index: Int ) {
    var sheet = SpriteSheetConfig(cols: 6, rows: 3, cellPx: CGSize(width: 480, height: 480))  //TODO fix ugly fallback
    let index = PackManager.list()
    guard let pack = index.getActivePack() else { //TODO error?
        return ("", sheet, 0)
    }
    
    sheet = SpriteSheetConfig(cols: pack.cols, rows: pack.rows, cellPx: CGSize(width: pack.cellW, height: pack.cellH))
    let packDirectory = SharedStore.packDir(pack.id)
    let imagePath = packDirectory.appendingPathComponent(pack.filename)

    return (imagePath.path, sheet, 0)
}
