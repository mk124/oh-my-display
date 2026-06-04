import Foundation
import OMDCore

enum OutputRenderer {
  static func renderDisplays(_ displays: [DisplayTarget], json: Bool) throws -> String {
    if json {
      return try encode(displays.map(DisplayTargetOutput.init))
    }
    return renderTable(
      headers: ["main", "builtin", "label", "selector"],
      rows: displays.map { display in
      [
        display.isMain ? "yes" : "no",
        display.isBuiltin ? "yes" : "no",
        display.label,
        display.selector.rawValue,
      ]
    })
  }

  static func renderState(_ state: DisplayState, json: Bool) throws -> String {
    if json {
      return try encode(DisplayStateOutput(state))
    }
    let pairs: [(String, String)] = [
      ("display", state.target.selector.rawValue),
      ("label", state.target.label),
      ("resolution.logical", state.logicalResolution.value?.description ?? "unknown"),
      ("resolution.backing", state.backingResolution.value?.description ?? "unknown"),
      ("resolution.scale", state.scaleFactor.value.map { String(format: "%.3g", $0) } ?? "unknown"),
      ("resolution.hidpi", state.isHiDPI.value.map { $0 ? "yes" : "no" } ?? "unknown"),
      ("resolution.refresh", state.resolutionRefreshHz.value.map { String(format: "%.3g", $0) } ?? "unknown"),
      ("displayMode.timing", state.outputTimingResolution.value?.description ?? "unknown"),
      ("displayMode.bpc", state.bitDepth.value.map(String.init) ?? "unknown"),
      ("displayMode.encoding", state.encoding.value?.rawValue ?? "unknown"),
      ("displayMode.range", state.range.value?.rawValue ?? "unknown"),
      ("displayMode.chroma", state.chroma.value?.rawValue ?? "unknown"),
      ("displayMode.hdr", state.hdrMode.value?.rawValue ?? "unknown"),
      ("dithering", state.ditheringEnabled.value.map { $0 ? "on" : "off" } ?? "unknown"),
      ("icc", state.iccProfileURL.value?.lastPathComponent ?? "unknown"),
    ]
    return pairs.map { "\($0.0): \($0.1)" }.joined(separator: "\n") + "\n"
  }

  static func renderResolutionModes(
    _ result: DisplayListResult<ResolutionMode>, json: Bool
  ) throws -> String {
    if json {
      return try encode(ResolutionModesOutput(result))
    }
    guard result.readability != .unreadable else {
      return "resolution modes unavailable: \(result.reason ?? "unknown")\n"
    }
    let modes = groupedByBacking(result.items)
    return renderTable(
      headers: ["logical", "backing", "scale", "hidpi", "refresh", "resolutionMode"],
      rows: modes.map { mode in
        [
          mode.logicalResolution.description,
          mode.backingResolution.description,
          String(format: "%.3g", mode.scaleFactor),
          mode.isHiDPI ? "yes" : "no",
          mode.refreshHz.map { String(format: "%.3g", $0) } ?? "unknown",
          mode.id.rawValue,
        ]
      })
  }

  static func renderDisplayModes(
    _ result: DisplayListResult<DisplayMode>, json: Bool
  ) throws -> String {
    if json {
      return try encode(DisplayModesOutput(result))
    }
    guard result.readability != .unreadable else {
      return "display modes unavailable: \(result.reason ?? "unknown")\n"
    }
    return renderTable(
      headers: ["timing", "refresh", "encoding", "bpc", "range", "chroma", "hdr", "displayMode"],
      rows: result.items.map { mode in
      [
        mode.outputTimingResolution.description,
        mode.outputTimingRefreshHz.map { String(format: "%.3g", $0) } ?? "unknown",
        mode.encoding.rawValue,
        mode.bitDepth.map(String.init) ?? "unknown",
        mode.range.rawValue,
        mode.chroma.rawValue,
        mode.hdrMode.rawValue,
        mode.id.rawValue,
      ]
    })
  }

  static func renderOperations(_ operations: [OperationReport], json: Bool) throws -> String {
    if json {
      return try encode(operations)
    }
    var lines: [String] = []
    for operation in operations {
      lines.append(
        "\(operation.operation): \(operation.skipped ? "skipped" : operation.status.rawValue)\(operation.reason.map { " (\($0))" } ?? "")"
      )
      for restore in operation.restore ?? [] {
        lines.append(
          "restore.\(restore.operation): \(restore.status.rawValue)\(restore.reason.map { " (\($0))" } ?? "")"
        )
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

  private static func groupedByBacking(_ modes: [ResolutionMode]) -> [ResolutionMode] {
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
      if lhsPixels != rhsPixels {
        return lhsPixels < rhsPixels
      }
      if lhs.backing.width != rhs.backing.width {
        return lhs.backing.width < rhs.backing.width
      }
      return lhs.backing.height < rhs.backing.height
    }.flatMap(\.modes)
  }

  private static func pixelCount(_ size: DisplaySize) -> Int {
    size.width * size.height
  }

  private static func renderTable(headers: [String], rows: [[String]]) -> String {
    precondition(!headers.isEmpty, "table headers must not be empty")
    precondition(rows.allSatisfy { $0.count == headers.count }, "table rows must match header count")

    let table = [headers] + rows
    let widths = headers.indices.map { index in
      table.map { $0[index].count }.max() ?? 0
    }
    let lines = table.map { row in
      row.enumerated().map { index, value in
        if index == row.count - 1 {
          return value
        }
        let padding = String(repeating: " ", count: widths[index] - value.count)
        return value + padding
      }.joined(separator: "  ")
    }
    return lines.joined(separator: "\n") + "\n"
  }
}

private struct DisplayTargetOutput: Codable {
  var selector: String
  var main: Bool
  var builtin: Bool
  var label: String

  init(_ display: DisplayTarget) {
    self.selector = display.selector.rawValue
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

  init(_ state: DisplayState) {
    self.currentMode = state.currentDisplayModeID.value?.rawValue
    self.timing = state.outputTimingResolution.value
    self.refreshHz = state.outputTimingRefreshHz.value
    self.bpc = state.bitDepth.value
    self.encoding = state.encoding.value?.rawValue
    self.range = state.range.value?.rawValue
    self.chroma = state.chroma.value?.rawValue
    self.hdr = state.hdrMode.value?.rawValue
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
