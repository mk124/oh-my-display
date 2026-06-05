import OMDCore

struct ICCCommands: Sendable {
  var context: OMDCLIContext

  init(context: OMDCLIContext = OMDCLIContext()) {
    self.context = context
  }

  func list(json: Bool) -> CommandResult {
    do {
      return try CommandResult(
        exitCode: .success,
        stdout: OutputRenderer.renderICCProfiles(context.core.listICCProfiles(), json: json))
    } catch let error as DisplayControlError {
      return .displayControlError(error)
    } catch {
      return .unexpected(error)
    }
  }
}
