import CoreGraphics
import XCTest

@testable import OMDCore

final class DisplayStateReaderTests: XCTestCase {
  func testReadDisplayStateKeepsResolutionAndDisplayModeAxesSeparate() throws {
    let target = target()
    let reader = reader(
      target: target,
      resolution: resolutionMode(
        id: "res-current", logical: DisplaySize(width: 1920, height: 1080), backing: DisplaySize(width: 3840, height: 2160), scale: 2, hidpi: true),
      displayMode: displayMode(
        id: "mode-current", timing: DisplaySize(width: 3840, height: 2160), bitDepth: 10, encoding: .rgb, range: .full, chroma: .none, hdr: .hdr10, isVRR: true),
      dithering: [DitheringFramebuffer(registryID: 10, isExternal: true, isActive: true, enableDither: false)])

    let state = try reader.readDisplayState(target.selector)

    XCTAssertEqual(state.currentResolutionModeID.value?.rawValue, "res-current")
    XCTAssertEqual(state.logicalResolution.value, DisplaySize(width: 1920, height: 1080))
    XCTAssertEqual(state.backingResolution.value, DisplaySize(width: 3840, height: 2160))
    XCTAssertEqual(state.isHiDPI.value, true)
    XCTAssertEqual(state.currentDisplayModeID.value?.rawValue, "mode-current")
    XCTAssertEqual(state.outputTimingResolution.value, DisplaySize(width: 3840, height: 2160))
    XCTAssertEqual(state.bitDepth.value, 10)
    XCTAssertEqual(state.encoding.value, .rgb)
    XCTAssertEqual(state.range.value, .full)
    XCTAssertEqual(state.chroma.readability, .readable)
    XCTAssertEqual(state.chroma.value, DisplayChroma.none)
    XCTAssertEqual(state.hdrMode.value, .hdr10)
    XCTAssertEqual(state.isVRR.value, true)
    XCTAssertEqual(state.ditheringEnabled.value, false)
    XCTAssertEqual(state.iccProfileURL.readability, .unreadable)
  }

  func testUnknownDisplayModeAxesAreDegradedInsteadOfInvented() throws {
    let target = target()
    let reader = reader(
      target: target, resolution: resolutionMode(id: "res-current"),
      displayMode: displayMode(id: "mode-current", bitDepth: nil, encoding: .unknown, range: .unknown, chroma: .unknown, hdr: .unknown))

    let state = try reader.readDisplayState(target.selector)

    XCTAssertEqual(state.bitDepth.readability, .unreadable)
    XCTAssertEqual(state.encoding.readability, .degraded)
    XCTAssertEqual(state.encoding.value, .unknown)
    XCTAssertEqual(state.range.readability, .degraded)
    XCTAssertEqual(state.chroma.readability, .degraded)
    XCTAssertEqual(state.hdrMode.readability, .degraded)
  }

  func testUnavailableBackendsLeaveAxesUnreadable() throws {
    let target = target()
    let reader = reader(target: target, resolution: nil, displayMode: nil)

    let state = try reader.readDisplayState(target.selector)

    XCTAssertEqual(state.currentResolutionModeID.readability, .unreadable)
    XCTAssertEqual(state.logicalResolution.readability, .unreadable)
    XCTAssertEqual(state.currentDisplayModeID.readability, .unreadable)
    XCTAssertEqual(state.outputTimingResolution.readability, .unreadable)
    XCTAssertEqual(state.bitDepth.readability, .unreadable)
    XCTAssertEqual(state.encoding.readability, .unreadable)
    XCTAssertEqual(state.isVRR.readability, .unreadable)
  }

  private func reader(target: DisplayTarget, resolution: ResolutionMode?, displayMode: DisplayMode?, dithering: [DitheringFramebuffer] = [])
    -> DisplayStateReader
  {
    let resolver = FakeStateResolver(target: target)
    return DisplayStateReader(
      resolver: resolver, resolutionService: ResolutionModeService(backend: FakeStateResolutionBackend(current: resolution), resolver: resolver),
      displayModeService: DisplayModeService(backend: FakeStateDisplayModeBackend(current: displayMode), resolver: resolver),
      ditheringService: DitheringService(resolver: resolver, backend: FakeStateDitheringBackend(storedFramebuffers: dithering)),
      iccProfileService: ICCProfileService(resolver: resolver, backend: FakeStateICCProfileBackend()))
  }

  private func target() -> DisplayTarget {
    DisplayTarget(selector: DisplaySelector("uuid:one"), displayID: 1, label: "Display", isMain: true, isBuiltin: false)
  }

  private func resolutionMode(
    id: String, logical: DisplaySize = DisplaySize(width: 1920, height: 1080), backing: DisplaySize = DisplaySize(width: 1920, height: 1080), scale: Double = 1,
    hidpi: Bool = false
  ) -> ResolutionMode {
    ResolutionMode(id: ResolutionModeID(id), logicalResolution: logical, backingResolution: backing, scaleFactor: scale, isHiDPI: hidpi, refreshHz: 60)
  }

  private func displayMode(
    id: String, timing: DisplaySize = DisplaySize(width: 1920, height: 1080), bitDepth: Int? = 8, encoding: DisplayEncoding = .rgb, range: DisplayRange = .full,
    chroma: DisplayChroma = .none, hdr: DisplayHDRMode = .sdr, isVRR: Bool = false
  ) -> DisplayMode {
    DisplayMode(
      id: DisplayModeID(id), outputTimingResolution: timing, outputTimingRefreshHz: 60, bitDepth: bitDepth, encoding: encoding, range: range, chroma: chroma,
      hdrMode: hdr, isVRR: isVRR)
  }
}

private struct FakeStateResolver: DisplayResolving, DisplayListing {
  var target: DisplayTarget

  func listTargets() throws -> [DisplayTarget] { [target] }

  func resolve(_ selector: DisplaySelector) throws -> ResolvedDisplay {
    guard selector == target.selector else { throw DisplayControlError.displayNotFound(selector.rawValue) }
    return ResolvedDisplay(target: target, displayID: CGDirectDisplayID(target.displayID))
  }
}

private struct FakeStateResolutionBackend: ResolutionModeBackend {
  var current: ResolutionMode?

  func resolutionModes(_ displayID: CGDirectDisplayID) -> [ResolutionMode] { current.map { [$0] } ?? [] }

  func currentResolutionMode(_ displayID: CGDirectDisplayID) -> ResolutionMode? { current }

  func setResolutionMode(_ displayID: CGDirectDisplayID, modeID: ResolutionModeID) -> DisplaySetResult { .applied() }
}

private struct FakeStateDisplayModeBackend: DisplayModeBackend {
  var current: DisplayMode?

  func displayModes(_ displayID: CGDirectDisplayID) -> DisplayListResult<DisplayMode> { .readable(current.map { [$0] } ?? []) }

  func currentDisplayMode(_ displayID: CGDirectDisplayID) -> DisplayMode? { current }

  func setDisplayMode(_ displayID: CGDirectDisplayID, modeID: DisplayModeID) -> DisplaySetResult { .applied() }
}

private struct FakeStateDitheringBackend: DitheringBackend {
  var storedFramebuffers: [DitheringFramebuffer]

  func framebuffers() -> [DitheringFramebuffer] { storedFramebuffers }

  func readDithering(on registryID: UInt64) -> Bool? { storedFramebuffers.first { $0.registryID == registryID }?.enableDither }

  func setDithering(_ enabled: Bool, on registryID: UInt64) -> Bool { true }
}

private struct FakeStateICCProfileBackend: ICCProfileBackend {
  func isReadableProfile(_ url: URL) -> Bool { true }

  func isRGBProfile(_ url: URL) -> Bool { true }

  func installedProfiles() throws -> [ICCProfile] { [] }

  func installedDisplayProfiles() throws -> [ICCProfile] { [] }

  func deviceID(for displayID: CGDirectDisplayID) -> ICCDisplayDeviceID? { nil }

  func profile(for deviceID: ICCDisplayDeviceID) -> ICCProfileReadback? { nil }

  func setCustomProfile(_ profileURL: URL, for deviceID: ICCDisplayDeviceID) -> Bool { true }

  func waitBeforeReadback() {}
}
