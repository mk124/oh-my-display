import Foundation
import XCTest

@testable import OMDCore

final class SetterContractTests: XCTestCase {
  func testDitheringInvalidSelectorReturnsBlockedResult() throws {
    let result = try DitheringService(resolver: MissingResolver()).setDithering(DisplaySelector("uuid:not-a-real-display"), enabled: false)

    XCTAssertEqual(result.status, .blocked)
    XCTAssertFalse(result.attemptedMutation)
  }

  func testDitheringUnexpectedResolverFailurePropagates() {
    XCTAssertThrowsError(try DitheringService(resolver: UnexpectedResolver()).setDithering(DisplaySelector("bad"), enabled: false)) { error in
      XCTAssertEqual(error as? DisplayControlError, .unexpected("CG failure"))
    }
  }

  func testICCInvalidSelectorReturnsBlockedResultBeforeFileCheck() throws {
    let result = try ICCProfileService(resolver: MissingResolver(), backend: FakeICCProfileBackend()).setICCProfile(
      DisplaySelector("uuid:not-a-real-display"), profileURL: URL(fileURLWithPath: "/definitely/not/readable.icc"))

    XCTAssertEqual(result.status, .blocked)
    XCTAssertFalse(result.attemptedMutation)
  }

  func testICCUnexpectedResolverFailurePropagates() {
    XCTAssertThrowsError(
      try ICCProfileService(resolver: UnexpectedResolver(), backend: FakeICCProfileBackend()).setICCProfile(
        DisplaySelector("bad"), profileURL: URL(fileURLWithPath: "/tmp/profile.icc"))
    ) { error in XCTAssertEqual(error as? DisplayControlError, .unexpected("CG failure")) }
  }
}

private struct MissingResolver: DisplayResolving {
  func resolve(_ selector: DisplaySelector) throws -> ResolvedDisplay { throw DisplayControlError.displayNotFound(selector.rawValue) }
}

private struct UnexpectedResolver: DisplayResolving {
  func resolve(_ selector: DisplaySelector) throws -> ResolvedDisplay { throw DisplayControlError.unexpected("CG failure") }
}
