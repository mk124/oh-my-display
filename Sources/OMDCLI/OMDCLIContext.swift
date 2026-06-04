import Foundation

struct OMDCLIContext: Sendable {
  var core: OMDCoreClient
  var isTTY: Bool
  var prompt: (@Sendable (String) -> Bool)?

  init(
    core: OMDCoreClient = LiveOMDCoreClient(),
    isTTY: Bool = true,
    prompt: (@Sendable (String) -> Bool)? = nil
  ) {
    self.core = core
    self.isTTY = isTTY
    self.prompt = prompt
  }
}
