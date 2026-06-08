import AppKit
import CoreGraphics
import OMDAppCore

extension AppDelegate {
  func installEventObservers() {
    NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceDidWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(screenParametersDidChange(_:)),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
    CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
    installHeartbeat()
  }

  func uninstallEventObservers() {
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
    CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
    heartbeatTimer?.invalidate()
    heartbeatTimer = nil
  }

  @objc func workspaceDidWake(_ notification: Notification) { check(trigger: .wake) }

  // External ICC changes fire no CGDisplay callback but do post this AppKit
  // notification (~0.2s) — the event-level trigger for ICC drift. Reuses
  // .displayChange: a color-space change is a display reconfiguration, steady-state.
  @objc func screenParametersDidChange(_ notification: Notification) { check(trigger: .displayChange) }

  // Eventless drift (e.g. a link renegotiated to YCbCr) fires no callback on any
  // layer, so a slow heartbeat is the detection of last resort. Scheduled in the
  // default run-loop mode only: menu tracking pauses it, so it can never repaint
  // an open menu. The pure-memory gate keeps idle cycles at zero display reads.
  func installHeartbeat() {
    let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.core?.hasEnforceableProfile == true else { return }
        self.check(trigger: .heartbeat)
      }
    }
    timer.tolerance = 5
    RunLoop.main.add(timer, forMode: .default)
    heartbeatTimer = timer
  }

  // Every check trigger (display event, wake, flow-end displayChange, menu open, heartbeat)
  // prompts one state comparison against the profiles; mismatches correct with an
  // attempt budget owned by OMDAppCore.reconcile. The flag stops overlapping passes.
  // Gave-up alerts defer to the default run-loop mode: a modal must not fire inside
  // menu tracking (the menuOpen path), and plain async dispatch is serviced there.
  func check(trigger: DisplayEventTrigger) {
    guard !isChecking, riskyMutationDepth == 0, safeMutationDepth == 0, let core else { return }
    isChecking = true
    defer { isChecking = false }
    do {
      let results = try core.reconcile(trigger: trigger)
      rebuildMenu()
      for result in results {
        if case .gaveUp(_, let currentOff) = result.outcome {
          let text = "\(result.display.label): profile enforcement gave up after 3 attempts. \(currentOff.message) Reselect a profile to re-enable."
          RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated { self?.showError(AppMenuError(text)) }
          }
        }
      }
    } catch { rebuildMenu() }
  }
}

// Begin-phase callbacks carry no readable state yet (kCGDisplayBeginConfigurationFlag);
// only completed reconfigurations prompt a check, and never from inside the callback.
private let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
  guard let userInfo, !flags.contains(.beginConfigurationFlag) else { return }
  let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
  Task { @MainActor in delegate.check(trigger: .displayChange) }
}
