import Foundation
import XCTest

@testable import OMDAppCore

final class MutationTests: XCTestCase {
  func testMutationBaselineCapturesAndRestoresAllReadableAxes() throws {
    let fixture = try AppCoreFixture()
    let iccURL = URL(fileURLWithPath: "/Library/ColorSync/Profiles/Baseline.icc")
    var state = fixture.fake.states[fixture.display.selector]!
    state.iccProfileURL = .readable(iccURL)
    fixture.fake.states[fixture.display.selector] = state

    let baseline = try fixture.core.captureMutationBaseline(for: fixture.display.selector)
    fixture.fake.clearCalls()

    let result = try fixture.core.restore(baseline)

    XCTAssertTrue(result.succeeded)
    XCTAssertEqual(fixture.fake.setResolutionCalls, ["res-4k-120-hidpi"])
    XCTAssertEqual(fixture.fake.setDisplayModeCalls, ["mode-rgb-12"])
    XCTAssertEqual(fixture.fake.setDitheringCalls, [true])
    XCTAssertEqual(fixture.fake.setICCCalls, [iccURL])
  }

  func testRestoreStopsAfterResolutionRestoreFailure() throws {
    let fixture = try AppCoreFixture()
    let baseline = try fixture.core.captureMutationBaseline(for: fixture.display.selector)
    fixture.fake.clearCalls()
    fixture.fake.resolutionSetResult = .blocked("resolutionRestoreFailed")

    let result = try fixture.core.restore(baseline)

    XCTAssertFalse(result.succeeded)
    XCTAssertEqual(result.operations.map(\.operation), [.resolution])
    XCTAssertEqual(fixture.fake.setResolutionCalls, ["res-4k-120-hidpi"])
    XCTAssertTrue(fixture.fake.setDisplayModeCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setDitheringCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setICCCalls.isEmpty)
  }

  func testRestoreTreatsNoOpAsSuccessfulAndContinues() throws {
    let fixture = try AppCoreFixture()
    let baseline = try fixture.core.captureMutationBaseline(for: fixture.display.selector)
    fixture.fake.clearCalls()
    fixture.fake.resolutionSetResult = .noOp("same resolution")
    fixture.fake.displayModeSetResult = .noOp("same display mode")

    let result = try fixture.core.restore(baseline)

    XCTAssertTrue(result.succeeded)
    XCTAssertEqual(fixture.fake.setResolutionCalls, ["res-4k-120-hidpi"])
    XCTAssertEqual(fixture.fake.setDisplayModeCalls, ["mode-rgb-12"])
    XCTAssertEqual(fixture.fake.setDitheringCalls, [true])
    XCTAssertTrue(fixture.fake.setICCCalls.isEmpty)
  }

  func testRestoreHandlesDitheringAndICCFailures() throws {
    let iccURL = URL(fileURLWithPath: "/Library/ColorSync/Profiles/Baseline.icc")

    let ditheringFixture = try AppCoreFixture()
    var ditheringState = ditheringFixture.fake.states[ditheringFixture.display.selector]!
    ditheringState.iccProfileURL = .readable(iccURL)
    ditheringFixture.fake.states[ditheringFixture.display.selector] = ditheringState
    let ditheringBaseline = try ditheringFixture.core.captureMutationBaseline(
      for: ditheringFixture.display.selector)
    ditheringFixture.fake.clearCalls()
    ditheringFixture.fake.ditheringSetResult = .blocked("ditheringRestoreFailed")

    let ditheringResult = try ditheringFixture.core.restore(ditheringBaseline)

    XCTAssertFalse(ditheringResult.succeeded)
    XCTAssertEqual(ditheringResult.operations.map(\.operation), [.resolution, .displayMode, .dithering])
    XCTAssertTrue(ditheringFixture.fake.setICCCalls.isEmpty)

    let iccFixture = try AppCoreFixture()
    var iccState = iccFixture.fake.states[iccFixture.display.selector]!
    iccState.iccProfileURL = .readable(iccURL)
    iccFixture.fake.states[iccFixture.display.selector] = iccState
    let iccBaseline = try iccFixture.core.captureMutationBaseline(for: iccFixture.display.selector)
    iccFixture.fake.clearCalls()
    iccFixture.fake.iccSetResult = .failed(attemptedMutation: true, reason: "iccRestoreFailed")

    let iccResult = try iccFixture.core.restore(iccBaseline)

    XCTAssertFalse(iccResult.succeeded)
    XCTAssertEqual(iccResult.operations.map(\.operation), [.resolution, .displayMode, .dithering, .icc])
    XCTAssertEqual(iccFixture.fake.setICCCalls, [iccURL])
  }

  func testDisplayModeScopedRestoreDoesNotRestoreResolutionFirst() throws {
    let fixture = try AppCoreFixture()
    let baseline = try fixture.core.captureMutationBaseline(for: fixture.display.selector)
    fixture.fake.clearCalls()
    fixture.fake.resolutionSetResult = .blocked("staleResolution")

    let result = try fixture.core.restoreDisplayMode(baseline)

    XCTAssertTrue(result.succeeded)
    XCTAssertEqual(result.operations.map(\.operation), [.displayMode])
    XCTAssertTrue(fixture.fake.setResolutionCalls.isEmpty)
    XCTAssertEqual(fixture.fake.setDisplayModeCalls, ["mode-rgb-12"])
    XCTAssertTrue(fixture.fake.setDitheringCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setICCCalls.isEmpty)
  }

  func testEmptyBaselineReportsBlockedWithoutCallingSetters() throws {
    let fixture = try AppCoreFixture()
    let baseline = DisplayMutationBaseline(
      display: fixture.display.selector,
      resolutionModeID: nil,
      displayModeID: nil,
      ditheringEnabled: nil,
      iccProfileURL: nil)

    let result = try fixture.core.restore(baseline)

    XCTAssertFalse(result.succeeded)
    XCTAssertEqual(result.summary, "restore: blocked (emptyBaseline)")
    XCTAssertTrue(fixture.fake.setResolutionCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setDisplayModeCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setDitheringCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setICCCalls.isEmpty)
  }
}
