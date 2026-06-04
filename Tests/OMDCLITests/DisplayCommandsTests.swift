import ArgumentParser
import Foundation
import OMDCore
import XCTest

@testable import OMDCLI

final class DisplayCommandsTests: XCTestCase {
  func testDisplayScopedCommandsDefaultToMainDisplay() throws {
    XCTAssertEqual(try DisplayGet.parse([]).display, "main")
    XCTAssertEqual(try DisplayResolutions.parse([]).display, "main")
    XCTAssertEqual(try DisplayModes.parse([]).display, "main")
    XCTAssertEqual(try DisplaySet.parse(["--dithering", "off"]).display, "main")
  }

  func testDisplayOptionOverridesMainDefault() throws {
    XCTAssertEqual(try DisplayGet.parse(["--display", "uuid:one"]).display, "uuid:one")
    XCTAssertEqual(try DisplayResolutions.parse(["--display", "uuid:one"]).display, "uuid:one")
    XCTAssertEqual(try DisplayModes.parse(["--display", "uuid:one"]).display, "uuid:one")
    XCTAssertEqual(
      try DisplaySet.parse(["--display", "uuid:one", "--dithering", "off"]).display,
      "uuid:one")
  }

  func testListJSONUsesCLIDTOAndDoesNotExposeRawDisplayID() throws {
    let core = FakeCore()
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.list(json: true)
    let displays = try jsonArray(result.stdout)

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(displays.first?["selector"] as? String, "uuid:one")
    XCTAssertEqual(displays.first?["main"] as? Bool, true)
    XCTAssertEqual(displays.first?["builtin"] as? Bool, false)
    XCTAssertNil(displays.first?["displayID"])
    XCTAssertTrue(core.callLog.allSatisfy { !$0.hasPrefix("set") })
  }

  func testDisplayListHumanUsesAlignedColumnsAndSelectorLast() {
    let core = FakeCore()
    core.displays.append(
      DisplayTarget(
        selector: DisplaySelector("uuid:two-long"),
        displayID: 2,
        label: "Long Living Room",
        isMain: false,
        isBuiltin: true
      ))
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.list(json: false)

    XCTAssertEqual(result.exitCode, .success)
    assertPlainTable(
      result.stdout,
      equals: """
        main  builtin  label             selector
        yes   no       One               uuid:one
        no    yes      Long Living Room  uuid:two-long

        """)
  }

  func testResolutionModesHumanUsesAlignedColumnsAndModeLast() {
    let commands = DisplayCommands(context: OMDCLIContext(core: FakeCore(), isTTY: false))

    let result = commands.resolutions(display: "uuid:one", json: false)

    XCTAssertEqual(result.exitCode, .success)
    assertPlainTable(
      result.stdout,
      equals: """
        logical    backing    scale  hidpi  refresh  resolutionMode
        1920x1080  3840x2160  2      yes    60       res-1920-hidpi
        2560x1440  5120x2880  2      yes    60       res-2560-hidpi

        """)
  }

  func testResolutionModesHumanGroupsByBackingPixelAreaAndLeavesJSONRaw() throws {
    let core = FakeCore()
    let res5120Wide = ResolutionMode(
      id: ResolutionModeID("res-5120-wide"),
      logicalResolution: DisplaySize(width: 5120, height: 1440),
      backingResolution: DisplaySize(width: 5120, height: 1440),
      scaleFactor: 1,
      isHiDPI: false,
      refreshHz: 60
    )
    let res3840LoDPI = ResolutionMode(
      id: ResolutionModeID("res-3840-lodpi"),
      logicalResolution: DisplaySize(width: 3840, height: 2160),
      backingResolution: DisplaySize(width: 3840, height: 2160),
      scaleFactor: 1,
      isHiDPI: false,
      refreshHz: 60
    )
    let res3008HiDPI = ResolutionMode(
      id: ResolutionModeID("res-3008-hidpi"),
      logicalResolution: DisplaySize(width: 3008, height: 1692),
      backingResolution: DisplaySize(width: 5120, height: 2880),
      scaleFactor: 1.7,
      isHiDPI: true,
      refreshHz: 60
    )
    let resEqualAreaWide = ResolutionMode(
      id: ResolutionModeID("res-equal-area-wide"),
      logicalResolution: DisplaySize(width: 8192, height: 1024),
      backingResolution: DisplaySize(width: 8192, height: 1024),
      scaleFactor: 1,
      isHiDPI: false,
      refreshHz: 60
    )
    let resEqualAreaNarrow = ResolutionMode(
      id: ResolutionModeID("res-equal-area-narrow"),
      logicalResolution: DisplaySize(width: 4096, height: 2048),
      backingResolution: DisplaySize(width: 4096, height: 2048),
      scaleFactor: 1,
      isHiDPI: false,
      refreshHz: 60
    )
    core.resolutionModesResult = .readable(
      [
        res5120Wide, core.res1920HiDPI, resEqualAreaWide, core.res2560HiDPI, res3840LoDPI,
        res3008HiDPI, resEqualAreaNarrow,
      ],
      source: "CoreGraphics")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let human = commands.resolutions(display: "uuid:one", json: false)
    let json = try jsonObject(commands.resolutions(display: "uuid:one", json: true).stdout)
    let modes = try XCTUnwrap(json["modes"] as? [[String: Any]])

    XCTAssertEqual(human.exitCode, .success)
    assertPlainTable(
      human.stdout,
      equals: """
        logical    backing    scale  hidpi  refresh  resolutionMode
        5120x1440  5120x1440  1      no     60       res-5120-wide
        1920x1080  3840x2160  2      yes    60       res-1920-hidpi
        3840x2160  3840x2160  1      no     60       res-3840-lodpi
        4096x2048  4096x2048  1      no     60       res-equal-area-narrow
        8192x1024  8192x1024  1      no     60       res-equal-area-wide
        2560x1440  5120x2880  2      yes    60       res-2560-hidpi
        3008x1692  5120x2880  1.7    yes    60       res-3008-hidpi

        """)
    XCTAssertEqual(
      modes.compactMap { rawValue($0["id"]) },
      [
        "res-5120-wide", "res-1920-hidpi", "res-equal-area-wide", "res-2560-hidpi",
        "res-3840-lodpi", "res-3008-hidpi", "res-equal-area-narrow",
      ])
  }

  func testDisplayModesHumanUsesAlignedColumnsAndModeLast() {
    let commands = DisplayCommands(context: OMDCLIContext(core: FakeCore(), isTTY: false))

    let result = commands.displayModes(display: "uuid:one", json: false)

    XCTAssertEqual(result.exitCode, .success)
    assertPlainTable(
      result.stdout,
      equals: """
        timing     refresh  encoding  bpc  range  chroma  hdr  displayMode
        3840x2160  60       rgb       8    full   444     sdr  mode-r1-rgb8
        3840x2160  60       rgb       10   full   444     sdr  mode-r1-rgb10

        """)
  }

  func testHumanModeListsHandleEmptyUnreadableAndDegradedResults() {
    let core = FakeCore()
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    core.resolutionModesResult = .readable([], source: "CoreGraphics")
    assertPlainTable(
      commands.resolutions(display: "uuid:one", json: false).stdout,
      equals: "logical  backing  scale  hidpi  refresh  resolutionMode\n")

    core.displayModesForResolution["res-1920-hidpi"] = .readable([], source: "CADisplay")
    assertPlainTable(
      commands.displayModes(display: "uuid:one", json: false).stdout,
      equals: "timing  refresh  encoding  bpc  range  chroma  hdr  displayMode\n")

    core.resolutionModesResult = .unreadable("CoreGraphics unavailable", source: "CoreGraphics")
    XCTAssertEqual(
      commands.resolutions(display: "uuid:one", json: false).stdout,
      "resolution modes unavailable: CoreGraphics unavailable\n")

    core.displayModesForResolution["res-1920-hidpi"] = .unreadable(
      "CADisplay unavailable", source: "CADisplay")
    XCTAssertEqual(
      commands.displayModes(display: "uuid:one", json: false).stdout,
      "display modes unavailable: CADisplay unavailable\n")

    core.resolutionModesResult = .degraded(
      [core.res1920HiDPI], reason: "partial", source: "CoreGraphics")
    assertPlainTable(
      commands.resolutions(display: "uuid:one", json: false).stdout,
      equals: """
        logical    backing    scale  hidpi  refresh  resolutionMode
        1920x1080  3840x2160  2      yes    60       res-1920-hidpi

        """)

    core.displayModesForResolution["res-1920-hidpi"] = .degraded(
      [core.modeR1RGB8], reason: "partial", source: "CADisplay")
    assertPlainTable(
      commands.displayModes(display: "uuid:one", json: false).stdout,
      equals: """
        timing     refresh  encoding  bpc  range  chroma  hdr  displayMode
        3840x2160  60       rgb       8    full   444     sdr  mode-r1-rgb8

        """)
  }

  func testModeListJSONUsesSeparateResolutionAndDisplayModeObjects() throws {
    let commands = DisplayCommands(context: OMDCLIContext(core: FakeCore(), isTTY: false))

    let resolutions = try jsonObject(commands.resolutions(display: "uuid:one", json: true).stdout)
    let displayModes = try jsonObject(
      commands.displayModes(display: "uuid:one", json: true).stdout)
    let resolutionItems = try XCTUnwrap(resolutions["modes"] as? [[String: Any]])
    let displayModeItems = try XCTUnwrap(displayModes["modes"] as? [[String: Any]])
    let resolutionMode = try XCTUnwrap(resolutionItems.first)
    let displayMode = try XCTUnwrap(displayModeItems.first)

    XCTAssertEqual(resolutions["readability"] as? String, "readable")
    XCTAssertEqual(displayModes["readability"] as? String, "readable")
    XCTAssertEqual(
      Set(resolutionMode.keys),
      ["id", "logicalResolution", "backingResolution", "scaleFactor", "isHiDPI", "refreshHz"])
    XCTAssertEqual(
      Set(displayMode.keys),
      [
        "id", "outputTimingResolution", "outputTimingRefreshHz", "bitDepth", "encoding",
        "range", "chroma", "hdrMode", "isVirtual", "isVRR", "isHighBandwidth",
      ])
  }

  func testGetJSONRedactsICCAbsolutePathAndGroupsState() throws {
    let core = FakeCore()
    core.state.iccProfileURL = .readable(URL(fileURLWithPath: "/Users/example/Color/Profile.icc"))
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.get(display: "main", json: true)
    let state = try jsonObject(result.stdout)
    let resolution = try XCTUnwrap(state["resolution"] as? [String: Any])
    let displayMode = try XCTUnwrap(state["displayMode"] as? [String: Any])

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(state["icc"] as? String, "Profile.icc")
    XCTAssertEqual(resolution["currentMode"] as? String, "res-1920-hidpi")
    XCTAssertEqual(
      Set(displayMode.keys),
      ["currentMode", "timing", "refreshHz", "bpc", "encoding", "range", "chroma", "hdr"])
    XCTAssertEqual(displayMode["currentMode"] as? String, "mode-r1-rgb8")
    XCTAssertEqual(displayMode["bpc"] as? Int, 8)
    XCTAssertEqual(displayMode["encoding"] as? String, "rgb")
    XCTAssertEqual(Set(state.keys), ["display", "label", "resolution", "displayMode", "dithering", "icc"])
    XCTAssertNil(state["iccProfileURL"])
    XCTAssertNil(state["iccProfileName"])
    XCTAssertNil(state["displayID"])
    XCTAssertFalse(result.stdout.contains("/Users/example"))
  }

  func testGetHumanUsesDisplayModeLabels() {
    let commands = DisplayCommands(context: OMDCLIContext(core: FakeCore(), isTTY: false))

    let result = commands.get(display: "main", json: false)

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(
      result.stdout,
      """
      display: uuid:one
      label: One
      resolution.logical: 1920x1080
      resolution.backing: 3840x2160
      resolution.scale: 2
      resolution.hidpi: yes
      resolution.refresh: 60
      displayMode.timing: 3840x2160
      displayMode.bpc: 8
      displayMode.encoding: rgb
      displayMode.range: full
      displayMode.chroma: 444
      displayMode.hdr: sdr
      dithering: on
      icc: unknown

      """)
  }

  func testReadCommandsDoNotCallSetters() {
    let core = FakeCore()
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    _ = commands.list(json: false)
    _ = commands.get(display: "main", json: false)
    _ = commands.resolutions(display: "uuid:one", json: false)
    _ = commands.displayModes(display: "uuid:one", json: false)

    XCTAssertTrue(core.callLog.contains("listDisplays"))
    XCTAssertTrue(core.callLog.contains("readState:uuid:one"))
    XCTAssertTrue(core.callLog.contains("listResolutions:uuid:one"))
    XCTAssertTrue(core.callLog.contains("listDisplayModes:uuid:one"))
    XCTAssertTrue(core.callLog.allSatisfy { !$0.hasPrefix("set") })
  }

  func testMutatingMainResolvesCurrentMainDisplay() {
    let core = FakeCore()
    core.ditheringResult = .applied("dither")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "main", dithering: .off))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.callLog, ["listDisplays", "setDithering:false"])
  }

  func testResolutionModeCanTargetMainDisplay() {
    let core = FakeCore()
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(display: "main", resolutionMode: "res-2560-hidpi", yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.callLog, [
      "listDisplays",
      "readState:uuid:one",
      "listResolutions:uuid:one",
      "listDisplayModes:uuid:one",
      "setResolution:res-2560-hidpi",
    ])
  }

  func testMutatingAllAndFriendlyNameReturnUsage() {
    let commands = DisplayCommands(context: OMDCLIContext(core: FakeCore(), isTTY: false))

    XCTAssertEqual(
      commands.set(DisplaySetOptions(display: "all", dithering: .off)).exitCode,
      .usage)
    XCTAssertEqual(
      commands.set(DisplaySetOptions(display: "Living Room", dithering: .off)).exitCode,
      .usage)
  }

  func testNoSetFlagsReturnsUsage() {
    let core = FakeCore()
    core.displays = []
    core.readError = DisplayControlError.unexpected("state should not be read")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "main"))

    XCTAssertEqual(result.exitCode, .usage)
    XCTAssertTrue(core.callLog.isEmpty)
  }

  func testDirectDitheringSetDoesNotReadDisplayState() {
    let core = FakeCore()
    core.readError = DisplayControlError.unexpected("state should not be read")
    core.ditheringResult = .applied("dither")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", dithering: .off))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.callLog, ["setDithering:false"])
  }

  func testDirectICCSetDoesNotReadDisplayState() {
    let core = FakeCore()
    core.readError = DisplayControlError.unexpected("state should not be read")
    core.iccResult = .applied("icc")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(display: "uuid:one", icc: URL(fileURLWithPath: "/tmp/a.icc")))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.callLog, ["setICC:a.icc"])
  }

  func testExactDisplayModeDelegatesValidationToCore() {
    let core = FakeCore()
    core.displayModeResult = .blocked("unknown display mode")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(
        display: "uuid:one",
        displayMode: "missing",
        yes: true))

    XCTAssertEqual(result.exitCode, .blocked)
    XCTAssertEqual(core.callLog.filter { $0.hasPrefix("listDisplayModes") }, [])
    XCTAssertEqual(core.displayModeSetCalls, [DisplayModeID("missing")])
  }

  func testResolutionModeAndSemanticResolutionFlagsAreMutuallyExclusive() {
    let commands = DisplayCommands(context: OMDCLIContext(core: FakeCore(), isTTY: false))

    let result = commands.set(
      DisplaySetOptions(
        display: "uuid:one",
        resolutionMode: "res-1920-hidpi",
        resolution: "1920x1080",
        yes: true))

    XCTAssertEqual(result.exitCode, .usage)
  }

  func testDisplayModeAndSemanticDisplayModeFlagsAreMutuallyExclusive() {
    let commands = DisplayCommands(context: OMDCLIContext(core: FakeCore(), isTTY: false))

    let result = commands.set(
      DisplaySetOptions(
        display: "uuid:one",
        displayMode: "mode-r1-rgb8",
        bpc: 10,
        yes: true))

    XCTAssertEqual(result.exitCode, .usage)
  }

  func testDisplayModeCannotCombineWithResolutionChange() {
    let commands = DisplayCommands(context: OMDCLIContext(core: FakeCore(), isTTY: false))

    let result = commands.set(
      DisplaySetOptions(
        display: "uuid:one",
        resolution: "2560x1440",
        hidpi: .on,
        displayMode: "mode-r1-rgb8",
        yes: true))

    XCTAssertEqual(result.exitCode, .usage)
    XCTAssertTrue(result.stderr.contains("--display-mode cannot be combined"))
  }

  func testInvalidResolutionReturnsUsageBeforeMutation() {
    let core = FakeCore()
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(display: "uuid:one", resolution: "1920-1080", yes: true))

    XCTAssertEqual(result.exitCode, .usage)
    XCTAssertTrue(core.resolutionSetCalls.isEmpty)
  }

  func testMalformedResolutionWithExtraOrMissingSeparatorsReturnsUsageBeforeMutation() {
    for resolution in ["1920xx1080", "x1920x1080", "1920x1080x", "x"] {
      let core = FakeCore()
      let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

      let result = commands.set(
        DisplaySetOptions(display: "uuid:one", resolution: resolution, yes: true))

      XCTAssertEqual(result.exitCode, .usage, resolution)
      XCTAssertTrue(core.resolutionSetCalls.isEmpty, resolution)
    }
  }

  func testSemanticResolutionUsesResolutionSetterOnly() {
    let core = FakeCore()
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(
        display: "uuid:one",
        resolution: "2560x1440",
        hidpi: .on,
        refresh: 60,
        yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.resolutionSetCalls, [ResolutionModeID("res-2560-hidpi")])
    XCTAssertTrue(core.displayModeSetCalls.isEmpty)
  }

  func testResolutionAttemptedFailureRestoresBaselineAndSkipsLaterOps() {
    let core = FakeCore()
    core.resolutionResult = .readbackMismatch("resolution readback mismatch")
    core.ditheringResult = .applied("dither")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(
        display: "uuid:one",
        resolutionMode: "res-2560-hidpi",
        dithering: .off,
        yes: true))

    XCTAssertEqual(result.exitCode, .partialFailure)
    XCTAssertTrue(result.stdout.contains("resolution: readbackMismatch"))
    XCTAssertTrue(result.stdout.contains("restore.resolution:"))
    XCTAssertTrue(result.stdout.contains("restore.displayMode:"))
    XCTAssertTrue(result.stdout.contains("dithering: skipped"))
    XCTAssertEqual(core.callLog.filter { $0.hasPrefix("set") }, [
      "setResolution:res-2560-hidpi",
      "setResolution:res-1920-hidpi",
      "setDisplayMode:mode-r1-rgb8",
    ])
  }

  func testResolutionAttemptedFailureReportsRestoreThrowWithoutDroppingOriginalFailure() {
    let core = FakeCore()
    core.resolutionResult = .readbackMismatch("resolution readback mismatch")
    core.setResolutionErrors["res-1920-hidpi"] = DisplayControlError.unexpected("restore exploded")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(
        display: "uuid:one",
        resolutionMode: "res-2560-hidpi",
        yes: true))

    XCTAssertEqual(result.exitCode, .partialFailure)
    XCTAssertTrue(result.stdout.contains("resolution: readbackMismatch"))
    XCTAssertTrue(result.stdout.contains("restore.resolution: failed"))
    XCTAssertTrue(result.stdout.contains("restore exploded"))
    XCTAssertTrue(result.stdout.contains("restore.displayMode: blocked"))
    XCTAssertTrue(result.stderr.isEmpty)
  }

  func testResolutionChangeNeedsYesInNonInteractiveUse() {
    let core = FakeCore()
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(display: "uuid:one", resolution: "2560x1440", hidpi: .on))

    XCTAssertEqual(result.exitCode, .blocked)
    XCTAssertTrue(core.resolutionSetCalls.isEmpty)
  }

  func testExactCurrentResolutionDoesNotPrompt() {
    let core = FakeCore()
    let recorder = PromptRecorder()
    let commands = DisplayCommands(
      context: OMDCLIContext(core: core, isTTY: true) { _ in
        recorder.prompted = true
        return false
      })

    let result = commands.set(
      DisplaySetOptions(display: "uuid:one", resolutionMode: "res-1920-hidpi"))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertFalse(recorder.prompted)
    XCTAssertEqual(core.resolutionSetCalls, [ResolutionModeID("res-1920-hidpi")])
  }

  func testTTYPromptDeclinedBlocksBeforeMutation() {
    let core = FakeCore()
    let recorder = PromptRecorder()
    let commands = DisplayCommands(
      context: OMDCLIContext(core: core, isTTY: true) { _ in
        recorder.prompted = true
        return false
      })

    let result = commands.set(
      DisplaySetOptions(display: "uuid:one", resolutionMode: "res-2560-hidpi"))

    XCTAssertEqual(result.exitCode, .blocked)
    XCTAssertTrue(recorder.prompted)
    XCTAssertTrue(core.resolutionSetCalls.isEmpty)
  }

  func testSemanticDisplayModeOnlyUsesCurrentTimingAndDisplayModeSetter() {
    let core = FakeCore()
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", bpc: 10, yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertTrue(core.resolutionSetCalls.isEmpty)
    XCTAssertEqual(core.displayModeSetCalls, [DisplayModeID("mode-r1-rgb10")])
  }

  func testSemanticDisplayModeNoCandidateReturnsUsageWithoutPromptOrRestore() {
    let core = FakeCore()
    let recorder = PromptRecorder()
    let commands = DisplayCommands(
      context: OMDCLIContext(core: core, isTTY: true) { _ in
        recorder.prompted = true
        return true
      })

    let result = commands.set(DisplaySetOptions(display: "uuid:one", bpc: 12))

    XCTAssertEqual(result.exitCode, .usage)
    XCTAssertTrue(result.stderr.contains("No display mode matches"))
    XCTAssertFalse(recorder.prompted)
    XCTAssertTrue(core.resolutionSetCalls.isEmpty)
    XCTAssertTrue(core.displayModeSetCalls.isEmpty)
  }

  func testResolutionNoOpWithSemanticDisplayModeResolvesBeforeMutation() {
    let core = FakeCore()
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(
        display: "uuid:one",
        resolutionMode: "res-1920-hidpi",
        bpc: 10,
        yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.callLog.filter { $0.hasPrefix("set") }, [
      "setResolution:res-1920-hidpi",
      "setDisplayMode:mode-r1-rgb10",
    ])
  }

  func testResolutionChangeThenSemanticDisplayModeResolvesAfterResolution() {
    let core = FakeCore()
    core.displayModesForResolution["res-2560-hidpi"] = .readable([core.modeR2RGB10])
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(
        display: "uuid:one",
        resolution: "2560x1440",
        hidpi: .on,
        bpc: 10,
        yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.callLog.filter { $0.hasPrefix("set") }, [
      "setResolution:res-2560-hidpi",
      "setDisplayMode:mode-r2-rgb10",
    ])
  }

  func testResolutionChangingSemanticDisplayModeRestoresWhenPostResolutionHasNoCandidate() {
    let core = FakeCore()
    core.displayModesForResolution["res-2560-hidpi"] = .readable([core.modeR2RGB8])
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(
        display: "uuid:one",
        resolution: "2560x1440",
        hidpi: .on,
        bpc: 10,
        yes: true))

    XCTAssertEqual(result.exitCode, .partialFailure)
    XCTAssertTrue(result.stdout.contains("displayMode: failed"))
    XCTAssertTrue(result.stdout.contains("restore.resolution: applied"))
    XCTAssertTrue(result.stdout.contains("restore.displayMode:"))
    XCTAssertEqual(core.callLog.filter { $0.hasPrefix("set") }, [
      "setResolution:res-2560-hidpi",
      "setResolution:res-1920-hidpi",
      "setDisplayMode:mode-r1-rgb8",
    ])
  }

  func testResolutionChangingSemanticDisplayModeRestoresWhenPostResolutionBackendIsUnreadable() {
    let core = FakeCore()
    core.displayModesForResolution["res-2560-hidpi"] = .unreadable(
      "CADisplay lost after resolution change",
      source: "CADisplay")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(
        display: "uuid:one",
        resolution: "2560x1440",
        hidpi: .on,
        bpc: 10,
        yes: true))

    XCTAssertEqual(result.exitCode, .partialFailure)
    XCTAssertTrue(result.stdout.contains("displayMode: failed"))
    XCTAssertTrue(result.stdout.contains("CADisplay lost after resolution change"))
    XCTAssertTrue(result.stdout.contains("restore.resolution: applied"))
    XCTAssertTrue(result.stdout.contains("restore.displayMode:"))
    XCTAssertEqual(core.callLog.filter { $0.hasPrefix("set") }, [
      "setResolution:res-2560-hidpi",
      "setResolution:res-1920-hidpi",
      "setDisplayMode:mode-r1-rgb8",
    ])
  }

  func testDisplayModeBackendUnavailableBeforeMutationExitsBlocked() {
    let core = FakeCore()
    core.displayModesForResolution["res-1920-hidpi"] = .unreadable(
      "CADisplay unavailable",
      source: "CADisplay")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", bpc: 10, yes: true))

    XCTAssertEqual(result.exitCode, .blocked)
    XCTAssertTrue(result.stdout.contains("displayMode: blocked"))
    XCTAssertTrue(core.displayModeSetCalls.isEmpty)
  }

  func testOperationsRunInResolutionDisplayModeDitheringICCOrder() {
    let core = FakeCore()
    core.displayModesForResolution["res-2560-hidpi"] = .readable([core.modeR2RGB10])
    core.ditheringResult = .applied("dither")
    core.iccResult = .applied("icc")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(
        display: "uuid:one",
        resolutionMode: "res-2560-hidpi",
        bpc: 10,
        dithering: .off,
        icc: URL(fileURLWithPath: "/tmp/a.icc"),
        yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.callLog.filter { $0.hasPrefix("set") }, [
      "setResolution:res-2560-hidpi",
      "setDisplayMode:mode-r2-rgb10",
      "setDithering:false",
      "setICC:a.icc",
    ])
  }

  func testFailureAfterResolutionAppliedExitsPartialFailureAndSkipsLaterOps() {
    let core = FakeCore()
    core.displayModesForResolution["res-2560-hidpi"] = .readable([core.modeR2RGB10])
    core.displayModeResult = .backendUnavailable("CADisplay unavailable")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(
        display: "uuid:one",
        resolutionMode: "res-2560-hidpi",
        bpc: 10,
        dithering: .off,
        icc: URL(fileURLWithPath: "/tmp/a.icc"),
        yes: true))

    XCTAssertEqual(result.exitCode, .partialFailure)
    XCTAssertTrue(result.stdout.contains("dithering: skipped"))
    XCTAssertTrue(result.stdout.contains("icc: skipped"))
    XCTAssertFalse(core.callLog.contains("setICC:a.icc"))
  }

  func testThrownDitheringAfterResolutionAppliedExitsPartialFailureAndSkipsLaterOps() {
    let core = FakeCore()
    core.setDitheringError = DisplayControlError.unexpected("dithering exploded")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(
        display: "uuid:one",
        resolutionMode: "res-2560-hidpi",
        dithering: .off,
        icc: URL(fileURLWithPath: "/tmp/a.icc"),
        yes: true))

    XCTAssertEqual(result.exitCode, .partialFailure)
    XCTAssertTrue(result.stdout.contains("resolution: applied"))
    XCTAssertTrue(result.stdout.contains("dithering: failed"))
    XCTAssertTrue(result.stdout.contains("dithering exploded"))
    XCTAssertTrue(result.stdout.contains("icc: skipped"))
    XCTAssertFalse(core.callLog.contains("setICC:a.icc"))
  }

  func testThrownICCAfterDitheringAppliedExitsPartialFailureAndKeepsReports() {
    let core = FakeCore()
    core.ditheringResult = .applied("dither")
    core.setICCError = DisplayControlError.unexpected("icc exploded")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(
        display: "uuid:one",
        dithering: .off,
        icc: URL(fileURLWithPath: "/tmp/a.icc")))

    XCTAssertEqual(result.exitCode, .partialFailure)
    XCTAssertTrue(result.stdout.contains("dithering: applied"))
    XCTAssertTrue(result.stdout.contains("icc: failed"))
    XCTAssertTrue(result.stdout.contains("icc exploded"))
    XCTAssertTrue(result.stderr.isEmpty)
  }

  func testOperationsJSONIncludesRestoreReports() throws {
    let core = FakeCore()
    core.displayModesForResolution["res-2560-hidpi"] = .readable([core.modeR2RGB8])
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(
        display: "uuid:one",
        resolution: "2560x1440",
        hidpi: .on,
        bpc: 10,
        json: true,
        yes: true))
    let operations = try jsonArray(result.stdout)
    let restore = try XCTUnwrap(operations[1]["restore"] as? [[String: Any]])

    XCTAssertEqual(result.exitCode, .partialFailure)
    XCTAssertEqual(operations[0]["operation"] as? String, "resolution")
    XCTAssertEqual(operations[1]["operation"] as? String, "displayMode")
    XCTAssertEqual(restore.map { $0["operation"] as? String }, ["resolution", "displayMode"])
  }

  func testHelpSurfaceListsCurrentDisplayCommandsAndSetOptions() {
    let rootHelp = OMDCommand.helpMessage()
    let displayHelp = Display.helpMessage()
    let setHelp = DisplaySet.helpMessage()

    XCTAssertEqual(
      rootHelp,
      """
      OVERVIEW: Read and set macOS display state.

      USAGE: omd <subcommand>

      OPTIONS:
        -h, --help              Show help information.

      SUBCOMMANDS:
        display                 Read and set display properties.
        version

        See 'omd help <subcommand>' for detailed help.
      """)
    XCTAssertEqual(
      displayHelp,
      """
      OVERVIEW: Read and set display properties.

      USAGE: display <subcommand>

      OPTIONS:
        -h, --help              Show help information.

      SUBCOMMANDS:
        list
        get
        resolutions
        modes
        set

        See 'display help <subcommand>' for detailed help.
      """)
    XCTAssertEqual(
      setHelp,
      """
      USAGE: set <options>

      OPTIONS:
        --display <display>     (default: main)
        --resolution-mode <resolution-mode>
        --resolution <resolution>
        --hidpi <hidpi>
        --refresh <refresh>
        --display-mode <display-mode>
        --encoding <encoding>
        --bpc <bpc>
        --range <range>
        --chroma <chroma>
        --hdr <hdr>
        --dithering <dithering>
        --icc <icc>
        --json
        --yes
        -h, --help              Show help information.
      """ + "\n")
  }
}

private final class FakeCore: OMDCoreClient, @unchecked Sendable {
  let res1920HiDPI = ResolutionMode(
    id: ResolutionModeID("res-1920-hidpi"),
    logicalResolution: DisplaySize(width: 1920, height: 1080),
    backingResolution: DisplaySize(width: 3840, height: 2160),
    scaleFactor: 2,
    isHiDPI: true,
    refreshHz: 60
  )
  let res2560HiDPI = ResolutionMode(
    id: ResolutionModeID("res-2560-hidpi"),
    logicalResolution: DisplaySize(width: 2560, height: 1440),
    backingResolution: DisplaySize(width: 5120, height: 2880),
    scaleFactor: 2,
    isHiDPI: true,
    refreshHz: 60
  )
  let modeR1RGB8 = DisplayMode(
    id: DisplayModeID("mode-r1-rgb8"),
    outputTimingResolution: DisplaySize(width: 3840, height: 2160),
    outputTimingRefreshHz: 60,
    bitDepth: 8,
    encoding: .rgb,
    range: .full,
    chroma: .c444,
    hdrMode: .sdr
  )
  let modeR1RGB10 = DisplayMode(
    id: DisplayModeID("mode-r1-rgb10"),
    outputTimingResolution: DisplaySize(width: 3840, height: 2160),
    outputTimingRefreshHz: 60,
    bitDepth: 10,
    encoding: .rgb,
    range: .full,
    chroma: .c444,
    hdrMode: .sdr
  )
  let modeR2RGB8 = DisplayMode(
    id: DisplayModeID("mode-r2-rgb8"),
    outputTimingResolution: DisplaySize(width: 5120, height: 2880),
    outputTimingRefreshHz: 60,
    bitDepth: 8,
    encoding: .rgb,
    range: .full,
    chroma: .c444,
    hdrMode: .sdr
  )
  let modeR2RGB10 = DisplayMode(
    id: DisplayModeID("mode-r2-rgb10"),
    outputTimingResolution: DisplaySize(width: 5120, height: 2880),
    outputTimingRefreshHz: 60,
    bitDepth: 10,
    encoding: .rgb,
    range: .full,
    chroma: .c444,
    hdrMode: .sdr
  )

  var displays: [DisplayTarget]
  var state: DisplayState
  var resolutionModesResult: DisplayListResult<ResolutionMode>
  var displayModesForResolution: [String: DisplayListResult<DisplayMode>] = [:]
  var resolutionResult: DisplaySetResult = .applied("resolution")
  var displayModeResult: DisplaySetResult = .applied("displayMode")
  var ditheringResult: DisplaySetResult = .noOp()
  var iccResult: DisplaySetResult = .noOp()
  var resolutionSetCalls: [ResolutionModeID] = []
  var displayModeSetCalls: [DisplayModeID] = []
  var callLog: [String] = []
  var readError: Error?
  var listResolutionError: Error?
  var listDisplayModeError: Error?
  var setResolutionErrors: [String: Error] = [:]
  var setDitheringError: Error?
  var setICCError: Error?

  init() {
    let target = DisplayTarget(
      selector: DisplaySelector("uuid:one"),
      displayID: 1,
      label: "One",
      isMain: true,
      isBuiltin: false
    )
    self.displays = [target]
    self.resolutionModesResult = .readable([res1920HiDPI, res2560HiDPI], source: "CoreGraphics")
    self.state = Self.state(
      target: target,
      resolution: res1920HiDPI,
      displayMode: modeR1RGB8
    )
    self.displayModesForResolution = [
      "res-1920-hidpi": .readable([modeR1RGB8, modeR1RGB10], source: "CADisplay"),
      "res-2560-hidpi": .readable([modeR2RGB8, modeR2RGB10], source: "CADisplay"),
    ]
  }

  func listDisplays() throws -> [DisplayTarget] {
    callLog.append("listDisplays")
    return displays
  }

  func readDisplayState(_ display: DisplaySelector) throws -> DisplayState {
    callLog.append("readState:\(display.rawValue)")
    if let readError {
      throw readError
    }
    return state
  }

  func listResolutionModes(_ display: DisplaySelector) throws
    -> DisplayListResult<ResolutionMode>
  {
    callLog.append("listResolutions:\(display.rawValue)")
    if let listResolutionError {
      throw listResolutionError
    }
    return resolutionModesResult
  }

  func setResolutionMode(
    _ display: DisplaySelector,
    modeID: ResolutionModeID
  ) throws -> DisplaySetResult {
    callLog.append("setResolution:\(modeID.rawValue)")
    resolutionSetCalls.append(modeID)
    if let error = setResolutionErrors[modeID.rawValue] {
      throw error
    }
    if state.currentResolutionModeID.value == modeID {
      return .noOp("same")
    }
    let result = resolutionResult
    if result.status == .applied, let mode = resolutionModesResult.items.first(where: { $0.id == modeID }) {
      applyResolution(mode)
    }
    return result
  }

  func listDisplayModes(_ display: DisplaySelector) throws
    -> DisplayListResult<DisplayMode>
  {
    callLog.append("listDisplayModes:\(display.rawValue)")
    if let listDisplayModeError {
      throw listDisplayModeError
    }
    let key = state.currentResolutionModeID.value?.rawValue ?? ""
    return displayModesForResolution[key] ?? .readable([], source: "CADisplay")
  }

  func setDisplayMode(
    _ display: DisplaySelector,
    modeID: DisplayModeID
  ) throws -> DisplaySetResult {
    callLog.append("setDisplayMode:\(modeID.rawValue)")
    displayModeSetCalls.append(modeID)
    if state.currentDisplayModeID.value == modeID {
      return .noOp("same")
    }
    let result = displayModeResult
    if result.status == .applied,
      let mode = try listDisplayModes(display).items.first(where: { $0.id == modeID })
    {
      applyDisplayMode(mode)
    }
    return result
  }

  func setDithering(_ display: DisplaySelector, enabled: Bool) throws -> DisplaySetResult {
    callLog.append("setDithering:\(enabled)")
    if let setDitheringError {
      throw setDitheringError
    }
    return ditheringResult
  }

  func setICCProfile(_ display: DisplaySelector, profileURL: URL) throws -> DisplaySetResult {
    callLog.append("setICC:\(profileURL.lastPathComponent)")
    if let setICCError {
      throw setICCError
    }
    return iccResult
  }

  private func applyResolution(_ mode: ResolutionMode) {
    state.currentResolutionModeID = .readable(mode.id)
    state.logicalResolution = .readable(mode.logicalResolution)
    state.backingResolution = .readable(mode.backingResolution)
    state.scaleFactor = .readable(mode.scaleFactor)
    state.isHiDPI = .readable(mode.isHiDPI)
    state.resolutionRefreshHz = mode.refreshHz.map { .readable($0) } ?? .unreadable()
    state.outputTimingResolution = .readable(mode.backingResolution)
    state.outputTimingRefreshHz = mode.refreshHz.map { .readable($0) } ?? .unreadable()
  }

  private func applyDisplayMode(_ mode: DisplayMode) {
    state.currentDisplayModeID = .readable(mode.id)
    state.outputTimingResolution = .readable(mode.outputTimingResolution)
    state.outputTimingRefreshHz = mode.outputTimingRefreshHz.map { .readable($0) } ?? .unreadable()
    state.bitDepth = mode.bitDepth.map { .readable($0) } ?? .unreadable()
    state.encoding = .readable(mode.encoding)
    state.range = .readable(mode.range)
    state.chroma = .readable(mode.chroma)
    state.hdrMode = .readable(mode.hdrMode)
  }

  private static func state(
    target: DisplayTarget,
    resolution: ResolutionMode,
    displayMode: DisplayMode
  ) -> DisplayState {
    DisplayState(
      target: target,
      currentResolutionModeID: .readable(resolution.id),
      logicalResolution: .readable(resolution.logicalResolution),
      backingResolution: .readable(resolution.backingResolution),
      scaleFactor: .readable(resolution.scaleFactor),
      isHiDPI: .readable(resolution.isHiDPI),
      resolutionRefreshHz: resolution.refreshHz.map { .readable($0) } ?? .unreadable(),
      currentDisplayModeID: .readable(displayMode.id),
      outputTimingResolution: .readable(displayMode.outputTimingResolution),
      outputTimingRefreshHz: displayMode.outputTimingRefreshHz.map { .readable($0) } ?? .unreadable(),
      bitDepth: displayMode.bitDepth.map { .readable($0) } ?? .unreadable(),
      encoding: .readable(displayMode.encoding),
      range: .readable(displayMode.range),
      chroma: .readable(displayMode.chroma),
      hdrMode: .readable(displayMode.hdrMode),
      ditheringEnabled: .readable(true),
      iccProfileURL: .unreadable()
    )
  }
}

private final class PromptRecorder: @unchecked Sendable {
  var prompted = false
}

private func assertPlainTable(
  _ output: String,
  equals expected: String,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertEqual(output, expected, file: file, line: line)
  XCTAssertFalse(output.contains("\t"), file: file, line: line)
  for row in output.split(separator: "\n", omittingEmptySubsequences: false) {
    guard !row.isEmpty else { continue }
    XCTAssertFalse(row.hasSuffix(" "), "line has trailing whitespace: \(row)", file: file, line: line)
  }
}

private func jsonArray(_ value: String, file: StaticString = #filePath, line: UInt = #line) throws
  -> [[String: Any]]
{
  let data = try XCTUnwrap(value.data(using: .utf8), file: file, line: line)
  return try XCTUnwrap(
    JSONSerialization.jsonObject(with: data) as? [[String: Any]],
    file: file,
    line: line)
}

private func jsonObject(_ value: String, file: StaticString = #filePath, line: UInt = #line) throws
  -> [String: Any]
{
  let data = try XCTUnwrap(value.data(using: .utf8), file: file, line: line)
  return try XCTUnwrap(
    JSONSerialization.jsonObject(with: data) as? [String: Any],
    file: file,
    line: line)
}

private func rawValue(_ value: Any?) -> String? {
  (value as? [String: Any])?["rawValue"] as? String
}
