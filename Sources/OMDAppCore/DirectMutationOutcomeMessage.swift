import Foundation

package enum DirectMutationFailure {
  case attempted(axis: String, display: String, value: String, summary: String)
  case commit(axis: String, display: String, value: String, summary: String)
}

package enum DirectMutationOutcomeMessage {
  package static func message(_ failure: DirectMutationFailure, recovery: DirectMutationRecoveryResult) -> String {
    switch recovery {
    case .restored: return restored(failure)
    case .restoreFailed(let result, let currentOff): return message(failure, restoreSummary: "Restore failed: \(result.summary)", currentOff: currentOff)
    case .restoreUnavailable(let reason, let currentOff):
      return message(failure, restoreSummary: "Restore could not be performed: \(reason)", currentOff: currentOff)
    }
  }

  private static func restored(_ failure: DirectMutationFailure) -> String {
    switch failure {
    case .attempted(let axis, let display, let value, let summary):
      return "Unable to Set \(axis) on \(display) to \(value): \(summary). Previous \(axis) state was restored. Current Profile was not updated."
    case .commit(let axis, let display, let value, let summary):
      return "Set \(axis) on \(display) to \(value), but Current Profile was not saved: \(summary). Previous \(axis) state was restored."
    }
  }

  private static func message(_ failure: DirectMutationFailure, restoreSummary: String, currentOff: CurrentOffUpdate) -> String {
    switch failure {
    case .attempted(let axis, let display, let value, let summary):
      return "Unable to Set \(axis) on \(display) to \(value): \(summary). \(restoreSummary). \(currentOff.message)"
    case .commit(let axis, let display, let value, let summary):
      return "Set \(axis) on \(display) to \(value), but Current Profile was not saved: \(summary). \(restoreSummary). \(currentOff.message)"
    }
  }
}
