import Foundation
import OMDCore

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

extension CommandResult {
  static func unexpected(_ error: Error) -> CommandResult {
    CommandResult(exitCode: .unexpected, stderr: String(describing: error) + "\n")
  }

  static func displayControlError(_ error: DisplayControlError) -> CommandResult {
    switch error {
    case .displayNotFound, .ambiguousDisplay, .invalidSelector:
      CommandResult(exitCode: .usage, stderr: error.description + "\n")
    case .unexpected:
      .unexpected(error)
    }
  }
}
