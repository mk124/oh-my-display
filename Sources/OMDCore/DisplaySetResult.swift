import Foundation

public enum DisplaySetStatus: String, Codable, Sendable {
  case noOp
  case applied
  case blocked
  case readbackMismatch
  case backendUnavailable
  case failed
}

public struct DisplaySetResult: Codable, Equatable, Sendable {
  public var status: DisplaySetStatus
  public var attemptedMutation: Bool
  public var reason: String?

  package var isSuccessful: Bool {
    status == .applied || status == .noOp
  }

  public init(status: DisplaySetStatus, attemptedMutation: Bool, reason: String? = nil) {
    self.status = status
    self.attemptedMutation = attemptedMutation
    self.reason = reason
  }

  public static func noOp(_ reason: String? = nil) -> Self {
    Self(status: .noOp, attemptedMutation: false, reason: reason)
  }

  public static func applied(_ reason: String? = nil) -> Self {
    Self(status: .applied, attemptedMutation: true, reason: reason)
  }

  public static func blocked(_ reason: String? = nil) -> Self {
    Self(status: .blocked, attemptedMutation: false, reason: reason)
  }

  public static func backendUnavailable(_ reason: String? = nil) -> Self {
    Self(status: .backendUnavailable, attemptedMutation: false, reason: reason)
  }

  public static func readbackMismatch(_ reason: String? = nil) -> Self {
    Self(status: .readbackMismatch, attemptedMutation: true, reason: reason)
  }

  public static func failed(attemptedMutation: Bool, reason: String? = nil) -> Self {
    Self(status: .failed, attemptedMutation: attemptedMutation, reason: reason)
  }
}
