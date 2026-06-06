import Foundation

package struct DisplayEventCoalescer: Sendable {
  private var pending: DisplayEventTrigger?

  package init() {}

  package mutating func record(_ trigger: DisplayEventTrigger) {
    pending = trigger
  }

  package mutating func takePending() -> DisplayEventTrigger? {
    defer { pending = nil }
    return pending
  }
}
