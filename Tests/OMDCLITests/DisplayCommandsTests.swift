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
    XCTAssertEqual(try DisplaySet.parse(["--display", "uuid:one", "--dithering", "off"]).display, "uuid:one")
  }

  func testListJSONUsesCLIDTOAndDoesNotExposeRawDisplayID() throws {
    let core = FakeCore()
    core.displays.append(DisplayTarget(selector: DisplaySelector("cg:2"), displayID: 2, label: "Fallback", isMain: false, isBuiltin: false))
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.list(json: true)
    let displays = try jsonArray(result.stdout)

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(displays.first?["selector"] as? String, "uuid:one")
    XCTAssertEqual(displays.dropFirst().first?["selector"] as? String, "")
    XCTAssertEqual(displays.first?["main"] as? Bool, true)
    XCTAssertEqual(displays.first?["builtin"] as? Bool, false)
    XCTAssertNil(displays.first?["displayID"])
    XCTAssertNil(displays.dropFirst().first?["displayID"])
    XCTAssertTrue(core.callLog.allSatisfy { !$0.hasPrefix("set") })
  }

  func testDisplayListHumanUsesAlignedColumnsAndSelectorLast() {
    let core = FakeCore()
    core.displays.append(DisplayTarget(selector: DisplaySelector("uuid:two-long"), displayID: 2, label: "Long Living Room", isMain: false, isBuiltin: true))
    core.displays.append(DisplayTarget(selector: DisplaySelector("cg:3"), displayID: 3, label: "Fallback", isMain: false, isBuiltin: false))
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.list(json: false)

    XCTAssertEqual(result.exitCode, .success)
    assertPlainTable(
      result.stdout,
      equals: """
        main  builtin  label             selector
        yes   no       One               uuid:one
        no    yes      Long Living Room  uuid:two-long
        no    no       Fallback

        """)
  }

  func testICCListHumanUsesAlignedColumnsAndPathLast() {
    let commands = ICCCommands(context: OMDCLIContext(core: FakeCore(), isTTY: false))

    let result = commands.list(json: false)

    XCTAssertEqual(result.exitCode, .success)
    assertPlainTable(
      result.stdout,
      equals: """
        name               path
        Display P3         /Library/ColorSync/Profiles/Display P3.icc
        sRGB IEC61966-2.1  /System/Library/ColorSync/Profiles/sRGB Profile.icc

        """)
  }

  func testICCListJSONUsesNameAndPath() throws {
    let core = FakeCore()
    let commands = ICCCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.list(json: true)
    let profiles = try jsonArray(result.stdout)

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(profiles.first?["name"] as? String, "Display P3")
    XCTAssertEqual(profiles.first?["path"] as? String, "/Library/ColorSync/Profiles/Display P3.icc")
    XCTAssertEqual(core.callLog, ["listICCProfiles"])
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
      id: ResolutionModeID("res-5120-wide"), logicalResolution: DisplaySize(width: 5120, height: 1440),
      backingResolution: DisplaySize(width: 5120, height: 1440), scaleFactor: 1, isHiDPI: false, refreshHz: 60)
    let res3840LoDPI = ResolutionMode(
      id: ResolutionModeID("res-3840-lodpi"), logicalResolution: DisplaySize(width: 3840, height: 2160),
      backingResolution: DisplaySize(width: 3840, height: 2160), scaleFactor: 1, isHiDPI: false, refreshHz: 60)
    let res1920HiDPI120B = ResolutionMode(
      id: ResolutionModeID("res-1920-hidpi-120-b"), logicalResolution: DisplaySize(width: 1920, height: 1080),
      backingResolution: DisplaySize(width: 3840, height: 2160), scaleFactor: 2, isHiDPI: true, refreshHz: 120)
    let res1920HiDPI120A = ResolutionMode(
      id: ResolutionModeID("res-1920-hidpi-120-a"), logicalResolution: DisplaySize(width: 1920, height: 1080),
      backingResolution: DisplaySize(width: 3840, height: 2160), scaleFactor: 2, isHiDPI: true, refreshHz: 120)
    let res3008HiDPI = ResolutionMode(
      id: ResolutionModeID("res-3008-hidpi"), logicalResolution: DisplaySize(width: 3008, height: 1692),
      backingResolution: DisplaySize(width: 5120, height: 2880), scaleFactor: 1.7, isHiDPI: true, refreshHz: 60)
    let resEqualAreaWide = ResolutionMode(
      id: ResolutionModeID("res-equal-area-wide"), logicalResolution: DisplaySize(width: 8192, height: 1024),
      backingResolution: DisplaySize(width: 8192, height: 1024), scaleFactor: 1, isHiDPI: false, refreshHz: 60)
    let resEqualAreaNarrow = ResolutionMode(
      id: ResolutionModeID("res-equal-area-narrow"), logicalResolution: DisplaySize(width: 4096, height: 2048),
      backingResolution: DisplaySize(width: 4096, height: 2048), scaleFactor: 1, isHiDPI: false, refreshHz: 60)
    core.resolutionModesResult = .readable(
      [
        res5120Wide, core.res1920HiDPI, resEqualAreaWide, core.res2560HiDPI, res1920HiDPI120B, res3840LoDPI, res3008HiDPI, res1920HiDPI120A, resEqualAreaNarrow,
      ], source: "CoreGraphics")
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
        1920x1080  3840x2160  2      yes    120      res-1920-hidpi-120-a
        1920x1080  3840x2160  2      yes    120      res-1920-hidpi-120-b
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
        "res-5120-wide", "res-1920-hidpi", "res-equal-area-wide", "res-2560-hidpi", "res-1920-hidpi-120-b", "res-3840-lodpi", "res-3008-hidpi",
        "res-1920-hidpi-120-a", "res-equal-area-narrow",
      ])
  }

  func testDisplayModesHumanUsesAlignedColumnsAndModeLast() {
    let commands = DisplayCommands(context: OMDCLIContext(core: FakeCore(), isTTY: false))

    let result = commands.displayModes(display: "uuid:one", json: false)

    XCTAssertEqual(result.exitCode, .success)
    assertPlainTable(
      result.stdout,
      equals: """
        timing     hdr  refresh  encoding  bpc  range  chroma  displayMode
        3840x2160  sdr  60       rgb       10   full   -       mode-r1-rgb-10
        3840x2160  sdr  60       rgb       8    full   -       mode-r1-rgb-8

        """)
  }

  func testDisplayModesHumanGroupsByTimingPixelAreaAndLeavesJSONRaw() throws {
    let core = FakeCore()
    func mode(
      _ id: String, timing: DisplaySize = DisplaySize(width: 3840, height: 2160), refresh: Double = 60, hdr: DisplayHDRMode = .sdr, bpc: Int = 8,
      encoding: DisplayEncoding = .rgb, range: DisplayRange = .full, chroma: DisplayChroma = .none, isVRR: Bool = false, hdrModeRaw: String? = nil,
      colorModeRaw: String? = nil, modeDescription: String? = nil
    ) -> DisplayMode {
      DisplayMode(
        id: DisplayModeID(id), outputTimingResolution: timing, outputTimingRefreshHz: refresh, bitDepth: bpc, encoding: encoding, range: range, chroma: chroma,
        hdrMode: hdr, hdrModeRaw: hdrModeRaw, colorModeRaw: colorModeRaw, modeDescription: modeDescription, isVRR: isVRR)
    }
    let dolbyDescription = "<CADisplayMode 3840 x 2160 fmt:DolbyVision range:full>"
    let rawModes = [
      mode("mode-4k-120-sdr-rgb-8-full-none", refresh: 120), mode("mode-4k-60-sdr-ycbcr-8-limited-420", encoding: .ycbcr, range: .limited, chroma: .c420),
      mode("mode-4k-60-sdr-rgb-10-full-none", bpc: 10), mode("mode-1080-120-sdr-rgb-8-full-none", timing: DisplaySize(width: 1920, height: 1080), refresh: 120),
      mode("mode-4k-60-hdr-rgb-8-full-none", hdr: .hdr10), mode("mode-4k-60-sdr-ycbcr-8-full-422", encoding: .ycbcr, chroma: .c422),
      mode("mode-4k-60-sdr-ycbcr-8-full-444", encoding: .ycbcr, chroma: .c444), mode("mode-4k-60-sdr-rgb-8-limited-none", range: .limited),
      mode(
        "mode-4k-60-dolby-none-12-full-none", hdr: .dolbyVision, bpc: 12, encoding: .none, hdrModeRaw: "Dolby", colorModeRaw: "DolbyVision",
        modeDescription: dolbyDescription), mode("mode-4k-60-sdr-rgb-8-full-none"), mode("mode-4k-60-sdr-rgb-8-full-none-vrr", isVRR: true),
    ]
    core.displayModesForResolution["res-1920-hidpi"] = .readable(rawModes, source: "CADisplay")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let human = commands.displayModes(display: "uuid:one", json: false)
    let json = try jsonObject(commands.displayModes(display: "uuid:one", json: true).stdout)
    let modes = try XCTUnwrap(json["modes"] as? [[String: Any]])

    XCTAssertEqual(human.exitCode, .success)
    assertPlainTable(
      human.stdout,
      equals: """
        timing     hdr           refresh   encoding  bpc  range    chroma  displayMode
        1920x1080  sdr           120       rgb       8    full     -       mode-1080-120-sdr-rgb-8-full-none
        3840x2160  sdr           120       rgb       8    full     -       mode-4k-120-sdr-rgb-8-full-none
        3840x2160  sdr           60        rgb       10   full     -       mode-4k-60-sdr-rgb-10-full-none
        3840x2160  sdr           60        rgb       8    full     -       mode-4k-60-sdr-rgb-8-full-none
        3840x2160  sdr           60        rgb       8    limited  -       mode-4k-60-sdr-rgb-8-limited-none
        3840x2160  sdr           60        ycbcr     8    full     444     mode-4k-60-sdr-ycbcr-8-full-444
        3840x2160  sdr           60        ycbcr     8    full     422     mode-4k-60-sdr-ycbcr-8-full-422
        3840x2160  sdr           60        ycbcr     8    limited  420     mode-4k-60-sdr-ycbcr-8-limited-420
        3840x2160  sdr           60 (VRR)  rgb       8    full     -       mode-4k-60-sdr-rgb-8-full-none-vrr
        3840x2160  hdr10         60        rgb       8    full     -       mode-4k-60-hdr-rgb-8-full-none
        3840x2160  dolby-vision  60        -         12   full     -       mode-4k-60-dolby-none-12-full-none

        """)
    XCTAssertEqual(modes.compactMap { rawValue($0["id"]) }, rawModes.map(\.id.rawValue))
    let dolby = try XCTUnwrap(modes.first { rawValue($0["id"]) == "mode-4k-60-dolby-none-12-full-none" })
    XCTAssertEqual(dolby["encoding"] as? String, "none")
    XCTAssertEqual(dolby["hdrMode"] as? String, "dolby-vision")
    XCTAssertEqual(dolby["hdrModeRaw"] as? String, "Dolby")
    XCTAssertEqual(dolby["colorModeRaw"] as? String, "DolbyVision")
    XCTAssertEqual(dolby["modeDescription"] as? String, dolbyDescription)
  }

  func testHumanModeListsHandleEmptyUnreadableAndDegradedResults() {
    let core = FakeCore()
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    core.resolutionModesResult = .readable([], source: "CoreGraphics")
    assertPlainTable(commands.resolutions(display: "uuid:one", json: false).stdout, equals: "logical  backing  scale  hidpi  refresh  resolutionMode\n")

    core.displayModesForResolution["res-1920-hidpi"] = .readable([], source: "CADisplay")
    assertPlainTable(
      commands.displayModes(display: "uuid:one", json: false).stdout, equals: "timing  hdr  refresh  encoding  bpc  range  chroma  displayMode\n")

    core.resolutionModesResult = .unreadable("CoreGraphics unavailable", source: "CoreGraphics")
    XCTAssertEqual(commands.resolutions(display: "uuid:one", json: false).stdout, "resolution modes unavailable: CoreGraphics unavailable\n")

    core.displayModesForResolution["res-1920-hidpi"] = .unreadable("CADisplay unavailable", source: "CADisplay")
    XCTAssertEqual(commands.displayModes(display: "uuid:one", json: false).stdout, "display modes unavailable: CADisplay unavailable\n")

    core.resolutionModesResult = .degraded([core.res1920HiDPI], reason: "partial", source: "CoreGraphics")
    assertPlainTable(
      commands.resolutions(display: "uuid:one", json: false).stdout,
      equals: """
        logical    backing    scale  hidpi  refresh  resolutionMode
        1920x1080  3840x2160  2      yes    60       res-1920-hidpi

        """)

    core.displayModesForResolution["res-1920-hidpi"] = .degraded([core.modeR1RGB8], reason: "partial", source: "CADisplay")
    assertPlainTable(
      commands.displayModes(display: "uuid:one", json: false).stdout,
      equals: """
        timing     hdr  refresh  encoding  bpc  range  chroma  displayMode
        3840x2160  sdr  60       rgb       8    full   -       mode-r1-rgb-8

        """)
  }

  func testModeListJSONUsesSeparateResolutionAndDisplayModeObjects() throws {
    let commands = DisplayCommands(context: OMDCLIContext(core: FakeCore(), isTTY: false))

    let resolutions = try jsonObject(commands.resolutions(display: "uuid:one", json: true).stdout)
    let displayModes = try jsonObject(commands.displayModes(display: "uuid:one", json: true).stdout)
    let resolutionItems = try XCTUnwrap(resolutions["modes"] as? [[String: Any]])
    let displayModeItems = try XCTUnwrap(displayModes["modes"] as? [[String: Any]])
    let resolutionMode = try XCTUnwrap(resolutionItems.first)
    let displayMode = try XCTUnwrap(displayModeItems.first)

    XCTAssertEqual(resolutions["readability"] as? String, "readable")
    XCTAssertEqual(displayModes["readability"] as? String, "readable")
    XCTAssertEqual(Set(resolutionMode.keys), ["id", "logicalResolution", "backingResolution", "scaleFactor", "isHiDPI", "refreshHz"])
    XCTAssertEqual(
      Set(displayMode.keys),
      ["id", "outputTimingResolution", "outputTimingRefreshHz", "bitDepth", "encoding", "range", "chroma", "hdrMode", "isVirtual", "isVRR", "isHighBandwidth"])
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
    XCTAssertEqual(Set(displayMode.keys), ["currentMode", "timing", "refreshHz", "bpc", "encoding", "range", "chroma", "hdr", "vrr"])
    XCTAssertEqual(displayMode["currentMode"] as? String, "mode-r1-rgb-8")
    XCTAssertEqual(displayMode["bpc"] as? Int, 8)
    XCTAssertEqual(displayMode["encoding"] as? String, "rgb")
    XCTAssertEqual(displayMode["vrr"] as? Bool, false)
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
      displayMode.chroma: -
      displayMode.hdr: sdr
      displayMode.vrr: off
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

    let result = commands.set(DisplaySetOptions(display: "main", resolutionMode: "res-2560-hidpi", yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(
      core.callLog, ["listDisplays", "readState:uuid:one", "listResolutions:uuid:one", "listDisplayModes:uuid:one", "setResolution:res-2560-hidpi"])
  }

  func testMutatingAllAndFriendlyNameReturnUsage() {
    let commands = DisplayCommands(context: OMDCLIContext(core: FakeCore(), isTTY: false))

    XCTAssertEqual(commands.set(DisplaySetOptions(display: "all", dithering: .off)).exitCode, .usage)
    XCTAssertEqual(commands.set(DisplaySetOptions(display: "Living Room", dithering: .off)).exitCode, .usage)
    XCTAssertEqual(commands.set(DisplaySetOptions(display: "cg:1", dithering: .off)).exitCode, .usage)
  }

  func testMutatingMainAllowsRuntimeFallbackSelector() {
    let core = FakeCore()
    core.displays = [DisplayTarget(selector: DisplaySelector("cg:1"), displayID: 1, label: "One", isMain: true, isBuiltin: false)]
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "main", dithering: .off))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.callLog, ["listDisplays", "setDithering:false"])
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

    let result = commands.set(DisplaySetOptions(display: "uuid:one", icc: URL(fileURLWithPath: "/tmp/a.icc")))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.callLog, ["setICC:a.icc"])
  }

  func testExactDisplayModeDelegatesValidationToCore() {
    let core = FakeCore()
    core.displayModeResult = .blocked("unknown display mode")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", displayMode: "missing", yes: true))

    XCTAssertEqual(result.exitCode, .blocked)
    XCTAssertEqual(core.callLog.filter { $0.hasPrefix("listDisplayModes") }, [])
    XCTAssertEqual(core.displayModeSetCalls, [DisplayModeID("missing")])
  }

  func testResolutionModeAndSemanticResolutionFlagsAreMutuallyExclusive() {
    let commands = DisplayCommands(context: OMDCLIContext(core: FakeCore(), isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", resolutionMode: "res-1920-hidpi", resolution: "1920x1080", yes: true))

    XCTAssertEqual(result.exitCode, .usage)
  }

  func testDisplayModeAndSemanticDisplayModeFlagsAreMutuallyExclusive() {
    let commands = DisplayCommands(context: OMDCLIContext(core: FakeCore(), isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", displayMode: "mode-r1-rgb-8", bpc: 10, yes: true))

    XCTAssertEqual(result.exitCode, .usage)
  }

  func testDisplayModeCannotCombineWithResolutionChange() {
    let commands = DisplayCommands(context: OMDCLIContext(core: FakeCore(), isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", resolution: "2560x1440", hidpi: .on, displayMode: "mode-r1-rgb-8", yes: true))

    XCTAssertEqual(result.exitCode, .usage)
    XCTAssertTrue(result.stderr.contains("--display-mode cannot be combined"))
  }

  func testInvalidResolutionReturnsUsageBeforeMutation() {
    let core = FakeCore()
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", resolution: "1920-1080", yes: true))

    XCTAssertEqual(result.exitCode, .usage)
    XCTAssertTrue(core.resolutionSetCalls.isEmpty)
  }

  func testMalformedResolutionWithExtraOrMissingSeparatorsReturnsUsageBeforeMutation() {
    for resolution in ["1920xx1080", "x1920x1080", "1920x1080x", "x"] {
      let core = FakeCore()
      let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

      let result = commands.set(DisplaySetOptions(display: "uuid:one", resolution: resolution, yes: true))

      XCTAssertEqual(result.exitCode, .usage, resolution)
      XCTAssertTrue(core.resolutionSetCalls.isEmpty, resolution)
    }
  }

  func testSemanticResolutionUsesResolutionSetterOnly() {
    let core = FakeCore()
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", resolution: "2560x1440", hidpi: .on, refresh: 60, yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.resolutionSetCalls, [ResolutionModeID("res-2560-hidpi")])
    XCTAssertTrue(core.displayModeSetCalls.isEmpty)
  }

  func testResolutionAttemptedFailureRestoresBaselineAndSkipsLaterOps() {
    let core = FakeCore()
    core.resolutionResult = .readbackMismatch("resolution readback mismatch")
    core.ditheringResult = .applied("dither")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", resolutionMode: "res-2560-hidpi", dithering: .off, yes: true))

    XCTAssertEqual(result.exitCode, .partialFailure)
    XCTAssertTrue(result.stdout.contains("resolution: readbackMismatch"))
    XCTAssertTrue(result.stdout.contains("restore.resolution:"))
    XCTAssertTrue(result.stdout.contains("restore.displayMode:"))
    XCTAssertTrue(result.stdout.contains("dithering: skipped"))
    XCTAssertEqual(
      core.callLog.filter { $0.hasPrefix("set") }, ["setResolution:res-2560-hidpi", "setResolution:res-1920-hidpi", "setDisplayMode:mode-r1-rgb-8"])
  }

  func testResolutionAttemptedFailureReportsRestoreThrowWithoutDroppingOriginalFailure() {
    let core = FakeCore()
    core.resolutionResult = .readbackMismatch("resolution readback mismatch")
    core.setResolutionErrors["res-1920-hidpi"] = DisplayControlError.unexpected("restore exploded")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", resolutionMode: "res-2560-hidpi", yes: true))

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

    let result = commands.set(DisplaySetOptions(display: "uuid:one", resolution: "2560x1440", hidpi: .on))

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

    let result = commands.set(DisplaySetOptions(display: "uuid:one", resolutionMode: "res-1920-hidpi"))

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

    let result = commands.set(DisplaySetOptions(display: "uuid:one", resolutionMode: "res-2560-hidpi"))

    XCTAssertEqual(result.exitCode, .blocked)
    XCTAssertTrue(recorder.prompted)
    XCTAssertTrue(core.resolutionSetCalls.isEmpty)
  }

  func testSemanticDisplayModeOnlyUsesCurrentTimingAndDisplayModeSetter() {
    let core = FakeCore()
    let vrr = DisplayMode(
      id: DisplayModeID("mode-r1-rgb-10-vrr"), outputTimingResolution: DisplaySize(width: 3840, height: 2160), outputTimingRefreshHz: 60, bitDepth: 10,
      encoding: .rgb, range: .full, chroma: .none, hdrMode: .sdr, isVRR: true)
    core.displayModesForResolution["res-1920-hidpi"] = .readable([core.modeR1RGB8, core.modeR1RGB10, vrr], source: "CADisplay")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", bpc: 10, yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertTrue(core.resolutionSetCalls.isEmpty)
    XCTAssertEqual(core.displayModeSetCalls, [DisplayModeID("mode-r1-rgb-10")])
  }

  func testSemanticDisplayModeCanSelectVRRWhenRequested() {
    let core = FakeCore()
    let vrr = DisplayMode(
      id: DisplayModeID("mode-r1-rgb-8-vrr"), outputTimingResolution: DisplaySize(width: 3840, height: 2160), outputTimingRefreshHz: 60, bitDepth: 8,
      encoding: .rgb, range: .full, chroma: .none, hdrMode: .sdr, isVRR: true)
    core.displayModesForResolution["res-1920-hidpi"] = .readable([core.modeR1RGB8, vrr], source: "CADisplay")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", vrr: .on, yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.displayModeSetCalls, [DisplayModeID("mode-r1-rgb-8-vrr")])
  }

  func testSemanticDisplayModeCanSelectDolbyVisionWhenChromaIsOmitted() {
    let core = FakeCore()
    let dolby = DisplayMode(
      id: DisplayModeID("mode-r1-dolby"), outputTimingResolution: DisplaySize(width: 3840, height: 2160), outputTimingRefreshHz: 60, bitDepth: 12,
      encoding: .none, range: .full, chroma: .none, hdrMode: .dolbyVision, hdrModeRaw: "Dolby", colorModeRaw: "DolbyVision",
      modeDescription: "<CADisplayMode 3840 x 2160 fmt:DolbyVision range:full>")
    core.displayModesForResolution["res-1920-hidpi"] = .readable([core.modeR1RGB8, dolby], source: "CADisplay")
    core.state.encoding = .readable(.ycbcr)
    core.state.chroma = .readable(.c444)
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", bpc: 12, hdr: .dolbyVision, yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.displayModeSetCalls, [DisplayModeID("mode-r1-dolby")])
  }

  func testSemanticDisplayModePrefersExactChromaBeforeUnknownWhenChromaIsOmitted() {
    let core = FakeCore()
    let unknownChroma = DisplayMode(
      id: DisplayModeID("mode-r1-rgb-10-unknown-chroma"), outputTimingResolution: DisplaySize(width: 3840, height: 2160), outputTimingRefreshHz: 60,
      bitDepth: 10, encoding: .rgb, range: .full, chroma: .unknown, hdrMode: .sdr)
    core.displayModesForResolution["res-1920-hidpi"] = .readable([unknownChroma, core.modeR1RGB10], source: "CADisplay")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", bpc: 10, yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.displayModeSetCalls, [DisplayModeID("mode-r1-rgb-10")])
  }

  func testSemanticDisplayModeUsesDegradedCurrentChromaWhenChromaIsOmitted() {
    let core = FakeCore()
    let unknownChroma = DisplayMode(
      id: DisplayModeID("mode-r1-rgb-10-unknown-chroma"), outputTimingResolution: DisplaySize(width: 3840, height: 2160), outputTimingRefreshHz: 60,
      bitDepth: 10, encoding: .rgb, range: .full, chroma: .unknown, hdrMode: .sdr)
    core.state.chroma = .degraded(.unknown, source: "CADisplay color mode")
    core.displayModesForResolution["res-1920-hidpi"] = .readable([unknownChroma, core.modeR1RGB10], source: "CADisplay")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", bpc: 10, yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.displayModeSetCalls, [DisplayModeID("mode-r1-rgb-10-unknown-chroma")])
  }

  func testSemanticDisplayModeCanSelectDolbyVisionLowLatency() {
    let core = FakeCore()
    let lowLatency = DisplayMode(
      id: DisplayModeID("mode-r1-dolby-low-latency"), outputTimingResolution: DisplaySize(width: 3840, height: 2160), outputTimingRefreshHz: 60, bitDepth: 12,
      encoding: .none, range: .limited, chroma: .none, hdrMode: .dolbyVisionLowLatency, hdrModeRaw: "Dolby", colorModeRaw: "DolbyVisionLowLatency",
      modeDescription: "<CADisplayMode 3840 x 2160 fmt:DolbyVision_LowLatency range:limited>")
    core.displayModesForResolution["res-1920-hidpi"] = .readable([core.modeR1RGB8, lowLatency], source: "CADisplay")
    core.state.encoding = .readable(.ycbcr)
    core.state.chroma = .readable(.c444)
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", bpc: 12, range: .limited, hdr: .dolbyVisionLowLatency, yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.displayModeSetCalls, [DisplayModeID("mode-r1-dolby-low-latency")])
  }

  func testDolbyVisionSemanticModeRejectsEncodingOrChromaFlags() {
    let core = FakeCore()
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let withEncoding = commands.set(DisplaySetOptions(display: "uuid:one", encoding: .rgb, bpc: 12, range: .full, hdr: .dolbyVision, yes: true))
    let withChroma = commands.set(DisplaySetOptions(display: "uuid:one", bpc: 12, range: .full, chroma: .c444, hdr: .dolbyVisionLowLatency, yes: true))

    XCTAssertEqual(withEncoding.exitCode, .usage)
    XCTAssertEqual(withChroma.exitCode, .usage)
    XCTAssertTrue(withEncoding.stderr.contains("omit those flags"))
    XCTAssertTrue(withChroma.stderr.contains("omit those flags"))
    XCTAssertTrue(core.displayModeSetCalls.isEmpty)
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

    let result = commands.set(DisplaySetOptions(display: "uuid:one", resolutionMode: "res-1920-hidpi", bpc: 10, yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.callLog.filter { $0.hasPrefix("set") }, ["setResolution:res-1920-hidpi", "setDisplayMode:mode-r1-rgb-10"])
  }

  func testResolutionChangeThenSemanticDisplayModeResolvesAfterResolution() {
    let core = FakeCore()
    core.displayModesForResolution["res-2560-hidpi"] = .readable([core.modeR2RGB10])
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", resolution: "2560x1440", hidpi: .on, bpc: 10, yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(core.callLog.filter { $0.hasPrefix("set") }, ["setResolution:res-2560-hidpi", "setDisplayMode:mode-r2-rgb-10"])
  }

  func testResolutionChangingSemanticDisplayModeRestoresWhenPostResolutionHasNoCandidate() {
    let core = FakeCore()
    core.displayModesForResolution["res-2560-hidpi"] = .readable([core.modeR2RGB8])
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", resolution: "2560x1440", hidpi: .on, bpc: 10, yes: true))

    XCTAssertEqual(result.exitCode, .partialFailure)
    XCTAssertTrue(result.stdout.contains("displayMode: failed"))
    XCTAssertTrue(result.stdout.contains("restore.resolution: applied"))
    XCTAssertTrue(result.stdout.contains("restore.displayMode:"))
    XCTAssertEqual(
      core.callLog.filter { $0.hasPrefix("set") }, ["setResolution:res-2560-hidpi", "setResolution:res-1920-hidpi", "setDisplayMode:mode-r1-rgb-8"])
  }

  func testResolutionChangingSemanticDisplayModeRestoresWhenPostResolutionBackendIsUnreadable() {
    let core = FakeCore()
    core.displayModesForResolution["res-2560-hidpi"] = .unreadable("CADisplay lost after resolution change", source: "CADisplay")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(DisplaySetOptions(display: "uuid:one", resolution: "2560x1440", hidpi: .on, bpc: 10, yes: true))

    XCTAssertEqual(result.exitCode, .partialFailure)
    XCTAssertTrue(result.stdout.contains("displayMode: failed"))
    XCTAssertTrue(result.stdout.contains("CADisplay lost after resolution change"))
    XCTAssertTrue(result.stdout.contains("restore.resolution: applied"))
    XCTAssertTrue(result.stdout.contains("restore.displayMode:"))
    XCTAssertEqual(
      core.callLog.filter { $0.hasPrefix("set") }, ["setResolution:res-2560-hidpi", "setResolution:res-1920-hidpi", "setDisplayMode:mode-r1-rgb-8"])
  }

  func testDisplayModeBackendUnavailableBeforeMutationExitsBlocked() {
    let core = FakeCore()
    core.displayModesForResolution["res-1920-hidpi"] = .unreadable("CADisplay unavailable", source: "CADisplay")
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
      DisplaySetOptions(display: "uuid:one", resolutionMode: "res-2560-hidpi", bpc: 10, dithering: .off, icc: URL(fileURLWithPath: "/tmp/a.icc"), yes: true))

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertEqual(
      core.callLog.filter { $0.hasPrefix("set") }, ["setResolution:res-2560-hidpi", "setDisplayMode:mode-r2-rgb-10", "setDithering:false", "setICC:a.icc"])
  }

  func testFailureAfterResolutionAppliedExitsPartialFailureAndSkipsLaterOps() {
    let core = FakeCore()
    core.displayModesForResolution["res-2560-hidpi"] = .readable([core.modeR2RGB10])
    core.displayModeResult = .backendUnavailable("CADisplay unavailable")
    let commands = DisplayCommands(context: OMDCLIContext(core: core, isTTY: false))

    let result = commands.set(
      DisplaySetOptions(display: "uuid:one", resolutionMode: "res-2560-hidpi", bpc: 10, dithering: .off, icc: URL(fileURLWithPath: "/tmp/a.icc"), yes: true))

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
      DisplaySetOptions(display: "uuid:one", resolutionMode: "res-2560-hidpi", dithering: .off, icc: URL(fileURLWithPath: "/tmp/a.icc"), yes: true))

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

    let result = commands.set(DisplaySetOptions(display: "uuid:one", dithering: .off, icc: URL(fileURLWithPath: "/tmp/a.icc")))

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

    let result = commands.set(DisplaySetOptions(display: "uuid:one", resolution: "2560x1440", hidpi: .on, bpc: 10, json: true, yes: true))
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
    let iccHelp = ICC.helpMessage()
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
        icc                     List installed ICC profiles.
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
      iccHelp,
      """
      OVERVIEW: List installed ICC profiles.

      USAGE: icc <subcommand>

      OPTIONS:
        -h, --help              Show help information.

      SUBCOMMANDS:
        list

        See 'icc help <subcommand>' for detailed help.
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
        --vrr <vrr>
        --dithering <dithering>
        --icc <icc>
        --json
        --yes
        -h, --help              Show help information.
      """ + "\n")
  }
}

private final class FakeCore: DisplayClient, @unchecked Sendable {
  let res1920HiDPI = ResolutionMode(
    id: ResolutionModeID("res-1920-hidpi"), logicalResolution: DisplaySize(width: 1920, height: 1080),
    backingResolution: DisplaySize(width: 3840, height: 2160), scaleFactor: 2, isHiDPI: true, refreshHz: 60)
  let res2560HiDPI = ResolutionMode(
    id: ResolutionModeID("res-2560-hidpi"), logicalResolution: DisplaySize(width: 2560, height: 1440),
    backingResolution: DisplaySize(width: 5120, height: 2880), scaleFactor: 2, isHiDPI: true, refreshHz: 60)
  let modeR1RGB8 = DisplayMode(
    id: DisplayModeID("mode-r1-rgb-8"), outputTimingResolution: DisplaySize(width: 3840, height: 2160), outputTimingRefreshHz: 60, bitDepth: 8, encoding: .rgb,
    range: .full, chroma: .none, hdrMode: .sdr)
  let modeR1RGB10 = DisplayMode(
    id: DisplayModeID("mode-r1-rgb-10"), outputTimingResolution: DisplaySize(width: 3840, height: 2160), outputTimingRefreshHz: 60, bitDepth: 10,
    encoding: .rgb, range: .full, chroma: .none, hdrMode: .sdr)
  let modeR2RGB8 = DisplayMode(
    id: DisplayModeID("mode-r2-rgb-8"), outputTimingResolution: DisplaySize(width: 5120, height: 2880), outputTimingRefreshHz: 60, bitDepth: 8, encoding: .rgb,
    range: .full, chroma: .none, hdrMode: .sdr)
  let modeR2RGB10 = DisplayMode(
    id: DisplayModeID("mode-r2-rgb-10"), outputTimingResolution: DisplaySize(width: 5120, height: 2880), outputTimingRefreshHz: 60, bitDepth: 10,
    encoding: .rgb, range: .full, chroma: .none, hdrMode: .sdr)

  var displays: [DisplayTarget]
  var state: DisplayState
  var resolutionModesResult: DisplayListResult<ResolutionMode>
  var displayModesForResolution: [String: DisplayListResult<DisplayMode>] = [:]
  var resolutionResult: DisplaySetResult = .applied("resolution")
  var displayModeResult: DisplaySetResult = .applied("displayMode")
  var ditheringResult: DisplaySetResult = .noOp()
  var iccResult: DisplaySetResult = .noOp()
  var iccProfiles: [ICCProfile] = [
    ICCProfile(name: "Display P3", url: URL(fileURLWithPath: "/Library/ColorSync/Profiles/Display P3.icc")),
    ICCProfile(name: "sRGB IEC61966-2.1", url: URL(fileURLWithPath: "/System/Library/ColorSync/Profiles/sRGB Profile.icc")),
  ]
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
    let target = DisplayTarget(selector: DisplaySelector("uuid:one"), displayID: 1, label: "One", isMain: true, isBuiltin: false)
    self.displays = [target]
    self.resolutionModesResult = .readable([res1920HiDPI, res2560HiDPI], source: "CoreGraphics")
    self.state = Self.state(target: target, resolution: res1920HiDPI, displayMode: modeR1RGB8)
    self.displayModesForResolution = [
      "res-1920-hidpi": .readable([modeR1RGB8, modeR1RGB10], source: "CADisplay"), "res-2560-hidpi": .readable([modeR2RGB8, modeR2RGB10], source: "CADisplay"),
    ]
  }

  func listDisplays() throws -> [DisplayTarget] {
    callLog.append("listDisplays")
    return displays
  }

  func readDisplayState(_ display: DisplaySelector) throws -> DisplayState {
    callLog.append("readState:\(display.rawValue)")
    if let readError { throw readError }
    return state
  }

  func listResolutionModes(_ display: DisplaySelector) throws -> DisplayListResult<ResolutionMode> {
    callLog.append("listResolutions:\(display.rawValue)")
    if let listResolutionError { throw listResolutionError }
    return resolutionModesResult
  }

  func setResolutionMode(_ display: DisplaySelector, modeID: ResolutionModeID) throws -> DisplaySetResult {
    callLog.append("setResolution:\(modeID.rawValue)")
    resolutionSetCalls.append(modeID)
    if let error = setResolutionErrors[modeID.rawValue] { throw error }
    if state.currentResolutionModeID.value == modeID { return .noOp("same") }
    let result = resolutionResult
    if result.status == .applied, let mode = resolutionModesResult.items.first(where: { $0.id == modeID }) { applyResolution(mode) }
    return result
  }

  func listDisplayModes(_ display: DisplaySelector) throws -> DisplayListResult<DisplayMode> {
    callLog.append("listDisplayModes:\(display.rawValue)")
    if let listDisplayModeError { throw listDisplayModeError }
    let key = state.currentResolutionModeID.value?.rawValue ?? ""
    return displayModesForResolution[key] ?? .readable([], source: "CADisplay")
  }

  func setDisplayMode(_ display: DisplaySelector, modeID: DisplayModeID) throws -> DisplaySetResult {
    callLog.append("setDisplayMode:\(modeID.rawValue)")
    displayModeSetCalls.append(modeID)
    if state.currentDisplayModeID.value == modeID { return .noOp("same") }
    let result = displayModeResult
    if result.status == .applied, let mode = try listDisplayModes(display).items.first(where: { $0.id == modeID }) { applyDisplayMode(mode) }
    return result
  }

  func setDithering(_ display: DisplaySelector, enabled: Bool) throws -> DisplaySetResult {
    callLog.append("setDithering:\(enabled)")
    if let setDitheringError { throw setDitheringError }
    return ditheringResult
  }

  func listICCProfiles() throws -> [ICCProfile] {
    callLog.append("listICCProfiles")
    return iccProfiles
  }

  func listDisplayAssignableICCProfiles() throws -> [ICCProfile] {
    callLog.append("listDisplayAssignableICCProfiles")
    return iccProfiles
  }

  func setICCProfile(_ display: DisplaySelector, profileURL: URL) throws -> DisplaySetResult {
    callLog.append("setICC:\(profileURL.lastPathComponent)")
    if let setICCError { throw setICCError }
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
    state.isVRR = .readable(mode.isVRR)
  }

  private static func state(target: DisplayTarget, resolution: ResolutionMode, displayMode: DisplayMode) -> DisplayState {
    DisplayState(
      target: target, currentResolutionModeID: .readable(resolution.id), logicalResolution: .readable(resolution.logicalResolution),
      backingResolution: .readable(resolution.backingResolution), scaleFactor: .readable(resolution.scaleFactor), isHiDPI: .readable(resolution.isHiDPI),
      resolutionRefreshHz: resolution.refreshHz.map { .readable($0) } ?? .unreadable(), currentDisplayModeID: .readable(displayMode.id),
      outputTimingResolution: .readable(displayMode.outputTimingResolution),
      outputTimingRefreshHz: displayMode.outputTimingRefreshHz.map { .readable($0) } ?? .unreadable(),
      bitDepth: displayMode.bitDepth.map { .readable($0) } ?? .unreadable(), encoding: .readable(displayMode.encoding), range: .readable(displayMode.range),
      chroma: .readable(displayMode.chroma), hdrMode: .readable(displayMode.hdrMode), isVRR: .readable(displayMode.isVRR), ditheringEnabled: .readable(true),
      iccProfileURL: .unreadable())
  }
}

private final class PromptRecorder: @unchecked Sendable { var prompted = false }

private func assertPlainTable(_ output: String, equals expected: String, file: StaticString = #filePath, line: UInt = #line) {
  XCTAssertEqual(output, expected, file: file, line: line)
  XCTAssertFalse(output.contains("\t"), file: file, line: line)
  for row in output.split(separator: "\n", omittingEmptySubsequences: false) {
    guard !row.isEmpty else { continue }
    XCTAssertFalse(row.hasSuffix(" "), "line has trailing whitespace: \(row)", file: file, line: line)
  }
}

private func jsonArray(_ value: String, file: StaticString = #filePath, line: UInt = #line) throws -> [[String: Any]] {
  let data = try XCTUnwrap(value.data(using: .utf8), file: file, line: line)
  return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]], file: file, line: line)
}

private func jsonObject(_ value: String, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
  let data = try XCTUnwrap(value.data(using: .utf8), file: file, line: line)
  return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any], file: file, line: line)
}

private func rawValue(_ value: Any?) -> String? { (value as? [String: Any])?["rawValue"] as? String }
