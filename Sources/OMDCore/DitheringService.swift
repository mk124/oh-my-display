import Foundation
import IOKit

struct DitheringService: Sendable {
  var resolver: DisplayResolving
  var backend: DitheringBackend

  init() {
    self.resolver = DisplayResolver()
    self.backend = LiveDitheringBackend()
  }

  init(resolver: DisplayResolving, backend: DitheringBackend = LiveDitheringBackend()) {
    self.resolver = resolver
    self.backend = backend
  }

  func readDithering(_ display: ResolvedDisplay) -> DisplayAxis<Bool> {
    switch framebuffer(for: display) {
    case .selected(let framebuffer):
      guard let enabled = framebuffer.enableDither else { return .unreadable(source: "enableDither unreadable") }
      return .readable(enabled, source: "IOMobileFramebuffer enableDither")
    case .ambiguous: return .unreadable(source: "multiple active framebuffer candidates")
    case .unavailable(let reason): return .unreadable(source: reason.message)
    }
  }

  func availability(_ display: ResolvedDisplay) -> DitheringAvailability {
    switch framebuffer(for: display) {
    case .selected: return .settable
    case .ambiguous: return .ambiguousFramebuffer
    case .unavailable(.noFramebuffers): return .noWritableFramebuffer
    case .unavailable(.noMatchingActiveFramebuffer): return .noMatchingActiveFramebuffer
    }
  }

  func setDithering(_ selector: DisplaySelector, enabled: Bool) throws -> DisplaySetResult {
    let resolved: ResolvedDisplay
    do { resolved = try resolver.resolve(selector) } catch let error as DisplayControlError {
      guard error.isUserResolvableSelectorError else { throw error }
      return .blocked(error.description)
    }

    switch framebuffer(for: resolved) {
    case .selected(let framebuffer):
      if framebuffer.enableDither == enabled { return .noOp("Requested dithering state is already current") }
      guard backend.setDithering(enabled, on: framebuffer.registryID) else {
        return .failed(attemptedMutation: true, reason: "IOMobileFramebuffer rejected enableDither write")
      }
      guard backend.readDithering(on: framebuffer.registryID) == enabled else {
        return .readbackMismatch("enableDither readback did not match requested value")
      }
      return .applied("Dithering setting applied")
    case .ambiguous: return .blocked("Multiple active framebuffer candidates match this display")
    case .unavailable(let reason): return .backendUnavailable(reason.message)
    }
  }

  private func framebuffer(for display: ResolvedDisplay) -> FramebufferSelection {
    let framebuffers = backend.framebuffers()
    guard !framebuffers.isEmpty else { return .unavailable(.noFramebuffers) }

    let expectedExternal = !display.target.isBuiltin
    let activeMatches = framebuffers.filter { framebuffer in framebuffer.isActive && framebuffer.isExternal == expectedExternal }

    guard !activeMatches.isEmpty else { return .unavailable(.noMatchingActiveFramebuffer) }
    guard activeMatches.count == 1, let match = activeMatches.first else { return .ambiguous }
    return .selected(match)
  }
}

struct DitheringFramebuffer: Equatable, Sendable {
  var registryID: UInt64
  var isExternal: Bool?
  var isActive: Bool
  var enableDither: Bool?
}

protocol DitheringBackend: Sendable {
  func framebuffers() -> [DitheringFramebuffer]
  func readDithering(on registryID: UInt64) -> Bool?
  func setDithering(_ enabled: Bool, on registryID: UInt64) -> Bool
}

private enum FramebufferSelection {
  case selected(DitheringFramebuffer)
  case ambiguous
  case unavailable(FramebufferUnavailableReason)
}

private enum FramebufferUnavailableReason {
  case noFramebuffers
  case noMatchingActiveFramebuffer

  var message: String {
    switch self {
    case .noFramebuffers: return "IOMobileFramebuffer nodes unavailable"
    case .noMatchingActiveFramebuffer: return "No active framebuffer candidate matches this display"
    }
  }
}

struct LiveDitheringBackend: DitheringBackend {
  func framebuffers() -> [DitheringFramebuffer] {
    var result: [DitheringFramebuffer] = []
    var seen: Set<UInt64> = []
    for className in ["IOMobileFramebufferShim", "IOMobileFramebufferAP"] {
      for framebuffer in framebuffers(matching: className) where !seen.contains(framebuffer.registryID) {
        seen.insert(framebuffer.registryID)
        result.append(framebuffer)
      }
    }
    return result
  }

  func readDithering(on registryID: UInt64) -> Bool? { framebuffers().first { $0.registryID == registryID }?.enableDither }

  func setDithering(_ enabled: Bool, on registryID: UInt64) -> Bool {
    withFramebufferService(registryID: registryID) { service in
      let value = enabled ? kCFBooleanTrue : kCFBooleanFalse
      return IORegistryEntrySetCFProperty(service, "enableDither" as CFString, value) == KERN_SUCCESS
    } ?? false
  }

  private func framebuffers(matching className: String) -> [DitheringFramebuffer] {
    guard let matching = IOServiceMatching(className) else { return [] }

    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
    defer { IOObjectRelease(iterator) }

    var result: [DitheringFramebuffer] = []
    var service = IOIteratorNext(iterator)
    while service != 0 {
      if let framebuffer = framebuffer(from: service) { result.append(framebuffer) }
      IOObjectRelease(service)
      service = IOIteratorNext(iterator)
    }
    return result
  }

  private func framebuffer(from service: io_service_t) -> DitheringFramebuffer? {
    var registryID: UInt64 = 0
    guard IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS else { return nil }

    return DitheringFramebuffer(
      registryID: registryID, isExternal: boolProperty(property("external", from: service)),
      isActive: boolProperty(property("NormalModeActive", from: service)) ?? false, enableDither: boolProperty(property("enableDither", from: service)))
  }

  private func property(_ key: String, from service: io_service_t) -> Any? {
    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
  }

  private func withFramebufferService<T>(registryID: UInt64, _ body: (io_service_t) -> T) -> T? {
    for className in ["IOMobileFramebufferShim", "IOMobileFramebufferAP"] {
      guard let matching = IOServiceMatching(className) else { continue }

      var iterator: io_iterator_t = 0
      guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { continue }
      defer { IOObjectRelease(iterator) }

      var service = IOIteratorNext(iterator)
      while service != 0 {
        var currentID: UInt64 = 0
        if IORegistryEntryGetRegistryEntryID(service, &currentID) == KERN_SUCCESS, currentID == registryID {
          let result = body(service)
          IOObjectRelease(service)
          return result
        }
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
      }
    }
    return nil
  }

  private func boolProperty(_ value: Any?) -> Bool? {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    return nil
  }
}
