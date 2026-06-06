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
    XCTAssertEqual(display.currentTitle, "Profile: Off")
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

  func testMenuStateOnlySelectsReadableCurrentValues() throws {
    let fixture = try AppCoreFixture()
    var state = fixture.fake.states[fixture.display.selector]!
    state.currentResolutionModeID = .unreadable(source: "missing")
    state.logicalResolution = .unreadable(source: "missing")
    state.isHiDPI = .unreadable(source: "missing")
    state.resolutionRefreshHz = .unreadable(source: "missing")
    state.currentDisplayModeID = .unreadable(source: "missing")
    fixture.fake.states[fixture.display.selector] = state

    let display = try XCTUnwrap(fixture.core.menuState().displays.first)

    XCTAssertFalse(display.resolutionItems.isEmpty)
    XCTAssertFalse(display.resolutionItems.contains { $0.isSelected })
    XCTAssertTrue(display.hidpiItems.isEmpty)
    XCTAssertTrue(display.refreshRateItems.isEmpty)
    XCTAssertFalse(display.displayModeItems.contains { $0.isSelected })
  }

  func testMenuStateSelectsFacetsByValuesWhenCurrentIDIsOrphan() throws {
    let fixture = try AppCoreFixture()
    var state = fixture.fake.states[fixture.display.selector]!
    state.currentResolutionModeID = .readable(ResolutionModeID("orphan-suffix-2"))
    fixture.fake.states[fixture.display.selector] = state

    let display = try XCTUnwrap(fixture.core.menuState().displays.first)

    XCTAssertEqual(display.resolutionItems.filter(\.isSelected).map(\.title), ["1920x1080"])
    XCTAssertEqual(display.hidpiItems.filter(\.isSelected).map(\.title), ["On"])
    XCTAssertEqual(display.refreshRateItems.filter(\.isSelected).map(\.title), ["120Hz"])
  }

  func testMenuStateFacetListsFollowDegradationMatrix() throws {
    let fixture = try AppCoreFixture()
    fixture.fake.resolutionModes[fixture.display.selector] = .readable([
      mode("res-4k-120-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 120),
      mode("res-1080-60-lodpi", logical: (1920, 1080), backing: (1920, 1080), hidpi: false, hz: 60),
    ])

    var display = try XCTUnwrap(fixture.core.menuState().displays.first)
    XCTAssertEqual(display.resolutionItems.map(\.title), ["1920x1080"])
    XCTAssertEqual(display.hidpiItems.map(\.isEnabled), [true, true])
    XCTAssertEqual(display.refreshRateItems.map(\.title), ["120Hz"])

    fixture.fake.resolutionModes[fixture.display.selector] = .readable([
      mode("res-4k-nil-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: nil)
    ])

    display = try XCTUnwrap(fixture.core.menuState().displays.first)
    XCTAssertEqual(display.resolutionItems.map(\.title), ["1920x1080"])
    XCTAssertEqual(display.hidpiItems.map(\.isEnabled), [true, false])
    XCTAssertTrue(display.refreshRateItems.isEmpty)

    fixture.fake.resolutionModes[fixture.display.selector] = .readable([])

    display = try XCTUnwrap(fixture.core.menuState().displays.first)
    XCTAssertTrue(display.resolutionItems.isEmpty)
    XCTAssertTrue(display.hidpiItems.isEmpty)
    XCTAssertTrue(display.refreshRateItems.isEmpty)
  }

  func testDirectResolutionSettingPersistsOnlyWhenCurrentProfileIsOn() throws {
    let fixture = try AppCoreFixture()
    fixture.fake.resolutionModes[fixture.display.selector] = .readable([
      mode("res-4k-120-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 120),
      mode("res-1080-60-lodpi", logical: (1920, 1080), backing: (1920, 1080), hidpi: false, hz: 60),
    ])
    _ = try fixture.core.addProfile(for: fixture.display.selector)

    _ = try fixture.core.setResolutionMode(
      ResolutionModeID("res-1080-60-lodpi"),
      for: fixture.display.selector)
    var document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertEqual(document.displays[0].profiles[0].intent.resolution?.isHiDPI, false)

    try fixture.core.setCurrentOff(for: fixture.display.selector)
    _ = try fixture.core.setResolutionMode(
      ResolutionModeID("res-4k-120-hidpi"),
      for: fixture.display.selector)
    document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertEqual(document.displays[0].profiles[0].intent.resolution?.isHiDPI, false)
  }

  func testCustomProfileNameHidesTechnicalSummaryInMenus() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)

    try fixture.core.renameProfile(profile.id, for: fixture.display.selector, to: "My HDR Profile")

    let display = try XCTUnwrap(fixture.core.menuState().displays.first)
    XCTAssertEqual(display.title, "One")
    XCTAssertEqual(display.currentTitle, "Profile: #1 My HDR Profile")
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
    XCTAssertEqual(display.displayModeItems.map(\.title), ["HDR10 RGB 10-bit full"])
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
      mode("res-4k-120-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 120),
      mode("res-1080-60-lodpi", logical: (1920, 1080), backing: (1920, 1080), hidpi: false, hz: 60),
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

  func testDitheringMenuStateUsesReadabilityAndAvailability() throws {
    let fixture = try AppCoreFixture()
    var state = fixture.fake.states[fixture.display.selector]!
    state.ditheringEnabled = .unreadable(source: "missing")
    fixture.fake.states[fixture.display.selector] = state

    var display = try XCTUnwrap(fixture.core.menuState().displays.first)

    XCTAssertEqual(display.ditheringItems.map(\.title), ["Off", "On"])
    XCTAssertFalse(display.ditheringItems.contains { $0.isSelected })
    XCTAssertTrue(display.isDitheringEnabled)

    state.ditheringAvailability = .noMatchingActiveFramebuffer
    fixture.fake.states[fixture.display.selector] = state

    display = try XCTUnwrap(fixture.core.menuState().displays.first)

    XCTAssertFalse(display.isDitheringEnabled)
  }

  func testICCMenuStateHandlesSelectionUnavailableAndDuplicateTitles() throws {
    let fixture = try AppCoreFixture()
    let first = URL(fileURLWithPath: "/Library/ColorSync/Profiles/Display.icc")
    let second = URL(fileURLWithPath: "/Users/me/Display.icc")
    fixture.fake.appICCProfiles = [
      ICCProfile(name: "Display", url: first),
      ICCProfile(name: "Display", url: second),
    ]
    var state = fixture.fake.states[fixture.display.selector]!
    state.iccProfileURL = .readable(second)
    fixture.fake.states[fixture.display.selector] = state

    var display = try XCTUnwrap(fixture.core.menuState().displays.first)

    XCTAssertEqual(display.iccProfileItems.count, 2)
    XCTAssertTrue(display.iccProfileItems.contains { $0.title == "Display (Display.icc) #1" })
    XCTAssertTrue(display.iccProfileItems.contains { $0.title == "Display (Display.icc) #2" })
    XCTAssertEqual(display.iccProfileItems.filter(\.isSelected).map(\.url), [second])

    fixture.fake.appICCProfilesError = FakeDisplayError("profiles failed")
    display = try XCTUnwrap(fixture.core.menuState().displays.first)

    XCTAssertEqual(display.iccProfileItems, [
      ICCProfileMenuItem(url: nil, title: "Unavailable", isEnabled: false)
    ])
  }

  func testDirectDitheringAndICCPersistOnlyWhenCurrentProfileIsOn() throws {
    let fixture = try AppCoreFixture()
    let originalURL = URL(fileURLWithPath: "/Library/ColorSync/Profiles/Original.icc")
    var state = fixture.fake.states[fixture.display.selector]!
    state.iccProfileURL = .readable(originalURL)
    fixture.fake.states[fixture.display.selector] = state
    _ = try fixture.core.addProfile(for: fixture.display.selector)

    _ = try fixture.core.setDithering(false, for: fixture.display.selector)
    var document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertEqual(document.displays[0].profiles[0].intent.ditheringEnabled, false)

    let newURL = URL(fileURLWithPath: "/Library/ColorSync/Profiles/New.icc")
    _ = try fixture.core.setICCProfile(newURL, for: fixture.display.selector)
    document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertEqual(document.displays[0].profiles[0].intent.iccProfileURL, newURL)

    try fixture.core.setCurrentOff(for: fixture.display.selector)
    _ = try fixture.core.setDithering(true, for: fixture.display.selector)
    document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertEqual(document.displays[0].profiles[0].intent.ditheringEnabled, false)
  }

  func testSafeDitheringNoOpStillRefreshesCurrentProfile() throws {
    let fixture = try AppCoreFixture()
    _ = try fixture.core.addProfile(for: fixture.display.selector)
    var state = fixture.fake.states[fixture.display.selector]!
    state.ditheringEnabled = .readable(false)
    fixture.fake.states[fixture.display.selector] = state

    let result = fixture.core.safelySetDithering(
      false,
      for: fixture.display.selector,
      displayName: fixture.display.label)

    let document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertTrue(result.succeeded)
    XCTAssertTrue(fixture.fake.setDitheringCalls.isEmpty)
    XCTAssertEqual(document.displays[0].profiles[0].intent.ditheringEnabled, false)
  }

  func testSafeICCBlocksWhenSelectedProfileDisappears() throws {
    let fixture = try AppCoreFixture()
    let selected = URL(fileURLWithPath: "/Library/ColorSync/Profiles/Selected.icc")

    let result = fixture.core.safelySetICCProfile(
      selected,
      for: fixture.display.selector,
      displayName: fixture.display.label,
      valueTitle: "Selected")

    XCTAssertFalse(result.succeeded)
    XCTAssertTrue(result.message?.contains("no longer available") == true)
    XCTAssertTrue(fixture.fake.setICCCalls.isEmpty)
  }

  func testSafeICCAttemptedFailureRestoresBaseline() throws {
    let fixture = try AppCoreFixture()
    let oldURL = URL(fileURLWithPath: "/Library/ColorSync/Profiles/Old.icc")
    let newURL = URL(fileURLWithPath: "/Library/ColorSync/Profiles/New.icc")
    var state = fixture.fake.states[fixture.display.selector]!
    state.iccProfileURL = .readable(oldURL)
    fixture.fake.states[fixture.display.selector] = state
    fixture.fake.appICCProfiles = [ICCProfile(name: "New", url: newURL)]
    fixture.fake.iccSetResults = [
      .readbackMismatch("readback mismatch"),
      .applied("restored"),
    ]
    _ = try fixture.core.addProfile(for: fixture.display.selector)

    let result = fixture.core.safelySetICCProfile(
      newURL,
      for: fixture.display.selector,
      displayName: fixture.display.label,
      valueTitle: "New")

    let document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertFalse(result.succeeded)
    XCTAssertTrue(result.message?.contains("Previous ICC Profile state was restored") == true)
    XCTAssertEqual(fixture.fake.setICCCalls, [newURL, oldURL])
    XCTAssertEqual(document.displays[0].profiles[0].intent.iccProfileURL, oldURL)
  }

  func testSafeICCRestoreFailureTurnsCurrentOff() throws {
    let fixture = try AppCoreFixture()
    let oldURL = URL(fileURLWithPath: "/Library/ColorSync/Profiles/Old.icc")
    let newURL = URL(fileURLWithPath: "/Library/ColorSync/Profiles/New.icc")
    var state = fixture.fake.states[fixture.display.selector]!
    state.iccProfileURL = .readable(oldURL)
    fixture.fake.states[fixture.display.selector] = state
    fixture.fake.appICCProfiles = [ICCProfile(name: "New", url: newURL)]
    fixture.fake.iccSetResults = [
      .readbackMismatch("readback mismatch"),
      .failed(attemptedMutation: true, reason: "restore failed"),
    ]
    _ = try fixture.core.addProfile(for: fixture.display.selector)

    let result = fixture.core.safelySetICCProfile(
      newURL,
      for: fixture.display.selector,
      displayName: fixture.display.label,
      valueTitle: "New")

    let document = try ProfileStore(documentURL: fixture.documentURL).load()
    XCTAssertFalse(result.succeeded)
    XCTAssertTrue(result.message?.contains("Current was turned Off") == true)
    XCTAssertNil(document.displays[0].currentProfileID)
  }

  func testSafeProfileSelectionCommitFailureRestoresBaseline() throws {
    let fixture = try AppCoreFixture()
    fixture.fake.displayModes[fixture.display.selector] = .readable([
      .mode(id: "mode-rgb-12", bitDepth: 12),
      .mode(id: "mode-rgb-10", bitDepth: 10),
    ])
    let profile = try fixture.core.addProfile(for: fixture.display.selector)
    try fixture.core.setCurrentOff(for: fixture.display.selector)

    var state = fixture.fake.states[fixture.display.selector]!
    state.currentDisplayModeID = .readable(DisplayModeID("mode-rgb-10"))
    state.bitDepth = .readable(10)
    fixture.fake.states[fixture.display.selector] = state
    fixture.fake.clearCalls()
    try replaceProfileStoreDirectoryWithFile(fixture.documentURL.deletingLastPathComponent())

    let result = fixture.core.safelySelectProfile(
      profile.id,
      for: fixture.display.selector,
      displayName: fixture.display.label)

    XCTAssertFalse(result.succeeded)
    XCTAssertTrue(result.message?.contains("Previous Profile state was restored") == true)
    XCTAssertEqual(fixture.fake.setDisplayModeCalls, ["mode-rgb-12", "mode-rgb-10"])
    XCTAssertNil(fixture.core.document.displays[0].currentProfileID)
  }

  func testSafeProfileSelectionPreMutationFailureDoesNotRestoreOrTurnCurrentOff() throws {
    let fixture = try AppCoreFixture()
    let profile = try fixture.core.addProfile(for: fixture.display.selector)
    fixture.core.document.displays[0].profiles[0].intent.resolution = nil
    fixture.fake.displayModesError = FakeDisplayError("display modes failed")
    fixture.fake.clearCalls()

    let result = fixture.core.safelySelectProfile(
      profile.id,
      for: fixture.display.selector,
      displayName: fixture.display.label)

    XCTAssertFalse(result.succeeded)
    XCTAssertTrue(result.message?.contains("Current Profile was not updated") == true)
    XCTAssertEqual(fixture.fake.setResolutionCalls, [])
    XCTAssertEqual(fixture.fake.setDisplayModeCalls, [])
    XCTAssertEqual(fixture.core.document.displays[0].currentProfileID, profile.id)
    XCTAssertTrue(
      fixture.core.document.displays[0].lastResult?.summary.contains("display modes failed")
        == true)
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

  private func replaceProfileStoreDirectoryWithFile(_ directory: URL) throws {
    try FileManager.default.removeItem(at: directory)
    try Data("not-a-directory".utf8).write(to: directory)
  }
}
