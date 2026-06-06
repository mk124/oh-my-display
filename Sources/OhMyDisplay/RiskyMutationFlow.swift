import AppKit
import OMDAppCore
import OMDCore

extension AppDelegate {
  func runRiskyMutation(
    display: DisplaySelector, canRestore: (OMDAppCore, DisplayMutationBaseline) throws -> Bool,
    restore: (OMDAppCore, DisplayMutationBaseline) throws -> ProfileApplyResult = { core, baseline in try core.restore(baseline) },
    commit: (OMDAppCore) throws -> Void = { _ in }, operation: (OMDAppCore) throws -> MutationOutcome
  ) throws {
    let core = try requireCore()
    let baseline = try core.captureMutationBaseline(for: display)
    guard try canRestore(core, baseline) else {
      showError(AppMenuError("Cannot safely restore the previous display state."))
      return
    }
    beginRiskyMutation()
    defer { endRiskyMutation() }
    suppressOwnEvents()
    let outcome: MutationOutcome
    do { outcome = try operation(core) } catch {
      suppressOwnEvents()
      showError(AppMenuError(restoreAfterFailure(baseline, originalError: error, core: core, restore: restore)))
      rebuildMenu()
      return
    }

    guard outcome.succeeded else {
      if outcome.attemptedMutation {
        suppressOwnEvents()
        let restoreResult = try restore(core, baseline)
        if !restoreResult.succeeded {
          showError(AppMenuError("Mutation failed: \(outcome.summary). Restore failed: \(restoreResult.summary). \(core.turnCurrentOff(for: display).message)"))
          rebuildMenu()
          return
        }
      }
      showError(AppMenuError(outcome.summary))
      rebuildMenu()
      return
    }

    guard confirmKeepChanges() else {
      suppressOwnEvents()
      let restoreResult = try restore(core, baseline)
      if !restoreResult.succeeded { showError(AppMenuError("Restore failed: \(restoreResult.summary). \(core.turnCurrentOff(for: display).message)")) }
      rebuildMenu()
      return
    }

    do { try commit(core) } catch {
      suppressOwnEvents()
      let restoreResult = try restore(core, baseline)
      if restoreResult.succeeded {
        showError(AppMenuError("Keep failed: \(error). Previous display state was restored."))
      } else {
        showError(AppMenuError("Keep failed: \(error). Restore failed: \(restoreResult.summary). \(core.turnCurrentOff(for: display).message)"))
      }
      rebuildMenu()
      return
    }
    rebuildMenu()
  }

  func restoreAfterFailure(
    _ baseline: DisplayMutationBaseline, originalError: Error, core: OMDAppCore, restore: (OMDAppCore, DisplayMutationBaseline) throws -> ProfileApplyResult
  ) -> String {
    do {
      let restoreResult = try restore(core, baseline)
      if restoreResult.succeeded { return "Mutation failed: \(originalError). Previous display state was restored." }
      return "Mutation failed: \(originalError). Restore failed: \(restoreResult.summary). " + core.turnCurrentOff(for: baseline.display).message
    } catch { return "Mutation failed: \(originalError). Restore threw: \(error). " + core.turnCurrentOff(for: baseline.display).message }
  }

  func beginRiskyMutation() {
    riskyMutationDepth += 1
    reconcileTimer?.invalidate()
    reconcileTimer = nil
  }

  func endRiskyMutation() { riskyMutationDepth -= 1 }

  func confirmKeepChanges() -> Bool {
    let alert = NSAlert()
    alert.icon = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
    alert.messageText = "Display Changed"
    alert.informativeText = "If the screen looks correct, choose Keep within 15 seconds. Otherwise, the previous display state will be restored."
    let restoreButton = alert.addButton(withTitle: "Restore (15)")
    alert.addButton(withTitle: "Keep")

    NSApp.activate(ignoringOtherApps: true)
    let deadline = Date().addingTimeInterval(15)
    let timer = Timer(timeInterval: 0.25, repeats: true) { timer in
      MainActor.assumeIsolated {
        let remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        restoreButton.title = "Restore (\(remaining))"
        guard remaining == 0 else { return }
        NSApp.stopModal(withCode: .alertFirstButtonReturn)
      }
    }
    RunLoop.current.add(timer, forMode: .modalPanel)
    let response = alert.runModal()
    timer.invalidate()
    alert.window.close()
    return response == .alertSecondButtonReturn
  }
}
