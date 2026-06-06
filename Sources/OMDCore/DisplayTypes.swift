import Foundation

public struct DisplaySelector: Codable, Hashable, Sendable, CustomStringConvertible {
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue }

  package var isStableIdentity: Bool {
    rawValue.hasPrefix("uuid:")
  }
}

public struct ResolutionModeID: Codable, Hashable, Sendable, CustomStringConvertible {
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue }
}

public struct DisplayModeID: Codable, Hashable, Sendable, CustomStringConvertible {
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue }
}

public struct DisplaySize: Codable, Equatable, Sendable, CustomStringConvertible {
  public var width: Int
  public var height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }

  public var description: String { "\(width)x\(height)" }
}

public enum AxisReadability: String, Codable, Sendable {
  case readable
  case unreadable
  case degraded
}

public struct DisplayAxis<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
  public var value: Value?
  public var readability: AxisReadability
  public var source: String?

  public init(value: Value?, readability: AxisReadability, source: String? = nil) {
    self.value = value
    self.readability = readability
    self.source = source
  }

  public static func readable(_ value: Value, source: String? = nil) -> Self {
    Self(value: value, readability: .readable, source: source)
  }

  public static func unreadable(source: String? = nil) -> Self {
    Self(value: nil, readability: .unreadable, source: source)
  }

  public static func degraded(_ value: Value? = nil, source: String? = nil) -> Self {
    Self(value: value, readability: .degraded, source: source)
  }
}

public struct DisplayListResult<Item: Codable & Equatable & Sendable>: Codable, Equatable,
  Sendable
{
  public var readability: AxisReadability
  public var source: String?
  public var reason: String?
  public var items: [Item]

  public init(
    readability: AxisReadability,
    source: String? = nil,
    reason: String? = nil,
    items: [Item] = []
  ) {
    self.readability = readability
    self.source = source
    self.reason = reason
    self.items = items
  }

  public static func readable(_ items: [Item], source: String? = nil) -> Self {
    Self(readability: .readable, source: source, items: items)
  }

  public static func unreadable(_ reason: String, source: String? = nil) -> Self {
    Self(readability: .unreadable, source: source, reason: reason, items: [])
  }

  public static func degraded(_ items: [Item], reason: String, source: String? = nil) -> Self {
    Self(readability: .degraded, source: source, reason: reason, items: items)
  }
}

public struct ICCProfile: Codable, Equatable, Sendable {
  public var name: String
  public var url: URL

  public init(name: String, url: URL) {
    self.name = name
    self.url = url
  }
}

public enum DitheringAvailability: String, Codable, Equatable, Sendable {
  case settable
  case noWritableFramebuffer
  case noMatchingActiveFramebuffer
  case ambiguousFramebuffer

  public var canSet: Bool {
    self == .settable
  }
}

public enum DisplayEncoding: String, Codable, Sendable {
  case none
  case rgb
  case ycbcr
  case unknown
}

public enum DisplayRange: String, Codable, Sendable {
  case full
  case limited
  case unknown
}

public enum DisplayChroma: String, Codable, Sendable {
  case none
  case c444 = "444"
  case c422 = "422"
  case c420 = "420"
  case unknown
}

public enum DisplayHDRMode: String, Codable, Sendable {
  case sdr
  case hdr10
  case dolbyVision = "dolby-vision"
  case dolbyVisionLowLatency = "dolby-vision-low-latency"
  case unknown
}

public struct DisplayTarget: Codable, Equatable, Sendable {
  public var selector: DisplaySelector
  public var displayID: UInt32
  public var label: String
  public var isMain: Bool
  public var isBuiltin: Bool

  public init(
    selector: DisplaySelector,
    displayID: UInt32,
    label: String,
    isMain: Bool,
    isBuiltin: Bool
  ) {
    self.selector = selector
    self.displayID = displayID
    self.label = label
    self.isMain = isMain
    self.isBuiltin = isBuiltin
  }
}

public struct ResolutionMode: Codable, Equatable, Sendable {
  public var id: ResolutionModeID
  public var logicalResolution: DisplaySize
  public var backingResolution: DisplaySize
  public var scaleFactor: Double
  public var isHiDPI: Bool
  public var refreshHz: Double?

  public init(
    id: ResolutionModeID,
    logicalResolution: DisplaySize,
    backingResolution: DisplaySize,
    scaleFactor: Double,
    isHiDPI: Bool,
    refreshHz: Double?
  ) {
    self.id = id
    self.logicalResolution = logicalResolution
    self.backingResolution = backingResolution
    self.scaleFactor = scaleFactor
    self.isHiDPI = isHiDPI
    self.refreshHz = refreshHz
  }
}

public struct DisplayMode: Codable, Equatable, Sendable {
  public var id: DisplayModeID
  public var outputTimingResolution: DisplaySize
  public var outputTimingRefreshHz: Double?
  public var bitDepth: Int?
  public var encoding: DisplayEncoding
  public var range: DisplayRange
  public var chroma: DisplayChroma
  public var hdrMode: DisplayHDRMode
  public var hdrModeRaw: String?
  public var colorModeRaw: String?
  public var modeDescription: String?
  public var isVirtual: Bool
  public var isVRR: Bool
  public var isHighBandwidth: Bool

  public init(
    id: DisplayModeID,
    outputTimingResolution: DisplaySize,
    outputTimingRefreshHz: Double?,
    bitDepth: Int?,
    encoding: DisplayEncoding,
    range: DisplayRange = .unknown,
    chroma: DisplayChroma = .unknown,
    hdrMode: DisplayHDRMode = .unknown,
    hdrModeRaw: String? = nil,
    colorModeRaw: String? = nil,
    modeDescription: String? = nil,
    isVirtual: Bool = false,
    isVRR: Bool = false,
    isHighBandwidth: Bool = false
  ) {
    self.id = id
    self.outputTimingResolution = outputTimingResolution
    self.outputTimingRefreshHz = outputTimingRefreshHz
    self.bitDepth = bitDepth
    self.encoding = encoding
    self.range = range
    self.chroma = chroma
    self.hdrMode = hdrMode
    self.hdrModeRaw = hdrModeRaw
    self.colorModeRaw = colorModeRaw
    self.modeDescription = modeDescription
    self.isVirtual = isVirtual
    self.isVRR = isVRR
    self.isHighBandwidth = isHighBandwidth
  }
}
