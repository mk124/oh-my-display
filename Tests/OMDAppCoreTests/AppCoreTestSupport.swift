import Foundation
import OMDCore

@testable import OMDAppCore

final class AppCoreFixture {
  let display: DisplayTarget
  let documentURL: URL
  let fake: FakeDisplayController
  let core: OMDAppCore

  init(
    selector: DisplaySelector = DisplaySelector("uuid:one")
  ) throws {
    display = DisplayTarget(
      selector: selector,
      displayID: 1,
      label: "One",
      isMain: true,
      isBuiltin: false
    )
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    documentURL = directory.appendingPathComponent("profiles.json")
    fake = FakeDisplayController()
    fake.displays = [display]
    fake.states[display.selector] = .state(target: display)
    fake.resolutionModes[display.selector] = .readable([
      mode("res-4k-120-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 120)
    ])
    fake.displayModes[display.selector] = .readable([
      .mode(id: "mode-rgb-12", bitDepth: 12)
    ])
    core = try OMDAppCore(client: fake, documentURL: documentURL)
  }

  deinit {
    try? FileManager.default.removeItem(at: documentURL.deletingLastPathComponent())
  }
}

final class FakeDisplayController: DisplayClient, @unchecked Sendable {
  var displays: [DisplayTarget] = []
  var states: [DisplaySelector: DisplayState] = [:]
  var resolutionModes: [DisplaySelector: DisplayListResult<ResolutionMode>] = [:]
  var displayModes: [DisplaySelector: DisplayListResult<DisplayMode>] = [:]
  var displayModesError: Error?
  var resolutionSetResult = DisplaySetResult.applied()
  var displayModeSetResult = DisplaySetResult.applied()
  var ditheringSetResult = DisplaySetResult.applied()
  var iccSetResult = DisplaySetResult.applied()
  var ditheringSetResults: [DisplaySetResult] = []
  var iccSetResults: [DisplaySetResult] = []
  var iccProfiles: [ICCProfile] = []
  var appICCProfiles: [ICCProfile] = []
  var appICCProfilesError: Error?
  var setResolutionCalls: [String] = []
  var setDisplayModeCalls: [String] = []
  var setDitheringCalls: [Bool] = []
  var setICCCalls: [URL] = []

  func clearCalls() {
    setResolutionCalls.removeAll()
    setDisplayModeCalls.removeAll()
    setDitheringCalls.removeAll()
    setICCCalls.removeAll()
  }

  func listDisplays() throws -> [DisplayTarget] {
    displays
  }

  func readDisplayState(_ display: DisplaySelector) throws -> DisplayState {
    states[display]!
  }

  func listResolutionModes(_ display: DisplaySelector) throws -> DisplayListResult<ResolutionMode> {
    resolutionModes[display] ?? .readable([])
  }

  func setResolutionMode(_ display: DisplaySelector, modeID: ResolutionModeID) throws
    -> DisplaySetResult
  {
    setResolutionCalls.append(modeID.rawValue)
    if resolutionSetResult.status == .applied,
      let mode = resolutionModes[display]?.items.first(where: { $0.id == modeID }),
      var state = states[display]
    {
      state.currentResolutionModeID = .readable(mode.id)
      state.logicalResolution = .readable(mode.logicalResolution)
      state.backingResolution = .readable(mode.backingResolution)
      state.scaleFactor = .readable(mode.scaleFactor)
      state.isHiDPI = .readable(mode.isHiDPI)
      state.outputTimingResolution = .readable(mode.backingResolution)
      if let refresh = mode.refreshHz {
        state.resolutionRefreshHz = .readable(refresh)
        state.outputTimingRefreshHz = .readable(refresh)
      } else {
        state.resolutionRefreshHz = .unreadable(source: "fake")
        state.outputTimingRefreshHz = .unreadable(source: "fake")
      }
      states[display] = state
    }
    return resolutionSetResult
  }

  func listDisplayModes(_ display: DisplaySelector) throws -> DisplayListResult<DisplayMode> {
    if let displayModesError {
      throw displayModesError
    }
    return displayModes[display] ?? .readable([])
  }

  func setDisplayMode(_ display: DisplaySelector, modeID: DisplayModeID) throws -> DisplaySetResult {
    setDisplayModeCalls.append(modeID.rawValue)
    if displayModeSetResult.status == .applied,
      let mode = displayModes[display]?.items.first(where: { $0.id == modeID }),
      var state = states[display]
    {
      state.currentDisplayModeID = .readable(mode.id)
      state.outputTimingResolution = .readable(mode.outputTimingResolution)
      if let refresh = mode.outputTimingRefreshHz {
        state.outputTimingRefreshHz = .readable(refresh)
      }
      if let bitDepth = mode.bitDepth {
        state.bitDepth = .readable(bitDepth)
      }
      state.encoding = .readable(mode.encoding)
      state.range = .readable(mode.range)
      state.chroma = .readable(mode.chroma)
      state.hdrMode = .readable(mode.hdrMode)
      state.isVRR = .readable(mode.isVRR)
      states[display] = state
    }
    return displayModeSetResult
  }

  func setDithering(_ display: DisplaySelector, enabled: Bool) throws -> DisplaySetResult {
    setDitheringCalls.append(enabled)
    let result = ditheringSetResults.isEmpty ? ditheringSetResult : ditheringSetResults.removeFirst()
    if result.status == .applied || result.status == .noOp,
      var state = states[display]
    {
      state.ditheringEnabled = .readable(enabled)
      states[display] = state
    }
    return result
  }

  func listICCProfiles() throws -> [ICCProfile] {
    iccProfiles
  }

  func listDisplayAssignableICCProfiles() throws -> [ICCProfile] {
    if let appICCProfilesError {
      throw appICCProfilesError
    }
    return appICCProfiles
  }

  func setICCProfile(_ display: DisplaySelector, profileURL: URL) throws -> DisplaySetResult {
    setICCCalls.append(profileURL)
    let result = iccSetResults.isEmpty ? iccSetResult : iccSetResults.removeFirst()
    if result.status == .applied || result.status == .noOp,
      var state = states[display]
    {
      state.iccProfileURL = .readable(profileURL)
      states[display] = state
    }
    return result
  }
}

struct FakeDisplayError: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}

extension DisplayState {
  static func state(target: DisplayTarget) -> DisplayState {
    DisplayState(
      target: target,
      currentResolutionModeID: .readable(ResolutionModeID("res-4k-120-hidpi")),
      logicalResolution: .readable(DisplaySize(width: 1920, height: 1080)),
      backingResolution: .readable(DisplaySize(width: 3840, height: 2160)),
      scaleFactor: .readable(2),
      isHiDPI: .readable(true),
      resolutionRefreshHz: .readable(120),
      currentDisplayModeID: .readable(DisplayModeID("mode-rgb-12")),
      outputTimingResolution: .readable(DisplaySize(width: 3840, height: 2160)),
      outputTimingRefreshHz: .readable(120),
      bitDepth: .readable(12),
      encoding: .readable(.rgb),
      range: .readable(.full),
      chroma: .readable(.none),
      hdrMode: .readable(.hdr10),
      isVRR: .readable(false),
      ditheringEnabled: .readable(true),
      ditheringAvailability: .settable,
      iccProfileURL: .unreadable(source: "not configured")
    )
  }
}

func mode(
  _ id: String,
  logical: (Int, Int),
  backing: (Int, Int),
  hidpi: Bool,
  hz: Double?
) -> ResolutionMode {
  ResolutionMode(
    id: ResolutionModeID(id),
    logicalResolution: DisplaySize(width: logical.0, height: logical.1),
    backingResolution: DisplaySize(width: backing.0, height: backing.1),
    scaleFactor: hidpi ? 2 : 1,
    isHiDPI: hidpi,
    refreshHz: hz)
}

extension DisplayMode {
  static func mode(
    id: String,
    timing: DisplaySize = DisplaySize(width: 3840, height: 2160),
    refresh: Double = 120,
    bitDepth: Int,
    encoding: DisplayEncoding = .rgb,
    range: DisplayRange = .full,
    chroma: DisplayChroma = .none,
    hdrMode: DisplayHDRMode = .hdr10,
    isVRR: Bool = false
  ) -> DisplayMode {
    DisplayMode(
      id: DisplayModeID(id),
      outputTimingResolution: timing,
      outputTimingRefreshHz: refresh,
      bitDepth: bitDepth,
      encoding: encoding,
      range: range,
      chroma: chroma,
      hdrMode: hdrMode,
      isVRR: isVRR
    )
  }
}
