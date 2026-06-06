import OMDCore

// Builds the three facet submenus from one resolution-mode snapshot; every
// enabled item is pre-resolved to the concrete mode a click applies.
func resolutionFacets(modes: [ResolutionMode], currentLogical: DisplaySize?, currentHiDPI: Bool?, currentRefreshHz: Double?)
  -> (hidpi: [ResolutionMenuItem], resolution: [ResolutionMenuItem], refreshRate: [ResolutionMenuItem])
{
  (
    hidpiItems(modes: modes, logical: currentLogical, hidpi: currentHiDPI, refresh: currentRefreshHz),
    resolutionItems(modes: modes, logical: currentLogical, hidpi: currentHiDPI, refresh: currentRefreshHz),
    refreshRateItems(modes: modes, logical: currentLogical, hidpi: currentHiDPI, refresh: currentRefreshHz)
  )
}

// The resolution list is locked to the current HiDPI side so a click never flips
// HiDPI as a side effect; without a readable anchor the full set degrades gracefully.
private func resolutionItems(modes: [ResolutionMode], logical: DisplaySize?, hidpi: Bool?, refresh: Double?) -> [ResolutionMenuItem] {
  let sideModes = hidpi.map { side in modes.filter { $0.isHiDPI == side } } ?? modes
  var groups: [(logical: DisplaySize, candidates: [ResolutionMode])] = []
  for mode in sideModes {
    if let index = groups.firstIndex(where: { $0.logical == mode.logicalResolution }) {
      groups[index].candidates.append(mode)
    } else {
      groups.append((mode.logicalResolution, [mode]))
    }
  }
  let native = panelNativeBacking(in: modes)
  let items = groups.sorted { logicalSortKey($0.logical) < logicalSortKey($1.logical) }.map { group in
    let best = bestMode(in: group.candidates, nearRefreshHz: refresh)
    return ResolutionMenuItem(
      id: best?.id,
      title: "\(group.logical)",
      isSelected: group.logical == logical,
      badgeText: best.map { "\($0.backingResolution)" },
      isNative: native != nil && best?.backingResolution == native)
  }
  return items.filter(\.isNative) + items.filter { !$0.isNative }
}

// Panel-native backing from the snapshot: driver-flagged timing wins (largest area on
// disagreement), but a flag smaller than the largest 1x backing is provably wrong --
// a 1x desktop mode never exceeds the physical panel -- so degrade to no pin rather
// than mis-pin. Without any flag, fall back to the largest 1x backing; nil when
// neither source is available.
private func panelNativeBacking(in modes: [ResolutionMode]) -> DisplaySize? {
  let maxOneX = modes.filter { $0.backingResolution == $0.logicalResolution }.map(\.backingResolution).max { pixelArea($0) < pixelArea($1) }
  guard let flagged = modes.filter(\.isNativeTiming).map(\.backingResolution).max(by: { pixelArea($0) < pixelArea($1) }) else { return maxOneX }
  if let maxOneX, pixelArea(flagged) < pixelArea(maxOneX) { return nil }
  return flagged
}

private func pixelArea(_ size: DisplaySize) -> Int { size.width * size.height }

private func hidpiItems(modes: [ResolutionMode], logical: DisplaySize?, hidpi: Bool?, refresh: Double?) -> [ResolutionMenuItem] {
  guard let logical, let hidpi, !modes.isEmpty else {
    return []
  }
  return [true, false].map { target in
    let candidates = modes.filter { $0.logicalResolution == logical && $0.isHiDPI == target }
    let best = bestMode(in: candidates, nearRefreshHz: refresh)
    return ResolutionMenuItem(id: best?.id, title: target ? "On" : "Off", isSelected: target == hidpi, isEnabled: best != nil)
  }
}

private func refreshRateItems(modes: [ResolutionMode], logical: DisplaySize?, hidpi: Bool?, refresh: Double?) -> [ResolutionMenuItem] {
  guard let logical, let hidpi else {
    return []
  }
  let candidates = modes.filter { $0.logicalResolution == logical && $0.isHiDPI == hidpi }
  return refreshRepresentatives(in: candidates).map { representative in
    let matching = candidates.filter { $0.refreshHz.map { approximatelyEqual($0, representative) } ?? false }
    return ResolutionMenuItem(
      id: bestMode(in: matching, nearRefreshHz: representative)?.id,
      title: formatHz(representative),
      isSelected: refresh.map { approximatelyEqual($0, representative) } ?? false)
  }
}

// Preference order: the refresh closest to `nearRefreshHz` (ties prefer higher;
// nil refreshes rank last; nil target means highest wins), then largest backing
// area, then lowest id. Callers pass same-HiDPI-side candidates, so the rank
// carries no HiDPI dimension.
func bestMode(in candidates: [ResolutionMode], nearRefreshHz refresh: Double?) -> ResolutionMode? {
  candidates.min { facetRank($0, refresh: refresh) < facetRank($1, refresh: refresh) }
}

private func facetRank(_ mode: ResolutionMode, refresh: Double?) -> (Double, Double, Int, String) {
  let backingArea = mode.backingResolution.width * mode.backingResolution.height
  guard let hz = mode.refreshHz else {
    return (.infinity, 0, -backingArea, mode.id.rawValue)
  }
  return (refresh.map { abs(hz - $0) } ?? 0, -hz, -backingArea, mode.id.rawValue)
}

// One representative per approximatelyEqual cluster: the value closest to an
// integer wins, ties keep the higher (input arrives sorted descending). The
// representative doubles as menu title and best-match anchor.
private func refreshRepresentatives(in modes: [ResolutionMode]) -> [Double] {
  var representatives: [Double] = []
  for refresh in modes.compactMap(\.refreshHz).sorted(by: >) {
    if let index = representatives.firstIndex(where: { approximatelyEqual($0, refresh) }) {
      if integerCloseness(refresh) < integerCloseness(representatives[index]) {
        representatives[index] = refresh
      }
    } else {
      representatives.append(refresh)
    }
  }
  return representatives
}

private func integerCloseness(_ value: Double) -> Double {
  abs(value - value.rounded())
}

private func logicalSortKey(_ size: DisplaySize) -> (Int, Int) {
  (size.width * size.height, size.width)
}
