/*
 * Sayvant CDS Glasses Tests
 *
 * Forked from VisionClaw (Meta Platforms sample app).
 * Removed Meta DAT SDK and WebRTC dependencies.
 */

import Foundation
import SwiftUI
import XCTest

@testable import CameraAccess

@MainActor
class CDSGlassesTests: XCTestCase {

  func testAppInitialization() async throws {
    // Basic smoke test to ensure the app structure is valid
    let app = CDSGlassesApp()
    XCTAssertNotNil(app.body)
  }
  
  func testPABackendBridgeInitialization() async throws {
    let bridge = PABackendBridge()
    XCTAssertEqual(bridge.connectionState, .notConfigured)
    XCTAssertEqual(bridge.completenessScore, 0)
    XCTAssertNil(bridge.activeRedFlag)
  }
  
  func testGeminiSessionViewModelInitialization() async throws {
    let viewModel = GeminiSessionViewModel()
    XCTAssertFalse(viewModel.isGeminiActive)
    XCTAssertEqual(viewModel.connectionState, .disconnected)
    XCTAssertFalse(viewModel.isModelSpeaking)
    XCTAssertEqual(viewModel.userTranscript, "")
    XCTAssertEqual(viewModel.aiTranscript, "")
  }
}
