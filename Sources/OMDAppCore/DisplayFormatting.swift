import Foundation
import OMDCore

extension DisplayHDRMode {
  var label: String {
    switch self {
    case .sdr:
      return "SDR"
    case .hdr10:
      return "HDR10"
    case .dolbyVision:
      return "Dolby Vision"
    case .dolbyVisionLowLatency:
      return "Dolby Vision LL"
    case .unknown:
      return "Unknown"
    }
  }
}

extension DisplayEncoding {
  var technicalLabel: String {
    switch self {
    case .rgb:
      return "RGB"
    case .ycbcr:
      return "YCbCr"
    case .none:
      return ""
    case .unknown:
      return "Unknown"
    }
  }
}

extension DisplaySize {
  var commonLabel: String {
    switch (width, height) {
    case (7680, 4320):
      return "8K"
    case (6016, 3384):
      return "6K"
    case (5120, 2880):
      return "5K"
    case (4096, 2160):
      return "DCI 4K"
    case (3840, 2160):
      return "4K"
    case (2560, 1440):
      return "QHD"
    case (1920, 1080):
      return "1080p"
    default:
      return description
    }
  }
}

func displayModeSort(_ lhs: DisplayMode, _ rhs: DisplayMode) -> Bool {
  if lhs.hdrMode != rhs.hdrMode {
    return hdrRank(lhs.hdrMode) < hdrRank(rhs.hdrMode)
  }
  if lhs.outputTimingRefreshHz != rhs.outputTimingRefreshHz {
    return (lhs.outputTimingRefreshHz ?? 0) > (rhs.outputTimingRefreshHz ?? 0)
  }
  if lhs.encoding != rhs.encoding {
    return encodingRank(lhs.encoding) < encodingRank(rhs.encoding)
  }
  if lhs.bitDepth != rhs.bitDepth {
    return (lhs.bitDepth ?? 0) > (rhs.bitDepth ?? 0)
  }
  if lhs.range != rhs.range {
    return rangeRank(lhs.range) < rangeRank(rhs.range)
  }
  if lhs.chroma != rhs.chroma {
    return chromaRank(lhs.chroma) < chromaRank(rhs.chroma)
  }
  if lhs.isVRR != rhs.isVRR {
    return !lhs.isVRR && rhs.isVRR
  }
  return lhs.id.rawValue < rhs.id.rawValue
}

func hdrRank(_ value: DisplayHDRMode) -> Int {
  switch value {
  case .sdr:
    return 0
  case .hdr10:
    return 1
  case .dolbyVision:
    return 2
  case .dolbyVisionLowLatency:
    return 3
  case .unknown:
    return 4
  }
}

func encodingRank(_ value: DisplayEncoding) -> Int {
  switch value {
  case .rgb:
    return 0
  case .ycbcr:
    return 1
  case .none:
    return 2
  case .unknown:
    return 3
  }
}

func rangeRank(_ value: DisplayRange) -> Int {
  switch value {
  case .full:
    return 0
  case .limited:
    return 1
  case .unknown:
    return 2
  }
}

func chromaRank(_ value: DisplayChroma) -> Int {
  switch value {
  case .none:
    return 0
  case .c444:
    return 1
  case .c422:
    return 2
  case .c420:
    return 3
  case .unknown:
    return 4
  }
}

func displayModeTitle(_ mode: DisplayMode) -> String {
  let refresh = mode.outputTimingRefreshHz.map(formatHz) ?? "unknown Hz"
  let vrr = mode.isVRR ? " (VRR)" : ""
  let encoding = mode.encoding.technicalLabel
  let bpc = mode.bitDepth.map { "\($0)-bit" }
  let range = mode.range == .unknown ? nil : mode.range.rawValue
  let chroma = mode.chroma == .none ? nil : mode.chroma.rawValue

  return [
    mode.outputTimingResolution.description,
    mode.hdrMode.label,
    "\(refresh)\(vrr)",
    encoding.isEmpty ? nil : encoding,
    bpc,
    range,
    chroma,
  ].compactMap { $0 }.joined(separator: " ")
}

func displayModeMenuTitle(_ mode: DisplayMode) -> String {
  let encoding = mode.encoding.technicalLabel
  let bpc = mode.bitDepth.map { "\($0)-bit" }
  let range = mode.range == .unknown ? nil : mode.range.rawValue
  let chroma = mode.chroma == .none ? nil : mode.chroma.rawValue
  let vrr = mode.isVRR ? "VRR" : nil

  return [
    mode.hdrMode.label,
    encoding.isEmpty ? nil : encoding,
    bpc,
    range,
    chroma,
    vrr,
  ].compactMap { $0 }.joined(separator: " ")
}

func iccProfileTitles(_ profiles: [ICCProfile]) -> [URL: String] {
  let sorted = profiles.sorted {
    let lhs = ICCProfileIdentity.sortKey($0.url)
    let rhs = ICCProfileIdentity.sortKey($1.url)
    return lhs.localizedStandardCompare(rhs) == .orderedAscending
  }
  let names = Dictionary(grouping: sorted, by: \.name)
  var rawTitles: [URL: String] = [:]

  for profile in sorted {
    let group = names[profile.name] ?? []
    rawTitles[profile.url] = group.count == 1
      ? profile.name
      : "\(profile.name) (\(profile.url.lastPathComponent))"
  }

  let titleGroups = Dictionary(grouping: sorted) { rawTitles[$0.url] ?? $0.name }
  var titles: [URL: String] = [:]
  for (title, group) in titleGroups {
    let ordered = group.sorted {
      ICCProfileIdentity.sortKey($0.url).localizedStandardCompare(
        ICCProfileIdentity.sortKey($1.url)) == .orderedAscending
    }
    for (index, profile) in ordered.enumerated() {
      titles[profile.url] = ordered.count == 1 ? title : "\(title) #\(index + 1)"
    }
  }
  return titles
}

func formatHz(_ value: Double) -> String {
  if value.rounded() == value {
    return "\(Int(value))Hz"
  }
  return "\(String(format: "%.2f", value))Hz"
}
