import Foundation
import OMDCore

package struct AppMenuState: Equatable, Sendable {
  package var displays: [DisplayMenuState]

  package init(displays: [DisplayMenuState]) {
    self.displays = displays
  }
}

package struct DisplayMenuState: Equatable, Sendable {
  package var display: DisplayTarget
  package var title: String
  package var currentTitle: String
  package var currentItems: [CurrentProfileMenuItem]
  package var profileItems: [ProfileMenuItem]
  package var resolutionItems: [ResolutionMenuItem]
  package var displayModeItems: [DisplayModeMenuItem]
  package var degradedReason: String?

  package init(
    display: DisplayTarget,
    title: String,
    currentTitle: String,
    currentItems: [CurrentProfileMenuItem],
    profileItems: [ProfileMenuItem],
    resolutionItems: [ResolutionMenuItem],
    displayModeItems: [DisplayModeMenuItem],
    degradedReason: String? = nil
  ) {
    self.display = display
    self.title = title
    self.currentTitle = currentTitle
    self.currentItems = currentItems
    self.profileItems = profileItems
    self.resolutionItems = resolutionItems
    self.displayModeItems = displayModeItems
    self.degradedReason = degradedReason
  }
}

package struct CurrentProfileMenuItem: Equatable, Sendable {
  package var profileID: UUID?
  package var title: String
  package var isSelected: Bool

  package init(profileID: UUID?, title: String, isSelected: Bool) {
    self.profileID = profileID
    self.title = title
    self.isSelected = isSelected
  }
}

package struct ProfileMenuItem: Equatable, Sendable {
  package var profileID: UUID
  package var title: String

  package init(profileID: UUID, title: String) {
    self.profileID = profileID
    self.title = title
  }
}

package struct ResolutionMenuItem: Equatable, Sendable {
  package var id: ResolutionModeID
  package var title: String
  package var isSelected: Bool

  package init(id: ResolutionModeID, title: String, isSelected: Bool) {
    self.id = id
    self.title = title
    self.isSelected = isSelected
  }
}

package struct DisplayModeMenuItem: Equatable, Sendable {
  package var id: DisplayModeID
  package var title: String
  package var isSelected: Bool

  package init(id: DisplayModeID, title: String, isSelected: Bool) {
    self.id = id
    self.title = title
    self.isSelected = isSelected
  }
}
