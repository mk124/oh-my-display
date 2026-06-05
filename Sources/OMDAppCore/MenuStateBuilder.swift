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
    return AppMenuState(
      displays: orderedDisplays.map { display in
        makeDisplayMenu(display: display)
      })
  }

  func makeDisplayMenu(display: DisplayTarget) -> DisplayMenuState {
    let record = record(for: display.selector)
    let currentProfile = record.flatMap(currentProfile(in:))
    let currentTitle = currentProfile?.label ?? "Off"
    let degradedReason = record?.lastResult?.summary
    let state = try? client.readDisplayState(display.selector)
    let resolutionItems = state.flatMap { try? makeResolutionItems(for: display.selector, state: $0) } ?? []
    let displayModeItems = state.flatMap { try? makeDisplayModeItems(for: display.selector, state: $0) } ?? []
    let profiles = record?.profiles.sorted { $0.ordinal < $1.ordinal } ?? []
    let currentItems = [
      CurrentProfileMenuItem(
        profileID: nil,
        title: "Off",
        isSelected: currentProfile == nil),
    ] + profiles.map { profile in
      CurrentProfileMenuItem(
        profileID: profile.id,
        title: profile.label,
        isSelected: profile.id == record?.currentProfileID)
    }
    let profileItems = profiles.map { profile in
      ProfileMenuItem(profileID: profile.id, title: profile.label)
    }

    return DisplayMenuState(
      display: display,
      title: display.label,
      currentTitle: "Current: \(currentTitle)",
      currentItems: currentItems,
      profileItems: profileItems,
      resolutionItems: resolutionItems,
      displayModeItems: displayModeItems,
      degradedReason: degradedReason
    )
  }

  func makeResolutionItems(for display: DisplaySelector) throws -> [ResolutionMenuItem] {
    let state = try client.readDisplayState(display)
    return try makeResolutionItems(for: display, state: state)
  }

  func makeResolutionItems(for display: DisplaySelector, state: DisplayState) throws
    -> [ResolutionMenuItem]
  {
    let currentID = readableValue(state.currentResolutionModeID)
    let result = try client.listResolutionModes(display)
    guard result.readability != .unreadable else {
      return []
    }
    return result.items.sorted(by: resolutionSort).map { mode in
      ResolutionMenuItem(
        id: mode.id,
        title: resolutionTitle(mode),
        isSelected: mode.id == currentID)
    }
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
        title: displayModeTitle(mode),
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
}
