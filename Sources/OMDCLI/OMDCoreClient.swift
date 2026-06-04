import Foundation
import OMDCore

protocol OMDCoreClient: Sendable {
  func listDisplays() throws -> [DisplayTarget]
  func readDisplayState(_ display: DisplaySelector) throws -> DisplayState
  func listResolutionModes(_ display: DisplaySelector) throws
    -> DisplayListResult<ResolutionMode>
  func setResolutionMode(_ display: DisplaySelector, modeID: ResolutionModeID) throws
    -> DisplaySetResult
  func listDisplayModes(_ display: DisplaySelector) throws
    -> DisplayListResult<DisplayMode>
  func setDisplayMode(_ display: DisplaySelector, modeID: DisplayModeID) throws
    -> DisplaySetResult
  func setDithering(_ display: DisplaySelector, enabled: Bool) throws -> DisplaySetResult
  func setICCProfile(_ display: DisplaySelector, profileURL: URL) throws -> DisplaySetResult
}

struct LiveOMDCoreClient: OMDCoreClient {
  init() {}

  func listDisplays() throws -> [DisplayTarget] {
    try OMDCore.listDisplays()
  }

  func readDisplayState(_ display: DisplaySelector) throws -> DisplayState {
    try OMDCore.readDisplayState(display)
  }

  func listResolutionModes(_ display: DisplaySelector) throws
    -> DisplayListResult<ResolutionMode>
  {
    try OMDCore.listResolutionModes(display)
  }

  func setResolutionMode(
    _ display: DisplaySelector, modeID: ResolutionModeID
  ) throws -> DisplaySetResult {
    try OMDCore.setResolutionMode(display, modeID: modeID)
  }

  func listDisplayModes(_ display: DisplaySelector) throws
    -> DisplayListResult<DisplayMode>
  {
    try OMDCore.listDisplayModes(display)
  }

  func setDisplayMode(
    _ display: DisplaySelector, modeID: DisplayModeID
  ) throws -> DisplaySetResult {
    try OMDCore.setDisplayMode(display, modeID: modeID)
  }

  func setDithering(_ display: DisplaySelector, enabled: Bool) throws -> DisplaySetResult {
    try OMDCore.setDithering(display, enabled: enabled)
  }

  func setICCProfile(_ display: DisplaySelector, profileURL: URL) throws -> DisplaySetResult
  {
    try OMDCore.setICCProfile(display, profileURL: profileURL)
  }
}
