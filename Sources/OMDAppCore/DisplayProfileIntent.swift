import Foundation
import OMDCore

package struct DisplayProfileIntent: Codable, Equatable, Sendable {
  package var resolution: ResolutionIntent?
  package var displayMode: DisplayModeIntent?
  package var ditheringEnabled: Bool?
  package var iccProfileURL: URL?

  package init(
    resolution: ResolutionIntent? = nil,
    displayMode: DisplayModeIntent? = nil,
    ditheringEnabled: Bool? = nil,
    iccProfileURL: URL? = nil
  ) {
    self.resolution = resolution
    self.displayMode = displayMode
    self.ditheringEnabled = ditheringEnabled
    self.iccProfileURL = iccProfileURL
  }

  package var technicalSummary: String {
    let hdr = displayMode?.hdrMode?.label ?? "Unknown"
    let size = (displayMode?.outputTimingResolution ?? resolution?.backingResolution)?.commonLabel
      ?? "Unknown"
    let refresh = displayMode?.outputTimingRefreshHz ?? resolution?.refreshHz
    let parts = [
      "[\(hdr)]",
      size,
      refresh.map(Self.formatRefresh),
      displayMode?.encoding?.technicalLabel,
      displayMode?.bitDepth.map { "\($0)-bit" },
    ].compactMap { $0 }.filter { !$0.isEmpty }

    return parts.isEmpty ? "Unknown Display State" : parts.joined(separator: " ")
  }

  private static func formatRefresh(_ value: Double) -> String {
    if value.rounded() == value {
      return "\(Int(value))Hz"
    }
    return "\(String(format: "%.2f", value))Hz"
  }
}

package struct ResolutionIntent: Codable, Equatable, Sendable {
  package var logicalResolution: DisplaySize
  package var backingResolution: DisplaySize
  package var scaleFactor: Double
  package var isHiDPI: Bool
  package var refreshHz: Double?

  package init(
    logicalResolution: DisplaySize,
    backingResolution: DisplaySize,
    scaleFactor: Double,
    isHiDPI: Bool,
    refreshHz: Double?
  ) {
    self.logicalResolution = logicalResolution
    self.backingResolution = backingResolution
    self.scaleFactor = scaleFactor
    self.isHiDPI = isHiDPI
    self.refreshHz = refreshHz
  }
}

package struct DisplayModeIntent: Codable, Equatable, Sendable {
  package var outputTimingResolution: DisplaySize
  package var outputTimingRefreshHz: Double?
  package var bitDepth: Int?
  package var encoding: DisplayEncoding?
  package var range: DisplayRange?
  package var chroma: DisplayChroma?
  package var hdrMode: DisplayHDRMode?
  package var isVRR: Bool?

  package init(
    outputTimingResolution: DisplaySize,
    outputTimingRefreshHz: Double?,
    bitDepth: Int?,
    encoding: DisplayEncoding?,
    range: DisplayRange?,
    chroma: DisplayChroma?,
    hdrMode: DisplayHDRMode?,
    isVRR: Bool?
  ) {
    self.outputTimingResolution = outputTimingResolution
    self.outputTimingRefreshHz = outputTimingRefreshHz
    self.bitDepth = bitDepth
    self.encoding = encoding
    self.range = range
    self.chroma = chroma
    self.hdrMode = hdrMode
    self.isVRR = isVRR
  }
}
