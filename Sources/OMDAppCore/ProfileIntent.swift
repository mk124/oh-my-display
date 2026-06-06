import Foundation
import OMDCore

extension OMDAppCore {
  func captureIntent(from state: DisplayState) -> DisplayProfileIntent {
    DisplayProfileIntent(
      resolution: captureResolutionIntent(from: state), displayMode: captureDisplayModeIntent(from: state),
      ditheringEnabled: readableValue(state.ditheringEnabled), iccProfileURL: readableValue(state.iccProfileURL))
  }

  func captureResolutionIntent(from state: DisplayState) -> ResolutionIntent? {
    guard let logical = readableValue(state.logicalResolution), let backing = readableValue(state.backingResolution),
      let scale = readableValue(state.scaleFactor), let isHiDPI = readableValue(state.isHiDPI)
    else { return nil }

    return ResolutionIntent(
      logicalResolution: logical, backingResolution: backing, scaleFactor: scale, isHiDPI: isHiDPI, refreshHz: readableValue(state.resolutionRefreshHz))
  }

  func captureDisplayModeIntent(from state: DisplayState) -> DisplayModeIntent? {
    guard let timing = readableValue(state.outputTimingResolution) else { return nil }

    return DisplayModeIntent(
      outputTimingResolution: timing, outputTimingRefreshHz: readableValue(state.outputTimingRefreshHz), bitDepth: readableValue(state.bitDepth),
      encoding: readableValue(state.encoding), range: readableValue(state.range), chroma: readableValue(state.chroma), hdrMode: readableValue(state.hdrMode),
      isVRR: readableValue(state.isVRR))
  }

  func apply(_ intent: DisplayProfileIntent, to display: DisplaySelector) throws -> ProfileApplyResult {
    try apply(intent, to: display, catchingFailures: false)
  }

  func applyCatchingFailures(_ intent: DisplayProfileIntent, to display: DisplaySelector) -> ProfileApplyResult {
    do { return try apply(intent, to: display, catchingFailures: true) } catch {
      return ProfileApplyResult(operations: [
        ProfileOperationResult(operation: .profile, result: .failed(attemptedMutation: false, reason: String(describing: error)))
      ])
    }
  }

  private func apply(_ intent: DisplayProfileIntent, to display: DisplaySelector, catchingFailures: Bool) throws -> ProfileApplyResult {
    var operations: [ProfileOperationResult] = []

    func run(_ operation: ProfileOperationKind, _ body: () throws -> DisplaySetResult) throws -> Bool {
      let result: DisplaySetResult
      do { result = try body() } catch {
        guard catchingFailures else { throw error }
        let result = DisplaySetResult.failed(attemptedMutation: false, reason: String(describing: error))
        operations.append(ProfileOperationResult(operation: operation, result: result))
        return false
      }
      operations.append(ProfileOperationResult(operation: operation, result: result))
      return result.isSuccessful
    }

    if let resolution = intent.resolution {
      guard
        try run(
          .resolution, { try resolveResolutionMode(resolution, for: display).flatMap { modeID in try client.setResolutionMode(display, modeID: modeID) } })
      else { return ProfileApplyResult(operations: operations) }
    }

    if let displayMode = intent.displayMode {
      guard
        try run(.displayMode, { try resolveDisplayMode(displayMode, for: display).flatMap { modeID in try client.setDisplayMode(display, modeID: modeID) } })
      else { return ProfileApplyResult(operations: operations) }
    }

    if let dithering = intent.ditheringEnabled {
      guard try run(.dithering, { try client.setDithering(display, enabled: dithering) }) else { return ProfileApplyResult(operations: operations) }
    }

    if let iccProfileURL = intent.iccProfileURL { _ = try run(.icc) { try client.setICCProfile(display, profileURL: iccProfileURL) } }

    if operations.isEmpty { operations.append(ProfileOperationResult(operation: .profile, result: .noOp("emptyProfile"))) }
    return ProfileApplyResult(operations: operations)
  }

  func resolveResolutionMode(_ intent: ResolutionIntent, for display: DisplaySelector) throws -> Resolved<ResolutionModeID> {
    let result = try client.listResolutionModes(display)
    guard result.readability != .unreadable else { return .blocked(result.reason ?? "resolutionModesUnavailable") }
    let matches = result.items.filter { mode in
      mode.logicalResolution == intent.logicalResolution && mode.backingResolution == intent.backingResolution
        && approximatelyEqual(mode.scaleFactor, intent.scaleFactor) && mode.isHiDPI == intent.isHiDPI && optionalApproxEqual(mode.refreshHz, intent.refreshHz)
    }
    guard matches.count == 1, let match = matches.first else { return .blocked(matches.isEmpty ? "resolutionNotFound" : "resolutionAmbiguous") }
    return .resolved(match.id)
  }

  func resolveDisplayMode(_ intent: DisplayModeIntent, for display: DisplaySelector) throws -> Resolved<DisplayModeID> {
    let result = try client.listDisplayModes(display)
    guard result.readability != .unreadable else { return .blocked(result.reason ?? "displayModesUnavailable") }
    let matches = result.items.filter { mode in
      mode.outputTimingResolution == intent.outputTimingResolution && optionalApproxEqual(mode.outputTimingRefreshHz, intent.outputTimingRefreshHz)
        && optionalEqual(mode.bitDepth, intent.bitDepth) && optionalEqual(mode.encoding, intent.encoding) && optionalEqual(mode.range, intent.range)
        && optionalEqual(mode.chroma, intent.chroma) && optionalEqual(mode.hdrMode, intent.hdrMode) && optionalEqual(mode.isVRR, intent.isVRR)
    }
    guard matches.count == 1, let match = matches.first else { return .blocked(matches.isEmpty ? "displayModeNotFound" : "displayModeAmbiguous") }
    return .resolved(match.id)
  }

  func updateCurrentProfile(for display: DisplaySelector, update: (inout DisplayProfileIntent, DisplayState) -> Void) throws {
    guard let index = currentProfileIndex(for: display) else { return }

    let state = try client.readDisplayState(display)
    try saveTransaction {
      update(&document.displays[index.record].profiles[index.profile].intent, state)
      document.displays[index.record].profiles[index.profile].isVerified = true
    }
  }
}
