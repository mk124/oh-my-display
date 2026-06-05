import Foundation
import OMDCore
import XCTest

@testable import OMDAppCore

final class ProfileTests: XCTestCase {
  func testAddProfileCapturesCurrentStateAndUsesComputedTechnicalLabel() throws {
    let fixture = try AppCoreFixture()

    let profile = try fixture.core.addProfile(for: fixture.display.selector)

    XCTAssertNil(profile.customName)
    XCTAssertTrue(profile.isVerified)
    XCTAssertEqual(profile.label, "#1 [HDR10] 4K 120Hz RGB 12-bit")
    XCTAssertEqual(profile.intent.displayMode?.encoding, .rgb)
    XCTAssertEqual(profile.intent.displayMode?.hdrMode, .hdr10)

    var changedProfile = profile
    changedProfile.intent.displayMode?.bitDepth = 10
    XCTAssertEqual(changedProfile.label, "#1 [HDR10] 4K 120Hz RGB 10-bit")

    let json = try String(contentsOf: fixture.documentURL, encoding: .utf8)
    XCTAssertFalse(json.contains("[HDR10]"))
    XCTAssertFalse(json.contains("4K 120Hz RGB 12-bit"))
  }

  func testEmptyStoreMenuShowsOffAndNoCurrentProfileActions() throws {
    let fixture = try AppCoreFixture()

    let menu = try fixture.core.menuState()
    let display = try XCTUnwrap(menu.displays.first)

    XCTAssertEqual(display.title, "One")
    XCTAssertEqual(display.currentTitle, "Current: Off")
    XCTAssertEqual(display.currentItems.map(\.title), ["Off"])
    XCTAssertTrue(display.currentItems[0].isSelected)
    XCTAssertTrue(display.profileItems.isEmpty)
  }

  func testMenuStateSortsMainDisplayFirst() throws {
    let fixture = try AppCoreFixture()
    let secondary = DisplayTarget(
      selector: DisplaySelector("uuid:secondary"),
      displayID: 2,
      label: "Secondary",
      isMain: false,
      isBuiltin: false
    )
    let main = DisplayTarget(
      selector: DisplaySelector("uuid:main"),
      displayID: 3,
      label: "Main",
      isMain: true,
      isBuiltin: false
    )
    fixture.fake.displays = [secondary, main]
    fixture.fake.states[secondary.selector] = .state(target: secondary)
    fixture.fake.states[main.selector] = .state(target: main)

    let menu = try fixture.core.menuState()

    XCTAssertEqual(menu.displays.map(\.title), ["Main", "Secondary"])
  }

  func testMenuStateOnlySelectsReadableCurrentModeIDs() throws {
    let fixture = try AppCoreFixture()
    var state = fixture.fake.states[fixture.display.selector]!
    state.currentResolutionModeID = .unreadable(source: "missing")
    state.currentDisplayModeID = .unreadable(source: "missing")
    fixture.fake.states[fixture.display.selector] = state

    let display = try XCTUnwrap(fixture.core.menuState().displays.first)

    XCTAssertFalse(display.resolutionItems.contains { $0.isSelected })
    XCTAssertFalse(display.displayModeItems.contains { $0.isSelected })
  }

  func testCustomProfileNameHidesTechnicalSummaryInMenus() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)

    try fixture.core.renameProfile(profile.id, for: fixture.display.selector, to: "My HDR Profile")

    let display = try XCTUnwrap(fixture.core.menuState().displays.first)
    XCTAssertEqual(display.title, "One")
    XCTAssertEqual(display.currentTitle, "Current: #1 My HDR Profile")
    XCTAssertEqual(display.currentItems.map(\.title), ["Off", "#1 My HDR Profile"])
    XCTAssertEqual(display.profileItems.map(\.title), ["#1 My HDR Profile"])
    XCTAssertFalse(display.currentTitle.contains("HDR10"))
  }

  func testProfilesCanBeManagedWithoutSelectingThem() throws {
    let fixture = try AppCoreFixture()
    let first = try fixture.core.addProfile(for: fixture.display.selector)
    let second = try fixture.core.addProfile(for: fixture.display.selector)

    try fixture.core.renameProfile(first.id, for: fixture.display.selector, to: "First")
    var document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertEqual(document.displays[0].currentProfileID, second.id)
    XCTAssertEqual(document.displays[0].profiles.first { $0.id == first.id }?.customName, "First")

    try fixture.core.deleteProfile(first.id, for: fixture.display.selector)
    document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertEqual(document.displays[0].profiles.map(\.id), [second.id])
    XCTAssertEqual(document.displays[0].currentProfileID, second.id)

    try fixture.core.deleteProfile(second.id, for: fixture.display.selector)
    document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertTrue(document.displays[0].profiles.isEmpty)
    XCTAssertNil(document.displays[0].currentProfileID)
  }

  func testDisplayModeMenuOnlyListsCurrentResolutionCandidates() throws {
    let fixture = try AppCoreFixture()
    var state = fixture.fake.states[fixture.display.selector]!
    state.resolutionRefreshHz = .readable(60)
    state.outputTimingRefreshHz = .readable(60)
    fixture.fake.states[fixture.display.selector] = state
    fixture.fake.displayModes[fixture.display.selector] = .readable([
      .mode(
        id: "mode-4k-60-rgb10",
        timing: DisplaySize(width: 3840, height: 2160),
        refresh: 60,
        bitDepth: 10),
      .mode(
        id: "mode-4k-120-rgb10",
        timing: DisplaySize(width: 3840, height: 2160),
        refresh: 120,
        bitDepth: 10),
      .mode(
        id: "mode-1080-60-rgb10",
        timing: DisplaySize(width: 1920, height: 1080),
        refresh: 60,
        bitDepth: 10),
    ])

    let display = try XCTUnwrap(fixture.core.menuState().displays.first)

    XCTAssertEqual(display.displayModeItems.map { $0.id.rawValue }, ["mode-4k-60-rgb10"])
  }

  func testDirectDisplayModeSettingPersistsOnlyWhenCurrentProfileIsOn() throws {
    let fixture = try AppCoreFixture()
    fixture.fake.displayModes[fixture.display.selector] = .readable([
      .mode(id: "mode-rgb-12", bitDepth: 12),
      .mode(id: "mode-rgb-10", bitDepth: 10),
    ])
    _ = try fixture.core.addProfile(for: fixture.display.selector)

    _ = try fixture.core.setDisplayMode(DisplayModeID("mode-rgb-10"), for: fixture.display.selector)
    var document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertEqual(document.displays[0].profiles[0].intent.displayMode?.bitDepth, 10)

    try fixture.core.setCurrentOff(for: fixture.display.selector)
    _ = try fixture.core.setDisplayMode(DisplayModeID("mode-rgb-12"), for: fixture.display.selector)
    document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertEqual(document.displays[0].profiles[0].intent.displayMode?.bitDepth, 10)
  }

  func testRiskyDisplayModeSettingCanDeferProfilePersistenceUntilKeep() throws {
    let fixture = try AppCoreFixture()
    fixture.fake.displayModes[fixture.display.selector] = .readable([
      .mode(id: "mode-rgb-12", bitDepth: 12),
      .mode(id: "mode-rgb-10", bitDepth: 10),
    ])
    _ = try fixture.core.addProfile(for: fixture.display.selector)

    _ = try fixture.core.setDisplayMode(
      DisplayModeID("mode-rgb-10"),
      for: fixture.display.selector,
      persistToCurrentProfile: false)
    var document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertEqual(document.displays[0].profiles[0].intent.displayMode?.bitDepth, 12)

    try fixture.core.refreshCurrentProfileDisplayMode(for: fixture.display.selector)
    document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertEqual(document.displays[0].profiles[0].intent.displayMode?.bitDepth, 10)
  }

  func testResolutionSettingRefreshesDependentDisplayModeTimingInCurrentProfile() throws {
    let fixture = try AppCoreFixture()
    fixture.fake.resolutionModes[fixture.display.selector] = .readable([
      ResolutionMode(
        id: ResolutionModeID("res-4k-120-hidpi"),
        logicalResolution: DisplaySize(width: 1920, height: 1080),
        backingResolution: DisplaySize(width: 3840, height: 2160),
        scaleFactor: 2,
        isHiDPI: true,
        refreshHz: 120),
      ResolutionMode(
        id: ResolutionModeID("res-1080-60-lodpi"),
        logicalResolution: DisplaySize(width: 1920, height: 1080),
        backingResolution: DisplaySize(width: 1920, height: 1080),
        scaleFactor: 1,
        isHiDPI: false,
        refreshHz: 60),
    ])
    _ = try fixture.core.addProfile(for: fixture.display.selector)

    _ = try fixture.core.setResolutionMode(
      ResolutionModeID("res-1080-60-lodpi"),
      for: fixture.display.selector)

    let document = try ProfileStore(documentURL: fixture.documentURL).load()
    let intent = document.displays[0].profiles[0].intent
    XCTAssertEqual(intent.resolution?.backingResolution, DisplaySize(width: 1920, height: 1080))
    XCTAssertEqual(intent.displayMode?.outputTimingResolution, DisplaySize(width: 1920, height: 1080))
    XCTAssertEqual(intent.displayMode?.outputTimingRefreshHz, 60)
  }

  func testApplyProfileDoesNotChangeCurrentUntilCommitted() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)
    try fixture.core.setCurrentOff(for: fixture.display.selector)

    let result = try fixture.core.applyProfile(profile.id, for: fixture.display.selector)
    var document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertTrue(result.succeeded)
    XCTAssertNil(document.displays[0].currentProfileID)

    try fixture.core.setCurrentProfile(profile.id, for: fixture.display.selector)
    document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertEqual(document.displays[0].currentProfileID, profile.id)
  }

  func testApplyProfileDoesNotVerifyUntilSelectionIsCommitted() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)
    try setProfileVerification(false, profileID: profile.id, in: fixture)
    try fixture.core.setCurrentOff(for: fixture.display.selector)

    let result = try fixture.core.applyProfile(profile.id, for: fixture.display.selector)
    XCTAssertTrue(result.succeeded)
    XCTAssertFalse(try storedProfile(profile.id, in: fixture).isVerified)

    try fixture.core.commitProfileSelection(profile.id, for: fixture.display.selector)
    XCTAssertTrue(try storedProfile(profile.id, in: fixture).isVerified)
  }

  func testFailedProfileSelectionDoesNotChangeCurrentProfile() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)
    try fixture.core.setCurrentOff(for: fixture.display.selector)
    fixture.fake.displayModeSetResult = .blocked("displayModeUnavailable")

    let result = try fixture.core.selectProfile(profile.id, for: fixture.display.selector)
    let document = try ProfileStore(documentURL: fixture.documentURL).load()

    XCTAssertFalse(result.succeeded)
    XCTAssertNil(document.displays[0].currentProfileID)
    XCTAssertTrue(document.displays[0].lastResult?.summary.contains("displayModeUnavailable") == true)
    XCTAssertEqual(fixture.fake.setDitheringCalls, [])
    XCTAssertEqual(fixture.fake.setICCCalls, [])
  }

  func testProfileNeedsConfirmationIgnoresSafeDitheringAndICC() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)
    try setProfileVerification(false, profileID: profile.id, in: fixture)

    var state = fixture.fake.states[fixture.display.selector]!
    state.ditheringEnabled = .readable(false)
    state.iccProfileURL = .readable(URL(fileURLWithPath: "/Library/ColorSync/Profiles/Other.icc"))
    fixture.fake.states[fixture.display.selector] = state

    XCTAssertFalse(try fixture.core.profileNeedsConfirmation(profile.id, for: fixture.display.selector))

    let sourceURL = URL(fileURLWithPath: "/Library/ColorSync/Profiles/Profile.icc")
    state.iccProfileURL = .readable(sourceURL)
    fixture.fake.states[fixture.display.selector] = state
    let iccProfile = try fixture.core.addProfile(for: fixture.display.selector)
    try setProfileVerification(false, profileID: iccProfile.id, in: fixture)
    XCTAssertEqual(iccProfile.intent.iccProfileURL, sourceURL)

    state.iccProfileURL = .unreadable(source: "missing")
    fixture.fake.states[fixture.display.selector] = state

    XCTAssertFalse(try fixture.core.profileNeedsConfirmation(iccProfile.id, for: fixture.display.selector))
  }

  func testProfileNeedsConfirmationCoversResolutionAndDisplayModeIDs() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)
    try setProfileVerification(false, profileID: profile.id, in: fixture)

    XCTAssertFalse(try fixture.core.profileNeedsConfirmation(profile.id, for: fixture.display.selector))

    var state = fixture.fake.states[fixture.display.selector]!
    state.currentResolutionModeID = .readable(ResolutionModeID("other-resolution"))
    fixture.fake.states[fixture.display.selector] = state
    XCTAssertTrue(try fixture.core.profileNeedsConfirmation(profile.id, for: fixture.display.selector))

    state.currentResolutionModeID = .unreadable(source: "missing")
    fixture.fake.states[fixture.display.selector] = state
    XCTAssertTrue(try fixture.core.profileNeedsConfirmation(profile.id, for: fixture.display.selector))

    state.currentResolutionModeID = .readable(ResolutionModeID("res-4k-120-hidpi"))
    state.currentDisplayModeID = .readable(DisplayModeID("other-mode"))
    fixture.fake.states[fixture.display.selector] = state
    XCTAssertTrue(try fixture.core.profileNeedsConfirmation(profile.id, for: fixture.display.selector))

    state.currentDisplayModeID = .unreadable(source: "missing")
    fixture.fake.states[fixture.display.selector] = state
    XCTAssertTrue(try fixture.core.profileNeedsConfirmation(profile.id, for: fixture.display.selector))

    state.currentDisplayModeID = .readable(DisplayModeID("mode-rgb-12"))
    fixture.fake.states[fixture.display.selector] = state
    XCTAssertFalse(try fixture.core.profileNeedsConfirmation(profile.id, for: fixture.display.selector))
  }

  func testProfileNeedsConfirmationWhenTargetModeCannotBeResolved() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)
    try setProfileVerification(false, profileID: profile.id, in: fixture)
    let resolutionModes = fixture.fake.resolutionModes[fixture.display.selector]!

    fixture.fake.resolutionModes[fixture.display.selector] = .readable([])
    XCTAssertTrue(try fixture.core.profileNeedsConfirmation(profile.id, for: fixture.display.selector))

    fixture.fake.resolutionModes[fixture.display.selector] = resolutionModes
    fixture.fake.displayModes[fixture.display.selector] = .readable([])
    XCTAssertTrue(try fixture.core.profileNeedsConfirmation(profile.id, for: fixture.display.selector))
  }

  func testVerifiedProfileSkipsConfirmationWhenCurrentStateDiffers() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)

    var state = fixture.fake.states[fixture.display.selector]!
    state.currentResolutionModeID = .readable(ResolutionModeID("other-resolution"))
    state.currentDisplayModeID = .readable(DisplayModeID("other-mode"))
    state.ditheringEnabled = .readable(false)
    state.iccProfileURL = .unreadable(source: "missing")
    fixture.fake.states[fixture.display.selector] = state

    XCTAssertFalse(try fixture.core.profileNeedsConfirmation(profile.id, for: fixture.display.selector))
  }

  func testProfileBaselineRestoreGateRequiresOnlyProfileAxes() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)
    let baseline = try fixture.core.captureMutationBaseline(for: fixture.display.selector)

    XCTAssertTrue(
      try fixture.core.baseline(
        baseline,
        canRestoreProfile: profile.id,
        for: fixture.display.selector))

    var missingResolution = baseline
    missingResolution.resolutionModeID = nil
    XCTAssertFalse(
      try fixture.core.baseline(
        missingResolution,
        canRestoreProfile: profile.id,
        for: fixture.display.selector))

    var missingDisplayMode = baseline
    missingDisplayMode.displayModeID = nil
    XCTAssertFalse(
      try fixture.core.baseline(
        missingDisplayMode,
        canRestoreProfile: profile.id,
        for: fixture.display.selector))

    var missingDithering = baseline
    missingDithering.ditheringEnabled = nil
    XCTAssertFalse(
      try fixture.core.baseline(
        missingDithering,
        canRestoreProfile: profile.id,
        for: fixture.display.selector))

    var missingUnusedICC = baseline
    missingUnusedICC.iccProfileURL = nil
    XCTAssertTrue(
      try fixture.core.baseline(
        missingUnusedICC,
        canRestoreProfile: profile.id,
        for: fixture.display.selector))

    let sourceURL = URL(fileURLWithPath: "/Library/ColorSync/Profiles/Profile With ICC.icc")
    var state = fixture.fake.states[fixture.display.selector]!
    state.iccProfileURL = .readable(sourceURL)
    fixture.fake.states[fixture.display.selector] = state
    let iccProfile = try fixture.core.addProfile(for: fixture.display.selector)
    let iccBaseline = try fixture.core.captureMutationBaseline(for: fixture.display.selector)

    XCTAssertTrue(
      try fixture.core.baseline(
        iccBaseline,
        canRestoreProfile: iccProfile.id,
        for: fixture.display.selector))

    var missingICC = iccBaseline
    missingICC.iccProfileURL = nil
    XCTAssertFalse(
      try fixture.core.baseline(
        missingICC,
        canRestoreProfile: iccProfile.id,
        for: fixture.display.selector))
  }

  private func storedProfile(_ profileID: UUID, in fixture: AppCoreFixture) throws
    -> DisplayProfile
  {
    try fixture.core.profile(profileID, for: fixture.display.selector)
  }

  private func setProfileVerification(
    _ isVerified: Bool,
    profileID: UUID,
    in fixture: AppCoreFixture
  ) throws {
    let recordIndex = try XCTUnwrap(
      fixture.core.document.displays.firstIndex {
        $0.binding.selector == fixture.display.selector
      })
    let profileIndex = try XCTUnwrap(
      fixture.core.document.displays[recordIndex].profiles.firstIndex {
        $0.id == profileID
      })
    fixture.core.document.displays[recordIndex].profiles[profileIndex].isVerified = isVerified
  }
}
