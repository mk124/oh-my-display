import Foundation

struct DisplayStateReader: Sendable {
  var resolver: DisplayResolving & DisplayListing
  var resolutionService: ResolutionModeService
  var displayModeService: DisplayModeService
  var ditheringService: DitheringService
  var iccProfileService: ICCProfileService

  init() {
    self.resolver = DisplayResolver()
    self.resolutionService = ResolutionModeService()
    self.displayModeService = DisplayModeService()
    self.ditheringService = DitheringService()
    self.iccProfileService = ICCProfileService()
  }

  init(
    resolver: DisplayResolving & DisplayListing,
    resolutionService: ResolutionModeService,
    displayModeService: DisplayModeService,
    ditheringService: DitheringService,
    iccProfileService: ICCProfileService
  ) {
    self.resolver = resolver
    self.resolutionService = resolutionService
    self.displayModeService = displayModeService
    self.ditheringService = ditheringService
    self.iccProfileService = iccProfileService
  }

  func listDisplays() throws -> [DisplayTarget] {
    try resolver.listTargets()
  }

  func readDisplayState(_ selector: DisplaySelector) throws -> DisplayState {
    let resolved = try resolver.resolve(selector)
    let resolution = resolutionService.currentResolutionMode(resolved)
    let displayMode = displayModeService.currentDisplayMode(resolved)

    return DisplayState(
      target: resolved.target,
      currentResolutionModeID: resolution.map { .readable($0.id, source: "CoreGraphics") }
        ?? .unreadable(source: "CoreGraphics current mode unavailable"),
      logicalResolution: resolution.map { .readable($0.logicalResolution, source: "CoreGraphics") }
        ?? .unreadable(source: "CoreGraphics current mode unavailable"),
      backingResolution: resolution.map { .readable($0.backingResolution, source: "CoreGraphics") }
        ?? .unreadable(source: "CoreGraphics current mode unavailable"),
      scaleFactor: resolution.map { .readable($0.scaleFactor, source: "CoreGraphics") }
        ?? .unreadable(source: "CoreGraphics current mode unavailable"),
      isHiDPI: resolution.map { .readable($0.isHiDPI, source: "CoreGraphics") }
        ?? .unreadable(source: "CoreGraphics current mode unavailable"),
      resolutionRefreshHz: resolution?.refreshHz.map { .readable($0, source: "CoreGraphics") }
        ?? .unreadable(source: "CoreGraphics refresh unavailable"),
      currentDisplayModeID: displayMode.map { .readable($0.id, source: "CADisplay") }
        ?? .unreadable(source: "CADisplay current mode unavailable"),
      outputTimingResolution: displayMode.map {
        .readable($0.outputTimingResolution, source: "CADisplay")
      } ?? .unreadable(source: "CADisplay current mode unavailable"),
      outputTimingRefreshHz: displayMode?.outputTimingRefreshHz.map {
        .readable($0, source: "CADisplay")
      } ?? .unreadable(source: "CADisplay refresh unavailable"),
      bitDepth: displayMode.flatMap { privateBitDepthAxis($0.bitDepth) }
        ?? .unreadable(source: "CADisplay bitDepth unavailable"),
      encoding: displayMode.map {
        privateEnumAxis($0.encoding, unknown: .unknown, source: "CADisplay color mode")
      } ?? .unreadable(source: "CADisplay encoding unavailable"),
      range: displayMode.map {
        privateEnumAxis($0.range, unknown: .unknown, source: "CADisplay color mode")
      } ?? .unreadable(source: "CADisplay range unavailable"),
      chroma: displayMode.map {
        privateEnumAxis($0.chroma, unknown: .unknown, source: "CADisplay color mode")
      } ?? .unreadable(source: "CADisplay chroma unavailable"),
      hdrMode: displayMode.map {
        privateEnumAxis($0.hdrMode, unknown: .unknown, source: "CADisplay HDR mode")
      } ?? .unreadable(source: "CADisplay HDR unavailable"),
      isVRR: displayMode.map { .readable($0.isVRR, source: "CADisplay VRR") }
        ?? .unreadable(source: "CADisplay VRR unavailable"),
      ditheringEnabled: ditheringService.readDithering(resolved),
      iccProfileURL: iccProfileService.readICCProfile(resolved)
    )
  }

  private func privateBitDepthAxis(_ value: Int?) -> DisplayAxis<Int> {
    value.map { .readable($0, source: "CADisplay bitDepth") }
      ?? .unreadable(source: "CADisplay bitDepth unavailable")
  }

  private func privateEnumAxis<Value: Codable & Equatable & Sendable>(
    _ value: Value, unknown: Value, source: String
  ) -> DisplayAxis<Value> {
    value == unknown ? .degraded(value, source: source) : .readable(value, source: source)
  }
}
