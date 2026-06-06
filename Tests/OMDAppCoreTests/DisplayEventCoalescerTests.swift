import XCTest

@testable import OMDAppCore

final class DisplayEventCoalescerTests: XCTestCase {
  func testRecordsOnlyOnePendingTrigger() {
    var coalescer = DisplayEventCoalescer()

    coalescer.record(.displayChange)
    coalescer.record(.wake)

    XCTAssertEqual(coalescer.takePending(), .wake)
    XCTAssertNil(coalescer.takePending())
  }
}
