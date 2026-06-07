import CoreGraphics
import OMDMonitorPanelBridge
import XCTest

// 只读 live 冒烟：契约由 DisplayModeService 的 mock 测试承担（与 OMDQuartzBridge 同待遇）。
final class MonitorPanelBridgeTests: XCTestCase {
  func testAvailabilityProbeDoesNotCrash() {
    _ = OMDMonitorPanelBridgeIsAvailable()
  }

  func testLiveBridgeReadsMainDisplayPreferenceWhenAvailable() throws {
    try XCTSkipUnless(OMDMonitorPanelBridgeIsAvailable(), "MonitorPanel bridge unavailable on this machine")

    var value = false
    XCTAssertTrue(OMDMonitorPanelCopyPreferHDRModes(CGMainDisplayID(), &value, nil))
  }

  func testCopyPreferHDRModesRejectsUnknownDisplayInsteadOfCrashing() {
    var value = false
    var error: Unmanaged<CFError>?

    let ok = OMDMonitorPanelCopyPreferHDRModes(0xFFFF_FFFF, &value, &error)

    XCTAssertFalse(ok)
    if OMDMonitorPanelBridgeIsAvailable() {
      let cfError = error?.takeRetainedValue()
      XCTAssertEqual(cfError.map(CFErrorGetCode), OMDMonitorPanelBridgeErrorCode.displayNotFound.rawValue)
    } else {
      error?.release()
    }
  }
}
