import Foundation
import OMDCore

extension OMDAppCore {
  // Event-driven enforcement: a confirmed match resets the display's attempt budget;
  // a mismatch corrects and consumes one of 3 attempts, verified by the next event's
  // pass; an exhausted budget turns the profile off instead of touching hardware again.
  package func reconcile(trigger: DisplayEventTrigger) throws -> [DisplayReconcileResult] {
    let displays = try client.listDisplays()
    let originalDocument = document
    var results: [DisplayReconcileResult] = []

    for display in displays {
      guard let recordIndex = recordIndex(for: display.selector) else {
        enforcementAttempts[display.selector] = nil
        results.append(DisplayReconcileResult(display: display, outcome: .skipped(reason: .off, profileID: nil)))
        continue
      }
      guard let currentProfileID = document.displays[recordIndex].currentProfileID else {
        enforcementAttempts[display.selector] = nil
        results.append(DisplayReconcileResult(display: display, outcome: .skipped(reason: .off, profileID: nil)))
        continue
      }
      guard document.displays[recordIndex].binding.isStrong else {
        enforcementAttempts[display.selector] = nil
        results.append(DisplayReconcileResult(display: display, outcome: .skipped(reason: .weakBinding, profileID: nil)))
        continue
      }
      guard let profile = document.displays[recordIndex].profiles.first(where: { $0.id == currentProfileID }) else {
        enforcementAttempts[display.selector] = nil
        document.displays[recordIndex].lastResult = ProfileLastResult(summary: "missingCurrentProfile")
        results.append(DisplayReconcileResult(display: display, outcome: .skipped(reason: .missingCurrentProfile, profileID: currentProfileID)))
        continue
      }

      do {
        let intent = try reconcileIntent(profile.intent, for: display.selector, trigger: trigger)
        let result: ProfileApplyResult
        if try intentSatisfied(intent, for: display.selector) {
          enforcementAttempts[display.selector] = nil
          result = ProfileApplyResult(operations: [ProfileOperationResult(operation: .profile, result: .noOp("intentSatisfied"))])
        } else {
          let attempts = enforcementAttempts[display.selector] ?? 0
          guard attempts < 3 else {
            enforcementAttempts[display.selector] = nil
            results.append(DisplayReconcileResult(display: display, outcome: .gaveUp(profileID: profile.id, currentOff: turnCurrentOff(for: display.selector))))
            continue
          }
          result = try apply(intent, to: display.selector)
          // Only physical mutations consume budget: an all-noOp/blocked pass cannot
          // bounce or storm, and an unappliable axis (e.g. a missing ICC file) must
          // not assassinate a profile whose hardware axes are already conformant.
          enforcementAttempts[display.selector] = result.operations.contains(where: \.result.attemptedMutation) ? attempts + 1 : nil
        }
        document.displays[recordIndex].lastResult = result.succeeded ? nil : ProfileLastResult(summary: result.summary)
        results.append(DisplayReconcileResult(display: display, outcome: .applied(profileID: profile.id, result: result)))
      } catch {
        document.displays[recordIndex].lastResult = ProfileLastResult(summary: "failed: \(error)")
        results.append(DisplayReconcileResult(display: display, outcome: .skipped(reason: .failed, profileID: profile.id)))
      }
    }

    // A disconnected display is no longer in an incident; reconnect gets a fresh budget.
    let present = Set(displays.map(\.selector))
    enforcementAttempts = enforcementAttempts.filter { present.contains($0.key) }

    if document != originalDocument { try save() }
    return results
  }

  func reconcileIntent(_ intent: DisplayProfileIntent, for display: DisplaySelector, trigger: DisplayEventTrigger) throws -> DisplayProfileIntent {
    guard trigger.isSteadyState, intent.displayMode != nil else { return intent }
    guard let expectedHDR = intent.displayMode?.hdrMode else {
      var guardedIntent = intent
      guardedIntent.displayMode = nil
      return guardedIntent
    }

    let state = try client.readDisplayState(display)
    guard state.hdrMode.readability == .readable, let currentHDR = state.hdrMode.value else {
      var guardedIntent = intent
      guardedIntent.displayMode = nil
      return guardedIntent
    }
    guard currentHDR != expectedHDR else { return intent }

    // Steady-state guard must not flip SDR/HDR/Dolby modes behind the user's back.
    var guardedIntent = intent
    guardedIntent.displayMode = nil
    return guardedIntent
  }
}
