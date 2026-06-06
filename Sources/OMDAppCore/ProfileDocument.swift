import Foundation
import OMDCore

struct ProfileDocument: Codable, Equatable, Sendable {
  var schemaVersion: Int
  var displays: [DisplayProfileRecord]

  init(schemaVersion: Int = 1, displays: [DisplayProfileRecord] = []) {
    self.schemaVersion = schemaVersion
    self.displays = displays
  }
}

struct DisplayProfileRecord: Codable, Equatable, Sendable {
  var binding: DisplayBinding
  var currentProfileID: UUID?
  var profiles: [DisplayProfile]
  var lastResult: ProfileLastResult?

  init(
    binding: DisplayBinding,
    currentProfileID: UUID? = nil,
    profiles: [DisplayProfile] = [],
    lastResult: ProfileLastResult? = nil
  ) {
    self.binding = binding
    self.currentProfileID = currentProfileID
    self.profiles = profiles
    self.lastResult = lastResult
  }
}

struct DisplayBinding: Codable, Equatable, Sendable {
  var selector: DisplaySelector

  init(target: DisplayTarget) {
    self.selector = target.selector
  }

  var isStrong: Bool {
    selector.isStableIdentity
  }
}

struct ProfileLastResult: Codable, Equatable, Sendable {
  var summary: String

  init(summary: String) {
    self.summary = summary
  }
}

package enum ProfileOperationKind: String, Codable, Equatable, Sendable {
  case resolution
  case displayMode
  case dithering
  case icc
  case profile
  case restore
}

package enum ReconcileSkipReason: String, Codable, Equatable, Sendable {
  case off
  case weakBinding
  case missingCurrentProfile
  case failed
}

package struct DisplayProfile: Codable, Equatable, Identifiable, Sendable {
  package var id: UUID
  package var ordinal: Int
  package var customName: String?
  package var intent: DisplayProfileIntent
  package var isVerified: Bool
  package var createdAt: Date

  package init(
    id: UUID = UUID(),
    ordinal: Int,
    customName: String? = nil,
    intent: DisplayProfileIntent,
    isVerified: Bool = false,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.ordinal = ordinal
    self.customName = customName
    self.intent = intent
    self.isVerified = isVerified
    self.createdAt = createdAt
  }

  enum CodingKeys: String, CodingKey {
    case id
    case ordinal
    case customName
    case intent
    case isVerified
    case createdAt
  }

  package init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    ordinal = try container.decode(Int.self, forKey: .ordinal)
    customName = try container.decodeIfPresent(String.self, forKey: .customName)
    intent = try container.decode(DisplayProfileIntent.self, forKey: .intent)
    isVerified = try container.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
    createdAt = try container.decode(Date.self, forKey: .createdAt)
  }

  package var label: String {
    "#\(ordinal) \(trimmedCustomName ?? intent.technicalSummary)"
  }

  package var technicalLabel: String {
    "#\(ordinal) \(intent.technicalSummary)"
  }

  package var shortLabel: String {
    trimmedCustomName.map { "#\(ordinal) \($0)" } ?? "#\(ordinal)"
  }

  private var trimmedCustomName: String? {
    guard let customName else {
      return nil
    }
    let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
