import Foundation
import OMDCore

struct OMDCLIContext: Sendable {
  var core: any DisplayClient
  var isTTY: Bool
  var prompt: (@Sendable (String) -> Bool)?

  init(core: any DisplayClient = LiveDisplayClient(), isTTY: Bool = true, prompt: (@Sendable (String) -> Bool)? = nil) {
    self.core = core
    self.isTTY = isTTY
    self.prompt = prompt
  }
}
