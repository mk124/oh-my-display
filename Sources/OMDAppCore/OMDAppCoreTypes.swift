import Foundation
import OMDCore

package enum DisplayEventTrigger: String, Codable, Equatable, Sendable {
  case startup
  case wake
  case displayChange

  var isSteadyState: Bool {
    self != .startup
  }
}

package struct DisplayMutationBaseline: Equatable, Sendable {
  package var display: DisplaySelector
  package var resolutionModeID: ResolutionModeID?
  package var displayModeID: DisplayModeID?
  package var ditheringEnabled: Bool?
  package var iccProfileURL: URL?

  package init(
    display: DisplaySelector,
    resolutionModeID: ResolutionModeID?,
    displayModeID: DisplayModeID?,
    ditheringEnabled: Bool?,
    iccProfileURL: URL?
  ) {
    self.display = display
    self.resolutionModeID = resolutionModeID
    self.displayModeID = displayModeID
    self.ditheringEnabled = ditheringEnabled
    self.iccProfileURL = iccProfileURL
  }

  package var canRestoreResolution: Bool { resolutionModeID != nil }
  package var canRestoreDisplayMode: Bool { displayModeID != nil }
  package var canRestoreDithering: Bool { ditheringEnabled != nil }
  package var canRestoreICC: Bool { iccProfileURL != nil }
}

package struct DisplayReconcileResult: Equatable, Sendable {
  package var display: DisplayTarget
  package var outcome: DisplayReconcileOutcome

  package init(
    display: DisplayTarget,
    outcome: DisplayReconcileOutcome
  ) {
    self.display = display
    self.outcome = outcome
  }
}

package enum DisplayReconcileOutcome: Equatable, Sendable {
  case skipped(reason: ReconcileSkipReason, profileID: UUID?)
  case applied(profileID: UUID, result: ProfileApplyResult)
}

package struct ProfileApplyResult: Equatable, Sendable {
  package var operations: [ProfileOperationResult]

  package init(operations: [ProfileOperationResult]) {
    self.operations = operations
  }

  package var succeeded: Bool {
    operations.allSatisfy { $0.result.isSuccessful }
  }

  package var summary: String {
    operations.map { operation in
      if let reason = operation.result.reason {
        return "\(operation.operation.rawValue): \(operation.result.status.rawValue) (\(reason))"
      }
      return "\(operation.operation.rawValue): \(operation.result.status.rawValue)"
    }.joined(separator: "; ")
  }
}

package struct ProfileOperationResult: Equatable, Sendable {
  package var operation: ProfileOperationKind
  package var result: DisplaySetResult

  package init(operation: ProfileOperationKind, result: DisplaySetResult) {
    self.operation = operation
    self.result = result
  }
}
