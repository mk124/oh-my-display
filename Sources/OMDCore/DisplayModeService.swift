import CoreGraphics
import Foundation
import OMDQuartzBridge

struct DisplayModeService: Sendable {
  var backend: DisplayModeBackend
  var resolver: DisplayResolving

  init() {
    self.backend = LiveDisplayModeBackend()
    self.resolver = DisplayResolver()
  }

  init(backend: DisplayModeBackend, resolver: DisplayResolving = DisplayResolver()) {
    self.backend = backend
    self.resolver = resolver
  }

  func listDisplayModes(_ selector: DisplaySelector) throws
    -> DisplayListResult<DisplayMode>
  {
    let resolved = try resolver.resolve(selector)
    return backend.displayModes(resolved.displayID)
  }

  func setDisplayMode(
    _ selector: DisplaySelector, modeID: DisplayModeID
  ) throws -> DisplaySetResult {
    let resolved: ResolvedDisplay
    do {
      resolved = try resolver.resolve(selector)
    } catch let error as DisplayControlError {
      guard error.isUserResolvableSelectorError else { throw error }
      return .blocked(error.description)
    }

    let list = backend.displayModes(resolved.displayID)
    guard list.readability != .unreadable else {
      return .backendUnavailable(list.reason ?? "Display mode backend is unavailable")
    }

    let matches = list.items.filter { $0.id == modeID }
    guard matches.count == 1 else {
      return .blocked(
        matches.isEmpty
          ? "Display mode id is not available for this display"
          : "Display mode id matched multiple current modes")
    }

    if backend.currentDisplayMode(resolved.displayID)?.id == modeID {
      return .noOp("Requested display mode is already current")
    }

    let setterResult = backend.setDisplayMode(resolved.displayID, modeID: modeID)
    guard setterResult.status == .applied else {
      return setterResult
    }

    guard backend.currentDisplayMode(resolved.displayID)?.id == modeID else {
      return .readbackMismatch("Display mode readback did not match requested mode")
    }
    return .applied("Display mode applied")
  }

  func currentDisplayMode(_ resolved: ResolvedDisplay) -> DisplayMode? {
    backend.currentDisplayMode(resolved.displayID)
  }

  static func displayModes(from dictionaries: [[String: Any]]) -> [DisplayMode] {
    let base = dictionaries.compactMap(Self.displayModeWithoutGeneratedID(from:))
    var seen: [String: Int] = [:]
    return base.map { mode in
      let baseID = publicDisplayModeID(for: mode)
      let duplicate = seen[baseID] ?? 0
      seen[baseID] = duplicate + 1
      let id = duplicate == 0 ? baseID : "\(baseID)-\(duplicate + 1)"
      var next = mode
      next.id = DisplayModeID(id)
      return next
    }
  }

  static func displayMode(from dictionary: [String: Any]) -> DisplayMode? {
    displayModeWithoutGeneratedID(from: dictionary).map { mode in
      var next = mode
      next.id = DisplayModeID(publicDisplayModeID(for: mode))
      return next
    }
  }

  static func publicDisplayModeID(for mode: DisplayMode) -> String {
    let refresh = mode.outputTimingRefreshHz.map { String(format: "%.3f", $0) } ?? "unknown"
    let bpc = mode.bitDepth.map(String.init) ?? "unknown"
    var parts = [
      "\(mode.outputTimingResolution.width)x\(mode.outputTimingResolution.height)",
      refresh,
    ]
    if mode.isVRR {
      parts.append("vrr")
    }
    parts.append(contentsOf: [
      mode.encoding.rawValue,
      bpc,
      mode.hdrMode.rawValue,
      mode.range.rawValue,
      mode.chroma.rawValue,
    ])
    return parts.joined(separator: "-")
  }

  private static func displayModeWithoutGeneratedID(from dictionary: [String: Any])
    -> DisplayMode?
  {
    guard
      let width = (dictionary["width"] as? NSNumber)?.intValue,
      let height = (dictionary["height"] as? NSNumber)?.intValue
    else {
      return nil
    }

    let refreshHz = (dictionary["refreshHz"] as? NSNumber)?.doubleValue
    let bitDepthValue = (dictionary["bitDepth"] as? NSNumber)?.intValue
    let bitDepth = bitDepthValue == 0 ? nil : bitDepthValue
    let encoding = DisplayEncoding(rawValue: dictionary["encoding"] as? String ?? "") ?? .unknown
    let range = DisplayRange(rawValue: dictionary["range"] as? String ?? "") ?? .unknown
    let chroma = DisplayChroma(rawValue: dictionary["chroma"] as? String ?? "") ?? .unknown
    let hdrRaw = dictionary["hdrMode"] as? String
    let colorModeRaw = dictionary["colorModeRaw"] as? String
    let hdrMode = DisplayHDRMode(rawValue: hdrRaw ?? "") ?? .unknown

    return DisplayMode(
      id: DisplayModeID(""),
      outputTimingResolution: DisplaySize(width: width, height: height),
      outputTimingRefreshHz: refreshHz == 0 ? nil : refreshHz,
      bitDepth: bitDepth,
      encoding: encoding,
      range: range,
      chroma: chroma,
      hdrMode: hdrMode,
      hdrModeRaw: dictionary["hdrModeRaw"] as? String,
      colorModeRaw: colorModeRaw,
      modeDescription: dictionary["modeDescription"] as? String,
      isVirtual: (dictionary["isVirtual"] as? NSNumber)?.boolValue ?? false,
      isVRR: (dictionary["isVRR"] as? NSNumber)?.boolValue ?? false,
      isHighBandwidth: (dictionary["isHighBandwidth"] as? NSNumber)?.boolValue ?? false
    )
  }

  static func bridgeFailureResult(_ cfError: Unmanaged<CFError>?, attemptedMutation: Bool)
    -> DisplaySetResult
  {
    let error = cfError?.takeRetainedValue()
    let message = error.map { CFErrorCopyDescription($0) as String? } ?? nil
    let reason = message ?? "CADisplay bridge failed"
    if attemptedMutation {
      return .failed(attemptedMutation: true, reason: reason)
    }

    let code = error.map { CFErrorGetCode($0) }
    switch code {
    case OMDQuartzBridgeErrorCode.displayNotFound.rawValue,
      OMDQuartzBridgeErrorCode.selectorUnavailable.rawValue,
      OMDQuartzBridgeErrorCode.currentModeUnavailable.rawValue:
      return .backendUnavailable(reason)
    case OMDQuartzBridgeErrorCode.modeIndexUnavailable.rawValue:
      return .blocked(reason)
    default:
      return .failed(attemptedMutation: false, reason: reason)
    }
  }
}

protocol DisplayModeBackend: Sendable {
  func displayModes(_ displayID: CGDirectDisplayID) -> DisplayListResult<DisplayMode>
  func currentDisplayMode(_ displayID: CGDirectDisplayID) -> DisplayMode?
  func setDisplayMode(_ displayID: CGDirectDisplayID, modeID: DisplayModeID)
    -> DisplaySetResult
}

struct LiveDisplayModeBackend: DisplayModeBackend {
  func displayModes(_ displayID: CGDirectDisplayID) -> DisplayListResult<DisplayMode> {
    guard OMDQuartzBridgeIsAvailable() else {
      return .unreadable("CADisplay bridge is unavailable", source: "CADisplay")
    }

    var cfError: Unmanaged<CFError>?
    guard
      let array = OMDQuartzCopyDisplayModeDictionaries(displayID, &cfError)?.takeRetainedValue()
        as? [[String: Any]]
    else {
      let result = DisplayModeService.bridgeFailureResult(
        cfError, attemptedMutation: false)
      return .unreadable(result.reason ?? "CADisplay mode list is unavailable", source: "CADisplay")
    }
    return .readable(DisplayModeService.displayModes(from: array), source: "CADisplay")
  }

  func currentDisplayMode(_ displayID: CGDirectDisplayID) -> DisplayMode? {
    guard OMDQuartzBridgeIsAvailable() else {
      return nil
    }
    var cfError: Unmanaged<CFError>?
    guard
      let dictionary = OMDQuartzCopyCurrentDisplayModeDictionary(displayID, &cfError)?
        .takeRetainedValue() as? [String: Any]
    else {
      return nil
    }

    if let index = (dictionary["modeIndex"] as? NSNumber)?.intValue {
      let list = displayModes(displayID).items
      if index >= 0, index < list.count {
        return list[index]
      }
    }
    return DisplayModeService.displayMode(from: dictionary)
  }

  func setDisplayMode(_ displayID: CGDirectDisplayID, modeID: DisplayModeID)
    -> DisplaySetResult
  {
    let modes = displayModes(displayID).items
    let indices = modes.enumerated().filter { $0.element.id == modeID }.map(\.offset)
    guard indices.count == 1, let index = indices.first else {
      return .blocked(
        indices.isEmpty
          ? "Display mode id is not available for this display"
          : "Display mode id matched multiple CADisplay modes")
    }

    var cfError: Unmanaged<CFError>?
    var attemptedMutation = false
    let ok = OMDQuartzSetCurrentDisplayModeAtIndex(
      displayID, CFIndex(index), &attemptedMutation, &cfError)
    if !ok {
      return DisplayModeService.bridgeFailureResult(
        cfError, attemptedMutation: attemptedMutation)
    }
    return .applied("CADisplay accepted display mode")
  }
}
