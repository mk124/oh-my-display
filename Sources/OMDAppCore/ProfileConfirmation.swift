import Foundation
import OMDCore

extension OMDAppCore {
  package func profileNeedsConfirmation(_ profileID: UUID, for display: DisplaySelector) throws -> Bool {
    let profile = try profile(profileID, for: display)
    guard !profile.isVerified else { return false }

    let state = try client.readDisplayState(display)

    if let resolution = profile.intent.resolution {
      switch try resolveResolutionMode(resolution, for: display) {
      case .resolved(let modeID): if state.currentResolutionModeID.readability != .readable || state.currentResolutionModeID.value != modeID { return true }
      case .blocked: return true
      }
    }

    if let displayMode = profile.intent.displayMode {
      switch try resolveDisplayMode(displayMode, for: display) {
      case .resolved(let modeID): if state.currentDisplayModeID.readability != .readable || state.currentDisplayModeID.value != modeID { return true }
      case .blocked: return true
      }
    }

    return false
  }

  package func resolutionModeNeedsConfirmation(_ modeID: ResolutionModeID, for display: DisplaySelector) throws -> Bool {
    let state = try client.readDisplayState(display)
    return state.currentResolutionModeID.readability != .readable || state.currentResolutionModeID.value != modeID
  }

  package func displayModeNeedsConfirmation(_ modeID: DisplayModeID, for display: DisplaySelector) throws -> Bool {
    let state = try client.readDisplayState(display)
    return state.currentDisplayModeID.readability != .readable || state.currentDisplayModeID.value != modeID
  }

  package func baseline(_ baseline: DisplayMutationBaseline, canRestoreProfile profileID: UUID, for display: DisplaySelector) throws -> Bool {
    let profile = try profile(profileID, for: display)
    return (profile.intent.resolution == nil || baseline.canRestoreResolution) && (profile.intent.displayMode == nil || baseline.canRestoreDisplayMode)
      && (profile.intent.ditheringEnabled == nil || baseline.canRestoreDithering) && (profile.intent.iccProfileURL == nil || baseline.canRestoreICC)
  }

}
