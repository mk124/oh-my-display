import Foundation

public enum ICCProfileIdentity {
  public static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
    if canonicalURL(lhs) == canonicalURL(rhs) {
      return true
    }
    guard let lhsID = resourceIdentifier(lhs), let rhsID = resourceIdentifier(rhs) else {
      return false
    }
    return lhsID == rhsID
  }

  public static func canonicalURL(_ url: URL) -> URL {
    url.resolvingSymlinksInPath().standardizedFileURL
  }

  public static func sortKey(_ url: URL) -> String {
    canonicalURL(url).path
  }

  private static func resourceIdentifier(_ url: URL) -> String? {
    let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
    guard let values = try? canonicalURL(url).resourceValues(forKeys: keys),
      let identifier = values.fileResourceIdentifier
    else {
      return nil
    }
    return String(describing: identifier)
  }
}
