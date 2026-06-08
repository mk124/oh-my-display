import Foundation
import OMDCore

extension OMDAppCore {
  func upsertRecord(for target: DisplayTarget, update: (inout DisplayProfileRecord) -> Void) {
    if let index = recordIndex(for: target.selector) {
      document.displays[index].binding = DisplayBinding(target: target)
      update(&document.displays[index])
      return
    }

    var record = DisplayProfileRecord(binding: DisplayBinding(target: target))
    update(&record)
    document.displays.append(record)
  }

  // The heartbeat's pure-memory gate: detection only matters while some display
  // keeps a strong-bound current profile; everything else has nothing to enforce.
  package var hasEnforceableProfile: Bool {
    document.displays.contains { $0.currentProfileID != nil && $0.binding.isStrong }
  }

  func record(for display: DisplaySelector) -> DisplayProfileRecord? { document.displays.first { $0.binding.selector == display } }

  func recordIndex(for display: DisplaySelector) -> Int? { document.displays.firstIndex { $0.binding.selector == display } }

  func currentProfile(in record: DisplayProfileRecord) -> DisplayProfile? {
    guard let currentProfileID = record.currentProfileID else { return nil }
    return record.profiles.first { $0.id == currentProfileID }
  }

  func profile(_ profileID: UUID, for display: DisplaySelector) throws -> DisplayProfile {
    guard let record = record(for: display) else { throw ProfileStoreError.missingDisplay(display.rawValue) }
    guard let profile = record.profiles.first(where: { $0.id == profileID }) else { throw ProfileStoreError.missingProfile(profileID) }
    return profile
  }

  func nextProfileOrdinal(for display: DisplaySelector) -> Int {
    let currentMax = record(for: display)?.profiles.map(\.ordinal).max() ?? 0
    return currentMax + 1
  }

  func saveTransaction(_ update: () throws -> Void) throws {
    let oldDocument = document
    do {
      try update()
      try save()
    } catch {
      document = oldDocument
      throw error
    }
  }

  func save() throws { try store.save(document) }
}
