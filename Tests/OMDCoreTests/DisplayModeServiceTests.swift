import CoreGraphics
import Foundation
import OMDQuartzBridge
import XCTest

@testable import OMDCore

final class DisplayModeServiceTests: XCTestCase {
  func testSetDisplayModeNoOpDoesNotAttemptMutation() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("mode-1")]), current: mode("mode-1"))
    let service = DisplayModeService(backend: backend, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("mode-1"))

    XCTAssertEqual(result.status, .noOp)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetDisplayModeReturnsBackendUnavailableBeforeMutation() throws {
    let backend = FakeDisplayModeBackend(listResult: .unreadable("CADisplay unavailable", source: "CADisplay"), current: nil)
    let service = DisplayModeService(backend: backend, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("mode-2"))

    XCTAssertEqual(result.status, .backendUnavailable)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetDisplayModeBlocksStaleIDBeforeMutation() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("mode-1")]), current: mode("mode-1"))
    let service = DisplayModeService(backend: backend, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("missing"))

    XCTAssertEqual(result.status, .blocked)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetDisplayModeBlocksDuplicateIDBeforeMutation() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("dup"), mode("dup")]), current: mode("mode-1"))
    let service = DisplayModeService(backend: backend, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("dup"))

    XCTAssertEqual(result.status, .blocked)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetDisplayModeMapsSelectorFailureToBlockedResult() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("mode-1")]), current: mode("mode-1"))
    let service = DisplayModeService(backend: backend, resolver: ThrowingDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("bad"), modeID: DisplayModeID("mode-1"))

    XCTAssertEqual(result.status, .blocked)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetDisplayModeDetectsReadbackMismatchAfterMutation() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("mode-1"), mode("mode-2")]), current: mode("mode-1"))
    backend.setResult = .applied("called")
    let service = DisplayModeService(backend: backend, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("mode-2"))

    XCTAssertEqual(result.status, .readbackMismatch)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [DisplayModeID("mode-2")])
  }

  func testSetDisplayModeReturnsAppliedWhenReadbackMatchesAfterMutation() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("mode-1"), mode("mode-2")]), current: mode("mode-1"))
    backend.updateCurrentAfterSet = true
    let service = DisplayModeService(backend: backend, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("mode-2"))

    XCTAssertEqual(result.status, .applied)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [DisplayModeID("mode-2")])
    XCTAssertEqual(backend.current?.id.rawValue, "mode-2")
  }

  func testDisplayModesGenerateDeterministicIDsAndDuplicateSuffix() {
    let modes = DisplayModeService.displayModes(from: [bridgeDictionary(), bridgeDictionary()])

    XCTAssertEqual(modes.map(\.id.rawValue), ["3840x2160-120.000-rgb-10-sdr-full-none", "3840x2160-120.000-rgb-10-sdr-full-none-2"])
    XCTAssertEqual(modes[0].range, .full)
    XCTAssertEqual(modes[0].encoding, .rgb)
    XCTAssertEqual(modes[0].chroma, .none)
  }

  func testDisplayModeIDsIncludeVRRStateBeforeDuplicateSuffix() {
    let modes = DisplayModeService.displayModes(from: [bridgeDictionary(isVRR: false), bridgeDictionary(isVRR: true), bridgeDictionary(isVRR: true)])

    XCTAssertEqual(
      modes.map(\.id.rawValue),
      ["3840x2160-120.000-rgb-10-sdr-full-none", "3840x2160-120.000-vrr-rgb-10-sdr-full-none", "3840x2160-120.000-vrr-rgb-10-sdr-full-none-2"])
  }

  func testDisplayModeParserKeepsYCbCrLimitedChromaAndHDRFacts() {
    let modes = DisplayModeService.displayModes(from: [
      bridgeDictionary(refreshHz: 59.94, bitDepth: 12, encoding: "ycbcr", range: "limited", chroma: "422", hdrMode: "hdr10")
    ])

    XCTAssertEqual(modes.count, 1)
    XCTAssertEqual(modes[0].id.rawValue, "3840x2160-59.940-ycbcr-12-hdr10-limited-422")
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
        refreshHz: 59.999998658895493, bitDepth: 12, encoding: "none", range: "limited", chroma: "none", hdrMode: "dolby-vision-low-latency",
        hdrModeRaw: "Dolby", colorModeRaw: "DolbyVisionLowLatency", modeDescription: "<CADisplayMode 3840 x 2160 fmt:DolbyVision_LowLatency range:limited>")
    ])

    XCTAssertEqual(modes.count, 1)
    XCTAssertEqual(modes[0].id.rawValue, "3840x2160-60.000-none-12-dolby-vision-low-latency-limited-none")
    XCTAssertEqual(modes[0].encoding, .none)
    XCTAssertEqual(modes[0].hdrMode, .dolbyVisionLowLatency)
    XCTAssertEqual(modes[0].hdrModeRaw, "Dolby")
    XCTAssertEqual(modes[0].colorModeRaw, "DolbyVisionLowLatency")
    XCTAssertEqual(modes[0].modeDescription, "<CADisplayMode 3840 x 2160 fmt:DolbyVision_LowLatency range:limited>")
  }

  func testDisplayModeParserKeepsNormalizedDolbyVisionValue() {
    let modes = DisplayModeService.displayModes(from: [bridgeDictionary(encoding: "none", hdrMode: "dolby-vision")])

    XCTAssertEqual(modes.count, 1)
    XCTAssertEqual(modes[0].encoding, .none)
    XCTAssertEqual(modes[0].hdrMode, .dolbyVision)
  }

  func testDisplayModeParserDoesNotTreatUnknownHDRValuesAsHDR10() {
    let modes = DisplayModeService.displayModes(from: [bridgeDictionary(hdrMode: "hdrpq16")])

    XCTAssertEqual(modes.count, 1)
    XCTAssertEqual(modes[0].hdrMode, .unknown)
  }

  func testDisplayModeParserTreatsZeroRefreshAndBitDepthAsUnknown() {
    let modes = DisplayModeService.displayModes(from: [bridgeDictionary(refreshHz: 0, bitDepth: 0)])

    XCTAssertEqual(modes.count, 1)
    XCTAssertNil(modes[0].outputTimingRefreshHz)
    XCTAssertNil(modes[0].bitDepth)
    XCTAssertEqual(modes[0].id.rawValue, "3840x2160-unknown-rgb-unknown-sdr-full-none")
  }

  func testDisplayModeParserTreatsMissingEncodingAsUnknown() {
    var dictionary = bridgeDictionary()
    dictionary.removeValue(forKey: "encoding")

    let modes = DisplayModeService.displayModes(from: [dictionary])

    XCTAssertEqual(modes.count, 1)
    XCTAssertEqual(modes[0].encoding, .unknown)
    XCTAssertEqual(modes[0].id.rawValue, "3840x2160-120.000-unknown-10-sdr-full-none")
  }

  func testBridgeFailureResultMapsStableErrorCodesBeforeMutation() {
    XCTAssertEqual(
      DisplayModeService.bridgeFailureResult(error(code: OMDQuartzBridgeErrorCode.selectorUnavailable.rawValue), attemptedMutation: false),
      .backendUnavailable("selector unavailable"))
    XCTAssertEqual(
      DisplayModeService.bridgeFailureResult(error(code: OMDQuartzBridgeErrorCode.modeIndexUnavailable.rawValue), attemptedMutation: false),
      .blocked("selector unavailable"))
    XCTAssertEqual(
      DisplayModeService.bridgeFailureResult(error(code: 999), attemptedMutation: false), .failed(attemptedMutation: false, reason: "selector unavailable"))
  }

  func testBridgeFailureResultPreservesAttemptedMutationRegardlessOfErrorCode() {
    let result = DisplayModeService.bridgeFailureResult(error(code: OMDQuartzBridgeErrorCode.selectorUnavailable.rawValue), attemptedMutation: true)

    XCTAssertEqual(result.status, .failed)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(result.reason, "selector unavailable")
  }

  // MARK: - HDR preference orchestration

  func testCrossCategorySwitchFlipsPreferenceAndSetsTarget() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("sdr-1"), mode("hdr-1", hdr: .hdr10)]), current: mode("sdr-1"))
    backend.updateCurrentAfterSet = true
    let prefs = FakeHDRPreferenceBackend(reading: false)
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("hdr-1"))

    XCTAssertEqual(result.status, .applied)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(prefs.setCalls, [true])
    XCTAssertEqual(backend.setCalls, [DisplayModeID("hdr-1")])
    XCTAssertFalse(result.reason?.contains("degraded") ?? false)
  }

  func testHDRToSDRSwitchFlipsPreferenceOffAndSetsTarget() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("sdr-1"), mode("hdr-1", hdr: .hdr10)]), current: mode("hdr-1", hdr: .hdr10))
    backend.updateCurrentAfterSet = true
    let prefs = FakeHDRPreferenceBackend(reading: true)
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("sdr-1"))

    XCTAssertEqual(result.status, .applied)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(prefs.setCalls, [false])
    XCTAssertEqual(backend.setCalls, [DisplayModeID("sdr-1")])
  }

  func testDolbyVisionTargetMapsToHDRPreference() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("sdr-1"), mode("dv-1", hdr: .dolbyVision)]), current: mode("sdr-1"))
    backend.updateCurrentAfterSet = true
    let prefs = FakeHDRPreferenceBackend(reading: false)
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("dv-1"))

    XCTAssertEqual(result.status, .applied)
    XCTAssertEqual(prefs.setCalls, [true])
  }

  func testAlignedPreferenceKeepsSameCategorySwitchSingleStep() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("sdr-1"), mode("sdr-2")]), current: mode("sdr-1"))
    backend.updateCurrentAfterSet = true
    let prefs = FakeHDRPreferenceBackend(reading: false)
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("sdr-2"))

    XCTAssertEqual(result.status, .applied)
    XCTAssertEqual(prefs.setCalls, [])
    XCTAssertEqual(backend.setCalls, [DisplayModeID("sdr-2")])
    XCTAssertFalse(result.reason?.contains("degraded") ?? false)
  }

  func testAlignedHDRPreferenceKeepsHDRToHDRSwitchSingleStep() throws {
    let backend = FakeDisplayModeBackend(
      listResult: .readable([mode("hdr-1", hdr: .hdr10), mode("hdr-2", hdr: .hdr10)]), current: mode("hdr-1", hdr: .hdr10))
    backend.updateCurrentAfterSet = true
    let prefs = FakeHDRPreferenceBackend(reading: true)
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("hdr-2"))

    XCTAssertEqual(result.status, .applied)
    XCTAssertEqual(prefs.setCalls, [])
    XCTAssertEqual(backend.setCalls, [DisplayModeID("hdr-2")])
  }

  func testSameCategorySwitchWithExternallyMisalignedPreferenceCorrectsIt() throws {
    let backend = FakeDisplayModeBackend(
      listResult: .readable([mode("hdr-1", hdr: .hdr10), mode("hdr-2", hdr: .hdr10)]), current: mode("hdr-1", hdr: .hdr10))
    backend.updateCurrentAfterSet = true
    let prefs = FakeHDRPreferenceBackend(reading: false)
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("hdr-2"))

    XCTAssertEqual(result.status, .applied)
    XCTAssertEqual(prefs.setCalls, [true])
    XCTAssertEqual(backend.setCalls, [DisplayModeID("hdr-2")])
  }

  func testNoOpWhenTargetIsCurrentAndPreferenceAligned() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("hdr-1", hdr: .hdr10)]), current: mode("hdr-1", hdr: .hdr10))
    let prefs = FakeHDRPreferenceBackend(reading: true)
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("hdr-1"))

    XCTAssertEqual(result.status, .noOp)
    XCTAssertEqual(prefs.setCalls, [])
    XCTAssertEqual(backend.setCalls, [])
  }

  func testHalfHDRRepairFlipsPreferenceAndStillSetsMatchingLink() throws {
    // The bad state this feature exists to fix: link already on the target HDR mode, switch off.
    // The flip's renegotiation moves the link, so the set must fire even though the link matched.
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("hdr-1", hdr: .hdr10)]), current: mode("hdr-1", hdr: .hdr10))
    backend.updateCurrentAfterSet = true
    let prefs = FakeHDRPreferenceBackend(reading: false)
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("hdr-1"))

    XCTAssertEqual(result.status, .applied)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(prefs.setCalls, [true])
    XCTAssertEqual(backend.setCalls, [DisplayModeID("hdr-1")])
  }

  func testSymmetricHalfSDRRepairFlipsPreferenceOff() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("sdr-1")]), current: mode("sdr-1"))
    backend.updateCurrentAfterSet = true
    let prefs = FakeHDRPreferenceBackend(reading: true)
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("sdr-1"))

    XCTAssertEqual(result.status, .applied)
    XCTAssertEqual(prefs.setCalls, [false])
    XCTAssertEqual(backend.setCalls, [DisplayModeID("sdr-1")])
  }

  func testUnknownTargetHDRModeStaysOutOfOrchestration() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("sdr-1"), mode("odd-1", hdr: .unknown)]), current: mode("sdr-1"))
    backend.updateCurrentAfterSet = true
    let prefs = FakeHDRPreferenceBackend(reading: false)
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("odd-1"))

    XCTAssertEqual(result.status, .applied)
    XCTAssertEqual(prefs.setCalls, [])
    XCTAssertFalse(result.reason?.contains("degraded") ?? false)
  }

  func testCrossCategorySwitchWithPreAlignedPreferenceSkipsFlip() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("sdr-1"), mode("hdr-1", hdr: .hdr10)]), current: mode("sdr-1"))
    backend.updateCurrentAfterSet = true
    let prefs = FakeHDRPreferenceBackend(reading: true)  // externally aligned already
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("hdr-1"))

    XCTAssertEqual(result.status, .applied)
    XCTAssertEqual(prefs.setCalls, [])
    XCTAssertEqual(backend.setCalls, [DisplayModeID("hdr-1")])
  }

  func testUnavailableBridgeDegradesToSingleStepWithNote() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("sdr-1"), mode("hdr-1", hdr: .hdr10)]), current: mode("sdr-1"))
    backend.updateCurrentAfterSet = true
    let prefs = FakeHDRPreferenceBackend(reading: false)
    prefs.available = false
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("hdr-1"))

    XCTAssertEqual(result.status, .applied)
    XCTAssertEqual(prefs.setCalls, [])
    XCTAssertTrue(result.reason?.contains("degraded") ?? false)
    XCTAssertTrue(result.reason?.contains("bridge is unavailable") ?? false)
  }

  func testPreferenceWriteFailureDegradesAndStillSets() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("sdr-1"), mode("hdr-1", hdr: .hdr10)]), current: mode("sdr-1"))
    backend.updateCurrentAfterSet = true
    let prefs = FakeHDRPreferenceBackend(reading: false)
    prefs.setSucceeds = false
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("hdr-1"))

    XCTAssertEqual(result.status, .applied)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(prefs.setCalls, [true])
    XCTAssertEqual(backend.setCalls, [DisplayModeID("hdr-1")])
    XCTAssertTrue(result.reason?.contains("write failed") ?? false)
  }

  func testUnreadablePreferenceDegradesToSingleStepWithNote() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("sdr-1"), mode("hdr-1", hdr: .hdr10)]), current: mode("sdr-1"))
    backend.updateCurrentAfterSet = true
    let prefs = FakeHDRPreferenceBackend(reading: nil)  // bridge available, read fails
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("hdr-1"))

    XCTAssertEqual(result.status, .applied)
    XCTAssertEqual(prefs.setCalls, [])
    XCTAssertTrue(result.reason?.contains("unreadable") ?? false)
  }

  func testReadbackMismatchInOrchestratedPathCarriesDegradedNote() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("sdr-1"), mode("hdr-1", hdr: .hdr10)]), current: mode("sdr-1"))
    backend.setResult = .applied("accepted")  // setter claims success but current never updates
    let prefs = FakeHDRPreferenceBackend(reading: false)
    prefs.setSucceeds = false  // the degraded note must survive into the mismatch reason
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("hdr-1"))

    XCTAssertEqual(result.status, .readbackMismatch)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertTrue(result.reason?.contains("write failed") ?? false)
  }

  func testDoubleFailureCarriesDegradedNoteIntoSetterFailureReason() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("sdr-1"), mode("hdr-1", hdr: .hdr10)]), current: mode("sdr-1"))
    backend.setResult = .blocked("CADisplay rejected")
    let prefs = FakeHDRPreferenceBackend(reading: false)
    prefs.setSucceeds = false  // prefer write fails AND micro-adjust blocks
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("hdr-1"))

    XCTAssertEqual(result.status, .blocked)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertTrue(result.reason?.contains("CADisplay rejected") ?? false)
    XCTAssertTrue(result.reason?.contains("write failed") ?? false)
  }

  func testSetterFailureAfterPreferenceFlipOverwritesAttemptedMutation() throws {
    let backend = FakeDisplayModeBackend(listResult: .readable([mode("sdr-1"), mode("hdr-1", hdr: .hdr10)]), current: mode("sdr-1"))
    backend.setResult = .blocked("CADisplay rejected")  // carries attemptedMutation: false
    let prefs = FakeHDRPreferenceBackend(reading: false)
    let service = DisplayModeService(backend: backend, hdrPreference: prefs, resolver: FakeDisplayModeResolver())

    let result = try service.setDisplayMode(DisplaySelector("uuid:one"), modeID: DisplayModeID("hdr-1"))

    XCTAssertEqual(result.status, .blocked)
    XCTAssertTrue(result.attemptedMutation, "the preference write already mutated system state; restore must fire")
  }

  private func mode(_ id: String, hdr: DisplayHDRMode = .sdr) -> DisplayMode {
    DisplayMode(
      id: DisplayModeID(id), outputTimingResolution: DisplaySize(width: 3840, height: 2160), outputTimingRefreshHz: 120, bitDepth: 10, encoding: .rgb,
      range: .full, chroma: .unknown, hdrMode: hdr)
  }

  private func bridgeDictionary(
    refreshHz: Double = 120, bitDepth: Int = 10, encoding: String = "rgb", range: String = "full", chroma: String = "none", hdrMode: String = "sdr",
    isVRR: Bool = false, hdrModeRaw: String? = nil, colorModeRaw: String? = nil, modeDescription: String? = nil
  ) -> [String: Any] {
    var dictionary: [String: Any] = [
      "width": NSNumber(value: 3840), "height": NSNumber(value: 2160), "refreshHz": NSNumber(value: refreshHz), "bitDepth": NSNumber(value: bitDepth),
      "encoding": encoding, "range": range, "chroma": chroma, "hdrMode": hdrMode, "isVirtual": NSNumber(value: false), "isVRR": NSNumber(value: isVRR),
      "isHighBandwidth": NSNumber(value: true),
    ]
    if let hdrModeRaw { dictionary["hdrModeRaw"] = hdrModeRaw }
    if let colorModeRaw { dictionary["colorModeRaw"] = colorModeRaw }
    if let modeDescription { dictionary["modeDescription"] = modeDescription }
    return dictionary
  }

  private func error(code: CFIndex) -> Unmanaged<CFError> {
    let error = CFErrorCreate(
      kCFAllocatorDefault, "OMDQuartzBridge" as CFString, code, [kCFErrorLocalizedDescriptionKey: "selector unavailable"] as CFDictionary)
    return Unmanaged.passRetained(error!)
  }
}

private final class FakeDisplayModeBackend: DisplayModeBackend, @unchecked Sendable {
  var listResult: DisplayListResult<DisplayMode>
  var current: DisplayMode?
  var setResult: DisplaySetResult = .applied("accepted")
  var updateCurrentAfterSet = false
  var setCalls: [DisplayModeID] = []

  init(listResult: DisplayListResult<DisplayMode>, current: DisplayMode?) {
    self.listResult = listResult
    self.current = current
  }

  func displayModes(_ displayID: CGDirectDisplayID) -> DisplayListResult<DisplayMode> { listResult }

  func currentDisplayMode(_ displayID: CGDirectDisplayID) -> DisplayMode? { current }

  func setDisplayMode(_ displayID: CGDirectDisplayID, modeID: DisplayModeID) -> DisplaySetResult {
    setCalls.append(modeID)
    if updateCurrentAfterSet { current = listResult.items.first { $0.id == modeID } }
    return setResult
  }
}

private final class FakeHDRPreferenceBackend: HDRPreferenceBackend, @unchecked Sendable {
  var available = true
  var reading: Bool?  // nil = the read fails (bridge error), not "no value yet"
  var setSucceeds = true
  var setCalls: [Bool] = []

  init(reading: Bool?) { self.reading = reading }

  var isAvailable: Bool { available }

  func preferHDRModes(_ displayID: CGDirectDisplayID) -> Bool? { reading }

  func setPreferHDRModes(_ displayID: CGDirectDisplayID, enabled: Bool) -> Bool {
    setCalls.append(enabled)
    return setSucceeds
  }
}

private struct FakeDisplayModeResolver: DisplayResolving {
  func resolve(_ selector: DisplaySelector) throws -> ResolvedDisplay {
    let target = DisplayTarget(selector: DisplaySelector("uuid:one"), displayID: 1, label: "Display", isMain: true, isBuiltin: false)
    return ResolvedDisplay(target: target, displayID: 1)
  }
}

private struct ThrowingDisplayModeResolver: DisplayResolving {
  func resolve(_ selector: DisplaySelector) throws -> ResolvedDisplay { throw DisplayControlError.displayNotFound(selector.rawValue) }
}
