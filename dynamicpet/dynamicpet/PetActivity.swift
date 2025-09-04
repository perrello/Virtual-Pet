//
//  PetActivity.swift
//  dynamicpet
//
//  Created by Angelo on 01/09/2025.
//
import ActivityKit
import Foundation

enum PetActivity {
    private static var activity: Activity<PetAttributes>?
//    private static var timer: Foundation.Timer?

    static func start(fps: Double = 1.0, mood: String = "Happy") {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attr = PetAttributes(name: "Mochi")
        let state = PetAttributes.ContentState(frameIndex: 0, mood: mood, start: Date.now, spriteRevision: UUID().uuidString)
        let content = ActivityContent(state: state, staleDate: nil)

        do {
            activity = try Activity.request(attributes: attr, content: content, pushType: nil)
//            timer?.invalidate()
//            guard fps > 0 else { return }
//            let t = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { _ in
//                tick()
//            }
//            RunLoop.main.add(t, forMode: .common)
//            timer = t
        } catch {
            print("Failed to start Live Activity:", error)
        }
    }
    
    static func refresh() {
        guard let activity else { return }
        let newState = PetAttributes.ContentState (
            frameIndex: 0, mood: "Happy", start: Date(), spriteRevision: UUID().uuidString
        )
        let content = ActivityContent(state: newState, staleDate: nil)
        Task { await activity.update(content) }
//        PetActivity.end()
//        PetActivity.start()

    }

//    static func tick() {
//        guard let act = activity else { return }
//        var state = act.content.state
//        state.frameIndex = (state.frameIndex + 1) % 18_000
//        let newContent = ActivityContent(state: state, staleDate: nil)
//        Task { await act.update(newContent) }
//    }

    static func end() {
//        timer?.invalidate(); timer = nil
        guard let act = activity else { return }
        let final = ActivityContent(state: act.content.state, staleDate: nil)
        Task { await act.end(final, dismissalPolicy: .immediate) }
    }
}
