protocol DisplayResolving: Sendable { func resolve(_ selector: DisplaySelector) throws -> ResolvedDisplay }

protocol DisplayListing: Sendable { func listTargets() throws -> [DisplayTarget] }

extension DisplayResolver: DisplayResolving {}
extension DisplayResolver: DisplayListing {}
