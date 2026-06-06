import OMDCore

extension OMDAppCore {
  package func menuState() throws -> AppMenuState {
    let displays = try client.listDisplays()
    let orderedDisplays = displays.enumerated().sorted { lhs, rhs in
      if lhs.element.isMain != rhs.element.isMain {
        return lhs.element.isMain
      }
      return lhs.offset < rhs.offset
    }.map(\.element)
    let iccProfiles = orderedDisplays.isEmpty
      ? nil
      : try? client.listDisplayAssignableICCProfiles()
    return AppMenuState(
      displays: orderedDisplays.map { display in
        makeDisplayMenu(display: display, iccProfiles: iccProfiles)
      })
  }

  func makeDisplayMenu(display: DisplayTarget, iccProfiles: [ICCProfile]?) -> DisplayMenuState {
    let record = record(for: display.selector)
    let currentProfile = record.flatMap(currentProfile(in:))
    let degradedReason = record?.lastResult?.summary
    let state = try? client.readDisplayState(display.selector)
    let resolutionMenus = state.map { makeResolutionFacetItems(for: display.selector, state: $0) }
      ?? (hidpi: [], resolution: [], refreshRate: [])
    let displayModeItems = state.flatMap { try? makeDisplayModeItems(for: display.selector, state: $0) } ?? []
    let ditheringItems = makeDitheringItems(state: state)
    let iccProfileItems = makeICCProfileItems(state: state, profiles: iccProfiles)
    let profiles = record?.profiles.sorted { $0.ordinal < $1.ordinal } ?? []
    let currentItems = [
      CurrentProfileMenuItem(
        profileID: nil,
        name: "Off",
        title: "Off",
        isSelected: currentProfile == nil),
    ] + profiles.map { profile in
      CurrentProfileMenuItem(
        profileID: profile.id,
        name: profile.shortLabel,
        title: profile.label,
        isSelected: profile.id == record?.currentProfileID)
    }
    let profileItems = profiles.map { profile in
      ProfileMenuItem(profileID: profile.id, title: profile.label)
    }

    return DisplayMenuState(
      display: display,
      title: display.label,
      currentItems: currentItems,
      profileItems: profileItems,
      hidpiItems: resolutionMenus.hidpi,
      resolutionItems: resolutionMenus.resolution,
      refreshRateItems: resolutionMenus.refreshRate,
      displayModeItems: displayModeItems,
      ditheringItems: ditheringItems.items,
      isDitheringEnabled: ditheringItems.isEnabled,
      iccProfileItems: iccProfileItems,
      degradedReason: degradedReason
    )
  }

  func makeResolutionFacetItems(for display: DisplaySelector, state: DisplayState)
    -> (hidpi: [ResolutionMenuItem], resolution: [ResolutionMenuItem], refreshRate: [ResolutionMenuItem])
  {
    guard let result = try? client.listResolutionModes(display),
      result.readability != .unreadable
    else {
      return ([], [], [])
    }
    return resolutionFacets(
      modes: result.items,
      currentLogical: readableValue(state.logicalResolution),
      currentHiDPI: readableValue(state.isHiDPI),
      currentRefreshHz: readableValue(state.resolutionRefreshHz))
  }

  func makeDisplayModeItems(for display: DisplaySelector) throws -> [DisplayModeMenuItem] {
    let state = try client.readDisplayState(display)
    return try makeDisplayModeItems(for: display, state: state)
  }

  func makeDisplayModeItems(for display: DisplaySelector, state: DisplayState) throws
    -> [DisplayModeMenuItem]
  {
    let result = try client.listDisplayModes(display)
    guard result.readability != .unreadable else {
      return []
    }
    let modes = displayModesForCurrentResolution(result.items, state: state)
    return modes.sorted(by: displayModeSort).map { mode in
      DisplayModeMenuItem(
        id: mode.id,
        title: displayModeMenuTitle(mode),
        isSelected: mode.id == readableValue(state.currentDisplayModeID))
    }
  }

  func displayModesForCurrentResolution(_ modes: [DisplayMode], state: DisplayState) -> [DisplayMode] {
    // Display Mode menu must not be a hidden resolution switcher.
    guard state.backingResolution.readability == .readable,
      let backingResolution = state.backingResolution.value
    else {
      return []
    }
    let refresh = state.resolutionRefreshHz.readability == .readable
      ? state.resolutionRefreshHz.value
      : nil

    return modes.filter { mode in
      guard mode.outputTimingResolution == backingResolution else {
        return false
      }
      guard let refresh, let modeRefresh = mode.outputTimingRefreshHz else {
        return true
      }
      return approximatelyEqual(modeRefresh, refresh)
    }
  }

  func makeDitheringItems(state: DisplayState?) -> (items: [DitheringMenuItem], isEnabled: Bool) {
    let current = state.flatMap { readableValue($0.ditheringEnabled) }
    return (
      [
        DitheringMenuItem(enabled: false, title: "Off", isSelected: current == false),
        DitheringMenuItem(enabled: true, title: "On", isSelected: current == true),
      ],
      state?.ditheringAvailability.canSet ?? true
    )
  }

  func makeICCProfileItems(state: DisplayState?, profiles: [ICCProfile]?) -> [ICCProfileMenuItem] {
    guard let profiles else {
      return [ICCProfileMenuItem(url: nil, name: "Unknown", title: "Unknown", isEnabled: false)]
    }

    let titles = iccProfileTitles(profiles)
    let current = state.flatMap { readableValue($0.iccProfileURL) }
    return profiles.sorted {
      let lhs = titles[$0.url] ?? $0.name
      let rhs = titles[$1.url] ?? $1.name
      if lhs != rhs {
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
      }
      return ICCProfileIdentity.sortKey($0.url).localizedStandardCompare(
        ICCProfileIdentity.sortKey($1.url)) == .orderedAscending
    }.map { profile in
      ICCProfileMenuItem(
        url: profile.url,
        name: profile.name,
        title: titles[profile.url] ?? profile.name,
        isSelected: current.map { ICCProfileIdentity.sameFile($0, profile.url) } ?? false)
    }
  }
}
