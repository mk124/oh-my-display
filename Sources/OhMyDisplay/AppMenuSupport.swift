import Foundation
import OMDAppCore
import OMDCore

struct DisplayPayload {
  var display: DisplaySelector
}

struct CurrentPayload {
  var display: DisplaySelector
  var displayName: String
  var profileID: UUID
}

struct ProfilePayload {
  var display: DisplaySelector
  var profileID: UUID
  var title: String
}

struct ResolutionPayload {
  var display: DisplaySelector
  var modeID: ResolutionModeID
}

struct DisplayModePayload {
  var display: DisplaySelector
  var modeID: DisplayModeID
}

struct DitheringPayload {
  var display: DisplaySelector
  var displayName: String
  var enabled: Bool
}

struct ICCProfilePayload {
  var display: DisplaySelector
  var displayName: String
  var url: URL
  var title: String
}

struct MutationOutcome {
  var succeeded: Bool
  var attemptedMutation: Bool
  var summary: String

  init(_ result: DisplaySetResult) {
    self.succeeded = result.isSuccessful
    self.attemptedMutation = result.attemptedMutation
    self.summary = result.reason ?? result.status.rawValue
  }

  init(_ result: ProfileApplyResult) {
    self.succeeded = result.succeeded
    self.attemptedMutation = result.operations.contains { $0.result.attemptedMutation }
    self.summary = result.summary
  }
}

struct AppMenuError: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}
