import CoreGraphics
import Foundation

struct ResolutionModeService: Sendable {
  var backend: ResolutionModeBackend
  var resolver: DisplayResolving

  init() {
    self.backend = LiveResolutionModeBackend()
    self.resolver = DisplayResolver()
  }

  init(backend: ResolutionModeBackend, resolver: DisplayResolving = DisplayResolver()) {
    self.backend = backend
    self.resolver = resolver
  }

  func listResolutionModes(_ selector: DisplaySelector) throws
    -> DisplayListResult<ResolutionMode>
  {
    let resolved = try resolver.resolve(selector)
    return .readable(backend.resolutionModes(resolved.displayID), source: "CoreGraphics")
  }

  func setResolutionMode(
    _ selector: DisplaySelector, modeID: ResolutionModeID
  ) throws -> DisplaySetResult {
    let resolved: ResolvedDisplay
    do {
      resolved = try resolver.resolve(selector)
    } catch let error as DisplayControlError {
      guard error.isUserResolvableSelectorError else { throw error }
      return .blocked(error.description)
    }

    let modes = backend.resolutionModes(resolved.displayID)
    let matches = modes.filter { $0.id == modeID }
    guard matches.count == 1 else {
      return .blocked(
        matches.isEmpty
          ? "Resolution mode id is not available for this display"
          : "Resolution mode id matched multiple current modes")
    }

    if backend.currentResolutionMode(resolved.displayID)?.id == modeID {
      return .noOp("Requested resolution mode is already current")
    }

    let setterResult = backend.setResolutionMode(resolved.displayID, modeID: modeID)
    guard setterResult.status == .applied else {
      return setterResult
    }

    guard backend.currentResolutionMode(resolved.displayID)?.id == modeID else {
      return .readbackMismatch("Resolution mode readback did not match requested mode")
    }
    return .applied("Resolution mode applied")
  }

  func currentResolutionMode(_ resolved: ResolvedDisplay) -> ResolutionMode? {
    backend.currentResolutionMode(resolved.displayID)
  }
}

protocol ResolutionModeBackend: Sendable {
  func resolutionModes(_ displayID: CGDirectDisplayID) -> [ResolutionMode]
  func currentResolutionMode(_ displayID: CGDirectDisplayID) -> ResolutionMode?
  func setResolutionMode(_ displayID: CGDirectDisplayID, modeID: ResolutionModeID)
    -> DisplaySetResult
}

struct LiveResolutionModeBackend: ResolutionModeBackend {
  var modeSetter: SessionResolutionModeSetter

  init(modeSetter: SessionResolutionModeSetter = SessionResolutionModeSetter()) {
    self.modeSetter = modeSetter
  }

  func resolutionModes(_ displayID: CGDirectDisplayID) -> [ResolutionMode] {
    let modes = Self.copyAllModes(displayID)
    return Self.publicModes(from: modes)
  }

  func currentResolutionMode(_ displayID: CGDirectDisplayID) -> ResolutionMode? {
    guard let current = CGDisplayCopyDisplayMode(displayID) else {
      return nil
    }
    let modes = Self.copyAllModes(displayID)
    let publicModes = Self.publicModes(from: modes)
    if let index = modes.firstIndex(where: { CFEqual($0, current) }),
      index < publicModes.count
    {
      return publicModes[index]
    }
    return Self.publicModes(from: [current]).first
  }

  func setResolutionMode(_ displayID: CGDirectDisplayID, modeID: ResolutionModeID)
    -> DisplaySetResult
  {
    let modes = Self.copyAllModes(displayID)
    let publicModes = Self.publicModes(from: modes)
    let indices = publicModes.enumerated().filter { $0.element.id == modeID }.map(\.offset)
    guard indices.count == 1, let index = indices.first, index < modes.count else {
      return .blocked(
        indices.isEmpty
          ? "Resolution mode id is not available for this display"
          : "Resolution mode id matched multiple CoreGraphics modes")
    }

    return modeSetter.setResolutionMode(displayID, mode: modes[index])
  }

  private static func copyAllModes(_ displayID: CGDirectDisplayID) -> [CGDisplayMode] {
    let options: [CFString: Any] = [
      kCGDisplayShowDuplicateLowResolutionModes: true
    ]
    return CGDisplayCopyAllDisplayModes(displayID, options as CFDictionary) as? [CGDisplayMode]
      ?? []
  }

  private static func publicModes(from modes: [CGDisplayMode]) -> [ResolutionMode] {
    var seen: [String: Int] = [:]
    return modes.map { mode in
      let logical = DisplaySize(width: mode.width, height: mode.height)
      let backing = DisplaySize(width: mode.pixelWidth, height: mode.pixelHeight)
      let refresh = mode.refreshRate > 0 ? mode.refreshRate : nil
      let scale = scaleFactor(logical: logical, backing: backing)
      let baseID = [
        "\(logical.width)x\(logical.height)",
        "\(backing.width)x\(backing.height)",
        String(Int((refresh ?? 0) * 1000)),
        scale > 1 ? "hidpi" : "lodpi",
      ].joined(separator: "-")
      let duplicate = seen[baseID] ?? 0
      seen[baseID] = duplicate + 1
      let id = duplicate == 0 ? baseID : "\(baseID)-\(duplicate + 1)"
      return ResolutionMode(
        id: ResolutionModeID(id),
        logicalResolution: logical,
        backingResolution: backing,
        scaleFactor: scale,
        isHiDPI: scale > 1.01,
        refreshHz: refresh
      )
    }
  }

  private static func scaleFactor(logical: DisplaySize, backing: DisplaySize) -> Double {
    guard logical.width > 0, logical.height > 0 else {
      return 1
    }
    let widthScale = Double(backing.width) / Double(logical.width)
    let heightScale = Double(backing.height) / Double(logical.height)
    return (widthScale + heightScale) / 2
  }
}

struct SessionResolutionModeSetter: Sendable {
  typealias Begin = @Sendable () -> (error: CGError, config: CGDisplayConfigRef?)
  typealias Configure = @Sendable (CGDisplayConfigRef, CGDirectDisplayID, CGDisplayMode) -> CGError
  typealias Complete = @Sendable (CGDisplayConfigRef, CGConfigureOption) -> CGError
  typealias Cancel = @Sendable (CGDisplayConfigRef) -> CGError

  var begin: Begin
  var configure: Configure
  var complete: Complete
  var cancel: Cancel

  init(
    begin: @escaping Begin = {
      var config: CGDisplayConfigRef?
      let error = CGBeginDisplayConfiguration(&config)
      return (error, config)
    },
    configure: @escaping Configure = { config, displayID, mode in
      CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
    },
    complete: @escaping Complete = { config, option in
      CGCompleteDisplayConfiguration(config, option)
    },
    cancel: @escaping Cancel = { config in
      CGCancelDisplayConfiguration(config)
    }
  ) {
    self.begin = begin
    self.configure = configure
    self.complete = complete
    self.cancel = cancel
  }

  func setResolutionMode(_ displayID: CGDirectDisplayID, mode: CGDisplayMode) -> DisplaySetResult {
    applyConfiguration { config in
      configure(config, displayID, mode)
    }
  }

  func applyConfiguration(_ configureDisplay: (CGDisplayConfigRef) -> CGError)
    -> DisplaySetResult
  {
    let (beginError, config) = begin()
    guard beginError == .success, let config else {
      return .failed(
        attemptedMutation: false,
        reason: "CGBeginDisplayConfiguration failed: \(beginError.rawValue)")
    }

    let configureError = configureDisplay(config)
    guard configureError == .success else {
      let cancelError = cancel(config)
      if cancelError != .success {
        return .failed(
          attemptedMutation: true,
          reason:
            "CGConfigureDisplayWithDisplayMode failed: \(configureError.rawValue); CGCancelDisplayConfiguration failed: \(cancelError.rawValue)")
      }

      return .failed(
        attemptedMutation: false,
        reason: "CGConfigureDisplayWithDisplayMode failed: \(configureError.rawValue)")
    }

    let completeError = complete(config, .forSession)
    guard completeError == .success else {
      return .failed(
        attemptedMutation: true,
        reason: "CGCompleteDisplayConfiguration failed: \(completeError.rawValue)")
    }

    return .applied("CoreGraphics accepted session display configuration")
  }
}
