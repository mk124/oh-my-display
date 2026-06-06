import Foundation
import OMDCore

package final class OMDAppCore {
  package static var defaultDocumentURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OhMyDisplay", isDirectory: true)
      .appendingPathComponent("profiles.json")
  }

  let client: any DisplayClient
  let store: ProfileStore
  var document: ProfileDocument
  // Correction attempts per display since the last confirmed match (see reconcile).
  // Runtime-only; same MainActor-confined posture as the mutable `document`.
  var enforcementAttempts: [DisplaySelector: Int] = [:]

  package init(client: any DisplayClient = LiveDisplayClient(), documentURL: URL = OMDAppCore.defaultDocumentURL) throws {
    self.client = client
    self.store = ProfileStore(documentURL: documentURL)
    self.document = try store.load()
  }
}
