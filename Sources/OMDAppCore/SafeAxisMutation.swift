import Foundation
import OMDCore

package struct DirectMutationResult: Equatable, Sendable {
  package var succeeded: Bool
  package var message: String?

  package static let success = Self(succeeded: true, message: nil)

  package static func failed(_ message: String) -> Self {
    Self(succeeded: false, message: message)
  }
}

extension OMDAppCore {
  package func safelySetDithering(
    _ enabled: Bool,
    for display: DisplaySelector,
    displayName: String
  ) -> DirectMutationResult {
    do {
      let baseline = try captureMutationBaseline(for: display)
      let state = try client.readDisplayState(display)
      guard state.ditheringAvailability.canSet else {
        return .failed(
          "Unable to Set Dithering on \(displayName): Dithering is not available. No display change was made.")
      }

      let shouldPersist = hasCurrentProfile(for: display)
      if readableValue(state.ditheringEnabled) == enabled {
        if shouldPersist {
          try refreshCurrentProfileDithering(for: display, enabled: enabled)
        }
        return .success
      }

      let value = enabled ? "On" : "Off"
      let result = try setDithering(enabled, for: display, persistToCurrentProfile: false)
      guard result.isSuccessful else {
        return handleDirectMutationFailure(
          .attempted(
            axis: "Dithering",
            display: displayName,
            value: value,
            summary: result.reason ?? result.status.rawValue),
          attemptedMutation: result.attemptedMutation,
          display: display,
          baseline: baseline,
          canRestore: baseline.canRestoreDithering,
          unavailableReason: "previous Dithering state was unreadable",
          restore: restoreDithering)
      }

      if shouldPersist {
        do {
          try refreshCurrentProfileDithering(for: display, enabled: enabled)
        } catch {
          return handleDirectMutationCommitFailure(
            axis: "Dithering",
            displayName: displayName,
            value: value,
            summary: String(describing: error),
            display: display,
            baseline: baseline,
            canRestore: baseline.canRestoreDithering,
            unavailableReason: "previous Dithering state was unreadable",
            restore: restoreDithering)
        }
      }
      return .success
    } catch {
      return .failed(String(describing: error))
    }
  }

  package func safelySetICCProfile(
    _ profileURL: URL,
    for display: DisplaySelector,
    displayName: String,
    valueTitle: String
  ) -> DirectMutationResult {
    do {
      let baseline = try captureMutationBaseline(for: display)
      let state = try client.readDisplayState(display)
      let profiles = try client.listDisplayAssignableICCProfiles()
      guard profiles.contains(where: { ICCProfileIdentity.sameFile($0.url, profileURL) }) else {
        return .failed(
          "Unable to Set ICC Profile on \(displayName): selected ICC profile is no longer available in the app. No display change was made.")
      }

      let shouldPersist = hasCurrentProfile(for: display)
      if readableValue(state.iccProfileURL).map({ ICCProfileIdentity.sameFile($0, profileURL) }) == true {
        if shouldPersist {
          try refreshCurrentProfileICC(for: display, profileURL: profileURL)
        }
        return .success
      }

      let result = try setICCProfile(profileURL, for: display, persistToCurrentProfile: false)
      guard result.isSuccessful else {
        return handleDirectMutationFailure(
          .attempted(
            axis: "ICC Profile",
            display: displayName,
            value: valueTitle,
            summary: result.reason ?? result.status.rawValue),
          attemptedMutation: result.attemptedMutation,
          display: display,
          baseline: baseline,
          canRestore: baseline.canRestoreICC,
          unavailableReason: "previous ICC Profile was unreadable",
          restore: restoreICC)
      }

      if shouldPersist {
        do {
          try refreshCurrentProfileICC(for: display, profileURL: profileURL)
        } catch {
          return handleDirectMutationCommitFailure(
            axis: "ICC Profile",
            displayName: displayName,
            value: valueTitle,
            summary: String(describing: error),
            display: display,
            baseline: baseline,
            canRestore: baseline.canRestoreICC,
            unavailableReason: "previous ICC Profile was unreadable",
            restore: restoreICC)
        }
      }
      return .success
    } catch {
      return .failed(String(describing: error))
    }
  }

  package func safelySelectProfile(
    _ profileID: UUID,
    for display: DisplaySelector,
    displayName: String
  ) -> DirectMutationResult {
    do {
      let profile = try profile(profileID, for: display)
      let baselineSnapshot = try captureMutationBaseline(for: display)
      let canRestore = try baseline(
        baselineSnapshot,
        canRestoreProfile: profileID,
        for: display)
      let value = profile.label

      let result = applyCatchingFailures(profile.intent, to: display)
      try? recordApplyResult(result, for: display)

      guard result.succeeded else {
        return handleDirectMutationFailure(
          .attempted(
            axis: "Profile",
            display: displayName,
            value: value,
            summary: result.summary),
          attemptedMutation: result.operations.contains { $0.result.attemptedMutation },
          display: display,
          baseline: baselineSnapshot,
          canRestore: canRestore,
          unavailableReason: "previous display state was unreadable",
          restore: restore)
      }

      do {
        try commitProfileSelection(profileID, for: display)
      } catch {
        return handleDirectMutationCommitFailure(
          axis: "Profile",
          displayName: displayName,
          value: value,
          summary: String(describing: error),
          display: display,
          baseline: baselineSnapshot,
          canRestore: canRestore,
          unavailableReason: "previous display state was unreadable",
          restore: restore)
      }

      return .success
    } catch {
      return .failed(String(describing: error))
    }
  }

  private func hasCurrentProfile(for display: DisplaySelector) -> Bool {
    record(for: display)?.currentProfileID != nil
  }

  private func handleDirectMutationFailure(
    _ failure: DirectMutationFailure,
    attemptedMutation: Bool,
    display: DisplaySelector,
    baseline: DisplayMutationBaseline,
    canRestore: Bool,
    unavailableReason: String,
    restore: (DisplayMutationBaseline) throws -> ProfileApplyResult
  ) -> DirectMutationResult {
    guard attemptedMutation else {
      return .failed(plainFailureMessage(failure))
    }
    let recovery = recoverDirectMutation(
      display: display,
      baseline: baseline,
      canRestore: canRestore,
      unavailableReason: unavailableReason,
      restore: restore)
    return .failed(DirectMutationOutcomeMessage.message(failure, recovery: recovery))
  }

  private func handleDirectMutationCommitFailure(
    axis: String,
    displayName: String,
    value: String,
    summary: String,
    display: DisplaySelector,
    baseline: DisplayMutationBaseline,
    canRestore: Bool,
    unavailableReason: String,
    restore: (DisplayMutationBaseline) throws -> ProfileApplyResult
  ) -> DirectMutationResult {
    let failure = DirectMutationFailure.commit(
      axis: axis,
      display: displayName,
      value: value,
      summary: summary)
    let recovery = recoverDirectMutation(
      display: display,
      baseline: baseline,
      canRestore: canRestore,
      unavailableReason: unavailableReason,
      restore: restore)
    return .failed(DirectMutationOutcomeMessage.message(failure, recovery: recovery))
  }

  private func plainFailureMessage(_ failure: DirectMutationFailure) -> String {
    switch failure {
    case .attempted(let axis, let display, let value, let summary):
      return "Unable to Set \(axis) on \(display) to \(value): \(summary). Current Profile was not updated."
    case .commit(let axis, let display, let value, let summary):
      return "Set \(axis) on \(display) to \(value), but Current Profile was not saved: \(summary)."
    }
  }
}
