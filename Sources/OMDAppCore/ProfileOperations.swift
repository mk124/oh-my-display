import Foundation
import OMDCore

extension OMDAppCore {
  @discardableResult package func addProfile(for display: DisplaySelector) throws -> DisplayProfile {
    let state = try client.readDisplayState(display)
    let target = state.target
    let profileID = UUID()
    let profile = DisplayProfile(id: profileID, ordinal: nextProfileOrdinal(for: display), intent: captureIntent(from: state), isVerified: true)

    try saveTransaction {
      upsertRecord(for: target) { record in
        record.profiles.append(profile)
        record.currentProfileID = profile.id
        record.lastResult = nil
      }
    }
    return profile
  }

  package func setCurrentOff(for display: DisplaySelector) throws {
    guard let index = recordIndex(for: display) else { return }
    try saveTransaction {
      document.displays[index].currentProfileID = nil
      document.displays[index].lastResult = nil
    }
  }

  package func renameProfile(_ profileID: UUID, for display: DisplaySelector, to name: String) throws {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { throw ProfileStoreError.emptyProfileName }
    guard let recordIndex = recordIndex(for: display) else { throw ProfileStoreError.missingDisplay(display.rawValue) }
    if document.displays[recordIndex].profiles.contains(where: { $0.id != profileID && $0.customName == trimmedName }) {
      throw ProfileStoreError.duplicateProfileName(trimmedName)
    }
    guard let profileIndex = document.displays[recordIndex].profiles.firstIndex(where: { $0.id == profileID }) else {
      throw ProfileStoreError.missingProfile(profileID)
    }

    try saveTransaction { document.displays[recordIndex].profiles[profileIndex].customName = trimmedName }
  }

  package func deleteProfile(_ profileID: UUID, for display: DisplaySelector) throws {
    guard let recordIndex = recordIndex(for: display) else { throw ProfileStoreError.missingDisplay(display.rawValue) }
    guard document.displays[recordIndex].profiles.contains(where: { $0.id == profileID }) else { throw ProfileStoreError.missingProfile(profileID) }
    try saveTransaction {
      document.displays[recordIndex].profiles.removeAll { $0.id == profileID }
      if document.displays[recordIndex].currentProfileID == profileID {
        document.displays[recordIndex].currentProfileID = nil
        document.displays[recordIndex].lastResult = nil
      }
    }
  }

  package func selectProfile(_ profileID: UUID, for display: DisplaySelector) throws -> ProfileApplyResult {
    let result = try applyProfile(profileID, for: display)
    if result.succeeded { try setCurrentProfile(profileID, for: display, isVerified: true) }
    return result
  }

  package func applyProfile(_ profileID: UUID, for display: DisplaySelector) throws -> ProfileApplyResult {
    let profile = try profile(profileID, for: display)
    let result = try apply(profile.intent, to: display)
    try recordApplyResult(result, for: display)
    return result
  }

  func recordApplyResult(_ result: ProfileApplyResult, for display: DisplaySelector) throws {
    guard let recordIndex = recordIndex(for: display) else { throw ProfileStoreError.missingDisplay(display.rawValue) }
    let lastResult = result.succeeded ? nil : ProfileLastResult(summary: result.summary)
    if document.displays[recordIndex].lastResult != lastResult { try saveTransaction { document.displays[recordIndex].lastResult = lastResult } }
  }

  package func setCurrentProfile(_ profileID: UUID, for display: DisplaySelector) throws { try setCurrentProfile(profileID, for: display, isVerified: false) }

  package func commitProfileSelection(_ profileID: UUID, for display: DisplaySelector) throws {
    try setCurrentProfile(profileID, for: display, isVerified: true)
  }

  func setCurrentProfile(_ profileID: UUID, for display: DisplaySelector, isVerified: Bool) throws {
    guard let recordIndex = recordIndex(for: display) else { throw ProfileStoreError.missingDisplay(display.rawValue) }
    guard let profileIndex = document.displays[recordIndex].profiles.firstIndex(where: { $0.id == profileID }) else {
      throw ProfileStoreError.missingProfile(profileID)
    }
    try saveTransaction {
      document.displays[recordIndex].currentProfileID = profileID
      if isVerified { document.displays[recordIndex].profiles[profileIndex].isVerified = true }
      document.displays[recordIndex].lastResult = nil
    }
  }

  package func refreshCurrentProfileAfterResolutionChange(for display: DisplaySelector) throws {
    try updateCurrentProfile(for: display) { intent, state in
      intent.resolution = captureResolutionIntent(from: state)
      intent.displayMode = captureDisplayModeIntent(from: state)
    }
  }

  package func refreshCurrentProfileDisplayMode(for display: DisplaySelector) throws {
    try updateCurrentProfile(for: display) { intent, state in intent.displayMode = captureDisplayModeIntent(from: state) }
  }

  package func refreshCurrentProfileDithering(for display: DisplaySelector) throws {
    try updateCurrentProfile(for: display) { intent, state in intent.ditheringEnabled = readableValue(state.ditheringEnabled) }
  }

  package func refreshCurrentProfileICC(for display: DisplaySelector) throws {
    try updateCurrentProfile(for: display) { intent, state in intent.iccProfileURL = readableValue(state.iccProfileURL) }
  }

  func refreshCurrentProfileDithering(for display: DisplaySelector, enabled: Bool) throws {
    try updateCurrentProfileIntent(for: display) { intent in intent.ditheringEnabled = enabled }
  }

  func refreshCurrentProfileICC(for display: DisplaySelector, profileURL: URL) throws {
    try updateCurrentProfileIntent(for: display) { intent in intent.iccProfileURL = profileURL }
  }

  func updateCurrentProfileIntent(for display: DisplaySelector, update: (inout DisplayProfileIntent) -> Void) throws {
    guard let index = currentProfileIndex(for: display) else { return }

    try saveTransaction {
      update(&document.displays[index.record].profiles[index.profile].intent)
      document.displays[index.record].profiles[index.profile].isVerified = true
    }
  }

  func currentProfileIndex(for display: DisplaySelector) -> (record: Int, profile: Int)? {
    guard let recordIndex = recordIndex(for: display), let currentProfileID = document.displays[recordIndex].currentProfileID,
      let profileIndex = document.displays[recordIndex].profiles.firstIndex(where: { $0.id == currentProfileID })
    else { return nil }
    return (recordIndex, profileIndex)
  }
}
