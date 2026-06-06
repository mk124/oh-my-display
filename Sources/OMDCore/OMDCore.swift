import Foundation

public func listDisplays() throws -> [DisplayTarget] { try DisplayStateReader().listDisplays() }

public func readDisplayState(_ display: DisplaySelector) throws -> DisplayState { try DisplayStateReader().readDisplayState(display) }

public func listResolutionModes(_ display: DisplaySelector) throws -> DisplayListResult<ResolutionMode> {
  try ResolutionModeService().listResolutionModes(display)
}

public func setResolutionMode(_ display: DisplaySelector, modeID: ResolutionModeID) throws -> DisplaySetResult {
  try ResolutionModeService().setResolutionMode(display, modeID: modeID)
}

public func listDisplayModes(_ display: DisplaySelector) throws -> DisplayListResult<DisplayMode> { try DisplayModeService().listDisplayModes(display) }

public func setDisplayMode(_ display: DisplaySelector, modeID: DisplayModeID) throws -> DisplaySetResult {
  try DisplayModeService().setDisplayMode(display, modeID: modeID)
}

public func setDithering(_ display: DisplaySelector, enabled: Bool) throws -> DisplaySetResult {
  try DitheringService().setDithering(display, enabled: enabled)
}

public func listICCProfiles() throws -> [ICCProfile] { try ICCProfileService().listICCProfiles() }

public func listDisplayAssignableICCProfiles() throws -> [ICCProfile] { try ICCProfileService().listDisplayAssignableICCProfiles() }

public func setICCProfile(_ display: DisplaySelector, profileURL: URL) throws -> DisplaySetResult {
  try ICCProfileService().setICCProfile(display, profileURL: profileURL)
}
