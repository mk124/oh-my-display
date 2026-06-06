import AppKit
import CoreGraphics
import OMDAppCore

extension AppDelegate {
  func installEventObservers() {
    NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceDidWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
    CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
  }

  func uninstallEventObservers() {
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
  }

  @objc func workspaceDidWake(_ notification: Notification) { check(trigger: .wake) }

  // Every completed reconfiguration prompts one state comparison against the profiles;
  // mismatches correct with an attempt budget owned by OMDAppCore.reconcile. The flag
  // stops the nested run loop of a gave-up alert from re-entering reconcile; mutation
  // flows are covered by the check their end fires.
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
          showError(AppMenuError(text))
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
