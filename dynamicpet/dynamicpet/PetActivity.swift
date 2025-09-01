//
//  PetActivity.swift
//  dynamicpet
//
//  Created by Angelo on 01/09/2025.
//
import ActivityKit

enum PetActivity {
    private static var activity: Activity<PetAttributes>?

    static func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attr = PetAttributes(name: "Mochi")
        let state = PetAttributes.ContentState(frameIndex: 0, mood: "Happy")
        let content = ActivityContent(state: state, staleDate: nil)

        do {
            activity = try Activity.request(attributes: attr,
                                            content: content,
                                            pushType: nil)
            print("Live Activity started")
        } catch {
            print("Failed to start Live Activity:", error)
        }
    }

    static func tick() {
        guard let act = activity else { return }

        var s = act.content.state
        s.frameIndex += 1

        let newContent = ActivityContent(state: s, staleDate: nil)
        Task { await act.update(newContent) }
    }

    static func end() {
        guard let act = activity else { return }

        // Nieuw: end(...) vereist ook 'final content'
        let final = ActivityContent(state: act.content.state, staleDate: nil)
        Task { await act.end(final, dismissalPolicy: .immediate) }
    }
}
