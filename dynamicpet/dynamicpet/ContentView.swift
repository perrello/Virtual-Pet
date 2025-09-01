//
//  ContentView.swift
//  dynamicpet
//
//  Created by Angelo on 01/09/2025.
//
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Button("Start Pet in Dynamic Island") { PetActivity.start() }
            Button("Next Frame") { PetActivity.tick() }
            Button("End") { PetActivity.end() }
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }
}

#Preview {
    ContentView()
}
