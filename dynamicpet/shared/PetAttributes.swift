//
//  PetAttributes.swift
//  dynamicpet
//
//  Created by Angelo on 01/09/2025.
//

import ActivityKit

struct PetAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var frameIndex: Int
        var mood: String
    }
    var name: String
}
