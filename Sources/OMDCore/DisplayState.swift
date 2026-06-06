import Foundation

public struct DisplayState: Codable, Equatable, Sendable {
  public var target: DisplayTarget

  public var currentResolutionModeID: DisplayAxis<ResolutionModeID>
  public var logicalResolution: DisplayAxis<DisplaySize>
  public var backingResolution: DisplayAxis<DisplaySize>
  public var scaleFactor: DisplayAxis<Double>
  public var isHiDPI: DisplayAxis<Bool>
  public var resolutionRefreshHz: DisplayAxis<Double>

  public var currentDisplayModeID: DisplayAxis<DisplayModeID>
  public var outputTimingResolution: DisplayAxis<DisplaySize>
  public var outputTimingRefreshHz: DisplayAxis<Double>
  public var bitDepth: DisplayAxis<Int>
  public var encoding: DisplayAxis<DisplayEncoding>
  public var range: DisplayAxis<DisplayRange>
  public var chroma: DisplayAxis<DisplayChroma>
  public var hdrMode: DisplayAxis<DisplayHDRMode>
  public var isVRR: DisplayAxis<Bool>

  public var ditheringEnabled: DisplayAxis<Bool>
  public var ditheringAvailability: DitheringAvailability
  public var iccProfileURL: DisplayAxis<URL>

  public init(
    target: DisplayTarget, currentResolutionModeID: DisplayAxis<ResolutionModeID>, logicalResolution: DisplayAxis<DisplaySize>,
    backingResolution: DisplayAxis<DisplaySize>, scaleFactor: DisplayAxis<Double>, isHiDPI: DisplayAxis<Bool>, resolutionRefreshHz: DisplayAxis<Double>,
    currentDisplayModeID: DisplayAxis<DisplayModeID>, outputTimingResolution: DisplayAxis<DisplaySize>, outputTimingRefreshHz: DisplayAxis<Double>,
    bitDepth: DisplayAxis<Int>, encoding: DisplayAxis<DisplayEncoding>, range: DisplayAxis<DisplayRange>, chroma: DisplayAxis<DisplayChroma>,
    hdrMode: DisplayAxis<DisplayHDRMode>, isVRR: DisplayAxis<Bool>, ditheringEnabled: DisplayAxis<Bool>,
    ditheringAvailability: DitheringAvailability = .settable, iccProfileURL: DisplayAxis<URL>
  ) {
    self.target = target
    self.currentResolutionModeID = currentResolutionModeID
    self.logicalResolution = logicalResolution
    self.backingResolution = backingResolution
    self.scaleFactor = scaleFactor
    self.isHiDPI = isHiDPI
    self.resolutionRefreshHz = resolutionRefreshHz
    self.currentDisplayModeID = currentDisplayModeID
    self.outputTimingResolution = outputTimingResolution
    self.outputTimingRefreshHz = outputTimingRefreshHz
    self.bitDepth = bitDepth
    self.encoding = encoding
    self.range = range
    self.chroma = chroma
    self.hdrMode = hdrMode
    self.isVRR = isVRR
    self.ditheringEnabled = ditheringEnabled
    self.ditheringAvailability = ditheringAvailability
    self.iccProfileURL = iccProfileURL
  }
}
