import Foundation

package protocol DisplayClient: Sendable {
  func listDisplays() throws -> [DisplayTarget]
  func readDisplayState(_ display: DisplaySelector) throws -> DisplayState
  func listResolutionModes(_ display: DisplaySelector) throws -> DisplayListResult<ResolutionMode>
  func setResolutionMode(_ display: DisplaySelector, modeID: ResolutionModeID) throws
    -> DisplaySetResult
  func listDisplayModes(_ display: DisplaySelector) throws -> DisplayListResult<DisplayMode>
  func setDisplayMode(_ display: DisplaySelector, modeID: DisplayModeID) throws -> DisplaySetResult
  func setDithering(_ display: DisplaySelector, enabled: Bool) throws -> DisplaySetResult
  func listICCProfiles() throws -> [ICCProfile]
  func listDisplayAssignableICCProfiles() throws -> [ICCProfile]
  func setICCProfile(_ display: DisplaySelector, profileURL: URL) throws -> DisplaySetResult
}

package struct LiveDisplayClient: DisplayClient {
  package init() {}

  package func listDisplays() throws -> [DisplayTarget] {
    try OMDCore.listDisplays()
  }

  package func readDisplayState(_ display: DisplaySelector) throws -> DisplayState {
    try OMDCore.readDisplayState(display)
  }

  package func listResolutionModes(_ display: DisplaySelector) throws
    -> DisplayListResult<ResolutionMode>
  {
    try OMDCore.listResolutionModes(display)
  }

  package func setResolutionMode(_ display: DisplaySelector, modeID: ResolutionModeID) throws
    -> DisplaySetResult
  {
    try OMDCore.setResolutionMode(display, modeID: modeID)
  }

  package func listDisplayModes(_ display: DisplaySelector) throws -> DisplayListResult<DisplayMode> {
    try OMDCore.listDisplayModes(display)
  }

  package func setDisplayMode(_ display: DisplaySelector, modeID: DisplayModeID) throws
    -> DisplaySetResult
  {
    try OMDCore.setDisplayMode(display, modeID: modeID)
  }

  package func setDithering(_ display: DisplaySelector, enabled: Bool) throws -> DisplaySetResult {
    try OMDCore.setDithering(display, enabled: enabled)
  }

  package func listICCProfiles() throws -> [ICCProfile] {
    try OMDCore.listICCProfiles()
  }

  package func listDisplayAssignableICCProfiles() throws -> [ICCProfile] {
    try OMDCore.listDisplayAssignableICCProfiles()
  }

  package func setICCProfile(_ display: DisplaySelector, profileURL: URL) throws
    -> DisplaySetResult
  {
    try OMDCore.setICCProfile(display, profileURL: profileURL)
  }
}
