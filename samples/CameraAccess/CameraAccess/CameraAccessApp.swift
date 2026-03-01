/*
 * Sayvant CDS Glasses
 *
 * Real-time clinical decision support via Meta Ray-Ban glasses.
 * Forked from VisionClaw (Meta Platforms sample app).
 *
 * Audio pipeline: Ray-Ban mic -> iPhone -> Gemini Live API -> PA Backend
 *                 PA guidance -> Gemini whisper -> iPhone -> Ray-Ban speaker
 */

import SwiftUI

@main
struct CDSGlassesApp: App {
  var body: some Scene {
    WindowGroup {
      MainAppView()
    }
  }
}
