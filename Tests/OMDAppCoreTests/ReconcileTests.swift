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

    XCTAssertEqual(results.map(\.outcome), [.skipped(reason: .missingCurrentProfile, profileID: missingID)])
    XCTAssertEqual(document.displays[0].lastResult?.summary, "missingCurrentProfile")
  }

  func testReconcileTouchesNothingWhenStateAlreadyMatchesProfile() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    fixture.fake.clearCalls()

    let results = try fixture.core.reconcile(trigger: .startup)

    guard case .applied(_, let result)? = results.first?.outcome else {
      XCTFail("Expected applied reconcile outcome")
      return
    }
    XCTAssertTrue(result.succeeded)
    XCTAssertTrue(fixture.fake.setResolutionCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setDisplayModeCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setDitheringCalls.isEmpty)
    XCTAssertTrue(fixture.fake.setICCCalls.isEmpty)
    XCTAssertNil(attempts(fixture))
  }

  func testStartupReconcileAppliesCurrentProfileForStrongBinding() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    driftResolution(fixture)
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
    XCTAssertEqual(attempts(fixture), 1)
  }

  func testConfirmationAfterCorrectionResetsTheAttemptBudget() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    driftResolution(fixture)
    _ = try fixture.core.reconcile(trigger: .displayChange)
    XCTAssertEqual(attempts(fixture), 1)
    fixture.fake.clearCalls()

    // The correction landed (fake applied it); the echo event's pass confirms and resets.
    let results = try fixture.core.reconcile(trigger: .displayChange)

    guard case .applied(_, let result)? = results.first?.outcome else {
      XCTFail("Expected applied reconcile outcome")
      return
    }
    XCTAssertTrue(result.succeeded)
    XCTAssertTrue(fixture.fake.setResolutionCalls.isEmpty)
    XCTAssertNil(attempts(fixture))
  }

  func testReconcileRecordsFailedOutcomeWhenApplyThrows() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)
    driftResolution(fixture)
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
    XCTAssertNil(attempts(fixture))
  }

  func testReconcilePersistsLastResultWhenApplyReturnsBlocked() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    driftResolution(fixture)
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
    XCTAssertNil(attempts(fixture))
  }

  func testSteadyStateReconcileSkipsDisplayModeWhenHDRModeMismatches() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    driftResolution(fixture)
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
    driftResolution(fixture)
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
    driftResolution(fixture)
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

  func testEnforcementGivesUpAfterThreeBouncedCorrectionsAndTurnsCurrentOff() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)
    driftResolution(fixture)
    fixture.fake.resolutionSetUpdatesState = false
    fixture.fake.clearCalls()

    for attempt in 1...3 {
      let results = try fixture.core.reconcile(trigger: .displayChange)
      guard case .applied? = results.first?.outcome else {
        XCTFail("Attempt \(attempt) should correct")
        return
      }
      XCTAssertEqual(attempts(fixture), attempt)
    }
    XCTAssertEqual(fixture.fake.setResolutionCalls.count, 3)

    let fourth = try fixture.core.reconcile(trigger: .displayChange)
    let document = try ProfileStore(documentURL: fixture.documentURL).load()

    XCTAssertEqual(fourth.map(\.outcome), [.gaveUp(profileID: profile.id, currentOff: .succeeded)])
    XCTAssertEqual(fixture.fake.setResolutionCalls.count, 3)
    XCTAssertNil(document.displays[0].currentProfileID)
    XCTAssertNil(attempts(fixture))

    let fifth = try fixture.core.reconcile(trigger: .displayChange)
    XCTAssertEqual(fifth.map(\.outcome), [.skipped(reason: .off, profileID: nil)])
  }

  func testEnforcementSparesProfileWhenDisplaySettlesAfterThirdAttempt() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)
    driftResolution(fixture)
    fixture.fake.resolutionSetUpdatesState = false
    fixture.fake.clearCalls()
    for _ in 1...3 { _ = try fixture.core.reconcile(trigger: .displayChange) }
    XCTAssertEqual(attempts(fixture), 3)

    settle(fixture)
    let fourth = try fixture.core.reconcile(trigger: .displayChange)
    let document = try ProfileStore(documentURL: fixture.documentURL).load()

    guard case .applied(_, let result)? = fourth.first?.outcome else {
      XCTFail("Expected applied reconcile outcome")
      return
    }
    XCTAssertTrue(result.succeeded)
    XCTAssertEqual(fixture.fake.setResolutionCalls.count, 3)
    XCTAssertEqual(document.displays[0].currentProfileID, profile.id)
    XCTAssertNil(attempts(fixture))
  }

  func testBlockedCorrectionsDoNotConsumeTheAttemptBudget() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)
    driftResolution(fixture)
    fixture.fake.resolutionModes[fixture.display.selector] = .readable([])
    fixture.fake.clearCalls()

    for _ in 1...4 {
      let results = try fixture.core.reconcile(trigger: .displayChange)
      guard case .applied(_, let result)? = results.first?.outcome else {
        XCTFail("Expected a blocked apply outcome")
        return
      }
      XCTAssertFalse(result.succeeded)
      XCTAssertNil(attempts(fixture))
    }
    XCTAssertTrue(fixture.fake.setResolutionCalls.isEmpty)
    let document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertEqual(document.displays[0].currentProfileID, profile.id)
  }

  func testApplyThrowsDoNotConsumeTheAttemptBudget() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)
    driftResolution(fixture)
    fixture.fake.resolutionSetUpdatesState = false
    fixture.fake.displayModesError = FakeDisplayError("displayModesFailed")
    fixture.fake.clearCalls()

    for _ in 1...4 {
      let results = try fixture.core.reconcile(trigger: .startup)
      XCTAssertEqual(results.map(\.outcome), [.skipped(reason: .failed, profileID: profile.id)])
      XCTAssertNil(attempts(fixture))
    }
    let document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertEqual(document.displays[0].currentProfileID, profile.id)
  }

  // The live incident: a profile axis that can never satisfy nor apply (missing ICC
  // file) must not burn the budget and assassinate otherwise-working enforcement.
  func testUnappliableAxisDoesNotAssassinateWorkingEnforcement() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)
    var document = try ProfileStore(documentURL: fixture.documentURL).load()
    document.displays[0].profiles[0].intent.iccProfileURL = URL(string: "file:///missing.icc")
    try ProfileStore(documentURL: fixture.documentURL).save(document)
    let core = try OMDAppCore(client: fixture.fake, documentURL: fixture.documentURL)
    var state = fixture.fake.states[fixture.display.selector]!
    state.iccProfileURL = .readable(URL(string: "file:///other.icc")!)
    fixture.fake.states[fixture.display.selector] = state
    fixture.fake.iccSetResult = .blocked("ICC profile file is not readable")
    fixture.fake.clearCalls()

    // Steady-state events: never satisfied (ICC axis) but physically conformant -> no burn.
    for _ in 1...4 {
      let results = try core.reconcile(trigger: .displayChange)
      guard case .applied(_, let result)? = results.first?.outcome else {
        XCTFail("Expected applied reconcile outcome")
        return
      }
      XCTAssertFalse(result.succeeded)
      XCTAssertNil(core.enforcementAttempts[fixture.display.selector])
    }

    // Resolution enforcement still works alongside the broken axis, and confirms reset.
    driftResolution(fixture)
    _ = try core.reconcile(trigger: .displayChange)
    XCTAssertEqual(core.enforcementAttempts[fixture.display.selector], 1)
    _ = try core.reconcile(trigger: .displayChange)
    XCTAssertNil(core.enforcementAttempts[fixture.display.selector])
    document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertEqual(document.displays[0].currentProfileID, profile.id)
  }

  func testAttemptBudgetsAreIndependentPerDisplay() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    let second = DisplayTarget(selector: DisplaySelector("uuid:two"), displayID: 2, label: "Two", isMain: false, isBuiltin: false)
    fixture.fake.displays.append(second)
    fixture.fake.states[second.selector] = .state(target: second)
    fixture.fake.resolutionModes[second.selector] = fixture.fake.resolutionModes[fixture.display.selector]
    fixture.fake.displayModes[second.selector] = fixture.fake.displayModes[fixture.display.selector]
    _ = try fixture.core.addProfile(for: second.selector)
    driftResolution(fixture)
    fixture.fake.resolutionSetUpdatesState = false
    fixture.fake.clearCalls()

    _ = try fixture.core.reconcile(trigger: .displayChange)
    _ = try fixture.core.reconcile(trigger: .displayChange)

    XCTAssertEqual(fixture.core.enforcementAttempts[fixture.display.selector], 2)
    XCTAssertNil(fixture.core.enforcementAttempts[second.selector])
  }

  func testTurningCurrentOffResetsTheAttemptBudget() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    driftResolution(fixture)
    fixture.fake.resolutionSetUpdatesState = false
    for _ in 1...2 { _ = try fixture.core.reconcile(trigger: .displayChange) }
    XCTAssertEqual(attempts(fixture), 2)

    try fixture.core.setCurrentOff(for: fixture.display.selector)
    let results = try fixture.core.reconcile(trigger: .displayChange)

    XCTAssertEqual(results.map(\.outcome), [.skipped(reason: .off, profileID: nil)])
    XCTAssertNil(attempts(fixture))
  }

  func testUnreadableLockedAxisDoesNotDriveRetries() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    var state = fixture.fake.states[fixture.display.selector]!
    state.ditheringEnabled = .unreadable(source: "test")
    fixture.fake.states[fixture.display.selector] = state
    fixture.fake.clearCalls()

    let results = try fixture.core.reconcile(trigger: .displayChange)

    guard case .applied(_, let result)? = results.first?.outcome else {
      XCTFail("Expected applied reconcile outcome")
      return
    }
    XCTAssertTrue(result.succeeded)
    XCTAssertTrue(fixture.fake.setDitheringCalls.isEmpty)
    XCTAssertNil(attempts(fixture))
  }

  func testDisconnectClearsTheAttemptBudget() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    driftResolution(fixture)
    fixture.fake.resolutionSetUpdatesState = false
    for _ in 1...2 { _ = try fixture.core.reconcile(trigger: .displayChange) }
    XCTAssertEqual(attempts(fixture), 2)

    fixture.fake.displays = []
    _ = try fixture.core.reconcile(trigger: .displayChange)
    XCTAssertNil(attempts(fixture))

    fixture.fake.displays = [fixture.display]
    _ = try fixture.core.reconcile(trigger: .displayChange)
    XCTAssertEqual(attempts(fixture), 1)
  }

  func testHasEnforceableProfileIsFalseForEmptyDocument() throws {
    let fixture = try AppCoreFixture()

    XCTAssertFalse(fixture.core.hasEnforceableProfile)
  }

  func testHasEnforceableProfileIsFalseWhenCurrentOff() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    try fixture.core.setCurrentOff(for: fixture.display.selector)

    XCTAssertFalse(fixture.core.hasEnforceableProfile)
  }

  func testHasEnforceableProfileIsFalseForWeakBinding() throws {
    let fixture = try AppCoreFixture(selector: DisplaySelector("cg:1"))
    _ = try fixture.core.addProfile(for: fixture.display.selector)

    XCTAssertFalse(fixture.core.hasEnforceableProfile)
  }

  func testHasEnforceableProfileIsTrueForStrongBoundCurrentProfile() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)

    XCTAssertTrue(fixture.core.hasEnforceableProfile)
  }

  func testHasEnforceableProfileIsTrueWithMixedRecords() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    try fixture.core.setCurrentOff(for: fixture.display.selector)
    let strongTwo = DisplayTarget(selector: DisplaySelector("uuid:two"), displayID: 2, label: "Two", isMain: false, isBuiltin: false)
    fixture.core.document.displays.append(
      DisplayProfileRecord(binding: DisplayBinding(target: strongTwo), currentProfileID: UUID()))

    XCTAssertTrue(fixture.core.hasEnforceableProfile)
  }

  // Guards the `!= .startup` derivation: the new triggers must stay steady-state
  // so the HDR clamp keeps applying to them.
  func testMenuOpenAndHeartbeatTriggersAreSteadyState() {
    XCTAssertTrue(DisplayEventTrigger.menuOpen.isSteadyState)
    XCTAssertTrue(DisplayEventTrigger.heartbeat.isSteadyState)
  }

  // Guards the integration, not just the property: reconcile driven by the new
  // triggers must run the HDR clamp end to end.
  func testMenuOpenAndHeartbeatReconcileSkipDisplayModeWhenHDRModeMismatches() throws {
    for trigger in [DisplayEventTrigger.menuOpen, .heartbeat] {
      let fixture = try AppCoreFixture()
      _ = try fixture.core.addProfile(for: fixture.display.selector)
      driftResolution(fixture)
      var state = fixture.fake.states[fixture.display.selector]!
      state.hdrMode = .readable(.sdr)
      fixture.fake.states[fixture.display.selector] = state
      fixture.fake.clearCalls()

      let results = try fixture.core.reconcile(trigger: trigger)

      guard case .applied(_, let result)? = results.first?.outcome else {
        XCTFail("Expected applied reconcile outcome for \(trigger)")
        continue
      }
      XCTAssertTrue(result.succeeded, "\(trigger)")
      XCTAssertTrue(fixture.fake.setDisplayModeCalls.isEmpty, "\(trigger)")
    }
  }

  // The locked ICC and the live ColorSync URL can name the same file in different
  // forms; intentSatisfied must treat that as satisfied, not drive a correction.
  func testReconcileTreatsSameFileICCUnderDifferentURLFormAsSatisfied() throws {
    let fixture = try AppCoreFixture()
    var state = fixture.fake.states[fixture.display.selector]!
    state.iccProfileURL = .readable(URL(fileURLWithPath: "/private/tmp/x.icc"))
    fixture.fake.states[fixture.display.selector] = state
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    state.iccProfileURL = .readable(URL(fileURLWithPath: "/private/tmp/sub/../x.icc"))
    fixture.fake.states[fixture.display.selector] = state
    fixture.fake.clearCalls()

    let results = try fixture.core.reconcile(trigger: .displayChange)

    XCTAssertTrue(fixture.fake.setICCCalls.isEmpty)
    guard case .applied(_, let result)? = results.first?.outcome else {
      XCTFail("Expected applied outcome")
      return
    }
    XCTAssertTrue(result.operations.allSatisfy { !$0.result.attemptedMutation })
  }

  // Simulates an external change: the display drifts off the profile's resolution.
  private func driftResolution(_ fixture: AppCoreFixture) {
    var state = fixture.fake.states[fixture.display.selector]!
    state.currentResolutionModeID = .readable(ResolutionModeID("res-drifted"))
    state.logicalResolution = .readable(DisplaySize(width: 1024, height: 768))
    fixture.fake.states[fixture.display.selector] = state
  }

  // Simulates the display settling onto the profile's mode on its own.
  private func settle(_ fixture: AppCoreFixture) {
    fixture.fake.states[fixture.display.selector] = .state(target: fixture.display)
  }

  private func attempts(_ fixture: AppCoreFixture) -> Int? {
    fixture.core.enforcementAttempts[fixture.display.selector]
  }
}
