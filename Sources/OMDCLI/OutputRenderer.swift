import Foundation
import OMDCore

enum OutputRenderer {
  static func renderDisplays(_ displays: [DisplayTarget], json: Bool) throws -> String {
    if json { return try encode(displays.map(DisplayTargetOutput.init)) }
    return renderTable(
      headers: ["main", "builtin", "label", "selector"],
      rows: displays.map { display in
        [display.isMain ? "yes" : "no", display.isBuiltin ? "yes" : "no", display.label, displayListSelectorText(display.selector)]
      })
  }

  static func renderState(_ state: DisplayState, json: Bool) throws -> String {
    if json { return try encode(DisplayStateOutput(state)) }
    let pairs: [(String, String)] = [
      ("display", state.target.selector.rawValue), ("label", state.target.label),
      ("resolution.logical", state.logicalResolution.value?.description ?? "unknown"),
      ("resolution.backing", state.backingResolution.value?.description ?? "unknown"),
      ("resolution.scale", state.scaleFactor.value.map { String(format: "%.3g", $0) } ?? "unknown"),
      ("resolution.hidpi", state.isHiDPI.value.map { $0 ? "yes" : "no" } ?? "unknown"),
      ("resolution.refresh", state.resolutionRefreshHz.value.map { String(format: "%.3g", $0) } ?? "unknown"),
      ("displayMode.timing", state.outputTimingResolution.value?.description ?? "unknown"),
      ("displayMode.bpc", state.bitDepth.value.map(String.init) ?? "unknown"), ("displayMode.encoding", state.encoding.value.map(encodingText) ?? "unknown"),
      ("displayMode.range", state.range.value?.rawValue ?? "unknown"), ("displayMode.chroma", state.chroma.value.map(chromaText) ?? "unknown"),
      ("displayMode.hdr", state.hdrMode.value?.rawValue ?? "unknown"), ("displayMode.vrr", state.isVRR.value.map { $0 ? "on" : "off" } ?? "unknown"),
      ("dithering", state.ditheringEnabled.value.map { $0 ? "on" : "off" } ?? "unknown"), ("icc", state.iccProfileURL.value?.lastPathComponent ?? "unknown"),
    ]
    return pairs.map { "\($0.0): \($0.1)" }.joined(separator: "\n") + "\n"
  }

  static func renderResolutionModes(_ result: DisplayListResult<ResolutionMode>, json: Bool) throws -> String {
    if json { return try encode(ResolutionModesOutput(result)) }
    guard result.readability != .unreadable else { return "resolution modes unavailable: \(result.reason ?? "unknown")\n" }
    let modes = sortedResolutionModesForTable(result.items)
    return renderTable(
      headers: ["logical", "backing", "scale", "hidpi", "refresh", "resolutionMode"],
      rows: modes.map { mode in
        [
          mode.logicalResolution.description, mode.backingResolution.description, String(format: "%.3g", mode.scaleFactor), mode.isHiDPI ? "yes" : "no",
          mode.refreshHz.map { String(format: "%.3g", $0) } ?? "unknown", mode.id.rawValue,
        ]
      })
  }

  static func renderDisplayModes(_ result: DisplayListResult<DisplayMode>, json: Bool) throws -> String {
    if json { return try encode(DisplayModesOutput(result)) }
    guard result.readability != .unreadable else { return "display modes unavailable: \(result.reason ?? "unknown")\n" }
    let modes = sortedDisplayModesForTable(result.items)
    return renderTable(
      headers: ["timing", "hdr", "refresh", "encoding", "bpc", "range", "chroma", "displayMode"],
      rows: modes.map { mode in
        [
          mode.outputTimingResolution.description, mode.hdrMode.rawValue, displayModeRefreshText(mode), encodingText(mode.encoding),
          mode.bitDepth.map(String.init) ?? "unknown", mode.range.rawValue, chromaText(mode.chroma), mode.id.rawValue,
        ]
      })
  }

  static func renderICCProfiles(_ profiles: [ICCProfile], json: Bool) throws -> String {
    if json { return try encode(profiles.map(ICCProfileOutput.init)) }
    return renderTable(headers: ["name", "path"], rows: profiles.map { profile in [profile.name, profile.url.standardizedFileURL.path] })
  }

  static func renderOperations(_ operations: [OperationReport], json: Bool) throws -> String {
    if json { return try encode(operations) }
    var lines: [String] = []
    for operation in operations {
      lines.append("\(operation.operation): \(operation.skipped ? "skipped" : operation.status.rawValue)\(operation.reason.map { " (\($0))" } ?? "")")
      for restore in operation.restore ?? [] {
        lines.append("restore.\(restore.operation): \(restore.status.rawValue)\(restore.reason.map { " (\($0))" } ?? "")")
      }
    }
    return lines.joined(separator: "\n") + "\n"
  }

  static func encode<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self) + "\n"
  }

  private static func sortedResolutionModesForTable(_ modes: [ResolutionMode]) -> [ResolutionMode] {
    var groups: [(backing: DisplaySize, modes: [ResolutionMode])] = []
    for mode in modes {
      if let index = groups.firstIndex(where: { $0.backing == mode.backingResolution }) {
        groups[index].modes.append(mode)
      } else {
        groups.append((mode.backingResolution, [mode]))
      }
    }
    return groups.sorted { lhs, rhs in
      let lhsPixels = pixelCount(lhs.backing)
      let rhsPixels = pixelCount(rhs.backing)
      if lhsPixels != rhsPixels { return lhsPixels < rhsPixels }
      if lhs.backing.width != rhs.backing.width { return lhs.backing.width < rhs.backing.width }
      return lhs.backing.height < rhs.backing.height
    }.flatMap { group in
      group.modes.sorted { lhs, rhs in
        let lhsLogical = lhs.logicalResolution
        let rhsLogical = rhs.logicalResolution
        let lhsLogicalPixels = pixelCount(lhsLogical)
        let rhsLogicalPixels = pixelCount(rhsLogical)
        if lhsLogicalPixels != rhsLogicalPixels { return lhsLogicalPixels < rhsLogicalPixels }
        if lhs.refreshHz != rhs.refreshHz { return optionalDoubleRank(lhs.refreshHz) > optionalDoubleRank(rhs.refreshHz) }
        if lhs.isHiDPI != rhs.isHiDPI { return lhs.isHiDPI }
        if lhs.scaleFactor != rhs.scaleFactor { return lhs.scaleFactor > rhs.scaleFactor }
        if lhsLogical.width != rhsLogical.width { return lhsLogical.width < rhsLogical.width }
        if lhsLogical.height != rhsLogical.height { return lhsLogical.height < rhsLogical.height }
        return lhs.id.rawValue < rhs.id.rawValue
      }
    }
  }

  private static func sortedDisplayModesForTable(_ modes: [DisplayMode]) -> [DisplayMode] {
    modes.sorted { lhs, rhs in
      let lhsTiming = lhs.outputTimingResolution
      let rhsTiming = rhs.outputTimingResolution
      let lhsPixels = pixelCount(lhsTiming)
      let rhsPixels = pixelCount(rhsTiming)
      if lhsPixels != rhsPixels { return lhsPixels < rhsPixels }
      if lhs.hdrMode != rhs.hdrMode { return hdrRank(lhs.hdrMode) < hdrRank(rhs.hdrMode) }
      if lhs.outputTimingRefreshHz != rhs.outputTimingRefreshHz {
        return optionalDoubleRank(lhs.outputTimingRefreshHz) > optionalDoubleRank(rhs.outputTimingRefreshHz)
      }
      if lhs.isVRR != rhs.isVRR { return !lhs.isVRR }
      if lhs.encoding != rhs.encoding { return encodingRank(lhs.encoding) < encodingRank(rhs.encoding) }
      if lhs.bitDepth != rhs.bitDepth { return optionalIntRank(lhs.bitDepth) > optionalIntRank(rhs.bitDepth) }
      if lhs.range != rhs.range { return rangeRank(lhs.range) < rangeRank(rhs.range) }
      if lhs.chroma != rhs.chroma { return chromaRank(lhs.chroma) < chromaRank(rhs.chroma) }
      if lhsTiming.width != rhsTiming.width { return lhsTiming.width < rhsTiming.width }
      if lhsTiming.height != rhsTiming.height { return lhsTiming.height < rhsTiming.height }
      return lhs.id.rawValue < rhs.id.rawValue
    }
  }

  private static func pixelCount(_ size: DisplaySize) -> Int { size.width * size.height }

  private static func optionalDoubleRank(_ value: Double?) -> Double { value ?? -Double.greatestFiniteMagnitude }

  private static func optionalIntRank(_ value: Int?) -> Int { value ?? Int.min }

  private static func displayModeRefreshText(_ mode: DisplayMode) -> String {
    let refresh = mode.outputTimingRefreshHz.map { String(format: "%.3g", $0) } ?? "unknown"
    return mode.isVRR ? "\(refresh) (VRR)" : refresh
  }

  private static func chromaText(_ value: DisplayChroma) -> String { value == .none ? "-" : value.rawValue }

  private static func encodingText(_ value: DisplayEncoding) -> String { value == .none ? "-" : value.rawValue }

  private static func hdrRank(_ value: DisplayHDRMode) -> Int {
    switch value {
    case .sdr: 0
    case .hdr10: 1
    case .dolbyVision: 2
    case .dolbyVisionLowLatency: 3
    case .unknown: 4
    }
  }

  private static func encodingRank(_ value: DisplayEncoding) -> Int {
    switch value {
    case .rgb: 0
    case .ycbcr: 1
    case .none: 2
    case .unknown: 3
    }
  }

  private static func rangeRank(_ value: DisplayRange) -> Int {
    switch value {
    case .full: 0
    case .limited: 1
    case .unknown: 2
    }
  }

  private static func chromaRank(_ value: DisplayChroma) -> Int {
    switch value {
    case .none: 0
    case .c444: 1
    case .c422: 2
    case .c420: 3
    case .unknown: 4
    }
  }

  private static func renderTable(headers: [String], rows: [[String]]) -> String {
    precondition(!headers.isEmpty, "table headers must not be empty")
    precondition(rows.allSatisfy { $0.count == headers.count }, "table rows must match header count")

    let table = [headers] + rows
    let widths = headers.indices.map { index in table.map { $0[index].count }.max() ?? 0 }
    let lines = table.map { row in
      row.enumerated().map { index, value in
        if index == row.count - 1 { return value }
        let padding = String(repeating: " ", count: widths[index] - value.count)
        return value + padding
      }.joined(separator: "  ").trimmingCharacters(in: .whitespaces)
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private static func displayListSelectorText(_ selector: DisplaySelector) -> String { selector.isStableIdentity ? selector.rawValue : "" }
}

private struct DisplayTargetOutput: Codable {
  var selector: String
  var main: Bool
  var builtin: Bool
  var label: String

  init(_ display: DisplayTarget) {
    self.selector = display.selector.isStableIdentity ? display.selector.rawValue : ""
    self.main = display.isMain
    self.builtin = display.isBuiltin
    self.label = display.label
  }
}

private struct DisplayStateOutput: Codable {
  var display: String
  var label: String
  var resolution: ResolutionOutput
  var displayMode: DisplayModeOutput
  var dithering: Bool?
  var icc: String?

  init(_ state: DisplayState) {
    self.display = state.target.selector.rawValue
    self.label = state.target.label
    self.resolution = ResolutionOutput(state)
    self.displayMode = DisplayModeOutput(state)
    self.dithering = state.ditheringEnabled.value
    self.icc = state.iccProfileURL.value?.lastPathComponent
  }
}

private struct ResolutionOutput: Codable {
  var currentMode: String?
  var logical: DisplaySize?
  var backing: DisplaySize?
  var scale: Double?
  var hidpi: Bool?
  var refreshHz: Double?

  init(_ state: DisplayState) {
    self.currentMode = state.currentResolutionModeID.value?.rawValue
    self.logical = state.logicalResolution.value
    self.backing = state.backingResolution.value
    self.scale = state.scaleFactor.value
    self.hidpi = state.isHiDPI.value
    self.refreshHz = state.resolutionRefreshHz.value
  }
}

private struct DisplayModeOutput: Codable {
  var currentMode: String?
  var timing: DisplaySize?
  var refreshHz: Double?
  var bpc: Int?
  var encoding: String?
  var range: String?
  var chroma: String?
  var hdr: String?
  var vrr: Bool?

  init(_ state: DisplayState) {
    self.currentMode = state.currentDisplayModeID.value?.rawValue
    self.timing = state.outputTimingResolution.value
    self.refreshHz = state.outputTimingRefreshHz.value
    self.bpc = state.bitDepth.value
    self.encoding = state.encoding.value?.rawValue
    self.range = state.range.value?.rawValue
    self.chroma = state.chroma.value?.rawValue
    self.hdr = state.hdrMode.value?.rawValue
    self.vrr = state.isVRR.value
  }
}

private struct ResolutionModesOutput: Codable {
  var readability: AxisReadability
  var reason: String?
  var modes: [ResolutionMode]

  init(_ result: DisplayListResult<ResolutionMode>) {
    self.readability = result.readability
    self.reason = result.reason
    self.modes = result.items
  }
}

private struct DisplayModesOutput: Codable {
  var readability: AxisReadability
  var reason: String?
  var modes: [DisplayMode]

  init(_ result: DisplayListResult<DisplayMode>) {
    self.readability = result.readability
    self.reason = result.reason
    self.modes = result.items
  }
}

private struct ICCProfileOutput: Codable {
  var name: String
  var path: String

  init(_ profile: ICCProfile) {
    self.name = profile.name
    self.path = profile.url.standardizedFileURL.path
  }
}
