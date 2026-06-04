import ApplicationServices
import CoreGraphics
import Foundation

struct ResolvedDisplay: Sendable {
  var target: DisplayTarget
  var displayID: CGDirectDisplayID
}

struct DisplayResolver: Sendable {
  func listTargets() throws -> [DisplayTarget] {
    var count: UInt32 = 0
    var err = CGGetOnlineDisplayList(0, nil, &count)
    guard err == .success else {
      throw DisplayControlError.unexpected("CGGetOnlineDisplayList count failed: \(err.rawValue)")
    }

    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    err = CGGetOnlineDisplayList(count, &ids, &count)
    guard err == .success else {
      throw DisplayControlError.unexpected("CGGetOnlineDisplayList failed: \(err.rawValue)")
    }

    return ids.prefix(Int(count)).map { id in
      let selector = Self.selector(for: id)
      let label = Self.label(for: id)
      return DisplayTarget(
        selector: selector,
        displayID: UInt32(id),
        label: label,
        isMain: CGDisplayIsMain(id) != 0,
        isBuiltin: CGDisplayIsBuiltin(id) != 0
      )
    }
  }

  func resolve(_ selector: DisplaySelector) throws -> ResolvedDisplay {
    let targets = try listTargets()
    let matches = targets.filter { $0.selector == selector }

    if matches.count == 1, let target = matches.first {
      return ResolvedDisplay(target: target, displayID: CGDirectDisplayID(target.displayID))
    }

    if matches.count > 1 {
      throw DisplayControlError.ambiguousDisplay(selector.rawValue)
    }

    if selector.rawValue.hasPrefix("cg:"),
      let id = UInt32(selector.rawValue.dropFirst(3)),
      let target = targets.first(where: { $0.displayID == id })
    {
      return ResolvedDisplay(target: target, displayID: CGDirectDisplayID(id))
    }

    throw DisplayControlError.displayNotFound(selector.rawValue)
  }

  static func selector(for displayID: CGDirectDisplayID) -> DisplaySelector {
    if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
      let uuidString = CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
      return DisplaySelector("uuid:\(uuidString)")
    }
    return DisplaySelector("cg:\(displayID)")
  }

  static func label(for displayID: CGDirectDisplayID) -> String {
    if let name = displayNameFromIOKit(displayID: displayID), !name.isEmpty {
      return name
    }
    return "Display \(displayID)"
  }

  private static func displayNameFromIOKit(displayID: CGDirectDisplayID) -> String? {
    let vendor = CGDisplayVendorNumber(displayID)
    let model = CGDisplayModelNumber(displayID)
    if vendor != 0 || model != 0 {
      return "Display \(String(format: "%04X", vendor)):\(String(format: "%04X", model))"
    }
    return nil
  }
}
