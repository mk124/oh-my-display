import Foundation
import OMDCore
import XCTest

@testable import OMDAppCore

final class ReconcileTests: XCTestCase {
  func testReconcileSkipsDisplaysWithCurrentOff() throws {
    let fixture = try AppCoreFixture()

    let results = try fixture.core.reconcile(trigger: .startup)

    XCTAssertEqual(results.map(\.outcome), [.skipped(reason: .off, profileID: nil)])
    XCTAssertTrue(fixture.fake.setResolutionCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setDisplayModeCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setDitheringCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setICCCalls.isEmpty)
  }

  func testReconcileSkipsWeakDisplayBindings() throws {
    let fixture = try AppCoreFixture(selector: DisplaySelector("cg:1"))
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    fixture.fake.clearCalls()

    let results = try fixture.core.reconcile(trigger: .startup)

    XCTAssertEqual(results.map(\.outcome), [.skipped(reason: .weakBinding, profileID: nil)])
    XCTAssertTrue(fixture.fake.setResolutionCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setDisplayModeCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setDitheringCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setICCCalls.isEmpty)
  }

  func testReconcileRecordsMissingCurrentProfile() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    let missingID = UUID()
    var document = try ProfileStore(documentURL: fixture.documentURL).load()
    document.displays[0].currentProfileID = missingID
    try ProfileStore(documentURL: fixture.documentURL).save(document)
    let core = try OMDAppCore(client: fixture.fake, documentURL: fixture.documentURL)

    let results = try core.reconcile(trigger: .startup)
    document = try ProfileStore(documentURL: fixture.documentURL).load()

    XCTAssertEqual(
      results.map(\.outcome),
      [.skipped(reason: .missingCurrentProfile, profileID: missingID)])
    XCTAssertEqual(document.displays[0].lastResult?.summary, "missingCurrentProfile")
  }

  func testReconcileRecordsFailedOutcomeWhenApplyThrows() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)
    fixture.fake.displayModesError = FakeDisplayError("displayModesFailed")
    fixture.fake.clearCalls()

    let results = try fixture.core.reconcile(trigger: .startup)
    let document = try ProfileStore(documentURL: fixture.documentURL).load()

    XCTAssertEqual(results.map(\.outcome), [.skipped(reason: .failed, profileID: profile.id)])
    XCTAssertTrue(document.displays[0].lastResult?.summary.contains("displayModesFailed") == true)
    XCTAssertEqual(fixture.fake.setResolutionCalls, ["res-4k-120-hidpi"])
    XCTAssertTrue(fixture.fake.setDisplayModeCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setDitheringCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setICCCalls.isEmpty)
  }

  func testReconcilePersistsLastResultWhenApplyReturnsBlocked() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    fixture.fake.resolutionSetResult = .blocked("resolutionBlocked")
    fixture.fake.clearCalls()

    let results = try fixture.core.reconcile(trigger: .startup)
    let document = try ProfileStore(documentURL: fixture.documentURL).load()

    guard case .applied(_, let result)? = results.first?.outcome else {
      XCTFail("Expected applied reconcile outcome")
      return
    }
    XCTAssertFalse(result.succeeded)
    XCTAssertTrue(document.displays[0].lastResult?.summary.contains("resolutionBlocked") == true)
    XCTAssertEqual(fixture.fake.setResolutionCalls, ["res-4k-120-hidpi"])
    XCTAssertTrue(fixture.fake.setDisplayModeCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setDitheringCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setICCCalls.isEmpty)
  }

  func testStartupReconcileAppliesCurrentProfileForStrongBinding() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    fixture.fake.clearCalls()

    let results = try fixture.core.reconcile(trigger: .startup)

    guard case .applied(_, let result)? = results.first?.outcome else {
      XCTFail("Expected applied reconcile outcome")
      return
    }
    XCTAssertTrue(result.succeeded)
    XCTAssertEqual(fixture.fake.setResolutionCalls, ["res-4k-120-hidpi"])
    XCTAssertEqual(fixture.fake.setDisplayModeCalls, ["mode-rgb-12"])
    XCTAssertEqual(fixture.fake.setDitheringCalls, [true])
    XCTAssertTrue(fixture.fake.setICCCalls.isEmpty)
  }

  func testSteadyStateReconcileSkipsDisplayModeWhenHDRModeMismatches() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    var state = fixture.fake.states[fixture.display.selector]!
    state.hdrMode = .readable(.sdr)
    fixture.fake.states[fixture.display.selector] = state
    fixture.fake.clearCalls()

    let results = try fixture.core.reconcile(trigger: .displayChange)

    guard case .applied(_, let result)? = results.first?.outcome else {
      XCTFail("Expected applied reconcile outcome")
      return
    }
    XCTAssertTrue(result.succeeded)
    XCTAssertEqual(fixture.fake.setResolutionCalls, ["res-4k-120-hidpi"])
    XCTAssertTrue(fixture.fake.setDisplayModeCalls.isEmpty)
    XCTAssertEqual(fixture.fake.setDitheringCalls, [true])
    XCTAssertTrue(fixture.fake.setICCCalls.isEmpty)
  }

  func testSteadyStateReconcileSkipsDisplayModeWhenHDRModeIsUnreadable() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    var state = fixture.fake.states[fixture.display.selector]!
    state.hdrMode = .unreadable(source: "missing")
    fixture.fake.states[fixture.display.selector] = state
    fixture.fake.clearCalls()

    let results = try fixture.core.reconcile(trigger: .displayChange)

    guard case .applied(_, let result)? = results.first?.outcome else {
      XCTFail("Expected applied reconcile outcome")
      return
    }
    XCTAssertTrue(result.succeeded)
    XCTAssertEqual(fixture.fake.setResolutionCalls, ["res-4k-120-hidpi"])
    XCTAssertTrue(fixture.fake.setDisplayModeCalls.isEmpty)
    XCTAssertEqual(fixture.fake.setDitheringCalls, [true])
    XCTAssertTrue(fixture.fake.setICCCalls.isEmpty)
  }

  func testSteadyStateReconcileSkipsDisplayModeWhenProfileHDRModeIsUnknown() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    var document = try ProfileStore(documentURL: fixture.documentURL).load()
    document.displays[0].profiles[0].intent.displayMode?.hdrMode = nil
    try ProfileStore(documentURL: fixture.documentURL).save(document)
    let core = try OMDAppCore(client: fixture.fake, documentURL: fixture.documentURL)
    fixture.fake.clearCalls()

    let results = try core.reconcile(trigger: .displayChange)

    guard case .applied(_, let result)? = results.first?.outcome else {
      XCTFail("Expected applied reconcile outcome")
      return
    }
    XCTAssertTrue(result.succeeded)
    XCTAssertEqual(fixture.fake.setResolutionCalls, ["res-4k-120-hidpi"])
    XCTAssertTrue(fixture.fake.setDisplayModeCalls.isEmpty)
    XCTAssertEqual(fixture.fake.setDitheringCalls, [true])
    XCTAssertTrue(fixture.fake.setICCCalls.isEmpty)
  }
}
