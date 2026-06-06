import AppKit

// LaunchServices only deduplicates regular .app launches; this also covers direct binary execution and `open -n`.
if let bundleID = Bundle.main.bundleIdentifier,
  NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0.processIdentifier != getpid() })
{
  exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
