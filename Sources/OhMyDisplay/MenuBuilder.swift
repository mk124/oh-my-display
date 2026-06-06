import AppKit
import OMDAppCore
import OMDCore

extension AppDelegate {
  func rebuildMenu() {
    let menu = NSMenu()
    defer {
      statusItem.menu = menu
    }

    guard let core else {
      menu.addItem(disabledItem("AppCore unavailable"))
      menu.addItem(.separator())
      menu.addItem(quitItem())
      return
    }

    do {
      let state = try core.menuState()
      if state.displays.isEmpty {
        menu.addItem(disabledItem("No Displays"))
      } else {
        for display in state.displays {
          menu.addItem(displayMenuItem(display))
        }
      }
    } catch {
      menu.addItem(disabledItem("Unable to read displays"))
      menu.addItem(disabledItem(String(describing: error)))
    }

    menu.addItem(.separator())
    menu.addItem(quitItem())
  }

  func displayMenuItem(_ display: DisplayMenuState) -> NSMenuItem {
    let title = display.degradedReason == nil ? display.title : "\(display.title) - Issue"
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
    let submenu = NSMenu()

    if let degradedReason = display.degradedReason {
      submenu.addItem(disabledItem("Issue: \(degradedReason)"))
      submenu.addItem(.separator())
    }

    let current = submenuItem("Profile", currentValue: display.currentItems.first(where: \.isSelected)?.name)
    current.submenu = currentMenu(display)
    submenu.addItem(current)
    submenu.addItem(.separator())
    submenu.addItem(facetMenu("HiDPI", items: display.hidpiItems, display: display))
    submenu.addItem(facetMenu("Resolution", items: display.resolutionItems, display: display))
    submenu.addItem(facetMenu("Refresh Rate", items: display.refreshRateItems, display: display))
    submenu.addItem(displayModeMenu(display))
    submenu.addItem(ditheringMenu(display))
    submenu.addItem(iccProfileMenu(display))

    item.submenu = submenu
    return item
  }

  func currentMenu(_ display: DisplayMenuState) -> NSMenu {
    let menu = NSMenu()
    for currentItem in display.currentItems {
      let item = NSMenuItem(
        title: currentItem.title,
        action: currentItem.profileID == nil
          ? #selector(setCurrentOff(_:)) : #selector(selectProfile(_:)),
        keyEquivalent: "")
      item.target = self
      item.state = currentItem.isSelected ? .on : .off
      item.isEnabled = !currentItem.isSelected
      if let profileID = currentItem.profileID {
        item.representedObject = CurrentPayload(
          display: display.display.selector,
          displayName: display.title,
          profileID: profileID)
      } else {
        item.representedObject = DisplayPayload(display: display.display.selector)
      }
      menu.addItem(item)
    }

    if !display.profileItems.isEmpty {
      menu.addItem(.separator())
      menu.addItem(manageProfilesMenu(display))
    }

    menu.addItem(.separator())
    let add = NSMenuItem(
      title: "Add New Profile",
      action: #selector(addProfile(_:)),
      keyEquivalent: "")
    add.target = self
    add.representedObject = DisplayPayload(display: display.display.selector)
    menu.addItem(add)
    return menu
  }

  func manageProfilesMenu(_ display: DisplayMenuState) -> NSMenuItem {
    let item = NSMenuItem(title: "Manage Profiles", action: nil, keyEquivalent: "")
    let submenu = NSMenu()
    for profile in display.profileItems {
      submenu.addItem(profileManagementMenu(profile, display: display.display.selector))
    }
    item.submenu = submenu
    return item
  }

  func profileManagementMenu(_ profile: ProfileMenuItem, display: DisplaySelector) -> NSMenuItem {
    let item = NSMenuItem(title: profile.title, action: nil, keyEquivalent: "")
    let submenu = NSMenu()
    let payload = ProfilePayload(
      display: display,
      profileID: profile.profileID,
      technicalLabel: profile.technicalLabel,
      customName: profile.customName)

    let rename = NSMenuItem(
      title: "Rename...",
      action: #selector(renameProfile(_:)),
      keyEquivalent: "")
    rename.target = self
    rename.representedObject = payload
    submenu.addItem(rename)

    let delete = NSMenuItem(
      title: "Delete",
      action: #selector(deleteProfile(_:)),
      keyEquivalent: "")
    delete.target = self
    delete.representedObject = payload
    submenu.addItem(delete)

    item.submenu = submenu
    return item
  }

  func facetMenu(_ title: String, items: [ResolutionMenuItem], display: DisplayMenuState) -> NSMenuItem {
    let item = submenuItem(title, currentValue: items.first(where: \.isSelected)?.title)
    let submenu = NSMenu()
    if items.isEmpty {
      submenu.addItem(disabledItem("Unknown"))
    }
    for facetItem in items {
      let menuItem: NSMenuItem
      if let modeID = facetItem.id, facetItem.isEnabled {
        menuItem = NSMenuItem(
          title: facetItem.title,
          action: #selector(setResolution(_:)),
          keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = ResolutionPayload(
          display: display.display.selector,
          modeID: modeID)
      } else {
        menuItem = disabledItem(facetItem.title)
      }
      menuItem.state = facetItem.isSelected ? .on : .off
      submenu.addItem(menuItem)
    }
    item.submenu = submenu
    return item
  }

  func displayModeMenu(_ display: DisplayMenuState) -> NSMenuItem {
    let item = submenuItem("Display Mode", currentValue: display.displayModeItems.first(where: \.isSelected)?.title)
    let submenu = NSMenu()
    if display.displayModeItems.isEmpty {
      submenu.addItem(disabledItem("Unknown"))
    } else {
      for mode in display.displayModeItems {
        let menuItem = NSMenuItem(
          title: mode.title,
          action: #selector(setDisplayMode(_:)),
          keyEquivalent: "")
        menuItem.target = self
        menuItem.state = mode.isSelected ? .on : .off
        menuItem.representedObject = DisplayModePayload(
          display: display.display.selector,
          modeID: mode.id)
        submenu.addItem(menuItem)
      }
    }
    item.submenu = submenu
    return item
  }

  func ditheringMenu(_ display: DisplayMenuState) -> NSMenuItem {
    let item = submenuItem("Dithering", currentValue: display.ditheringItems.first(where: \.isSelected)?.title)
    item.isEnabled = display.isDitheringEnabled
    let submenu = NSMenu()
    for dithering in display.ditheringItems {
      let menuItem = NSMenuItem(
        title: dithering.title,
        action: #selector(setDithering(_:)),
        keyEquivalent: "")
      menuItem.target = self
      menuItem.state = dithering.isSelected ? .on : .off
      menuItem.representedObject = DitheringPayload(
        display: display.display.selector,
        displayName: display.title,
        enabled: dithering.enabled)
      submenu.addItem(menuItem)
    }
    item.submenu = submenu
    return item
  }

  func iccProfileMenu(_ display: DisplayMenuState) -> NSMenuItem {
    let item = submenuItem("ICC Profile", currentValue: display.iccProfileItems.first(where: \.isSelected)?.name)
    let submenu = NSMenu()
    for profile in display.iccProfileItems {
      let menuItem = NSMenuItem(
        title: profile.title,
        action: profile.url == nil ? nil : #selector(setICCProfile(_:)),
        keyEquivalent: "")
      menuItem.target = self
      menuItem.state = profile.isSelected ? .on : .off
      menuItem.isEnabled = profile.isEnabled
      if let url = profile.url {
        menuItem.toolTip = url.path
        menuItem.representedObject = ICCProfilePayload(
          display: display.display.selector,
          displayName: display.title,
          url: url,
          title: profile.title)
      }
      submenu.addItem(menuItem)
    }
    item.submenu = submenu
    return item
  }

  func submenuItem(_ title: String, currentValue: String?) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    if let currentValue {
      item.badge = NSMenuItemBadge(string: currentValue)
    }
    return item
  }

  func disabledItem(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }

  func quitItem() -> NSMenuItem {
    let item = NSMenuItem(
      title: "Quit",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    item.target = NSApp
    return item
  }
}
