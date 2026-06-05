import Foundation
import OMDCore

extension OMDAppCore {
  package func setResolutionMode(
    _ modeID: ResolutionModeID,
    for display: DisplaySelector,
    persistToCurrentProfile: Bool = true
  ) throws
    -> DisplaySetResult
  {
    let result = try client.setResolutionMode(display, modeID: modeID)
    if result.isSuccessful && persistToCurrentProfile {
      try refreshCurrentProfileAfterResolutionChange(for: display)
    }
    return result
  }

  package func setDisplayMode(
    _ modeID: DisplayModeID,
    for display: DisplaySelector,
    persistToCurrentProfile: Bool = true
  ) throws
    -> DisplaySetResult
  {
    let result = try client.setDisplayMode(display, modeID: modeID)
    if result.isSuccessful && persistToCurrentProfile {
      try refreshCurrentProfileDisplayMode(for: display)
    }
    return result
  }

  package func captureMutationBaseline(for display: DisplaySelector) throws -> DisplayMutationBaseline {
    let state = try client.readDisplayState(display)
    return DisplayMutationBaseline(
      display: display,
      resolutionModeID: readableValue(state.currentResolutionModeID),
      displayModeID: readableValue(state.currentDisplayModeID),
      ditheringEnabled: readableValue(state.ditheringEnabled),
      iccProfileURL: readableValue(state.iccProfileURL)
    )
  }

  package func restore(_ baseline: DisplayMutationBaseline) throws -> ProfileApplyResult {
    try restore(baseline, operations: [.resolution, .displayMode, .dithering, .icc])
  }

  package func restoreResolution(_ baseline: DisplayMutationBaseline) throws -> ProfileApplyResult {
    try restore(baseline, operations: [.resolution])
  }

  package func restoreDisplayMode(_ baseline: DisplayMutationBaseline) throws -> ProfileApplyResult {
    try restore(baseline, operations: [.displayMode])
  }

  private func restore(
    _ baseline: DisplayMutationBaseline,
    operations requestedOperations: [ProfileOperationKind]
  ) throws -> ProfileApplyResult {
    var operations: [ProfileOperationResult] = []

    if requestedOperations.contains(.resolution), let resolutionModeID = baseline.resolutionModeID {
      let result = try client.setResolutionMode(baseline.display, modeID: resolutionModeID)
      operations.append(ProfileOperationResult(operation: .resolution, result: result))
      guard result.isSuccessful else {
        return ProfileApplyResult(operations: operations)
      }
    }

    if requestedOperations.contains(.displayMode), let displayModeID = baseline.displayModeID {
      let result = try client.setDisplayMode(baseline.display, modeID: displayModeID)
      operations.append(ProfileOperationResult(operation: .displayMode, result: result))
      guard result.isSuccessful else {
        return ProfileApplyResult(operations: operations)
      }
    }

    if requestedOperations.contains(.dithering), let ditheringEnabled = baseline.ditheringEnabled {
      let result = try client.setDithering(baseline.display, enabled: ditheringEnabled)
      operations.append(ProfileOperationResult(operation: .dithering, result: result))
      guard result.isSuccessful else {
        return ProfileApplyResult(operations: operations)
      }
    }

    if requestedOperations.contains(.icc), let iccProfileURL = baseline.iccProfileURL {
      let result = try client.setICCProfile(baseline.display, profileURL: iccProfileURL)
      operations.append(ProfileOperationResult(operation: .icc, result: result))
    }

    if operations.isEmpty {
      operations.append(ProfileOperationResult(operation: .restore, result: .blocked("emptyBaseline")))
    }
    return ProfileApplyResult(operations: operations)
  }
}
