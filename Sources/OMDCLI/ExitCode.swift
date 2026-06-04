import Foundation

enum OMDExitCode: Int32, Sendable {
  case success = 0
  case blocked = 2
  case partialFailure = 3
  case usage = 64
  case unexpected = 70
}

struct CommandResult: Equatable, Sendable {
  var exitCode: OMDExitCode
  var stdout: String
  var stderr: String

  init(exitCode: OMDExitCode, stdout: String = "", stderr: String = "") {
    self.exitCode = exitCode
    self.stdout = stdout
    self.stderr = stderr
  }
}
