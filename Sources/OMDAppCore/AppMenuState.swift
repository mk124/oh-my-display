import Foundation
import OMDCore

package struct AppMenuState: Equatable, Sendable {
  package var displays: [DisplayMenuState]
}

package struct DisplayMenuState: Equatable, Sendable {
  package var display: DisplayTarget
  package var title: String
  package var currentTitle: String
  package var currentItems: [CurrentProfileMenuItem]
  package var profileItems: [ProfileMenuItem]
  package var hidpiItems: [ResolutionMenuItem] = []
  package var resolutionItems: [ResolutionMenuItem]
  package var refreshRateItems: [ResolutionMenuItem] = []
  package var displayModeItems: [DisplayModeMenuItem]
  package var ditheringItems: [DitheringMenuItem] = []
  package var isDitheringEnabled = true
  package var iccProfileItems: [ICCProfileMenuItem] = []
  package var degradedReason: String?
}

package struct CurrentProfileMenuItem: Equatable, Sendable {
  package var profileID: UUID?
  package var title: String
  package var isSelected: Bool
}

package struct ProfileMenuItem: Equatable, Sendable {
  package var profileID: UUID
  package var title: String
}

package struct ResolutionMenuItem: Equatable, Sendable {
  package var id: ResolutionModeID?
  package var title: String
  package var isSelected: Bool
  package var isEnabled = true
}

package struct DisplayModeMenuItem: Equatable, Sendable {
  package var id: DisplayModeID
  package var title: String
  package var isSelected: Bool
}

package struct DitheringMenuItem: Equatable, Sendable {
  package var enabled: Bool
  package var title: String
  package var isSelected: Bool
}

package struct ICCProfileMenuItem: Equatable, Sendable {
  package var url: URL?
  package var title: String
  package var isSelected = false
  package var isEnabled = true
}
