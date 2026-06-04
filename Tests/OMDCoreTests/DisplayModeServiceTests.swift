import CoreGraphics
import Foundation
import OMDQuartzBridge
import XCTest

@testable import OMDCore

final class DisplayModeServiceTests: XCTestCase {
  func testListDisplayModesReturnsBackendResult() throws {
    let backend = FakeDisplayModeBackend(
      listResult: .readable([mode("mode-1"), mode("mode-2")], source: "CADisplay"),
      current: mode("mode-1")
    )
    let service = DisplayModeService(backend: backend, resolver: FakeDisplayModeResolver())

    let result = try service.listDisplayModes(DisplaySelector("uuid:one"))

    XCTAssertEqual(result.readability, .readable)
    XCTAssertEqual(result.source, "CADisplay")
    XCTAssertEqual(result.items.map(\.id.rawValue), ["mode-1", "mode-2"])
  }

  func testSetDisplayModeNoOpDoesNotAttemptMutation() throws {
    let backend = FakeDisplayModeBackend(
      listResult: .readable([mode("mode-1")]),
      current: mode("mode-1")
    )
    let service = DisplayModeService(backend: backend, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(
      DisplaySelector("uuid:one"), modeID: DisplayModeID("mode-1"))

    XCTAssertEqual(result.status, .noOp)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetDisplayModeReturnsBackendUnavailableBeforeMutation() throws {
    let backend = FakeDisplayModeBackend(
      listResult: .unreadable("CADisplay unavailable", source: "CADisplay"),
      current: nil
    )
    let service = DisplayModeService(backend: backend, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(
      DisplaySelector("uuid:one"), modeID: DisplayModeID("mode-2"))

    XCTAssertEqual(result.status, .backendUnavailable)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetDisplayModeBlocksStaleIDBeforeMutation() throws {
    let backend = FakeDisplayModeBackend(
      listResult: .readable([mode("mode-1")]),
      current: mode("mode-1")
    )
    let service = DisplayModeService(backend: backend, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(
      DisplaySelector("uuid:one"), modeID: DisplayModeID("missing"))

    XCTAssertEqual(result.status, .blocked)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetDisplayModeBlocksDuplicateIDBeforeMutation() throws {
    let backend = FakeDisplayModeBackend(
      listResult: .readable([mode("dup"), mode("dup")]),
      current: mode("mode-1")
    )
    let service = DisplayModeService(backend: backend, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(
      DisplaySelector("uuid:one"), modeID: DisplayModeID("dup"))

    XCTAssertEqual(result.status, .blocked)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetDisplayModeMapsSelectorFailureToBlockedResult() throws {
    let backend = FakeDisplayModeBackend(
      listResult: .readable([mode("mode-1")]),
      current: mode("mode-1")
    )
    let service = DisplayModeService(backend: backend, resolver: ThrowingDisplayModeResolver())

    let result = try service.setDisplayMode(
      DisplaySelector("bad"), modeID: DisplayModeID("mode-1"))

    XCTAssertEqual(result.status, .blocked)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetDisplayModeDetectsReadbackMismatchAfterMutation() throws {
    let backend = FakeDisplayModeBackend(
      listResult: .readable([mode("mode-1"), mode("mode-2")]),
      current: mode("mode-1")
    )
    backend.setResult = .applied("called")
    let service = DisplayModeService(backend: backend, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(
      DisplaySelector("uuid:one"), modeID: DisplayModeID("mode-2"))

    XCTAssertEqual(result.status, .readbackMismatch)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [DisplayModeID("mode-2")])
  }

  func testSetDisplayModeReturnsAppliedWhenReadbackMatchesAfterMutation() throws {
    let backend = FakeDisplayModeBackend(
      listResult: .readable([mode("mode-1"), mode("mode-2")]),
      current: mode("mode-1")
    )
    backend.updateCurrentAfterSet = true
    let service = DisplayModeService(backend: backend, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(
      DisplaySelector("uuid:one"), modeID: DisplayModeID("mode-2"))

    XCTAssertEqual(result.status, .applied)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [DisplayModeID("mode-2")])
    XCTAssertEqual(backend.current?.id.rawValue, "mode-2")
  }

  func testDisplayModesGenerateDeterministicIDsAndDuplicateSuffix() {
    let modes = DisplayModeService.displayModes(from: [
      bridgeDictionary(),
      bridgeDictionary(),
    ])

    XCTAssertEqual(
      modes.map(\.id.rawValue),
      [
        "3840x2160-120.000-rgb-10-sdr-full-none",
        "3840x2160-120.000-rgb-10-sdr-full-none-2",
      ])
    XCTAssertEqual(modes[0].range, .full)
    XCTAssertEqual(modes[0].encoding, .rgb)
    XCTAssertEqual(modes[0].chroma, .none)
  }

  func testDisplayModeIDsIncludeVRRStateBeforeDuplicateSuffix() {
    let modes = DisplayModeService.displayModes(from: [
      bridgeDictionary(isVRR: false),
      bridgeDictionary(isVRR: true),
      bridgeDictionary(isVRR: true),
    ])

    XCTAssertEqual(
      modes.map(\.id.rawValue),
      [
        "3840x2160-120.000-rgb-10-sdr-full-none",
        "3840x2160-120.000-vrr-rgb-10-sdr-full-none",
        "3840x2160-120.000-vrr-rgb-10-sdr-full-none-2",
      ])
  }

  func testDisplayModeParserKeepsYCbCrLimitedChromaAndHDRFacts() {
    let modes = DisplayModeService.displayModes(from: [
      bridgeDictionary(
        refreshHz: 59.94,
        bitDepth: 12,
        encoding: "ycbcr",
        range: "limited",
        chroma: "422",
        hdrMode: "hdr10"
      )
    ])

    XCTAssertEqual(modes.count, 1)
    XCTAssertEqual(
      modes[0].id.rawValue,
      "3840x2160-59.940-ycbcr-12-hdr10-limited-422")
    XCTAssertEqual(modes[0].outputTimingRefreshHz, 59.94)
    XCTAssertEqual(modes[0].bitDepth, 12)
    XCTAssertEqual(modes[0].encoding, .ycbcr)
    XCTAssertEqual(modes[0].range, .limited)
    XCTAssertEqual(modes[0].chroma, .c422)
    XCTAssertEqual(modes[0].hdrMode, .hdr10)
  }

  func testDisplayModeParserKeepsDolbyVisionLowLatencyRawFacts() {
    let modes = DisplayModeService.displayModes(from: [
      bridgeDictionary(
        refreshHz: 59.999998658895493,
        bitDepth: 12,
        encoding: "none",
        range: "limited",
        chroma: "none",
        hdrMode: "dolby-vision-low-latency",
        hdrModeRaw: "Dolby",
        colorModeRaw: "DolbyVisionLowLatency",
        modeDescription: "<CADisplayMode 3840 x 2160 fmt:DolbyVision_LowLatency range:limited>"
      )
    ])

    XCTAssertEqual(modes.count, 1)
    XCTAssertEqual(
      modes[0].id.rawValue,
      "3840x2160-60.000-none-12-dolby-vision-low-latency-limited-none")
    XCTAssertEqual(modes[0].encoding, .none)
    XCTAssertEqual(modes[0].hdrMode, .dolbyVisionLowLatency)
    XCTAssertEqual(modes[0].hdrModeRaw, "Dolby")
    XCTAssertEqual(modes[0].colorModeRaw, "DolbyVisionLowLatency")
    XCTAssertEqual(
      modes[0].modeDescription,
      "<CADisplayMode 3840 x 2160 fmt:DolbyVision_LowLatency range:limited>")
  }

  func testDisplayModeParserKeepsNormalizedDolbyVisionValue() {
    let modes = DisplayModeService.displayModes(from: [
      bridgeDictionary(encoding: "none", hdrMode: "dolby-vision")
    ])

    XCTAssertEqual(modes.count, 1)
    XCTAssertEqual(modes[0].encoding, .none)
    XCTAssertEqual(modes[0].hdrMode, .dolbyVision)
  }

  func testDisplayModeParserDoesNotTreatUnknownHDRValuesAsHDR10() {
    let modes = DisplayModeService.displayModes(from: [
      bridgeDictionary(hdrMode: "hdrpq16")
    ])

    XCTAssertEqual(modes.count, 1)
    XCTAssertEqual(modes[0].hdrMode, .unknown)
  }

  func testDisplayModeParserTreatsZeroRefreshAndBitDepthAsUnknown() {
    let modes = DisplayModeService.displayModes(from: [
      bridgeDictionary(refreshHz: 0, bitDepth: 0)
    ])

    XCTAssertEqual(modes.count, 1)
    XCTAssertNil(modes[0].outputTimingRefreshHz)
    XCTAssertNil(modes[0].bitDepth)
    XCTAssertEqual(
      modes[0].id.rawValue, "3840x2160-unknown-rgb-unknown-sdr-full-none")
  }

  func testDisplayModeParserTreatsMissingEncodingAsUnknown() {
    var dictionary = bridgeDictionary()
    dictionary.removeValue(forKey: "encoding")

    let modes = DisplayModeService.displayModes(from: [dictionary])

    XCTAssertEqual(modes.count, 1)
    XCTAssertEqual(modes[0].encoding, .unknown)
    XCTAssertEqual(
      modes[0].id.rawValue,
      "3840x2160-120.000-unknown-10-sdr-full-none")
  }

  func testBridgeFailureResultMapsStableErrorCodesBeforeMutation() {
    XCTAssertEqual(
      DisplayModeService.bridgeFailureResult(
        error(code: OMDQuartzBridgeErrorCode.selectorUnavailable.rawValue), attemptedMutation: false
      ),
      .backendUnavailable("selector unavailable")
    )
    XCTAssertEqual(
      DisplayModeService.bridgeFailureResult(
        error(code: OMDQuartzBridgeErrorCode.modeIndexUnavailable.rawValue),
        attemptedMutation: false),
      .blocked("selector unavailable")
    )
    XCTAssertEqual(
      DisplayModeService.bridgeFailureResult(error(code: 999), attemptedMutation: false),
      .failed(attemptedMutation: false, reason: "selector unavailable")
    )
  }

  func testBridgeFailureResultPreservesAttemptedMutationRegardlessOfErrorCode() {
    let result = DisplayModeService.bridgeFailureResult(
      error(code: OMDQuartzBridgeErrorCode.selectorUnavailable.rawValue),
      attemptedMutation: true
    )

    XCTAssertEqual(result.status, .failed)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(result.reason, "selector unavailable")
  }

  private static func mode(_ id: String) -> DisplayMode {
    DisplayMode(
      id: DisplayModeID(id),
      outputTimingResolution: DisplaySize(width: 3840, height: 2160),
      outputTimingRefreshHz: 120,
      bitDepth: 10,
      encoding: .rgb,
      range: .full,
      chroma: .unknown,
      hdrMode: .sdr
    )
  }

  private func mode(_ id: String) -> DisplayMode {
    Self.mode(id)
  }

  private func bridgeDictionary(
    refreshHz: Double = 120,
    bitDepth: Int = 10,
    encoding: String = "rgb",
    range: String = "full",
    chroma: String = "none",
    hdrMode: String = "sdr",
    isVRR: Bool = false,
    hdrModeRaw: String? = nil,
    colorModeRaw: String? = nil,
    modeDescription: String? = nil
  ) -> [String: Any] {
    var dictionary: [String: Any] = [
      "width": NSNumber(value: 3840),
      "height": NSNumber(value: 2160),
      "refreshHz": NSNumber(value: refreshHz),
      "bitDepth": NSNumber(value: bitDepth),
      "encoding": encoding,
      "range": range,
      "chroma": chroma,
      "hdrMode": hdrMode,
      "isVirtual": NSNumber(value: false),
      "isVRR": NSNumber(value: isVRR),
      "isHighBandwidth": NSNumber(value: true),
    ]
    if let hdrModeRaw {
      dictionary["hdrModeRaw"] = hdrModeRaw
    }
    if let colorModeRaw {
      dictionary["colorModeRaw"] = colorModeRaw
    }
    if let modeDescription {
      dictionary["modeDescription"] = modeDescription
    }
    return dictionary
  }

  private func error(code: CFIndex) -> Unmanaged<CFError> {
    let error = CFErrorCreate(
      kCFAllocatorDefault,
      "OMDQuartzBridge" as CFString,
      code,
      [kCFErrorLocalizedDescriptionKey: "selector unavailable"] as CFDictionary
    )
    return Unmanaged.passRetained(error!)
  }
}

private final class FakeDisplayModeBackend: DisplayModeBackend, @unchecked Sendable {
  var listResult: DisplayListResult<DisplayMode>
  var current: DisplayMode?
  var setResult: DisplaySetResult = .applied("accepted")
  var updateCurrentAfterSet = false
  var setCalls: [DisplayModeID] = []

  init(
    listResult: DisplayListResult<DisplayMode>,
    current: DisplayMode?
  ) {
    self.listResult = listResult
    self.current = current
  }

  func displayModes(_ displayID: CGDirectDisplayID) -> DisplayListResult<DisplayMode> {
    listResult
  }

  func currentDisplayMode(_ displayID: CGDirectDisplayID) -> DisplayMode? {
    current
  }

  func setDisplayMode(
    _ displayID: CGDirectDisplayID,
    modeID: DisplayModeID
  ) -> DisplaySetResult {
    setCalls.append(modeID)
    if updateCurrentAfterSet {
      current = listResult.items.first { $0.id == modeID }
    }
    return setResult
  }
}

private struct FakeDisplayModeResolver: DisplayResolving {
  func resolve(_ selector: DisplaySelector) throws -> ResolvedDisplay {
    let target = DisplayTarget(
      selector: DisplaySelector("uuid:one"),
      displayID: 1,
      label: "Display",
      isMain: true,
      isBuiltin: false
    )
    return ResolvedDisplay(target: target, displayID: 1)
  }
}

private struct ThrowingDisplayModeResolver: DisplayResolving {
  func resolve(_ selector: DisplaySelector) throws -> ResolvedDisplay {
    throw DisplayControlError.displayNotFound(selector.rawValue)
  }
}
