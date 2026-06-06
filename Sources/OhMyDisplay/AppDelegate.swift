import AppKit
import OMDAppCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  var core: OMDAppCore?
  let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  var reconcileTimer: Timer?
  var suppressEventsUntil: Date?
  var riskyMutationDepth = 0
  var safeMutationDepth = 0
  var displayEventCoalescer = DisplayEventCoalescer()

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      core = try OMDAppCore()
      configureStatusItem()
      installEventObservers()
      rebuildMenu()
      runReconcile(trigger: .startup, showErrors: false)
    } catch {
      configureStatusItem()
      rebuildMenu()
      showError(error)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    uninstallEventObservers()
  }

  func configureStatusItem() {
    let button = statusItem.button
    button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Oh My Display")
    button?.imagePosition = .imageOnly
    statusItem.menu = NSMenu()
  }

  func requireCore() throws -> OMDAppCore {
    guard let core else {
      throw AppMenuError("AppCore unavailable")
    }
    return core
  }

  func showError(_ error: Error) {
    let alert = NSAlert()
    alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
    alert.messageText = "Oh My Display"
    alert.informativeText = String(describing: error)
    alert.alertStyle = .warning
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
  }
}
