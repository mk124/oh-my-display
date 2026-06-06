import OMDCore
import XCTest

@testable import OMDAppCore

final class ResolutionFacetsTests: XCTestCase {
  func testResolutionListDeduplicatesAndSortsByLogicalAreaAscending() {
    let facets = resolutionFacets(
      modes: externalModes,
      currentLogical: size(1920, 1080),
      currentHiDPI: true,
      currentRefreshHz: 120)

    XCTAssertEqual(facets.resolution.map(\.title), ["1280x720", "1920x1080", "2560x1440"])
    XCTAssertEqual(facets.resolution.map(\.isSelected), [false, true, false])
    XCTAssertEqual(
      resolutionFacets(
        modes: externalModes,
        currentLogical: size(1920, 1080),
        currentHiDPI: true,
        currentRefreshHz: 120).resolution,
      facets.resolution)
  }

  func testResolutionItemsPreserveCurrentHiDPIThenRefresh() {
    let facets = resolutionFacets(
      modes: externalModes,
      currentLogical: size(1920, 1080),
      currentHiDPI: true,
      currentRefreshHz: 60)

    // 1080 keeps both axes over the 120Hz and LoDPI variants; 720 has no HiDPI
    // side, so it falls back to LoDPI while still preserving 60Hz over 30Hz.
    XCTAssertEqual(
      facets.resolution.compactMap { $0.id?.rawValue },
      ["res-720-60-lodpi", "res-1080-60-hidpi", "res-1440-60-hidpi"])
  }

  func testResolutionItemFallsBackToNearestRefreshPreferringHigherOnTie() {
    let modes = [
      mode("res-1080-60-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
      mode("res-1440-50-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: 50),
      mode("res-1440-599-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: 59.9),
      mode("res-1440-601-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: 60.1),
    ]

    let facets = resolutionFacets(
      modes: modes,
      currentLogical: size(1920, 1080),
      currentHiDPI: true,
      currentRefreshHz: 60)

    XCTAssertEqual(facets.resolution.last?.id?.rawValue, "res-1440-601-hidpi")
  }

  func testBestModeTieBreakPrefersLargerBackingThenLowerID() {
    // The larger backing carries the lexicographically larger id, proving
    // backing area outranks id; equal backings then fall to id order.
    let duplicates = [
      mode("res-a-small", logical: (1920, 1080), backing: (2880, 1620), hidpi: true, hz: 60),
      mode("res-z-large", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
      mode("res-b-large", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
    ]

    let best = bestMode(in: duplicates, preferringHiDPI: true, nearRefreshHz: 60)

    XCTAssertEqual(best?.id.rawValue, "res-b-large")
    XCTAssertEqual(
      bestMode(in: duplicates.reversed(), preferringHiDPI: true, nearRefreshHz: 60)?.id,
      best?.id)
  }

  func testHiDPIItemsResolveOppositeSidePreservingRefresh() {
    let facets = resolutionFacets(
      modes: externalModes,
      currentLogical: size(1920, 1080),
      currentHiDPI: true,
      currentRefreshHz: 120)

    XCTAssertEqual(facets.hidpi.map(\.title), ["On", "Off"])
    XCTAssertEqual(facets.hidpi.map(\.isSelected), [true, false])
    XCTAssertEqual(
      facets.hidpi.compactMap { $0.id?.rawValue },
      ["res-1080-120-hidpi", "res-1080-60-lodpi"])
  }

  func testHiDPIOffDisabledWhenLogicalHasNoLoDPICounterpart() {
    let modes = [
      mode("res-1080-60-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
      mode("res-1440-60-lodpi", logical: (2560, 1440), backing: (2560, 1440), hidpi: false, hz: 60),
    ]

    let facets = resolutionFacets(
      modes: modes,
      currentLogical: size(1920, 1080),
      currentHiDPI: true,
      currentRefreshHz: 60)

    // The LoDPI mode at another logical must not leak in: HiDPI never falls
    // back across logical resolutions.
    let off = facets.hidpi[1]
    XCTAssertNil(off.id)
    XCTAssertFalse(off.isEnabled)
    XCTAssertTrue(facets.hidpi[0].isSelected)
  }

  func testRefreshItemsClusterJitterAndUseCanonicalTitle() {
    let modes = [
      mode("res-1080-120-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 120),
      mode("res-1080-60-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
      mode("res-1080-60001-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60.001),
    ]

    let facets = resolutionFacets(
      modes: modes,
      currentLogical: size(1920, 1080),
      currentHiDPI: true,
      currentRefreshHz: 60)

    XCTAssertEqual(facets.refreshRate.map(\.title), ["120Hz", "60Hz"])
    XCTAssertEqual(facets.refreshRate.map(\.isSelected), [false, true])
    XCTAssertEqual(facets.refreshRate.last?.id?.rawValue, "res-1080-60-hidpi")
  }

  func testRefreshItemsEmptyWhenAllRefreshUnknown() {
    let modes = [
      mode("res-1080-nil-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: nil)
    ]

    let facets = resolutionFacets(
      modes: modes,
      currentLogical: size(1920, 1080),
      currentHiDPI: true,
      currentRefreshHz: nil)

    XCTAssertTrue(facets.refreshRate.isEmpty)
    XCTAssertEqual(facets.resolution.count, 1)
    XCTAssertEqual(facets.hidpi.first?.isSelected, true)
  }

  func testRefreshItemsListConcreteValuesOnlyWhenMixedWithNil() {
    let modes = [
      mode("res-1080-nil-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: nil),
      mode("res-1080-60-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
    ]

    let facets = resolutionFacets(
      modes: modes,
      currentLogical: size(1920, 1080),
      currentHiDPI: true,
      currentRefreshHz: nil)

    XCTAssertEqual(facets.refreshRate.map(\.title), ["60Hz"])
    XCTAssertFalse(facets.refreshRate[0].isSelected)
  }

  func testNilAnchorRefreshDegradesToHighestRefreshAndRanksNilLast() {
    let modes = [
      mode("res-1080-60-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
      mode("res-1440-nil-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: nil),
      mode("res-1440-60-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: 60),
      mode("res-1440-120-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: 120),
    ]

    let facets = resolutionFacets(
      modes: modes,
      currentLogical: size(1920, 1080),
      currentHiDPI: true,
      currentRefreshHz: nil)

    XCTAssertEqual(facets.resolution.last?.id?.rawValue, "res-1440-120-hidpi")
  }

  func testEmptyModeListYieldsEmptyFacets() {
    let facets = resolutionFacets(
      modes: [],
      currentLogical: size(1920, 1080),
      currentHiDPI: true,
      currentRefreshHz: 60)

    XCTAssertTrue(facets.hidpi.isEmpty)
    XCTAssertTrue(facets.resolution.isEmpty)
    XCTAssertTrue(facets.refreshRate.isEmpty)
  }

  func testHiDPIAndRefreshFacetsRequireValueAnchor() {
    let facets = resolutionFacets(
      modes: externalModes,
      currentLogical: nil,
      currentHiDPI: nil,
      currentRefreshHz: nil)

    XCTAssertTrue(facets.hidpi.isEmpty)
    XCTAssertTrue(facets.refreshRate.isEmpty)
    XCTAssertEqual(facets.resolution.count, 3)
    XCTAssertFalse(facets.resolution.contains { $0.isSelected })
    XCTAssertFalse(facets.resolution.contains { $0.id == nil })
  }

  func testUnselectedEnabledItemsAlwaysChangeTheirFacetDimension() throws {
    let modes = externalModes + [
      mode("res-1080-5994-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 59.94),
      mode("res-1080-60-hidpi-2", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
    ]
    let logical = size(1920, 1080)
    let refresh = 60.0

    let facets = resolutionFacets(
      modes: modes,
      currentLogical: logical,
      currentHiDPI: true,
      currentRefreshHz: refresh)

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

  private func resolved(_ item: ResolutionMenuItem, in modes: [ResolutionMode]) throws
    -> ResolutionMode
  {
    try XCTUnwrap(modes.first { $0.id == item.id })
  }
}

// 4K-style external display: 1920x1080 in HiDPI (120/60Hz) and LoDPI (60Hz),
// HiDPI-only 2560x1440, LoDPI-only 1280x720 (60/30Hz).
private let externalModes = [
  mode("res-1080-120-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 120),
  mode("res-1080-60-hidpi", logical: (1920, 1080), backing: (3840, 2160), hidpi: true, hz: 60),
  mode("res-1080-60-lodpi", logical: (1920, 1080), backing: (1920, 1080), hidpi: false, hz: 60),
  mode("res-1440-60-hidpi", logical: (2560, 1440), backing: (5120, 2880), hidpi: true, hz: 60),
  mode("res-720-60-lodpi", logical: (1280, 720), backing: (1280, 720), hidpi: false, hz: 60),
  mode("res-720-30-lodpi", logical: (1280, 720), backing: (1280, 720), hidpi: false, hz: 30),
]

private func size(_ width: Int, _ height: Int) -> DisplaySize {
  DisplaySize(width: width, height: height)
}
