//
//  PetAttributes.swift
//  dynamicpet
//
//  Created by Angelo on 01/09/2025.
//

import ActivityKit
import Foundation

struct PetAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var frameIndex: Int
        var mood: String
        var start: Date //TODO why?
        var spriteRevision: String // unique string
    }
    var name: String
}
