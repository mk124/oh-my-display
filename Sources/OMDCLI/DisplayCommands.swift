import Foundation
import OMDCore

enum DitheringArgument: String, Sendable {
  case on
  case off

  var boolValue: Bool { self == .on }
}

enum HiDPIArgument: String, Sendable {
  case on
  case off

  var boolValue: Bool { self == .on }
}

enum VRRArgument: String, Sendable {
  case on
  case off

  var boolValue: Bool { self == .on }
}

enum EncodingArgument: String, Sendable {
  case rgb
  case ycbcr

  var coreValue: DisplayEncoding {
    switch self {
    case .rgb: .rgb
    case .ycbcr: .ycbcr
    }
  }
}

enum RangeArgument: String, Sendable {
  case full
  case limited

  var coreValue: DisplayRange {
    switch self {
    case .full: .full
    case .limited: .limited
    }
  }
}

enum ChromaArgument: String, Sendable {
  case c444 = "444"
  case c422 = "422"
  case c420 = "420"

  var coreValue: DisplayChroma {
    switch self {
    case .c444: .c444
    case .c422: .c422
    case .c420: .c420
    }
  }
}

enum HDRArgument: String, Sendable {
  case sdr
  case hdr10
  case dolbyVision = "dolby-vision"
  case dolbyVisionLowLatency = "dolby-vision-low-latency"

  var coreValue: DisplayHDRMode {
    switch self {
    case .sdr: .sdr
    case .hdr10: .hdr10
    case .dolbyVision: .dolbyVision
    case .dolbyVisionLowLatency: .dolbyVisionLowLatency
    }
  }
}

struct DisplaySetOptions: Sendable {
  var display: String
  var resolutionMode: String?
  var resolution: String?
  var hidpi: HiDPIArgument?
  var refresh: Double?
  var displayMode: String?
  var encoding: EncodingArgument?
  var bpc: Int?
  var range: RangeArgument?
  var chroma: ChromaArgument?
  var hdr: HDRArgument?
  var vrr: VRRArgument?
  var dithering: DitheringArgument?
  var icc: URL?
  var json: Bool
  var yes: Bool

  init(
    display: String,
    resolutionMode: String? = nil,
    resolution: String? = nil,
    hidpi: HiDPIArgument? = nil,
    refresh: Double? = nil,
    displayMode: String? = nil,
    encoding: EncodingArgument? = nil,
    bpc: Int? = nil,
    range: RangeArgument? = nil,
    chroma: ChromaArgument? = nil,
    hdr: HDRArgument? = nil,
    vrr: VRRArgument? = nil,
    dithering: DitheringArgument? = nil,
    icc: URL? = nil,
    json: Bool = false,
    yes: Bool = false
  ) {
    self.display = display
    self.resolutionMode = resolutionMode
    self.resolution = resolution
    self.hidpi = hidpi
    self.refresh = refresh
    self.displayMode = displayMode
    self.encoding = encoding
    self.bpc = bpc
    self.range = range
    self.chroma = chroma
    self.hdr = hdr
    self.vrr = vrr
    self.dithering = dithering
    self.icc = icc
    self.json = json
    self.yes = yes
  }
}

struct RestoreReport: Codable, Equatable, Sendable {
  var operation: String
  var status: DisplaySetStatus
  var attemptedMutation: Bool
  var reason: String?

  init(operation: String, result: DisplaySetResult) {
    self.operation = operation
    self.status = result.status
    self.attemptedMutation = result.attemptedMutation
    self.reason = result.reason
  }
}

struct OperationReport: Codable, Equatable, Sendable {
  var operation: String
  var status: DisplaySetStatus
  var attemptedMutation: Bool
  var reason: String?
  var skipped: Bool
  var skipReason: String?
  var restore: [RestoreReport]?

  init(operation: String, result: DisplaySetResult, restore: [RestoreReport]? = nil) {
    self.operation = operation
    self.status = result.status
    self.attemptedMutation = result.attemptedMutation
    self.reason = result.reason
    self.skipped = false
    self.skipReason = nil
    self.restore = restore
  }

  init(
    operation: String,
    status: DisplaySetStatus,
    attemptedMutation: Bool,
    reason: String?,
    skipped: Bool = false,
    skipReason: String? = nil,
    restore: [RestoreReport]? = nil
  ) {
    self.operation = operation
    self.status = status
    self.attemptedMutation = attemptedMutation
    self.reason = reason
    self.skipped = skipped
    self.skipReason = skipReason
    self.restore = restore
  }
}

struct DisplayCommands: Sendable {
  var context: OMDCLIContext

  init(context: OMDCLIContext = OMDCLIContext()) {
    self.context = context
  }

  func list(json: Bool) -> CommandResult {
    do {
      return try CommandResult(
        exitCode: .success,
        stdout: OutputRenderer.renderDisplays(context.core.listDisplays(), json: json))
    } catch let error as DisplayControlError {
      return displayControlError(error)
    } catch {
      return unexpected(error)
    }
  }

  func get(display: String, json: Bool) -> CommandResult {
    do {
      let selector = try selectorForRead(display)
      return try CommandResult(
        exitCode: .success,
        stdout: OutputRenderer.renderState(context.core.readDisplayState(selector), json: json))
    } catch let error as UsageError {
      return error.result
    } catch let error as DisplayControlError {
      return displayControlError(error)
    } catch {
      return unexpected(error)
    }
  }

  func resolutions(display: String, json: Bool) -> CommandResult {
    do {
      let selector = try selectorForRead(display)
      return try CommandResult(
        exitCode: .success,
        stdout: OutputRenderer.renderResolutionModes(
          context.core.listResolutionModes(selector), json: json))
    } catch let error as UsageError {
      return error.result
    } catch let error as DisplayControlError {
      return displayControlError(error)
    } catch {
      return unexpected(error)
    }
  }

  func displayModes(display: String, json: Bool) -> CommandResult {
    do {
      let selector = try selectorForRead(display)
      return try CommandResult(
        exitCode: .success,
        stdout: OutputRenderer.renderDisplayModes(
          context.core.listDisplayModes(selector), json: json))
    } catch let error as UsageError {
      return error.result
    } catch let error as DisplayControlError {
      return displayControlError(error)
    } catch {
      return unexpected(error)
    }
  }

  func set(_ options: DisplaySetOptions) -> CommandResult {
    do {
      if !hasAnySetFlag(options) {
        return usage("No set flags were provided")
      }

      let selector = try selectorForMutation(options.display)
      if hasOnlyDirectSetFlags(options) {
        let reports = try run(
          selector: selector,
          resolution: nil,
          baseline: nil,
          displayMode: nil,
          dithering: options.dithering,
          icc: options.icc
        )
        return try CommandResult(
          exitCode: exitCode(for: reports),
          stdout: OutputRenderer.renderOperations(reports, json: options.json)
        )
      }

      let initialState = try context.core.readDisplayState(selector)
      let resolution = try resolveResolutionRequest(
        selector: selector, state: initialState, options: options)
      let resolutionMayChange = resolution.map {
        initialState.currentResolutionModeID.readability != .readable
          || initialState.currentResolutionModeID.value != $0
      } ?? false
      let baseline = try resolutionMayChange
        ? baselineForResolutionChange(selector: selector, state: initialState)
        : nil

      let displayMode = try resolveDisplayModeRequest(
        selector: selector,
        state: initialState,
        options: options,
        resolutionMayChange: resolutionMayChange,
        baseline: baseline
      )

      if needsConfirmation(
        state: initialState,
        resolution: resolution,
        displayMode: displayMode,
        resolutionMayChange: resolutionMayChange
      ), !options.yes {
        if !context.isTTY {
          return preMutationBlocked(
            "Display mode change requires --yes in non-interactive use",
            json: options.json,
            operation: "confirmation")
        }
        let accepted = context.prompt?("Apply requested display changes?") ?? false
        if !accepted {
          return preMutationBlocked("Display mode change declined", json: options.json)
        }
      }

      let reports = try run(
        selector: selector,
        resolution: resolution,
        baseline: baseline,
        displayMode: displayMode,
        dithering: options.dithering,
        icc: options.icc
      )
      return try CommandResult(
        exitCode: exitCode(for: reports),
        stdout: OutputRenderer.renderOperations(reports, json: options.json)
      )
    } catch let error as UsageError {
      return error.result
    } catch let error as PreMutationBlock {
      return preMutationBlocked(error.reason, json: options.json, operation: error.operation)
    } catch let error as DisplayControlError {
      return displayControlError(error)
    } catch {
      return unexpected(error)
    }
  }

  private func selectorForRead(_ input: String) throws -> DisplaySelector {
    if input == "main" {
      guard let main = try context.core.listDisplays().first(where: { $0.isMain }) else {
        throw UsageError("No main display is currently available")
      }
      return main.selector
    }
    return DisplaySelector(input)
  }

  private func hasAnySetFlag(_ options: DisplaySetOptions) -> Bool {
    hasResolutionFlags(options)
      || hasDisplayModeFlags(options)
      || options.dithering != nil
      || options.icc != nil
  }

  private func hasOnlyDirectSetFlags(_ options: DisplaySetOptions) -> Bool {
    !hasResolutionFlags(options) && !hasDisplayModeFlags(options)
  }

  private func hasResolutionFlags(_ options: DisplaySetOptions) -> Bool {
    options.resolutionMode != nil
      || options.resolution != nil
      || options.hidpi != nil
      || options.refresh != nil
  }

  private func hasDisplayModeFlags(_ options: DisplaySetOptions) -> Bool {
    options.displayMode != nil
      || options.encoding != nil
      || options.bpc != nil
      || options.range != nil
      || options.chroma != nil
      || options.hdr != nil
      || options.vrr != nil
  }

  private func selectorForMutation(_ input: String) throws -> DisplaySelector {
    if input == "all" {
      throw UsageError("--display all is not supported for mutation")
    }
    if input == "main" {
      return try selectorForRead(input)
    }
    if !input.contains(":") {
      throw UsageError("Mutating commands require a stable selector copied from `omd display list`")
    }
    return DisplaySelector(input)
  }

  private func resolveResolutionRequest(
    selector: DisplaySelector,
    state: DisplayState,
    options: DisplaySetOptions
  ) throws -> ResolutionModeID? {
    let hasSemantic = options.resolution != nil || options.hidpi != nil || options.refresh != nil
    if options.resolutionMode != nil && hasSemantic {
      throw UsageError("--resolution-mode cannot be combined with semantic resolution flags")
    }
    if let exact = options.resolutionMode {
      return ResolutionModeID(exact)
    }
    guard hasSemantic else {
      return nil
    }

    let list = try context.core.listResolutionModes(selector)
    let modes = try readableItems(list, operation: "resolution")
    let parsedResolution = try parseResolutionArgument(options.resolution)
    let desiredLogical = try desiredValue(
      parsedResolution.map { DisplaySize(width: $0.width, height: $0.height) },
      state.logicalResolution,
      "logical resolution"
    )
    let desiredHiDPI = try desiredValue(options.hidpi?.boolValue, state.isHiDPI, "HiDPI")
    let desiredRefresh = try desiredValue(options.refresh, state.resolutionRefreshHz, "refresh")

    let matches = modes.filter { mode in
      mode.logicalResolution == desiredLogical
        && mode.isHiDPI == desiredHiDPI
        && approximatelyEqual(mode.refreshHz, desiredRefresh)
    }
    guard matches.count == 1, let match = matches.first else {
      throw UsageError(
        matches.isEmpty
          ? "No resolution mode matches the requested flags"
          : "Multiple resolution modes match; use --resolution-mode")
    }
    return match.id
  }

  private func resolveDisplayModeRequest(
    selector: DisplaySelector,
    state: DisplayState,
    options: DisplaySetOptions,
    resolutionMayChange: Bool,
    baseline: MutationBaseline?
  ) throws -> DisplayModeRequest? {
    let hasSemantic =
      options.encoding != nil
      || options.bpc != nil
      || options.range != nil
      || options.chroma != nil
      || options.hdr != nil
      || options.vrr != nil
    if options.displayMode != nil && hasSemantic {
      throw UsageError("--display-mode cannot be combined with semantic display-mode flags")
    }
    if let exact = options.displayMode {
      if resolutionMayChange {
        throw UsageError("--display-mode cannot be combined with a resolution change")
      }
      return .preResolved(DisplayModeID(exact))
    }
    guard hasSemantic else {
      return nil
    }

    let intent = try displayModeIntent(options: options, state: state)
    if resolutionMayChange {
      guard let baseline else {
        throw UsageError("Current resolution mode id is unreadable; specify a stable current state first")
      }
      return .postResolution(intent, baseline)
    }

    let id = try resolveSemanticDisplayMode(
      selector: selector,
      state: state,
      intent: intent
    )
    return .preResolved(id)
  }

  private func run(
    selector: DisplaySelector,
    resolution: ResolutionModeID?,
    baseline: MutationBaseline?,
    displayMode: DisplayModeRequest?,
    dithering: DitheringArgument?,
    icc: URL?
  ) throws -> [OperationReport] {
    var reports: [OperationReport] = []
    var remaining: [String] = []
    if resolution != nil { remaining.append("resolution") }
    if displayMode != nil { remaining.append("displayMode") }
    if dithering != nil { remaining.append("dithering") }
    if icc != nil { remaining.append("icc") }

    var resolutionChanged = false
    if let resolution {
      remaining.removeFirst()
      let result = try context.core.setResolutionMode(selector, modeID: resolution)
      resolutionChanged = result.status == .applied || result.attemptedMutation
      reports.append(OperationReport(operation: "resolution", result: result))
      if result.status.isStoppingStatus {
        if result.attemptedMutation, let baseline {
          let restore = restoreBaseline(baseline, selector: selector)
          reports[reports.count - 1] = OperationReport(
            operation: "resolution",
            result: result,
            restore: restore
          )
        }
        appendSkipped(&reports, remaining)
        return reports
      }
    }

    if let displayMode {
      remaining.removeFirst()
      let displayModeID: DisplayModeID
      let baseline: MutationBaseline?
      switch displayMode {
      case .preResolved(let id):
        displayModeID = id
        baseline = nil
      case .postResolution(let intent, let storedBaseline):
        baseline = storedBaseline
        do {
          displayModeID = try resolveSemanticDisplayMode(
            selector: selector,
            state: context.core.readDisplayState(selector),
            intent: intent
          )
        } catch where resolutionChanged {
          let restore = restoreBaseline(storedBaseline, selector: selector)
          reports.append(
            OperationReport(
              operation: "displayMode",
              status: .failed,
              attemptedMutation: false,
              reason: failureReason(error),
              restore: restore
            ))
          appendSkipped(&reports, remaining)
          return reports
        }
      }

      let result: DisplaySetResult
      do {
        result = try context.core.setDisplayMode(selector, modeID: displayModeID)
      } catch {
        if resolutionChanged, let baseline {
          let restore = restoreBaseline(baseline, selector: selector)
          reports.append(
            OperationReport(
              operation: "displayMode",
              status: .failed,
              attemptedMutation: false,
              reason: failureReason(error),
              restore: restore
            ))
          appendSkipped(&reports, remaining)
          return reports
        }
        throw error
      }
      if result.status.isStoppingStatus, resolutionChanged, let baseline {
        let restore = restoreBaseline(baseline, selector: selector)
        reports.append(OperationReport(operation: "displayMode", result: result, restore: restore))
        appendSkipped(&reports, remaining)
        return reports
      }
      reports.append(OperationReport(operation: "displayMode", result: result))
      if result.status.isStoppingStatus {
        appendSkipped(&reports, remaining)
        return reports
      }
    }

    if let dithering {
      remaining.removeFirst()
      let result: DisplaySetResult
      do {
        result = try context.core.setDithering(selector, enabled: dithering.boolValue)
      } catch {
        guard !reports.isEmpty else {
          throw error
        }
        reports.append(
          OperationReport(
            operation: "dithering",
            status: .failed,
            attemptedMutation: false,
            reason: failureReason(error)
          ))
        appendSkipped(&reports, remaining)
        return reports
      }
      reports.append(OperationReport(operation: "dithering", result: result))
      if result.status.isStoppingStatus {
        appendSkipped(&reports, remaining)
        return reports
      }
    }

    if let icc {
      remaining.removeFirst()
      let result: DisplaySetResult
      do {
        result = try context.core.setICCProfile(selector, profileURL: icc)
      } catch {
        guard !reports.isEmpty else {
          throw error
        }
        reports.append(
          OperationReport(
            operation: "icc",
            status: .failed,
            attemptedMutation: false,
            reason: failureReason(error)
          ))
        appendSkipped(&reports, remaining)
        return reports
      }
      reports.append(OperationReport(operation: "icc", result: result))
      if result.status.isStoppingStatus {
        appendSkipped(&reports, remaining)
      }
    }

    return reports
  }

  private func requireUniqueResolutionMode(
    selector: DisplaySelector, id: ResolutionModeID
  ) throws {
    let list = try context.core.listResolutionModes(selector)
    let matches = try readableItems(list, operation: "resolution").filter { $0.id == id }
    guard matches.count == 1 else {
      throw UsageError(
        matches.isEmpty
          ? "Resolution mode id is not available for this display"
          : "Resolution mode id matched multiple modes")
    }
  }

  private func baselineForResolutionChange(
    selector: DisplaySelector,
    state: DisplayState
  ) throws -> MutationBaseline {
    let originalResolutionID = try desiredValue(
      Optional<ResolutionModeID>.none,
      state.currentResolutionModeID,
      "current resolution mode id"
    )
    try requireUniqueResolutionMode(selector: selector, id: originalResolutionID)

    let originalDisplayModeID: DisplayModeID?
    if state.currentDisplayModeID.readability == .readable,
      let id = state.currentDisplayModeID.value
    {
      let displayModeList = try? context.core.listDisplayModes(selector)
      let displayModeItems = displayModeList?.readability == .unreadable
        ? []
        : displayModeList?.items ?? []
      let matches = displayModeItems.filter { $0.id == id }
      originalDisplayModeID = matches.count == 1 ? id : nil
    } else {
      originalDisplayModeID = nil
    }

    return MutationBaseline(
      originalResolutionID: originalResolutionID,
      originalDisplayModeID: originalDisplayModeID
    )
  }

  private func restoreBaseline(_ baseline: MutationBaseline, selector: DisplaySelector)
    -> [RestoreReport]
  {
    var reports: [RestoreReport] = []
    let resolution: DisplaySetResult
    do {
      resolution = try context.core.setResolutionMode(
        selector, modeID: baseline.originalResolutionID)
    } catch {
      reports.append(
        RestoreReport(
          operation: "resolution",
          result: .failed(attemptedMutation: false, reason: failureReason(error))
        ))
      reports.append(
        RestoreReport(
          operation: "displayMode",
          result: .blocked("resolutionRestoreFailed")
        ))
      return reports
    }
    reports.append(RestoreReport(operation: "resolution", result: resolution))
    guard resolution.status == .applied || resolution.status == .noOp else {
      reports.append(
        RestoreReport(
          operation: "displayMode",
          result: .blocked("resolutionRestoreFailed")
        ))
      return reports
    }

    guard let originalDisplayModeID = baseline.originalDisplayModeID else {
      reports.append(
        RestoreReport(
          operation: "displayMode",
          result: .blocked("displayModeRestoreUnavailable")
        ))
      return reports
    }

    let displayModeList: DisplayListResult<DisplayMode>
    do {
      displayModeList = try context.core.listDisplayModes(selector)
    } catch {
      reports.append(
        RestoreReport(
          operation: "displayMode",
          result: .blocked("displayModeRestoreUnavailable: \(failureReason(error))")
        ))
      return reports
    }
    guard displayModeList.readability != .unreadable else {
      reports.append(
        RestoreReport(
          operation: "displayMode",
          result: .blocked(
            "displayModeRestoreUnavailable: \(displayModeList.reason ?? "display modes unavailable")"
          )
        ))
      return reports
    }
    let matches = displayModeList.items.filter { $0.id == originalDisplayModeID }
    guard matches.count == 1 else {
      reports.append(
        RestoreReport(
          operation: "displayMode",
          result: .blocked("displayModeRestoreUnavailable")
        ))
      return reports
    }

    let displayMode: DisplaySetResult
    do {
      displayMode = try context.core.setDisplayMode(
        selector, modeID: originalDisplayModeID)
    } catch {
      reports.append(
        RestoreReport(
          operation: "displayMode",
          result: .failed(attemptedMutation: false, reason: failureReason(error))
        ))
      return reports
    }
    reports.append(RestoreReport(operation: "displayMode", result: displayMode))
    return reports
  }

  private func resolveSemanticDisplayMode(
    selector: DisplaySelector,
    state: DisplayState,
    intent: DisplayModeIntent
  ) throws -> DisplayModeID {
    let modes = try readableItems(
      context.core.listDisplayModes(selector), operation: "displayMode")
    let timing = try desiredValue(
      Optional<DisplaySize>.none,
      state.outputTimingResolution,
      "output timing resolution"
    )
    let refresh = state.outputTimingRefreshHz.readability == .readable
      ? state.outputTimingRefreshHz.value
      : nil

    let baseMatches = modes.filter { mode in
      mode.outputTimingResolution == timing
        && (refresh == nil || approximatelyEqual(mode.outputTimingRefreshHz, refresh!))
        && mode.encoding == intent.encoding
        && mode.bitDepth == intent.bpc
        && mode.range == intent.range
        && mode.hdrMode == intent.hdr
        && mode.isVRR == intent.isVRR
    }
    let matches = matchingChromaModes(baseMatches, intent)
    guard matches.count == 1, let match = matches.first else {
      throw UsageError(
        matches.isEmpty
          ? "No display mode matches the requested flags"
          : "Multiple display modes match; use --display-mode")
    }
    return match.id
  }

  private func displayModeIntent(options: DisplaySetOptions, state: DisplayState) throws
    -> DisplayModeIntent
  {
    try validateDolbyVisionSemanticFlags(options)
    return try DisplayModeIntent(
      encoding: desiredEncoding(options: options, state: state),
      bpc: desiredValue(options.bpc, state.bitDepth, "bpc"),
      range: desiredValue(options.range?.coreValue, state.range, "range"),
      chroma: desiredChroma(options: options, state: state),
      chromaWasProvided: options.chroma != nil,
      hdr: desiredValue(options.hdr?.coreValue, state.hdrMode, "hdr"),
      isVRR: options.vrr?.boolValue ?? false
    )
  }

  private func needsConfirmation(
    state: DisplayState,
    resolution: ResolutionModeID?,
    displayMode: DisplayModeRequest?,
    resolutionMayChange: Bool
  ) -> Bool {
    if resolutionMayChange {
      return true
    }
    if let resolution,
      state.currentResolutionModeID.readability != .readable
        || state.currentResolutionModeID.value != resolution
    {
      return true
    }
    if let displayModeID = displayMode?.preResolvedID,
      state.currentDisplayModeID.readability != .readable
        || state.currentDisplayModeID.value != displayModeID
    {
      return true
    }
    if case .postResolution = displayMode {
      return true
    }
    return false
  }

  private func appendSkipped(_ reports: inout [OperationReport], _ names: [String]) {
    for name in names {
      reports.append(
        OperationReport(
          operation: name,
          status: .blocked,
          attemptedMutation: false,
          reason: "Skipped because an earlier operation did not complete successfully",
          skipped: true,
          skipReason: "dependency"
        ))
    }
  }

  private func readableItems<Item>(
    _ result: DisplayListResult<Item>, operation: String
  ) throws -> [Item] {
    guard result.readability != .unreadable else {
      throw PreMutationBlock(
        operation: operation,
        reason: result.reason ?? "\(operation) modes unavailable")
    }
    return result.items
  }

  private func validateDolbyVisionSemanticFlags(_ options: DisplaySetOptions) throws {
    guard options.hdr?.coreValue.isDolby == true else {
      return
    }
    if options.encoding != nil || options.chroma != nil {
      throw UsageError("Dolby Vision modes do not use --encoding or --chroma; omit those flags")
    }
  }

  private func desiredValue<T: Codable & Equatable & Sendable>(
    _ provided: T?,
    _ axis: DisplayAxis<T>,
    _ name: String
  ) throws -> T {
    if let provided {
      return provided
    }
    if axis.readability == .readable, let value = axis.value {
      return value
    }
    throw UsageError("Current \(name) is unreadable; specify it explicitly")
  }

  private func desiredEncoding(
    options: DisplaySetOptions,
    state: DisplayState
  ) throws -> DisplayEncoding {
    if let encoding = options.encoding?.coreValue {
      return encoding
    }
    if options.hdr?.coreValue.isDolby == true {
      return .none
    }
    return try desiredValue(nil, state.encoding, "encoding")
  }

  private func desiredChroma(
    options: DisplaySetOptions,
    state: DisplayState
  ) throws -> DisplayChroma {
    if let chroma = options.chroma?.coreValue {
      return chroma
    }
    if options.hdr?.coreValue.isDolby == true {
      return .none
    }
    if state.chroma.readability != .unreadable, let value = state.chroma.value {
      return value
    }
    throw UsageError("Current chroma is unreadable; specify it explicitly")
  }

  private func parseResolutionArgument(_ value: String?) throws -> (width: Int, height: Int)? {
    guard let value else {
      return nil
    }
    guard let parsed = Self.parseResolution(value) else {
      throw UsageError("Resolution must be formatted as <width>x<height>")
    }
    return parsed
  }

  private static func parseResolution(_ value: String) -> (width: Int, height: Int)? {
    let pieces = value.lowercased().split(separator: "x", omittingEmptySubsequences: false)
    guard pieces.count == 2,
      !pieces[0].isEmpty,
      !pieces[1].isEmpty,
      let width = Int(pieces[0]),
      let height = Int(pieces[1])
    else {
      return nil
    }
    return (width, height)
  }

  private func approximatelyEqual(_ lhs: Double?, _ rhs: Double) -> Bool {
    guard let lhs else { return false }
    return abs(lhs - rhs) < 0.01
  }

  private func matchingChromaModes(
    _ modes: [DisplayMode],
    _ intent: DisplayModeIntent
  ) -> [DisplayMode] {
    if intent.chromaWasProvided {
      return modes.filter { $0.chroma == intent.chroma }
    }

    let exact = modes.filter { $0.chroma == intent.chroma }
    return exact.isEmpty ? modes.filter { $0.chroma == .unknown } : exact
  }

  private func exitCode(for reports: [OperationReport]) -> OMDExitCode {
    guard reports.allSatisfy({ $0.status == .applied || $0.status == .noOp }) else {
      let attemptedOrApplied = reports.contains { $0.attemptedMutation || $0.status == .applied }
      return attemptedOrApplied ? .partialFailure : .blocked
    }
    return .success
  }

  private func preMutationBlocked(
    _ reason: String,
    json: Bool,
    operation: String = "display"
  ) -> CommandResult {
    let report = OperationReport(
      operation: operation, status: .blocked, attemptedMutation: false, reason: reason)
    return
      (try? CommandResult(
        exitCode: .blocked, stdout: OutputRenderer.renderOperations([report], json: json)))
      ?? CommandResult(exitCode: .blocked, stderr: reason + "\n")
  }

  private func usage(_ message: String) -> CommandResult {
    CommandResult(exitCode: .usage, stderr: message + "\n")
  }

  private func unexpected(_ error: Error) -> CommandResult {
    CommandResult(exitCode: .unexpected, stderr: String(describing: error) + "\n")
  }

  private func displayControlError(_ error: DisplayControlError) -> CommandResult {
    switch error {
    case .displayNotFound, .ambiguousDisplay, .invalidSelector:
      usage(error.description)
    case .unexpected:
      unexpected(error)
    }
  }

  private func failureReason(_ error: Error) -> String {
    if let error = error as? UsageError {
      return error.message
    }
    if let error = error as? PreMutationBlock {
      return error.reason
    }
    if let error = error as? DisplayControlError {
      return error.description
    }
    return String(describing: error)
  }
}

private struct UsageError: Error {
  var message: String
  var result: CommandResult

  init(_ message: String) {
    self.message = message
    self.result = CommandResult(exitCode: .usage, stderr: message + "\n")
  }
}

private struct PreMutationBlock: Error {
  var operation: String
  var reason: String
}

private struct DisplayModeIntent: Sendable {
  var encoding: DisplayEncoding
  var bpc: Int
  var range: DisplayRange
  var chroma: DisplayChroma
  var chromaWasProvided: Bool
  var hdr: DisplayHDRMode
  var isVRR: Bool
}

extension DisplayHDRMode {
  fileprivate var isDolby: Bool {
    self == .dolbyVision || self == .dolbyVisionLowLatency
  }
}

private struct MutationBaseline: Sendable {
  var originalResolutionID: ResolutionModeID
  var originalDisplayModeID: DisplayModeID?
}

private enum DisplayModeRequest: Sendable {
  case preResolved(DisplayModeID)
  case postResolution(DisplayModeIntent, MutationBaseline)

  var preResolvedID: DisplayModeID? {
    switch self {
    case .preResolved(let id): id
    case .postResolution: nil
    }
  }
}

extension DisplaySetStatus {
  fileprivate var isStoppingStatus: Bool {
    switch self {
    case .blocked, .backendUnavailable, .failed, .readbackMismatch:
      true
    case .noOp, .applied:
      false
    }
  }
}
