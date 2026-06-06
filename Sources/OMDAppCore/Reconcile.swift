import Foundation
import OMDCore

extension OMDAppCore {
  package func reconcile(trigger: DisplayEventTrigger) throws -> [DisplayReconcileResult] {
    let displays = try client.listDisplays()
    let originalDocument = document
    var results: [DisplayReconcileResult] = []

    for display in displays {
      guard let recordIndex = recordIndex(for: display.selector) else {
        results.append(DisplayReconcileResult(display: display, outcome: .skipped(reason: .off, profileID: nil)))
        continue
      }
      guard let currentProfileID = document.displays[recordIndex].currentProfileID else {
        results.append(DisplayReconcileResult(display: display, outcome: .skipped(reason: .off, profileID: nil)))
        continue
      }
      guard document.displays[recordIndex].binding.isStrong else {
        results.append(DisplayReconcileResult(display: display, outcome: .skipped(reason: .weakBinding, profileID: nil)))
        continue
      }
      guard let profile = document.displays[recordIndex].profiles.first(where: { $0.id == currentProfileID }) else {
        document.displays[recordIndex].lastResult = ProfileLastResult(summary: "missingCurrentProfile")
        results.append(DisplayReconcileResult(display: display, outcome: .skipped(reason: .missingCurrentProfile, profileID: currentProfileID)))
        continue
      }

      do {
        let intent = try reconcileIntent(profile.intent, for: display.selector, trigger: trigger)
        let result = try apply(intent, to: display.selector)
        document.displays[recordIndex].lastResult = result.succeeded ? nil : ProfileLastResult(summary: result.summary)
        results.append(DisplayReconcileResult(display: display, outcome: .applied(profileID: profile.id, result: result)))
      } catch {
        document.displays[recordIndex].lastResult = ProfileLastResult(summary: "failed: \(error)")
        results.append(DisplayReconcileResult(display: display, outcome: .skipped(reason: .failed, profileID: profile.id)))
      }
    }

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
