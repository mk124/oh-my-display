import CoreGraphics
import OMDMonitorPanelBridge

/// System HDR preference (the System Settings "High Dynamic Range" switch), backed by the
/// private MonitorPanel framework. Orthogonal to the CADisplay link mode: flipping it makes
/// WindowServer renegotiate the link and compose in true HDR/SDR.
protocol HDRPreferenceBackend: Sendable {
  var isAvailable: Bool { get }
  /// nil when the preference cannot be read (bridge failure, display not found).
  func preferHDRModes(_ displayID: CGDirectDisplayID) -> Bool?
  /// false when the write failed.
  func setPreferHDRModes(_ displayID: CGDirectDisplayID, enabled: Bool) -> Bool
}

struct LiveHDRPreferenceBackend: HDRPreferenceBackend {
  var isAvailable: Bool { OMDMonitorPanelBridgeIsAvailable() }

  func preferHDRModes(_ displayID: CGDirectDisplayID) -> Bool? {
    var value = false
    return OMDMonitorPanelCopyPreferHDRModes(displayID, &value, nil) ? value : nil
  }

  func setPreferHDRModes(_ displayID: CGDirectDisplayID, enabled: Bool) -> Bool {
    OMDMonitorPanelSetPreferHDRModes(displayID, enabled, nil)
  }
}

/// Null object for injection defaults: behaves like a missing MonitorPanel framework.
struct UnavailableHDRPreferenceBackend: HDRPreferenceBackend {
  var isAvailable: Bool { false }
  func preferHDRModes(_ displayID: CGDirectDisplayID) -> Bool? { nil }
  func setPreferHDRModes(_ displayID: CGDirectDisplayID, enabled: Bool) -> Bool { false }
}

extension DisplayHDRMode {
  /// The system HDR preference this mode's category calls for; nil when unknown (stay out of orchestration).
  var prefersHDR: Bool? {
    switch self {
    case .sdr: false
    case .hdr10, .dolbyVision, .dolbyVisionLowLatency: true
    case .unknown: nil
    }
  }
}
