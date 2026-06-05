import AppKit
import OMDAppCore

extension AppDelegate {
  @objc func addProfile(_ sender: NSMenuItem) {
    runAction(sender) { core, payload in
      _ = try core.addProfile(for: payload.display)
    }
  }

  @objc func setCurrentOff(_ sender: NSMenuItem) {
    runAction(sender) { core, payload in
      try core.setCurrentOff(for: payload.display)
    }
  }

  @objc func selectProfile(_ sender: NSMenuItem) {
    guard let payload = sender.representedObject as? CurrentPayload else {
      return
    }
    do {
      let core = try requireCore()
      guard try core.profileNeedsConfirmation(payload.profileID, for: payload.display)
      else {
        let result = try core.selectProfile(payload.profileID, for: payload.display)
        if !result.succeeded {
          showError(AppMenuError(result.summary))
        }
        rebuildMenu()
        return
      }

      try runRiskyMutation(
        display: payload.display,
        canRestore: { core, baseline in
          try core.baseline(baseline, canRestoreProfile: payload.profileID, for: payload.display)
        },
        commit: { core in
          try core.commitProfileSelection(payload.profileID, for: payload.display)
        }
      ) { core in
        let result = try core.applyProfile(payload.profileID, for: payload.display)
        return MutationOutcome(result)
      }
    } catch {
      showError(error)
    }
  }

  @objc func renameProfile(_ sender: NSMenuItem) {
    guard let payload = sender.representedObject as? ProfilePayload else {
      return
    }
    let alert = NSAlert()
    alert.icon = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
    alert.messageText = "Rename Profile"
    alert.informativeText = payload.title
    alert.addButton(withTitle: "Rename")
    alert.addButton(withTitle: "Cancel")
    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    alert.accessoryView = input
    NSApp.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn else {
      return
    }

    do {
      try requireCore().renameProfile(payload.profileID, for: payload.display, to: input.stringValue)
      rebuildMenu()
    } catch {
      showError(error)
    }
  }

  @objc func deleteProfile(_ sender: NSMenuItem) {
    guard let payload = sender.representedObject as? ProfilePayload else {
      return
    }
    do {
      try requireCore().deleteProfile(payload.profileID, for: payload.display)
      rebuildMenu()
    } catch {
      showError(error)
    }
  }

  @objc func setResolution(_ sender: NSMenuItem) {
    guard let payload = sender.representedObject as? ResolutionPayload else {
      return
    }
    do {
      guard sender.state != .on else {
        return
      }
      let core = try requireCore()
      guard try core.resolutionModeNeedsConfirmation(payload.modeID, for: payload.display)
      else {
        _ = try core.setResolutionMode(payload.modeID, for: payload.display)
        rebuildMenu()
        return
      }

      try runRiskyMutation(
        display: payload.display,
        canRestore: { _, baseline in baseline.canRestoreResolution },
        restore: { core, baseline in
          try core.restoreResolution(baseline)
        },
        commit: { core in
          try core.refreshCurrentProfileAfterResolutionChange(for: payload.display)
        }
      ) { core in
        let result = try core.setResolutionMode(
          payload.modeID,
          for: payload.display,
          persistToCurrentProfile: false)
        return MutationOutcome(result)
      }
    } catch {
      showError(error)
    }
  }

  @objc func setDisplayMode(_ sender: NSMenuItem) {
    guard let payload = sender.representedObject as? DisplayModePayload else {
      return
    }
    do {
      guard sender.state != .on else {
        return
      }
      let core = try requireCore()
      guard try core.displayModeNeedsConfirmation(payload.modeID, for: payload.display)
      else {
        _ = try core.setDisplayMode(payload.modeID, for: payload.display)
        rebuildMenu()
        return
      }

      try runRiskyMutation(
        display: payload.display,
        canRestore: { _, baseline in baseline.canRestoreDisplayMode },
        restore: { core, baseline in
          try core.restoreDisplayMode(baseline)
        },
        commit: { core in
          try core.refreshCurrentProfileDisplayMode(for: payload.display)
        }
      ) { core in
        let result = try core.setDisplayMode(
          payload.modeID,
          for: payload.display,
          persistToCurrentProfile: false)
        return MutationOutcome(result)
      }
    } catch {
      showError(error)
    }
  }

  func runAction(_ sender: NSMenuItem, _ action: (OMDAppCore, DisplayPayload) throws -> Void) {
    guard let payload = sender.representedObject as? DisplayPayload else {
      return
    }
    do {
      try action(requireCore(), payload)
      rebuildMenu()
    } catch {
      showError(error)
    }
  }
}
