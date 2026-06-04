import XCTest

@testable import OMDCore

final class DisplayTypesTests: XCTestCase {
  func testDisplaySetResultCarriesAttemptedMutation() {
    XCTAssertFalse(DisplaySetResult.noOp("same").attemptedMutation)
    XCTAssertFalse(DisplaySetResult.blocked("no write").attemptedMutation)
    XCTAssertFalse(DisplaySetResult.backendUnavailable("missing").attemptedMutation)
    XCTAssertTrue(DisplaySetResult.applied("done").attemptedMutation)
    XCTAssertTrue(DisplaySetResult.readbackMismatch("changed").attemptedMutation)
    XCTAssertFalse(
      DisplaySetResult.failed(attemptedMutation: false, reason: "preflight").attemptedMutation)
    XCTAssertTrue(
      DisplaySetResult.failed(attemptedMutation: true, reason: "boom").attemptedMutation)
  }

  func testDisplayStateCodableRoundTrip() throws {
    let state = DisplayState(
      target: target(),
      currentResolutionModeID: .readable(ResolutionModeID("res-1")),
      logicalResolution: .readable(DisplaySize(width: 1920, height: 1080)),
      backingResolution: .readable(DisplaySize(width: 3840, height: 2160)),
      scaleFactor: .readable(2),
      isHiDPI: .readable(true),
      resolutionRefreshHz: .readable(60),
      currentDisplayModeID: .readable(DisplayModeID("mode-1")),
      outputTimingResolution: .readable(DisplaySize(width: 3840, height: 2160)),
      outputTimingRefreshHz: .readable(60),
      bitDepth: .readable(10),
      encoding: .readable(.rgb),
      range: .unreadable(source: "private axis unavailable"),
      chroma: .unreadable(source: "private axis unavailable"),
      hdrMode: .readable(.sdr),
      ditheringEnabled: .unreadable(source: "dither unavailable"),
      iccProfileURL: .unreadable(source: "icc unavailable")
    )

    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(DisplayState.self, from: data)

    XCTAssertEqual(decoded, state)
  }

  func testDisplayListResultCodableRoundTrip() throws {
    let result = DisplayListResult.readable(
      [
        ResolutionMode(
          id: ResolutionModeID("1920x1080-3840x2160-60000-hidpi"),
          logicalResolution: DisplaySize(width: 1920, height: 1080),
          backingResolution: DisplaySize(width: 3840, height: 2160),
          scaleFactor: 2,
          isHiDPI: true,
          refreshHz: 60
        )
      ],
      source: "CoreGraphics")

    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(
      DisplayListResult<ResolutionMode>.self, from: data)

    XCTAssertEqual(decoded, result)
  }

  private func target() -> DisplayTarget {
    DisplayTarget(
      selector: DisplaySelector("uuid:test"),
      displayID: 1,
      label: "Display",
      isMain: true,
      isBuiltin: false
    )
  }
}
