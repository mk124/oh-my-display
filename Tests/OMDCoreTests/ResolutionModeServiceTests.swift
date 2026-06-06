import CoreGraphics
import XCTest

@testable import OMDCore

final class ResolutionModeServiceTests: XCTestCase {
  func testSetResolutionModeNoOpDoesNotAttemptMutation() throws {
    let backend = FakeResolutionBackend(modes: [mode("res-1")], current: mode("res-1"))
    let service = ResolutionModeService(backend: backend, resolver: FakeResolutionResolver())

    let result = try service.setResolutionMode(DisplaySelector("uuid:one"), modeID: ResolutionModeID("res-1"))

    XCTAssertEqual(result.status, .noOp)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetResolutionModeBlocksStaleIDBeforeMutation() throws {
    let backend = FakeResolutionBackend(modes: [mode("res-1")], current: mode("res-1"))
    let service = ResolutionModeService(backend: backend, resolver: FakeResolutionResolver())

    let result = try service.setResolutionMode(DisplaySelector("uuid:one"), modeID: ResolutionModeID("missing"))

    XCTAssertEqual(result.status, .blocked)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetResolutionModeBlocksDuplicateIDBeforeMutation() throws {
    let backend = FakeResolutionBackend(modes: [mode("dup"), mode("dup")], current: mode("res-1"))
    let service = ResolutionModeService(backend: backend, resolver: FakeResolutionResolver())

    let result = try service.setResolutionMode(DisplaySelector("uuid:one"), modeID: ResolutionModeID("dup"))

    XCTAssertEqual(result.status, .blocked)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetResolutionModeMapsSelectorFailureToBlockedResult() throws {
    let backend = FakeResolutionBackend(modes: [mode("res-1")], current: mode("res-1"))
    let service = ResolutionModeService(backend: backend, resolver: ThrowingResolutionResolver())

    let result = try service.setResolutionMode(DisplaySelector("bad"), modeID: ResolutionModeID("res-1"))

    XCTAssertEqual(result.status, .blocked)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetResolutionModePropagatesUnexpectedResolverFailure() {
    let backend = FakeResolutionBackend(modes: [mode("res-1")], current: mode("res-1"))
    let service = ResolutionModeService(backend: backend, resolver: UnexpectedResolutionResolver())

    XCTAssertThrowsError(try service.setResolutionMode(DisplaySelector("bad"), modeID: ResolutionModeID("res-1"))) { error in
      XCTAssertEqual(error as? DisplayControlError, .unexpected("CG failure"))
    }
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetResolutionModeDetectsReadbackMismatchAfterMutation() throws {
    let backend = FakeResolutionBackend(modes: [mode("res-1"), mode("res-2")], current: mode("res-1"))
    backend.setResult = .applied("called")
    let service = ResolutionModeService(backend: backend, resolver: FakeResolutionResolver())

    let result = try service.setResolutionMode(DisplaySelector("uuid:one"), modeID: ResolutionModeID("res-2"))

    XCTAssertEqual(result.status, .readbackMismatch)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [ResolutionModeID("res-2")])
  }

  func testSetResolutionModeReturnsAppliedWhenReadbackMatchesAfterMutation() throws {
    let backend = FakeResolutionBackend(modes: [mode("res-1"), mode("res-2")], current: mode("res-1"))
    backend.updateCurrentAfterSet = true
    let service = ResolutionModeService(backend: backend, resolver: FakeResolutionResolver())

    let result = try service.setResolutionMode(DisplaySelector("uuid:one"), modeID: ResolutionModeID("res-2"))

    XCTAssertEqual(result.status, .applied)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [ResolutionModeID("res-2")])
    XCTAssertEqual(backend.current?.id.rawValue, "res-2")
  }

  func testSetResolutionModeReturnsSetterFailureWithAttemptedMutation() throws {
    let backend = FakeResolutionBackend(modes: [mode("res-1"), mode("res-2")], current: mode("res-1"))
    backend.setResult = .failed(attemptedMutation: true, reason: "setter failed after mutation")
    let service = ResolutionModeService(backend: backend, resolver: FakeResolutionResolver())

    let result = try service.setResolutionMode(DisplaySelector("uuid:one"), modeID: ResolutionModeID("res-2"))

    XCTAssertEqual(result.status, .failed)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(result.reason, "setter failed after mutation")
    XCTAssertEqual(backend.setCalls, [ResolutionModeID("res-2")])
  }

  func testSessionResolutionModeSetterCompletesForSession() throws {
    let recorder = DisplayConfigurationRecorder()

    let result = recorder.apply()

    XCTAssertEqual(result.status, .applied)
    XCTAssertEqual(result.reason, "CoreGraphics accepted session display configuration")
    XCTAssertEqual(recorder.events, ["begin", "configure:1", "complete:1"])
  }

  func testSessionResolutionModeSetterCancelsOnConfigureFailure() throws {
    let recorder = DisplayConfigurationRecorder(configureResult: .failure)

    let result = recorder.apply()

    XCTAssertEqual(result.status, .failed)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(result.reason, "CGConfigureDisplayWithDisplayMode failed: \(CGError.failure.rawValue)")
    XCTAssertEqual(recorder.events, ["begin", "configure:1", "cancel"])
  }

  func testSessionResolutionModeSetterReportsCancelFailureAsAttemptedMutation() throws {
    let recorder = DisplayConfigurationRecorder(configureResult: .failure, cancelResult: .failure)

    let result = recorder.apply()

    XCTAssertEqual(result.status, .failed)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(
      result.reason, "CGConfigureDisplayWithDisplayMode failed: \(CGError.failure.rawValue); CGCancelDisplayConfiguration failed: \(CGError.failure.rawValue)")
    XCTAssertEqual(recorder.events, ["begin", "configure:1", "cancel"])
  }

  func testSessionResolutionModeSetterReportsBeginFailureBeforeMutation() throws {
    let recorder = DisplayConfigurationRecorder(beginResult: .failure)

    let result = recorder.apply()

    XCTAssertEqual(result.status, .failed)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(result.reason, "CGBeginDisplayConfiguration failed: \(CGError.failure.rawValue)")
    XCTAssertEqual(recorder.events, ["begin"])
  }

  func testSessionResolutionModeSetterReportsCompleteFailureAsAttemptedMutation() throws {
    let recorder = DisplayConfigurationRecorder(completeResult: .failure)

    let result = recorder.apply()

    XCTAssertEqual(result.status, .failed)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(result.reason, "CGCompleteDisplayConfiguration failed: \(CGError.failure.rawValue)")
    XCTAssertEqual(recorder.events, ["begin", "configure:1", "complete:1"])
  }

  private static func mode(_ id: String) -> ResolutionMode {
    ResolutionMode(
      id: ResolutionModeID(id), logicalResolution: DisplaySize(width: 1920, height: 1080), backingResolution: DisplaySize(width: 3840, height: 2160),
      scaleFactor: 2, isHiDPI: true, refreshHz: 60)
  }

  private func mode(_ id: String) -> ResolutionMode { Self.mode(id) }
}

private final class DisplayConfigurationRecorder: @unchecked Sendable {
  var events: [String] = []
  var beginResult: CGError
  var configureResult: CGError
  var completeResult: CGError
  var cancelResult: CGError
  let config: CGDisplayConfigRef = OpaquePointer(bitPattern: 1)!

  init(beginResult: CGError = .success, configureResult: CGError = .success, completeResult: CGError = .success, cancelResult: CGError = .success) {
    self.beginResult = beginResult
    self.configureResult = configureResult
    self.completeResult = completeResult
    self.cancelResult = cancelResult
  }

  func setter() -> SessionResolutionModeSetter { SessionResolutionModeSetter(begin: begin, configure: configure, complete: complete, cancel: cancel) }

  func apply() -> DisplaySetResult { setter().applyConfiguration { [self] config in configure(config, displayID: 1) } }

  private func begin() -> (error: CGError, config: CGDisplayConfigRef?) {
    events.append("begin")
    guard beginResult == .success else { return (beginResult, nil) }
    return (beginResult, config)
  }

  private func configure(_ config: CGDisplayConfigRef, displayID: CGDirectDisplayID, mode: CGDisplayMode) -> CGError { configure(config, displayID: displayID) }

  private func configure(_ config: CGDisplayConfigRef, displayID: CGDirectDisplayID) -> CGError {
    events.append("configure:\(displayID)")
    return configureResult
  }

  private func complete(_ config: CGDisplayConfigRef, option: CGConfigureOption) -> CGError {
    events.append("complete:\(option.rawValue)")
    return completeResult
  }

  private func cancel(_ config: CGDisplayConfigRef) -> CGError {
    events.append("cancel")
    return cancelResult
  }
}

private final class FakeResolutionBackend: ResolutionModeBackend, @unchecked Sendable {
  var modes: [ResolutionMode]
  var current: ResolutionMode?
  var setResult: DisplaySetResult = .applied("accepted")
  var updateCurrentAfterSet = false
  var setCalls: [ResolutionModeID] = []

  init(modes: [ResolutionMode], current: ResolutionMode?) {
    self.modes = modes
    self.current = current
  }

  func resolutionModes(_ displayID: CGDirectDisplayID) -> [ResolutionMode] { modes }

  func currentResolutionMode(_ displayID: CGDirectDisplayID) -> ResolutionMode? { current }

  func setResolutionMode(_ displayID: CGDirectDisplayID, modeID: ResolutionModeID) -> DisplaySetResult {
    setCalls.append(modeID)
    if updateCurrentAfterSet { current = modes.first { $0.id == modeID } }
    return setResult
  }
}

private struct FakeResolutionResolver: DisplayResolving {
  func resolve(_ selector: DisplaySelector) throws -> ResolvedDisplay {
    let target = DisplayTarget(selector: DisplaySelector("uuid:one"), displayID: 1, label: "Display", isMain: true, isBuiltin: false)
    return ResolvedDisplay(target: target, displayID: 1)
  }
}

private struct ThrowingResolutionResolver: DisplayResolving {
  func resolve(_ selector: DisplaySelector) throws -> ResolvedDisplay { throw DisplayControlError.displayNotFound(selector.rawValue) }
}

private struct UnexpectedResolutionResolver: DisplayResolving {
  func resolve(_ selector: DisplaySelector) throws -> ResolvedDisplay { throw DisplayControlError.unexpected("CG failure") }
}
