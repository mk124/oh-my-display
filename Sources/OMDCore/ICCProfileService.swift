import ApplicationServices
@preconcurrency import ColorSync
import CoreGraphics
import Foundation

struct ICCProfileService: Sendable {
  var resolver: DisplayResolving
  var backend: ICCProfileBackend

  init() {
    self.resolver = DisplayResolver()
    self.backend = LiveICCProfileBackend()
  }

  init(resolver: DisplayResolving = DisplayResolver(), backend: ICCProfileBackend) {
    self.resolver = resolver
    self.backend = backend
  }

  func readICCProfile(_ display: ResolvedDisplay) -> DisplayAxis<URL> {
    guard let deviceID = backend.deviceID(for: display.displayID) else {
      return .unreadable(source: "ColorSync display UUID unavailable")
    }

    if let profile = backend.profile(for: deviceID) {
      return .readable(profile.url, source: profile.source)
    }

    return .unreadable(source: "ColorSync profile URL unavailable")
  }

  func setICCProfile(_ selector: DisplaySelector, profileURL: URL) throws -> DisplaySetResult
  {
    let resolved: ResolvedDisplay
    do {
      resolved = try resolver.resolve(selector)
    } catch let error as DisplayControlError {
      guard error.isUserResolvableSelectorError else {
        throw error
      }
      return .blocked(error.description)
    }
    guard backend.isReadableProfile(profileURL) else {
      return .blocked("ICC profile file is not readable")
    }
    guard let deviceID = backend.deviceID(for: resolved.displayID) else {
      return .backendUnavailable("ColorSync display UUID unavailable")
    }

    guard backend.setCustomProfile(profileURL, for: deviceID) else {
      return .failed(attemptedMutation: true, reason: "ColorSync rejected the profile")
    }

    for attempt in 0..<10 {
      if backend.profile(for: deviceID)?.url.standardizedFileURL == profileURL.standardizedFileURL {
        return .applied("ICC profile applied")
      }
      if attempt < 9 {
        backend.waitBeforeReadback()
      }
    }

    return .readbackMismatch("ICC profile readback did not match requested file")
  }
}

struct ICCDisplayDeviceID: @unchecked Sendable {
  var rawValue: CFUUID
}

struct ICCProfileReadback: Sendable {
  var url: URL
  var source: String
}

protocol ICCProfileBackend: Sendable {
  func isReadableProfile(_ url: URL) -> Bool
  func deviceID(for displayID: CGDirectDisplayID) -> ICCDisplayDeviceID?
  func profile(for deviceID: ICCDisplayDeviceID) -> ICCProfileReadback?
  func setCustomProfile(_ profileURL: URL, for deviceID: ICCDisplayDeviceID) -> Bool
  func waitBeforeReadback()
}

struct LiveICCProfileBackend: ICCProfileBackend {
  func isReadableProfile(_ url: URL) -> Bool {
    FileManager.default.isReadableFile(atPath: url.path)
  }

  func deviceID(for displayID: CGDirectDisplayID) -> ICCDisplayDeviceID? {
    guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
      return nil
    }
    return ICCDisplayDeviceID(rawValue: uuid)
  }

  func profile(for deviceID: ICCDisplayDeviceID) -> ICCProfileReadback? {
    guard
      let info = ColorSyncDeviceCopyDeviceInfo(
        kColorSyncDisplayDeviceClass.takeUnretainedValue(),
        deviceID.rawValue
      )?.takeRetainedValue() as? [String: Any]
    else {
      return nil
    }

    return Self.profileReadback(from: info)
  }

  func setCustomProfile(_ profileURL: URL, for deviceID: ICCDisplayDeviceID) -> Bool {
    let defaultID = kColorSyncDeviceDefaultProfileID.takeUnretainedValue()
    let profiles = [defaultID: profileURL as CFURL] as CFDictionary
    return ColorSyncDeviceSetCustomProfiles(
      kColorSyncDisplayDeviceClass.takeUnretainedValue(),
      deviceID.rawValue,
      profiles
    )
  }

  func waitBeforeReadback() {
    Thread.sleep(forTimeInterval: 0.1)
  }

  static func profileReadback(from info: [String: Any]) -> ICCProfileReadback? {
    if let url = customProfileURL(from: info) {
      return ICCProfileReadback(url: url, source: "ColorSync custom profile")
    }
    if let url = factoryProfileURL(from: info) {
      return ICCProfileReadback(url: url, source: "ColorSync factory profile")
    }
    return nil
  }

  static func customProfileURL(from info: [String: Any]) -> URL? {
    let customProfilesKey = kColorSyncCustomProfiles.takeUnretainedValue() as String
    guard let section = info[customProfilesKey] as? [String: Any] else {
      return nil
    }

    let defaultKey = kColorSyncDeviceDefaultProfileID.takeUnretainedValue() as String
    if let url = profileURLValue(section[defaultKey]) {
      return url
    }

    if let factoryDefaultID = factoryDefaultProfileID(from: info) {
      return profileURLValue(section[factoryDefaultID])
    }

    let urls = section.compactMap { key, value in
      key == defaultKey ? nil : profileURLValue(value)
    }
    return urls.count == 1 ? urls[0] : nil
  }

  static func factoryProfileURL(from info: [String: Any]) -> URL? {
    let factoryProfilesKey = kColorSyncFactoryProfiles.takeUnretainedValue() as String
    guard let section = info[factoryProfilesKey] as? [String: Any] else {
      return nil
    }

    guard let defaultProfileID = factoryDefaultProfileID(from: info, factoryProfiles: section),
      let profileInfo = section[defaultProfileID] as? [String: Any]
    else {
      return nil
    }

    let profileURLKey = kColorSyncDeviceProfileURL.takeUnretainedValue() as String
    return profileURLValue(profileInfo[profileURLKey])
      ?? profileURLValue(profileInfo["DeviceProfileURL"])
  }

  private static func factoryDefaultProfileID(from info: [String: Any]) -> String? {
    let factoryProfilesKey = kColorSyncFactoryProfiles.takeUnretainedValue() as String
    guard let factoryProfiles = info[factoryProfilesKey] as? [String: Any] else {
      return nil
    }
    return factoryDefaultProfileID(from: info, factoryProfiles: factoryProfiles)
  }

  private static func factoryDefaultProfileID(
    from info: [String: Any], factoryProfiles: [String: Any]
  ) -> String? {
    let defaultKey = kColorSyncDeviceDefaultProfileID.takeUnretainedValue() as String
    if let defaultProfileID = factoryProfiles[defaultKey] as? String {
      return defaultProfileID
    }
    let profileIDs = factoryProfiles.keys.filter { $0 != defaultKey }
    return profileIDs.count == 1 ? profileIDs[0] : nil
  }

  private static func profileURLValue(_ value: Any?) -> URL? {
    if value == nil || value is NSNull {
      return nil
    }
    if CFGetTypeID(value as CFTypeRef) == CFNullGetTypeID() {
      return nil
    }
    if let url = value as? URL {
      return url
    }
    if let urlString = value as? String {
      return URL(string: urlString) ?? URL(fileURLWithPath: urlString)
    }
    return nil
  }
}
