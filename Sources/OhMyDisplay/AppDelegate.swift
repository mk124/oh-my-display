import AppKit
import OMDAppCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  var core: OMDAppCore?
  let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  var isChecking = false
  var riskyMutationDepth = 0
  var safeMutationDepth = 0
  var heartbeatTimer: Timer?

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      core = try OMDAppCore()
      configureStatusItem()
      installEventObservers()
      rebuildMenu()
      check(trigger: .startup)
    } catch {
      configureStatusItem()
      rebuildMenu()
      showError(error)
    }
  }

  func applicationWillTerminate(_ notification: Notification) { uninstallEventObservers() }

  func configureStatusItem() {
    let button = statusItem.button
    button?.image = Self.menuBarIcon()
    button?.imagePosition = .imageOnly
    let menu = NSMenu()
    menu.delegate = self
    statusItem.menu = menu
  }

  // A code-drawn single-colour template glyph echoing the logo's monitor: a stroked rounded screen
  // over a stand bar. viewBox 100 × 83 with the ink pre-centered, so the status button — which
  // centers the whole image — places it dead-center, free of the SF Symbol baseline offset.
  private static func menuBarIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 15 * 100.0 / 83.0, height: 15), flipped: false) { rect in
      guard let c = NSGraphicsContext.current?.cgContext else { return false }
      c.scaleBy(x: rect.width / 100, y: rect.height / 83)
      c.setLineJoin(.round)
      let ink = NSColor.black.cgColor
      // outline 88×58 with an 8 border → interior hole 80×50 = 16:10
      let screen = CGPath(roundedRect: CGRect(x: 6, y: 19, width: 88, height: 58),
        cornerWidth: 9, cornerHeight: 9, transform: nil)
      c.setFillColor(ink.copy(alpha: 0.18)!)  // soft glow inside the screen (renders faint on the bar)
      c.addPath(screen)
      c.fillPath()
      c.setStrokeColor(ink)
      c.setLineWidth(8)
      c.addPath(screen)
      c.strokePath()
      let stand = CGPath(roundedRect: CGRect(x: 29, y: 2, width: 42, height: 7),
        cornerWidth: 3, cornerHeight: 3, transform: nil)
      c.setFillColor(ink)
      c.addPath(stand)
      c.fillPath()
      return true
    }
    image.isTemplate = true
    return image
  }

  func requireCore() throws -> OMDAppCore {
    guard let core else { throw AppMenuError("AppCore unavailable") }
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
