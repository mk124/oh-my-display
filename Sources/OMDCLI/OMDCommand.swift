import ArgumentParser
import Foundation

public struct OMDCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "omd",
    abstract: "Read and set macOS display state.",
    subcommands: [Display.self, ICC.self, VersionCommand.self]
  )

  public init() {}
}

struct Display: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Read and set display properties.",
    subcommands: [
      DisplayList.self, DisplayGet.self, DisplayResolutions.self, DisplayModes.self,
      DisplaySet.self,
    ]
  )
}

struct ICC: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List installed ICC profiles.",
    subcommands: [ICCList.self]
  )
}

struct ICCList: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "list")

  @Flag var json = false

  func run() throws {
    emitAndExit(ICCCommands(context: liveContext()).list(json: json))
  }
}

struct DisplayList: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "list")

  @Flag var json = false

  func run() throws {
    emitAndExit(DisplayCommands(context: liveContext()).list(json: json))
  }
}

struct DisplayGet: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "get")

  @Option var display: String = "main"
  @Flag var json = false

  func run() throws {
    emitAndExit(DisplayCommands(context: liveContext()).get(display: display, json: json))
  }
}

struct DisplayResolutions: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "resolutions")

  @Option var display: String = "main"
  @Flag var json = false

  func run() throws {
    emitAndExit(DisplayCommands(context: liveContext()).resolutions(display: display, json: json))
  }
}

struct DisplayModes: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "modes")

  @Option var display: String = "main"
  @Flag var json = false

  func run() throws {
    emitAndExit(
      DisplayCommands(context: liveContext()).displayModes(display: display, json: json))
  }
}

struct DisplaySet: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "set")

  @Option var display: String = "main"
  @Option(name: .customLong("resolution-mode")) var resolutionMode: String?
  @Option var resolution: String?
  @Option var hidpi: HiDPIArgument?
  @Option var refresh: Double?
  @Option(name: .customLong("display-mode")) var displayMode: String?
  @Option var encoding: EncodingArgument?
  @Option var bpc: Int?
  @Option var range: RangeArgument?
  @Option var chroma: ChromaArgument?
  @Option var hdr: HDRArgument?
  @Option var vrr: VRRArgument?
  @Option var dithering: DitheringArgument?
  @Option var icc: String?
  @Flag var json = false
  @Flag var yes = false

  func run() throws {
    let options = DisplaySetOptions(
      display: display,
      resolutionMode: resolutionMode,
      resolution: resolution,
      hidpi: hidpi,
      refresh: refresh,
      displayMode: displayMode,
      encoding: encoding,
      bpc: bpc,
      range: range,
      chroma: chroma,
      hdr: hdr,
      vrr: vrr,
      dithering: dithering,
      icc: icc.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) },
      json: json,
      yes: yes
    )
    emitAndExit(DisplayCommands(context: liveContext()).set(options))
  }
}

private func liveContext() -> OMDCLIContext {
  OMDCLIContext(isTTY: isatty(STDIN_FILENO) == 1) { question in
    FileHandle.standardError.write((question + " [y/N] ").data(using: .utf8)!)
    guard let answer = readLine() else {
      return false
    }
    return answer.lowercased() == "y" || answer.lowercased() == "yes"
  }
}

func emitAndExit(_ result: CommandResult) -> Never {
  if !result.stdout.isEmpty {
    FileHandle.standardOutput.write(result.stdout.data(using: .utf8)!)
  }
  if !result.stderr.isEmpty {
    FileHandle.standardError.write(result.stderr.data(using: .utf8)!)
  }
  Foundation.exit(result.exitCode.rawValue)
}

extension EncodingArgument: ExpressibleByArgument {}
extension RangeArgument: ExpressibleByArgument {}
extension ChromaArgument: ExpressibleByArgument {}
extension HDRArgument: ExpressibleByArgument {}
extension VRRArgument: ExpressibleByArgument {}
extension DitheringArgument: ExpressibleByArgument {}
extension HiDPIArgument: ExpressibleByArgument {}
