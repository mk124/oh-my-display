import Foundation

enum ProfileStoreError: Error, Equatable {
  case unsupportedSchemaVersion(Int)
  case emptyProfileName
  case duplicateProfileName(String)
  case missingDisplay(String)
  case missingCurrentProfile
  case missingProfile(UUID)
}

struct ProfileStore {
  var documentURL: URL

  init(documentURL: URL) { self.documentURL = documentURL }

  func load() throws -> ProfileDocument {
    guard FileManager.default.fileExists(atPath: documentURL.path) else { return ProfileDocument() }

    let data = try Data(contentsOf: documentURL)
    let document: ProfileDocument
    do { document = try JSONDecoder().decode(ProfileDocument.self, from: data) } catch {
      try quarantineCorruptDocument()
      return ProfileDocument()
    }
    guard document.schemaVersion == 1 else { throw ProfileStoreError.unsupportedSchemaVersion(document.schemaVersion) }
    return document
  }

  func save(_ document: ProfileDocument) throws {
    try FileManager.default.createDirectory(at: documentURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(document)
    try data.write(to: documentURL, options: [.atomic])
  }

  private func quarantineCorruptDocument() throws {
    let quarantineURL = documentURL.deletingLastPathComponent().appendingPathComponent(
      "\(documentURL.lastPathComponent).corrupt-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)")
    try FileManager.default.moveItem(at: documentURL, to: quarantineURL)
  }
}
