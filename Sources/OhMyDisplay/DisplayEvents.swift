import AppKit
import CoreGraphics
import OMDAppCore

extension AppDelegate {
  func installEventObservers() {
    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(workspaceDidWake(_:)),
      name: NSWorkspace.didWakeNotification,
      object: nil)
    CGDisplayRegisterReconfigurationCallback(
      displayReconfigurationCallback,
      Unmanaged.passUnretained(self).toOpaque())
  }

  func uninstallEventObservers() {
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    CGDisplayRemoveReconfigurationCallback(
      displayReconfigurationCallback,
      Unmanaged.passUnretained(self).toOpaque())
  }

  @objc func workspaceDidWake(_ notification: Notification) {
    scheduleReconcile(trigger: .wake)
  }

  func scheduleReconcile(trigger: DisplayEventTrigger) {
    guard riskyMutationDepth == 0 else {
      return
    }
    if let suppressEventsUntil, suppressEventsUntil > Date() {
      return
    }
    reconcileTimer?.invalidate()
    reconcileTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) {
      [weak self] _ in
      Task { @MainActor in
        self?.runReconcile(trigger: trigger, showErrors: false)
      }
    }
  }

  func runReconcile(trigger: DisplayEventTrigger, showErrors: Bool) {
    guard riskyMutationDepth == 0 else {
      return
    }
    guard let core else {
      return
    }
    do {
      suppressOwnEvents()
      _ = try core.reconcile(trigger: trigger)
      rebuildMenu()
    } catch {
      if showErrors {
        showError(error)
      }
      rebuildMenu()
    }
  }

  func suppressOwnEvents() {
    suppressEventsUntil = Date().addingTimeInterval(3)
  }
}

private let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = {
  _, _, userInfo in
  guard let userInfo else {
    return
  }
  let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
  Task { @MainActor in
    delegate.scheduleReconcile(trigger: .displayChange)
  }
}
