import Foundation
import OMDCore

enum Resolved<Value> {
  case resolved(Value)
  case blocked(String)

  func flatMap(_ operation: (Value) throws -> DisplaySetResult) rethrows -> DisplaySetResult {
    switch self {
    case .resolved(let value): return try operation(value)
    case .blocked(let reason): return .blocked(reason)
    }
  }
}

func readableValue<Value>(_ axis: DisplayAxis<Value>) -> Value? { axis.readability == .readable ? axis.value : nil }

func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 0.01 }

func optionalApproxEqual(_ lhs: Double?, _ rhs: Double?) -> Bool {
  guard let lhs, let rhs else { return true }
  return approximatelyEqual(lhs, rhs)
}

func optionalEqual<Value: Equatable>(_ lhs: Value?, _ rhs: Value?) -> Bool {
  guard let rhs else { return true }
  return lhs == rhs
}
