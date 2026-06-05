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

    let current = NSMenuItem(title: display.currentTitle, action: nil, keyEquivalent: "")
    current.submenu = currentMenu(display)
    submenu.addItem(current)
    submenu.addItem(.separator())
    submenu.addItem(resolutionMenu(display))
    submenu.addItem(displayModeMenu(display))

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
      title: profile.title)

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

  func resolutionMenu(_ display: DisplayMenuState) -> NSMenuItem {
    let item = NSMenuItem(title: "Resolution", action: nil, keyEquivalent: "")
    let submenu = NSMenu()
    if display.resolutionItems.isEmpty {
      submenu.addItem(disabledItem("Unavailable"))
    } else {
      for resolution in display.resolutionItems {
        let menuItem = NSMenuItem(
          title: resolution.title,
          action: #selector(setResolution(_:)),
          keyEquivalent: "")
        menuItem.target = self
        menuItem.state = resolution.isSelected ? .on : .off
        menuItem.representedObject = ResolutionPayload(
          display: display.display.selector,
          modeID: resolution.id)
        submenu.addItem(menuItem)
      }
    }
    item.submenu = submenu
    return item
  }

  func displayModeMenu(_ display: DisplayMenuState) -> NSMenuItem {
    let item = NSMenuItem(title: "Display Mode", action: nil, keyEquivalent: "")
    let submenu = NSMenu()
    if display.displayModeItems.isEmpty {
      submenu.addItem(disabledItem("Unavailable"))
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
