import Foundation

/// Public error contract for OMDCore throwing APIs.
public enum DisplayControlError: Error, Equatable, Sendable, CustomStringConvertible {
  case displayNotFound(String)
  case ambiguousDisplay(String)
  case invalidSelector(String)
  case unexpected(String)

  public var description: String {
    switch self {
    case .displayNotFound(let selector): return "Display not found: \(selector)"
    case .ambiguousDisplay(let selector): return "Display selector is ambiguous: \(selector)"
    case .invalidSelector(let selector): return "Invalid display selector: \(selector)"
    case .unexpected(let message): return message
    }
  }

  var isUserResolvableSelectorError: Bool {
    switch self {
    case .displayNotFound, .ambiguousDisplay, .invalidSelector: return true
    case .unexpected: return false
    }
  }
}
