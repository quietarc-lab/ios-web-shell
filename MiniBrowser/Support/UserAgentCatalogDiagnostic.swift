import Foundation

/// A compact, copy-time snapshot of the fixed UA catalog and its local
/// restriction state. Raw User-Agent values are intentionally excluded.
enum UserAgentCatalogDiagnostic {
    static func snapshot(catalog: [BrowserUserAgent],
                         restrictedKeys: Set<String>,
                         expiryByID: [Int: Date],
                         selectedID: Int?) -> String {
        let catalogByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        let catalogIDs = Set(catalogByID.keys)
        let restrictedIDs = restrictedKeys
            .compactMap(Int.init)
            .filter { catalogIDs.contains($0) }
            .sorted()
        let restrictedIDSet = Set(restrictedIDs)
        let availableIDs = catalog.map(\.id).filter { !restrictedIDSet.contains($0) }
        let unknownRestrictionCount = restrictedKeys.reduce(into: 0) { count, key in
            guard let id = Int(key), catalogIDs.contains(id) else {
                count += 1
                return
            }
        }

        var lines = [
            "UA_CATALOG_SNAPSHOT",
            "CATALOG_VERSION: \(BrowserUserAgent.catalogVersion)",
            "TOTAL_COUNT: \(catalog.count)",
            "AVAILABLE_COUNT: \(availableIDs.count)",
            "RESTRICTED_COUNT: \(restrictedIDs.count)",
            "UNKNOWN_RESTRICTION_COUNT: \(unknownRestrictionCount)",
            "SELECTED_ID: \(selectedID.map(String.init) ?? "(none)")",
            "SELECTED_NAME: \(selectedID.flatMap { catalogByID[$0]?.name } ?? "(none)")"
        ]

        if restrictedIDs.isEmpty {
            lines.append("RESTRICTED_IDS: NONE")
            lines.append("RESTRICTED: NONE")
        } else {
            lines.append("RESTRICTED_IDS: \(restrictedIDs.map(String.init).joined(separator: ","))")
            let restricted = restrictedIDs.map { id in
                let name = catalogByID[id]?.name ?? "(unknown)"
                let expiry = expiryByID[id].map(formatExpiry) ?? "(unknown)"
                return "\(id)=\(name)@\(expiry)"
            }
            lines.append("RESTRICTED: \(restricted.joined(separator: ";"))")
        }

        let available = availableIDs.map { id in
            "\(id)=\(catalogByID[id]?.name ?? "(unknown)")"
        }
        lines.append("AVAILABLE_IDS: \(availableIDs.map(String.init).joined(separator: ","))")
        lines.append("AVAILABLE: \(available.joined(separator: ";"))")
        return lines.joined(separator: "\n")
    }

    private static func formatExpiry(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
