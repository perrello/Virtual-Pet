//
//  dynamicpetApp.swift
//  dynamicpet
//
//  Created by Angelo on 01/09/2025.
//

import SwiftUI

@main
struct dynamicpetApp: App {
    var body: some Scene {
        let _ = PetActivity.start(fps: 1.0, mood: "Sad") //TODO prettier
        WindowGroup {
            ContentView()
        }
    }
}
