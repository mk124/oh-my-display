import CoreGraphics
import XCTest

@testable import OMDCore

final class DitheringServiceTests: XCTestCase {
  func testReadDitheringReturnsActiveExternalFramebufferState() {
    let backend = FakeDitheringBackend(framebuffers: [framebuffer(id: 1, external: true, active: true, enabled: false)])
    let service = DitheringService(resolver: FakeDisplayResolver(isBuiltin: false), backend: backend)

    let axis = service.readDithering(FakeDisplayResolver.resolvedDisplay(isBuiltin: false))

    XCTAssertEqual(axis.readability, .readable)
    XCTAssertEqual(axis.value, false)
  }

  func testSetDitheringNoOpDoesNotWrite() throws {
    let backend = FakeDitheringBackend(framebuffers: [framebuffer(id: 1, external: true, active: true, enabled: false)])
    let service = DitheringService(resolver: FakeDisplayResolver(isBuiltin: false), backend: backend)

    let result = try service.setDithering(DisplaySelector("uuid:one"), enabled: false)

    XCTAssertEqual(result.status, .noOp)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetDitheringWritesAndVerifiesReadback() throws {
    let backend = FakeDitheringBackend(framebuffers: [framebuffer(id: 1, external: true, active: true, enabled: false)])
    let service = DitheringService(resolver: FakeDisplayResolver(isBuiltin: false), backend: backend)

    let result = try service.setDithering(DisplaySelector("uuid:one"), enabled: true)

    XCTAssertEqual(result.status, .applied)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [SetCall(registryID: 1, enabled: true)])
    XCTAssertEqual(backend.readDithering(on: 1), true)
  }

  func testSetDitheringUsesBuiltinDisplayInternalFramebuffer() throws {
    let backend = FakeDitheringBackend(framebuffers: [
      framebuffer(id: 1, external: true, active: true, enabled: true), framebuffer(id: 2, external: false, active: true, enabled: true),
    ])
    let service = DitheringService(resolver: FakeDisplayResolver(isBuiltin: true), backend: backend)

    let result = try service.setDithering(DisplaySelector("uuid:one"), enabled: false)

    XCTAssertEqual(result.status, .applied)
    XCTAssertEqual(backend.setCalls, [SetCall(registryID: 2, enabled: false)])
  }

  func testSetDitheringBlocksAmbiguousActiveFramebufferCandidates() throws {
    let backend = FakeDitheringBackend(framebuffers: [
      framebuffer(id: 1, external: true, active: true, enabled: true), framebuffer(id: 2, external: true, active: true, enabled: true),
    ])
    let service = DitheringService(resolver: FakeDisplayResolver(isBuiltin: false), backend: backend)

    let result = try service.setDithering(DisplaySelector("uuid:one"), enabled: false)

    XCTAssertEqual(result.status, .blocked)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testSetDitheringReturnsBackendUnavailableWhenNoCandidateMatches() throws {
    let backend = FakeDitheringBackend(framebuffers: [framebuffer(id: 1, external: false, active: true, enabled: true)])
    let service = DitheringService(resolver: FakeDisplayResolver(isBuiltin: false), backend: backend)

    let result = try service.setDithering(DisplaySelector("uuid:one"), enabled: false)

    XCTAssertEqual(result.status, .backendUnavailable)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [])
  }

  func testAvailabilityDistinguishesUnreadableValueFromUnavailableFramebuffer() {
    let unreadableBackend = FakeDitheringBackend(framebuffers: [framebuffer(id: 1, external: true, active: true, enabled: nil)])
    let unavailableBackend = FakeDitheringBackend(framebuffers: [framebuffer(id: 1, external: false, active: true, enabled: true)])
    let ambiguousBackend = FakeDitheringBackend(framebuffers: [
      framebuffer(id: 1, external: true, active: true, enabled: true), framebuffer(id: 2, external: true, active: true, enabled: true),
    ])

    XCTAssertEqual(
      DitheringService(resolver: FakeDisplayResolver(isBuiltin: false), backend: unreadableBackend).availability(
        FakeDisplayResolver.resolvedDisplay(isBuiltin: false)), .settable)
    XCTAssertEqual(
      DitheringService(resolver: FakeDisplayResolver(isBuiltin: false), backend: unavailableBackend).availability(
        FakeDisplayResolver.resolvedDisplay(isBuiltin: false)), .noMatchingActiveFramebuffer)
    XCTAssertEqual(
      DitheringService(resolver: FakeDisplayResolver(isBuiltin: false), backend: ambiguousBackend).availability(
        FakeDisplayResolver.resolvedDisplay(isBuiltin: false)), .ambiguousFramebuffer)
  }

  func testSetDitheringReportsFailedWriteAsAttemptedFailure() throws {
    let backend = FakeDitheringBackend(framebuffers: [framebuffer(id: 1, external: true, active: true, enabled: true)], setResult: false)
    let service = DitheringService(resolver: FakeDisplayResolver(isBuiltin: false), backend: backend)

    let result = try service.setDithering(DisplaySelector("uuid:one"), enabled: false)

    XCTAssertEqual(result.status, .failed)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [SetCall(registryID: 1, enabled: false)])
  }

  func testSetDitheringReportsReadbackMismatch() throws {
    let backend = FakeDitheringBackend(framebuffers: [framebuffer(id: 1, external: true, active: true, enabled: true)], updateReadbackOnSet: false)
    let service = DitheringService(resolver: FakeDisplayResolver(isBuiltin: false), backend: backend)

    let result = try service.setDithering(DisplaySelector("uuid:one"), enabled: false)

    XCTAssertEqual(result.status, .readbackMismatch)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(backend.setCalls, [SetCall(registryID: 1, enabled: false)])
  }

  private static func framebuffer(id: UInt64, external: Bool, active: Bool, enabled: Bool?) -> DitheringFramebuffer {
    DitheringFramebuffer(registryID: id, isExternal: external, isActive: active, enableDither: enabled)
  }

  private func framebuffer(id: UInt64, external: Bool, active: Bool, enabled: Bool?) -> DitheringFramebuffer {
    Self.framebuffer(id: id, external: external, active: active, enabled: enabled)
  }
}

private struct FakeDisplayResolver: DisplayResolving {
  var isBuiltin: Bool

  static func resolvedDisplay(isBuiltin: Bool) -> ResolvedDisplay {
    ResolvedDisplay(target: DisplayTarget(selector: DisplaySelector("uuid:one"), displayID: 1, label: "One", isMain: true, isBuiltin: isBuiltin), displayID: 1)
  }

  func resolve(_ selector: DisplaySelector) throws -> ResolvedDisplay { Self.resolvedDisplay(isBuiltin: isBuiltin) }
}

struct SetCall: Equatable {
  var registryID: UInt64
  var enabled: Bool
}

private final class FakeDitheringBackend: DitheringBackend, @unchecked Sendable {
  var storedFramebuffers: [DitheringFramebuffer]
  var setResult: Bool
  var updateReadbackOnSet: Bool
  var setCalls: [SetCall] = []

  init(framebuffers: [DitheringFramebuffer], setResult: Bool = true, updateReadbackOnSet: Bool = true) {
    self.storedFramebuffers = framebuffers
    self.setResult = setResult
    self.updateReadbackOnSet = updateReadbackOnSet
  }

  func framebuffers() -> [DitheringFramebuffer] { storedFramebuffers }

  func readDithering(on registryID: UInt64) -> Bool? { storedFramebuffers.first { $0.registryID == registryID }?.enableDither }

  func setDithering(_ enabled: Bool, on registryID: UInt64) -> Bool {
    setCalls.append(SetCall(registryID: registryID, enabled: enabled))
    if setResult, updateReadbackOnSet, let index = storedFramebuffers.firstIndex(where: { $0.registryID == registryID }) {
      storedFramebuffers[index].enableDither = enabled
    }
    return setResult
  }
}
