import Foundation
import OMDCore

package enum CurrentOffUpdate: Equatable, Sendable {
  case succeeded
  case failed(String)

  package var message: String {
    switch self {
    case .succeeded: return "Current was turned Off; this display is no longer controlled by a profile."
    case .failed(let summary): return "Current Off update also failed: \(summary). Profile control state could not be cleared."
    }
  }
}

package enum DirectMutationRecoveryResult: Equatable, Sendable {
  case restored(ProfileApplyResult)
  case restoreFailed(ProfileApplyResult, CurrentOffUpdate)
  case restoreUnavailable(String, CurrentOffUpdate)
}

extension OMDAppCore {
  package func recoverDirectMutation(
    display: DisplaySelector, baseline: DisplayMutationBaseline, canRestore: Bool, unavailableReason: String,
    restore: (DisplayMutationBaseline) throws -> ProfileApplyResult
  ) -> DirectMutationRecoveryResult {
    guard canRestore else { return .restoreUnavailable(unavailableReason, turnCurrentOff(for: display)) }

    do {
      let result = try restore(baseline)
      return result.succeeded ? .restored(result) : .restoreFailed(result, turnCurrentOff(for: display))
    } catch { return .restoreUnavailable("restore threw: \(error)", turnCurrentOff(for: display)) }
  }

  package func turnCurrentOff(for display: DisplaySelector) -> CurrentOffUpdate {
    do {
      try setCurrentOff(for: display)
      return .succeeded
    } catch { return .failed(String(describing: error)) }
  }
}
