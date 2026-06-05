import Foundation
import OMDCore

extension OMDAppCore {
  func captureIntent(from state: DisplayState) -> DisplayProfileIntent {
    DisplayProfileIntent(
      resolution: captureResolutionIntent(from: state),
      displayMode: captureDisplayModeIntent(from: state),
      ditheringEnabled: readableValue(state.ditheringEnabled),
      iccProfileURL: readableValue(state.iccProfileURL)
    )
  }

  func captureResolutionIntent(from state: DisplayState) -> ResolutionIntent? {
    guard let logical = readableValue(state.logicalResolution),
      let backing = readableValue(state.backingResolution),
      let scale = readableValue(state.scaleFactor),
      let isHiDPI = readableValue(state.isHiDPI)
    else {
      return nil
    }

    return ResolutionIntent(
      logicalResolution: logical,
      backingResolution: backing,
      scaleFactor: scale,
      isHiDPI: isHiDPI,
      refreshHz: readableValue(state.resolutionRefreshHz)
    )
  }

  func captureDisplayModeIntent(from state: DisplayState) -> DisplayModeIntent? {
    guard let timing = readableValue(state.outputTimingResolution) else {
      return nil
    }

    return DisplayModeIntent(
      outputTimingResolution: timing,
      outputTimingRefreshHz: readableValue(state.outputTimingRefreshHz),
      bitDepth: readableValue(state.bitDepth),
      encoding: readableValue(state.encoding),
      range: readableValue(state.range),
      chroma: readableValue(state.chroma),
      hdrMode: readableValue(state.hdrMode),
      isVRR: readableValue(state.isVRR)
    )
  }

  func apply(_ intent: DisplayProfileIntent, to display: DisplaySelector) throws
    -> ProfileApplyResult
  {
    var operations: [ProfileOperationResult] = []

    if let resolution = intent.resolution {
      let resolutionResult = try resolveResolutionMode(resolution, for: display).flatMap {
        modeID in
        try client.setResolutionMode(display, modeID: modeID)
      }
      operations.append(ProfileOperationResult(operation: .resolution, result: resolutionResult))
      guard resolutionResult.isSuccessful else {
        return ProfileApplyResult(operations: operations)
      }
    }

    if let displayMode = intent.displayMode {
      let displayModeResult = try resolveDisplayMode(displayMode, for: display).flatMap {
        modeID in
        try client.setDisplayMode(display, modeID: modeID)
      }
      operations.append(ProfileOperationResult(operation: .displayMode, result: displayModeResult))
      guard displayModeResult.isSuccessful else {
        return ProfileApplyResult(operations: operations)
      }
    }

    if let dithering = intent.ditheringEnabled {
      let result = try client.setDithering(display, enabled: dithering)
      operations.append(ProfileOperationResult(operation: .dithering, result: result))
      guard result.isSuccessful else {
        return ProfileApplyResult(operations: operations)
      }
    }

    if let iccProfileURL = intent.iccProfileURL {
      let result = try client.setICCProfile(display, profileURL: iccProfileURL)
      operations.append(ProfileOperationResult(operation: .icc, result: result))
    }

    if operations.isEmpty {
      operations.append(ProfileOperationResult(operation: .profile, result: .noOp("emptyProfile")))
    }

    return ProfileApplyResult(operations: operations)
  }

  func resolveResolutionMode(_ intent: ResolutionIntent, for display: DisplaySelector) throws
    -> Resolved<ResolutionModeID>
  {
    let result = try client.listResolutionModes(display)
    guard result.readability != .unreadable else {
      return .blocked(result.reason ?? "resolutionModesUnavailable")
    }
    let matches = result.items.filter { mode in
      mode.logicalResolution == intent.logicalResolution
        && mode.backingResolution == intent.backingResolution
        && approximatelyEqual(mode.scaleFactor, intent.scaleFactor)
        && mode.isHiDPI == intent.isHiDPI
        && optionalApproxEqual(mode.refreshHz, intent.refreshHz)
    }
    guard matches.count == 1, let match = matches.first else {
      return .blocked(matches.isEmpty ? "resolutionNotFound" : "resolutionAmbiguous")
    }
    return .resolved(match.id)
  }

  func resolveDisplayMode(_ intent: DisplayModeIntent, for display: DisplaySelector) throws
    -> Resolved<DisplayModeID>
  {
    let result = try client.listDisplayModes(display)
    guard result.readability != .unreadable else {
      return .blocked(result.reason ?? "displayModesUnavailable")
    }
    let matches = result.items.filter { mode in
      mode.outputTimingResolution == intent.outputTimingResolution
        && optionalApproxEqual(mode.outputTimingRefreshHz, intent.outputTimingRefreshHz)
        && optionalEqual(mode.bitDepth, intent.bitDepth)
        && optionalEqual(mode.encoding, intent.encoding)
        && optionalEqual(mode.range, intent.range)
        && optionalEqual(mode.chroma, intent.chroma)
        && optionalEqual(mode.hdrMode, intent.hdrMode)
        && optionalEqual(mode.isVRR, intent.isVRR)
    }
    guard matches.count == 1, let match = matches.first else {
      return .blocked(matches.isEmpty ? "displayModeNotFound" : "displayModeAmbiguous")
    }
    return .resolved(match.id)
  }

  func updateCurrentProfile(
    for display: DisplaySelector,
    update: (inout DisplayProfileIntent, DisplayState) -> Void
  ) throws {
    guard let recordIndex = recordIndex(for: display),
      let currentProfileID = document.displays[recordIndex].currentProfileID,
      let profileIndex = document.displays[recordIndex].profiles.firstIndex(where: {
        $0.id == currentProfileID
      })
    else {
      return
    }

    let state = try client.readDisplayState(display)
    try saveTransaction {
      update(&document.displays[recordIndex].profiles[profileIndex].intent, state)
      document.displays[recordIndex].profiles[profileIndex].isVerified = true
    }
  }
}
