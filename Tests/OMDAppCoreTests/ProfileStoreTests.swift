import Foundation
import OMDCore
import XCTest

@testable import OMDAppCore

final class ProfileStoreTests: XCTestCase {
  func testCorruptProfileStoreIsQuarantinedAndStartsEmpty() throws {
    let fixture = try AppCoreFixture()
    try FileManager.default.createDirectory(
      at: fixture.documentURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try Data("not-json".utf8).write(to: fixture.documentURL)

    let document = try ProfileStore(documentURL: fixture.documentURL).load()
    let quarantined = try FileManager.default.contentsOfDirectory(
      atPath: fixture.documentURL.deletingLastPathComponent().path)

    XCTAssertTrue(document.displays.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.documentURL.path))
    XCTAssertTrue(quarantined.contains { $0.hasPrefix("profiles.json.corrupt-") })
  }

  func testFailedSaveRollsBackInMemoryDocument() throws {
    let blockedDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    try Data("not-a-directory".utf8).write(to: blockedDirectory)
    defer {
      try? FileManager.default.removeItem(at: blockedDirectory)
    }

    let documentURL = blockedDirectory.appendingPathComponent("profiles.json")
    let fake = FakeDisplayController()
    let display = DisplayTarget(
      selector: DisplaySelector("uuid:one"),
      displayID: 1,
      label: "One",
      isMain: true,
      isBuiltin: false
    )
    fake.displays = [display]
    fake.states[display.selector] = .state(target: display)
    let core = try OMDAppCore(client: fake, documentURL: documentURL)

    XCTAssertThrowsError(try core.addProfile(for: display.selector))

    let menuDisplay = try XCTUnwrap(core.menuState().displays.first)
    XCTAssertEqual(menuDisplay.currentTitle, "Current: Off")
    XCTAssertEqual(menuDisplay.currentItems.map(\.title), ["Off"])
  }
}
