import OMDCore
import XCTest

@testable import OMDAppCore

final class ResolutionFacetsTests: XCTestCase {
  func testResolutionListDeduplicatesAndSortsByLogicalAreaAscending() {
    let facets = resolutionFacets(modes: externalModes, currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: 120)

    // LoDPI-only 1280x720 is locked out on the HiDPI side.
    XCTAssertEqual(facets.resolution.map(\.title), ["1920x1080", "2560x1440"])
    XCTAssertEqual(facets.resolution.map(\.isSelected), [true, false])
    XCTAssertEqual(resolutionFacets(modes: externalModes, currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: 120).resolution, facets.resolution)
  }

  func testResolutionListLocksToCurrentHiDPISide() {
    // A resolution click must never flip HiDPI as a side effect: each side lists
    // only its own logicals; an unreadable anchor degrades to the full set.
    let hidpiSide = resolutionFacets(modes: externalModes, currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: 60)
    let lodpiSide = resolutionFacets(modes: externalModes, currentLogical: size(1920, 1080), currentHiDPI: false, currentRefreshHz: 60)
    let unanchored = resolutionFacets(modes: externalModes, currentLogical: nil, currentHiDPI: nil, currentRefreshHz: nil)

    XCTAssertEqual(hidpiSide.resolution.map(\.title), ["1920x1080", "2560x1440"])
    // 1080 leads the LoDPI side as the pinned geometric-native match, not by area.
    XCTAssertEqual(lodpiSide.resolution.map(\.title), ["1920x1080", "1280x720"])
    XCTAssertEqual(unanchored.resolution.map(\.title), ["1280x720", "1920x1080", "2560x1440"])
  }

  func testResolutionItemsPreserveRefreshWithinCurrentHiDPISide() {
    let facets = resolutionFacets(modes: externalModes, currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: 60)

    // 1080 prefers 60Hz over the 120Hz variant; LoDPI modes never enter the list.
    XCTAssertEqual(facets.resolution.compactMap { $0.id?.rawValue }, ["res-1080-60-hidpi", "res-1440-60-hidpi"])
  }

  func testResolutionItemFallsBackToNearestRefreshPreferringHigherOnTie() {
    let modes: [ResolutionMode] = [
      .mode(id: "res-1080-60-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
      .mode(id: "res-1440-50-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: 50),
      .mode(id: "res-1440-599-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: 59.9),
      .mode(id: "res-1440-601-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: 60.1),
    ]

    let facets = resolutionFacets(modes: modes, currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: 60)

    XCTAssertEqual(facets.resolution.last?.id?.rawValue, "res-1440-601-hidpi")
  }

  func testBestModeTieBreakPrefersLargerBackingThenLowerID() {
    // The larger backing carries the lexicographically larger id, proving
    // backing area outranks id; equal backings then fall to id order.
    let duplicates: [ResolutionMode] = [
      .mode(id: "res-a-small", logical: (1920, 1080), backing: (2880, 1620), hidpi: true, hz: 60),
      .mode(id: "res-z-large", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
      .mode(id: "res-b-large", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
    ]

    let best = bestMode(in: duplicates, nearRefreshHz: 60)

    XCTAssertEqual(best?.id.rawValue, "res-b-large")
    XCTAssertEqual(bestMode(in: duplicates.reversed(), nearRefreshHz: 60)?.id, best?.id)
  }

  func testHiDPIItemsResolveOppositeSidePreservingRefresh() {
    let facets = resolutionFacets(modes: externalModes, currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: 120)

    XCTAssertEqual(facets.hidpi.map(\.title), ["On", "Off"])
    XCTAssertEqual(facets.hidpi.map(\.isSelected), [true, false])
    XCTAssertEqual(facets.hidpi.compactMap { $0.id?.rawValue }, ["res-1080-120-hidpi", "res-1080-60-lodpi"])
  }

  func testHiDPIOffDisabledWhenLogicalHasNoLoDPICounterpart() {
    let modes: [ResolutionMode] = [
      .mode(id: "res-1080-60-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
      .mode(id: "res-1440-60-lodpi", logical: (2560, 1440), backing: (2560, 1440), hidpi: false, hz: 60),
    ]

    let facets = resolutionFacets(modes: modes, currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: 60)

    // The LoDPI mode at another logical must not leak in: HiDPI never falls
    // back across logical resolutions.
    let off = facets.hidpi[1]
    XCTAssertNil(off.id)
    XCTAssertFalse(off.isEnabled)
    XCTAssertTrue(facets.hidpi[0].isSelected)
  }

  func testRefreshItemsClusterJitterAndUseCanonicalTitle() {
    let modes: [ResolutionMode] = [
      .mode(id: "res-1080-120-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 120),
      .mode(id: "res-1080-60-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
      .mode(id: "res-1080-60001-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60.001),
    ]

    let facets = resolutionFacets(modes: modes, currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: 60)

    XCTAssertEqual(facets.refreshRate.map(\.title), ["120Hz", "60Hz"])
    XCTAssertEqual(facets.refreshRate.map(\.isSelected), [false, true])
    XCTAssertEqual(facets.refreshRate.last?.id?.rawValue, "res-1080-60-hidpi")
  }

  func testRefreshItemsEmptyWhenAllRefreshUnknown() {
    let modes: [ResolutionMode] = [
      .mode(id: "res-1080-nil-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: nil)
    ]

    let facets = resolutionFacets(modes: modes, currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: nil)

    XCTAssertTrue(facets.refreshRate.isEmpty)
    XCTAssertEqual(facets.resolution.count, 1)
    XCTAssertEqual(facets.hidpi.first?.isSelected, true)
  }

  func testRefreshItemsListConcreteValuesOnlyWhenMixedWithNil() {
    let modes: [ResolutionMode] = [
      .mode(id: "res-1080-nil-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: nil),
      .mode(id: "res-1080-60-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
    ]

    let facets = resolutionFacets(modes: modes, currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: nil)

    XCTAssertEqual(facets.refreshRate.map(\.title), ["60Hz"])
    XCTAssertFalse(facets.refreshRate[0].isSelected)
  }

  func testNilAnchorRefreshDegradesToHighestRefreshAndRanksNilLast() {
    let modes: [ResolutionMode] = [
      .mode(id: "res-1080-60-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
      .mode(id: "res-1440-nil-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: nil),
      .mode(id: "res-1440-60-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: 60),
      .mode(id: "res-1440-120-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: 120),
    ]

    let facets = resolutionFacets(modes: modes, currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: nil)

    XCTAssertEqual(facets.resolution.last?.id?.rawValue, "res-1440-120-hidpi")
  }

  func testEmptyModeListYieldsEmptyFacets() {
    let facets = resolutionFacets(modes: [], currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: 60)

    XCTAssertTrue(facets.hidpi.isEmpty)
    XCTAssertTrue(facets.resolution.isEmpty)
    XCTAssertTrue(facets.refreshRate.isEmpty)
  }

  func testHiDPIAndRefreshFacetsRequireValueAnchor() {
    let facets = resolutionFacets(modes: externalModes, currentLogical: nil, currentHiDPI: nil, currentRefreshHz: nil)

    XCTAssertTrue(facets.hidpi.isEmpty)
    XCTAssertTrue(facets.refreshRate.isEmpty)
    XCTAssertEqual(facets.resolution.count, 3)
    XCTAssertFalse(facets.resolution.contains { $0.isSelected })
    XCTAssertFalse(facets.resolution.contains { $0.id == nil })
  }

  func testUnselectedEnabledItemsAlwaysChangeTheirFacetDimension() throws {
    let modes = externalModes + [
      .mode(id: "res-1080-5994-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 59.94),
      .mode(id: "res-1080-60-hidpi-2", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
    ]
    let logical = size(1920, 1080)
    let refresh = 60.0

    let facets = resolutionFacets(modes: modes, currentLogical: logical, currentHiDPI: true, currentRefreshHz: refresh)

    // No clickable item may resolve to a mode that leaves its own facet
    // dimension unchanged -- that click would re-apply the current state and
    // trigger a confirmation dialog with no visible change.
    for item in facets.resolution where !item.isSelected {
      try XCTAssertNotEqual(resolved(item, in: modes).logicalResolution, logical)
    }
    for item in facets.hidpi where !item.isSelected && item.isEnabled {
      try XCTAssertFalse(resolved(item, in: modes).isHiDPI)
    }
    for item in facets.refreshRate where !item.isSelected {
      let hz = try XCTUnwrap(resolved(item, in: modes).refreshHz)
      XCTAssertFalse(approximatelyEqual(hz, refresh))
    }
  }

  func testResolutionItemsBadgeBackingAndPinFlaggedNativeFirst() {
    let facets = resolutionFacets(modes: flaggedModes, currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: 120)

    // HiDPI side only; the row whose backing matches the flagged panel native
    // pins first and every row badges its resolved backing.
    XCTAssertEqual(facets.resolution.map(\.title), ["1920x1080", "2560x1440"])
    XCTAssertEqual(facets.resolution.map(\.isNative), [true, false])
    XCTAssertEqual(facets.resolution.map(\.badgeText), ["3840x2160", "5120x2880"])
  }

  func testResolutionPinningAppliesIndependentlyOfHiDPIAnchor() {
    let facets = resolutionFacets(modes: flaggedModes, currentLogical: size(1920, 1080), currentHiDPI: false, currentRefreshHz: 60)

    // LoDPI anchor: the 1x 4K row is the native match and pins; HiDPI-only
    // 1440 is locked out of this side.
    XCTAssertEqual(facets.resolution.map(\.title), ["3840x2160", "1280x720", "1920x1080"])
    XCTAssertEqual(facets.resolution.map(\.isNative), [true, false, false])
    XCTAssertEqual(facets.resolution.map(\.badgeText), ["3840x2160", "1280x720", "1920x1080"])
  }

  func testPanelNativeFallsBackToLargestOneXBackingWhenNoFlags() {
    // externalModes carries no native flags; the largest 1x backing is 1920x1080.
    let facets = resolutionFacets(modes: externalModes, currentLogical: size(1920, 1080), currentHiDPI: false, currentRefreshHz: 60)

    XCTAssertEqual(facets.resolution.map(\.title), ["1920x1080", "1280x720"])
    XCTAssertEqual(facets.resolution.map(\.isNative), [true, false])
  }

  func testPanelNativeUnavailableWithoutFlagsOrOneXModes() {
    let modes: [ResolutionMode] = [
      .mode(id: "res-1080-60-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
      .mode(id: "res-1440-60-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: 60),
    ]

    let facets = resolutionFacets(modes: modes, currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: 60)

    // Neither inference source exists: degrade to the unpinned area-ascending list.
    XCTAssertEqual(facets.resolution.map(\.title), ["1920x1080", "2560x1440"])
    XCTAssertEqual(facets.resolution.map(\.isNative), [false, false])
  }

  func testInconsistentFlagBackingsResolveToLargestArea() {
    let modes: [ResolutionMode] = [
      .mode(id: "res-1080-60-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60, native: true),
      .mode(id: "res-1440-60-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: 60, native: true),
    ]

    let facets = resolutionFacets(modes: modes, currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: 60)

    XCTAssertEqual(facets.resolution.map(\.title), ["2560x1440", "1920x1080"])
    XCTAssertEqual(facets.resolution.map(\.isNative), [true, false])
  }

  func testFlagSmallerThanOneXBackingDegradesToNoPin() {
    // A 1x desktop mode never exceeds the physical panel, so a flag below the
    // largest 1x backing is provably wrong (lying EDID): no pin, no geometric
    // substitute.
    let modes: [ResolutionMode] = [
      .mode(id: "res-1080-60-lodpi", logical: (1920, 1080), backing: (1920, 1080), hidpi: false, hz: 60, native: true),
      .mode(id: "res-2160-60-lodpi", logical: (3840, 2160), backing: (3840, 2160), hidpi: false, hz: 60),
    ]

    let facets = resolutionFacets(modes: modes, currentLogical: size(1920, 1080), currentHiDPI: false, currentRefreshHz: 60)

    XCTAssertEqual(facets.resolution.map(\.isNative), [false, false])
  }

  func testFlagLargerThanOneXBackingTrustsFlagForHiDPIOnlyPanels() {
    // 5K-iMac shape: the panel-native backing exists only behind a HiDPI mode,
    // so the flag exceeds every 1x backing (cross-checked against the full
    // snapshot, including the filtered-out LoDPI side) and stays trusted.
    let modes: [ResolutionMode] = [
      .mode(id: "res-1440-60-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: 60, native: true),
      .mode(id: "res-2160-60-lodpi", logical: (3840, 2160), backing: (3840, 2160), hidpi: false, hz: 60),
    ]

    let facets = resolutionFacets(modes: modes, currentLogical: size(2560, 1440), currentHiDPI: true, currentRefreshHz: 60)

    XCTAssertEqual(facets.resolution.map(\.title), ["2560x1440"])
    XCTAssertEqual(facets.resolution.map(\.isNative), [true])
  }

  func testPanelNativeInfersFromFullSnapshotNotFilteredSide() {
    // The lying-EDID guard must see both HiDPI sides: the flagged HiDPI mode is
    // smaller than a LoDPI-only 1x mode that never enters the filtered list.
    // If inference ever switched to the side-filtered set, this would mis-pin.
    let modes: [ResolutionMode] = [
      .mode(id: "res-1080-60-hidpi", logical: (1920, 1080), backing: (2880, 1620), hidpi: true, hz: 60, native: true),
      .mode(id: "res-2160-60-lodpi", logical: (3840, 2160), backing: (3840, 2160), hidpi: false, hz: 60),
    ]

    let facets = resolutionFacets(modes: modes, currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: 60)

    XCTAssertEqual(facets.resolution.map(\.title), ["1920x1080"])
    XCTAssertEqual(facets.resolution.map(\.isNative), [false])
  }

  func testHiDPIAndRefreshFacetItemsCarryNoBadgeOrNativeMark() {
    let facets = resolutionFacets(modes: flaggedModes, currentLogical: size(1920, 1080), currentHiDPI: true, currentRefreshHz: 120)

    XCTAssertTrue(facets.hidpi.allSatisfy { $0.badgeText == nil && !$0.isNative })
    XCTAssertTrue(facets.refreshRate.allSatisfy { $0.badgeText == nil && !$0.isNative })
  }

  func testSingleAllNativeListMarksItemNative() {
    let modes: [ResolutionMode] = [
      .mode(id: "res-2160-60-lodpi", logical: (3840, 2160), backing: (3840, 2160), hidpi: false, hz: 60, native: true)
    ]

    let facets = resolutionFacets(modes: modes, currentLogical: size(3840, 2160), currentHiDPI: false, currentRefreshHz: 60)

    XCTAssertEqual(facets.resolution.map(\.isNative), [true])
    XCTAssertEqual(facets.resolution.map(\.badgeText), ["3840x2160"])
  }

  private func resolved(_ item: ResolutionMenuItem, in modes: [ResolutionMode]) throws -> ResolutionMode {
    try XCTUnwrap(modes.first { $0.id == item.id })
  }
}

// Flagged 4K set: native timing flags sit on the panel-native 3840x2160 backings
// (the HiDPI 1080 mode and the 1x 4K mode), mirroring real driver behavior.
private let flaggedModes: [ResolutionMode] = [
  .mode(id: "res-1080-120-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 120, native: true),
  .mode(id: "res-1080-60-lodpi", logical: (1920, 1080), backing: (1920, 1080), hidpi: false, hz: 60),
  .mode(id: "res-2160-60-lodpi", logical: (3840, 2160), backing: (3840, 2160), hidpi: false, hz: 60, native: true),
  .mode(id: "res-1440-60-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: 60),
  .mode(id: "res-720-60-lodpi", logical: (1280, 720), backing: (1280, 720), hidpi: false, hz: 60),
]

// 4K-style external display: 1920x1080 in HiDPI (120/60Hz) and LoDPI (60Hz),
// HiDPI-only 2560x1440, LoDPI-only 1280x720 (60/30Hz). Intentionally flag-free:
// the guardrail tests above exercise the zero-flag path, and its largest 1x
// backing (the geometric fallback) is 1920x1080.
private let externalModes: [ResolutionMode] = [
  .mode(id: "res-1080-120-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 120),
  .mode(id: "res-1080-60-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
  .mode(id: "res-1080-60-lodpi", logical: (1920, 1080), backing: (1920, 1080), hidpi: false, hz: 60),
  .mode(id: "res-1440-60-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: 60),
  .mode(id: "res-720-60-lodpi", logical: (1280, 720), backing: (1280, 720), hidpi: false, hz: 60),
  .mode(id: "res-720-30-lodpi", logical: (1280, 720), backing: (1280, 720), hidpi: false, hz: 30),
]

private func size(_ width: Int, _ height: Int) -> DisplaySize {
  DisplaySize(width: width, height: height)
}
