@preconcurrency import ColorSync
import CoreGraphics
import XCTest

@testable import OMDCore

final class ICCProfileServiceTests: XCTestCase {
  func testSetICCProfileBlocksUnreadableFileBeforeMutation() throws {
    let backend = FakeICCProfileBackend(isReadable: false)
    let service = ICCProfileService(resolver: FakeResolver(), backend: backend)

    let result = try service.setICCProfile(
      DisplaySelector("uuid:one"), profileURL: profile("target.icc"))

    XCTAssertEqual(result.status, .blocked)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setProfileURLs, [])
  }

  func testSetICCProfileReturnsBackendUnavailableWhenDeviceIDIsMissing() throws {
    let backend = FakeICCProfileBackend(deviceID: nil)
    let service = ICCProfileService(resolver: FakeResolver(), backend: backend)

    let result = try service.setICCProfile(
      DisplaySelector("uuid:one"), profileURL: profile("target.icc"))

    XCTAssertEqual(result.status, .backendUnavailable)
    XCTAssertFalse(result.attemptedMutation)
    XCTAssertEqual(backend.setProfileURLs, [])
  }

  func testSetICCProfileReportsColorSyncRejectAsAttemptedFailure() throws {
    let backend = FakeICCProfileBackend(setResult: false)
    let service = ICCProfileService(resolver: FakeResolver(), backend: backend)

    let result = try service.setICCProfile(
      DisplaySelector("uuid:one"), profileURL: profile("target.icc"))

    XCTAssertEqual(result.status, .failed)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(backend.setProfileURLs, [profile("target.icc")])
  }

  func testSetICCProfileReturnsAppliedWhenReadbackMatches() throws {
    let target = profile("target.icc")
    let backend = FakeICCProfileBackend(readbacks: [
      ICCProfileReadback(url: target, source: "fake readback")
    ])
    let service = ICCProfileService(resolver: FakeResolver(), backend: backend)

    let result = try service.setICCProfile(DisplaySelector("uuid:one"), profileURL: target)

    XCTAssertEqual(result.status, .applied)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(backend.setProfileURLs, [target])
    XCTAssertEqual(backend.waitCount, 0)
  }

  func testSetICCProfileReturnsAppliedWhenDelayedReadbackMatches() throws {
    let target = profile("target.icc")
    let backend = FakeICCProfileBackend(readbacks: [
      nil,
      ICCProfileReadback(url: profile("other.icc"), source: "fake readback"),
      ICCProfileReadback(url: target, source: "fake readback"),
    ])
    let service = ICCProfileService(resolver: FakeResolver(), backend: backend)

    let result = try service.setICCProfile(DisplaySelector("uuid:one"), profileURL: target)

    XCTAssertEqual(result.status, .applied)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(backend.setProfileURLs, [target])
    XCTAssertEqual(backend.waitCount, 2)
  }

  func testSetICCProfileReturnsReadbackMismatchWhenReadbackNeverMatches() throws {
    let backend = FakeICCProfileBackend(
      readbacks: Array(
        repeating: ICCProfileReadback(url: profile("other.icc"), source: "fake readback"), count: 10
      ))
    let service = ICCProfileService(resolver: FakeResolver(), backend: backend)

    let result = try service.setICCProfile(
      DisplaySelector("uuid:one"), profileURL: profile("target.icc"))

    XCTAssertEqual(result.status, .readbackMismatch)
    XCTAssertTrue(result.attemptedMutation)
    XCTAssertEqual(backend.setProfileURLs, [profile("target.icc")])
    XCTAssertEqual(backend.waitCount, 9)
  }

  func testReadICCProfileReturnsReadableProfileFromBackend() {
    let target = profile("current.icc")
    let backend = FakeICCProfileBackend(readbacks: [
      ICCProfileReadback(url: target, source: "fake readback")
    ])
    let service = ICCProfileService(resolver: FakeResolver(), backend: backend)

    let axis = service.readICCProfile(FakeResolver.resolvedDisplay)

    XCTAssertEqual(axis.readability, .readable)
    XCTAssertEqual(axis.value, target)
    XCTAssertEqual(axis.source, "fake readback")
  }

  func testDeviceInfoParserPrefersCustomDefaultProfileDirectURL() {
    let target = profile("custom.icc")
    let info: [String: Any] = [
      customProfilesKey: [
        defaultProfileKey: target
      ],
      factoryProfilesKey: [
        defaultProfileKey: "Factory",
        "Factory": [
          profileURLKey: profile("factory.icc")
        ],
      ],
    ]

    let readback = LiveICCProfileBackend.profileReadback(from: info)

    XCTAssertEqual(readback?.url, target)
    XCTAssertEqual(readback?.source, "ColorSync custom profile")
  }

  func testDeviceInfoParserUsesCustomURLForFactoryDefaultProfileID() {
    let target = profile("custom.icc")
    let info: [String: Any] = [
      customProfilesKey: [
        "Factory": target
      ],
      factoryProfilesKey: [
        defaultProfileKey: "Factory",
        "Factory": [
          profileURLKey: profile("factory.icc")
        ],
      ],
    ]

    let readback = LiveICCProfileBackend.profileReadback(from: info)

    XCTAssertEqual(readback?.url, target)
    XCTAssertEqual(readback?.source, "ColorSync custom profile")
  }

  func testDeviceInfoParserFallsBackToFactoryProfileDictionary() {
    let target = profile("factory.icc")
    let info: [String: Any] = [
      factoryProfilesKey: [
        defaultProfileKey: "Factory",
        "Factory": [
          profileURLKey: target
        ],
      ]
    ]

    let readback = LiveICCProfileBackend.profileReadback(from: info)

    XCTAssertEqual(readback?.url, target)
    XCTAssertEqual(readback?.source, "ColorSync factory profile")
  }

  func testDeviceInfoParserIgnoresUnsetCustomProfile() {
    let factory = profile("factory.icc")
    let info: [String: Any] = [
      customProfilesKey: [
        defaultProfileKey: kCFNull as Any
      ],
      factoryProfilesKey: [
        defaultProfileKey: "Factory",
        "Factory": [
          profileURLKey: factory
        ],
      ],
    ]

    let readback = LiveICCProfileBackend.profileReadback(from: info)

    XCTAssertEqual(readback?.url, factory)
    XCTAssertEqual(readback?.source, "ColorSync factory profile")
  }

  func testDeviceInfoParserDoesNotUseNonDefaultCustomProfileWhenFactoryDefaultIsKnown() {
    let factoryDefault = profile("factory-default.icc")
    let info: [String: Any] = [
      customProfilesKey: [
        "Other": profile("other-custom.icc")
      ],
      factoryProfilesKey: [
        defaultProfileKey: "Default",
        "Default": [
          profileURLKey: factoryDefault
        ],
        "Other": [
          profileURLKey: profile("other-factory.icc")
        ],
      ],
    ]

    let readback = LiveICCProfileBackend.profileReadback(from: info)

    XCTAssertEqual(readback?.url, factoryDefault)
    XCTAssertEqual(readback?.source, "ColorSync factory profile")
  }

  private func profile(_ name: String) -> URL {
    URL(fileURLWithPath: "/tmp/\(name)")
  }

  private var customProfilesKey: String {
    kColorSyncCustomProfiles.takeUnretainedValue() as String
  }

  private var factoryProfilesKey: String {
    kColorSyncFactoryProfiles.takeUnretainedValue() as String
  }

  private var defaultProfileKey: String {
    kColorSyncDeviceDefaultProfileID.takeUnretainedValue() as String
  }

  private var profileURLKey: String {
    kColorSyncDeviceProfileURL.takeUnretainedValue() as String
  }
}

private struct FakeResolver: DisplayResolving {
  static let resolvedDisplay = ResolvedDisplay(
    target: DisplayTarget(
      selector: DisplaySelector("uuid:one"),
      displayID: 1,
      label: "One",
      isMain: true,
      isBuiltin: false
    ),
    displayID: 1
  )

  func resolve(_ selector: DisplaySelector) throws -> ResolvedDisplay {
    Self.resolvedDisplay
  }
}

final class FakeICCProfileBackend: ICCProfileBackend, @unchecked Sendable {
  var isReadable: Bool
  var fakeDeviceID: ICCDisplayDeviceID?
  var setResult: Bool
  var readbacks: [ICCProfileReadback?]
  var setProfileURLs: [URL] = []
  var waitCount = 0

  init(
    isReadable: Bool = true,
    deviceID: ICCDisplayDeviceID? = ICCDisplayDeviceID(rawValue: CFUUIDCreate(kCFAllocatorDefault)),
    setResult: Bool = true,
    readbacks: [ICCProfileReadback?] = []
  ) {
    self.isReadable = isReadable
    self.fakeDeviceID = deviceID
    self.setResult = setResult
    self.readbacks = readbacks
  }

  func isReadableProfile(_ url: URL) -> Bool {
    isReadable
  }

  func deviceID(for displayID: CGDirectDisplayID) -> ICCDisplayDeviceID? {
    fakeDeviceID
  }

  func profile(for deviceID: ICCDisplayDeviceID) -> ICCProfileReadback? {
    if !readbacks.isEmpty {
      return readbacks.removeFirst() ?? nil
    }
    return nil
  }

  func setCustomProfile(_ profileURL: URL, for deviceID: ICCDisplayDeviceID) -> Bool {
    setProfileURLs.append(profileURL)
    return setResult
  }

  func waitBeforeReadback() {
    waitCount += 1
  }
}
