import ArgumentParser
import Foundation

private let omdVersion = "0.2.0"

struct VersionCommand: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "version")

  @Flag var json = false

  func run() throws {
    let payload = VersionPayload(cliVersion: omdVersion, coreVersion: omdVersion)
    let output: String
    if json {
      output = try OutputRenderer.encode(payload)
    } else {
      output = "omd \(omdVersion)\nOMDCore \(omdVersion)\n"
    }
    emitAndExit(CommandResult(exitCode: .success, stdout: output))
  }
}

private struct VersionPayload: Codable {
  var cliVersion: String
  var coreVersion: String
}
