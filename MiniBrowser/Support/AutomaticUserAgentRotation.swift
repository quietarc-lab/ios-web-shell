import Foundation

/// Builds the in-memory order used by one automatic-post session. The
/// catalog itself remains canonical and stable; only the session order is
/// shuffled. A greedy selection prefers a different browser and device family
/// from the previous candidate, then relaxes the device constraint, and
/// finally the browser constraint when the remaining pool requires it.
enum AutomaticUserAgentRotation {
    static func makeOrder(catalog: [BrowserUserAgent],
                          restrictedIDs: Set<Int>) -> [Int] {
        var remaining = catalog.indices.filter {
            !restrictedIDs.contains(catalog[$0].id)
        }.shuffled()
        var order: [Int] = []
        order.reserveCapacity(remaining.count)

        var previous: BrowserUserAgent?
        while !remaining.isEmpty {
            let candidates: [Int]
            if let previous {
                let strict = remaining.filter {
                    catalog[$0].browserFamily != previous.browserFamily &&
                    catalog[$0].deviceFamily != previous.deviceFamily
                }
                if !strict.isEmpty {
                    candidates = strict
                } else {
                    // Relax the device constraint first: retain a different
                    // browser family whenever one remains, even if the next
                    // profile is on the same device family. Only when that
                    // is impossible do we prefer a different device.
                    let differentBrowser = remaining.filter {
                        catalog[$0].browserFamily != previous.browserFamily
                    }
                    let differentDevice = remaining.filter {
                        catalog[$0].deviceFamily != previous.deviceFamily
                    }
                    candidates = differentBrowser.isEmpty
                        ? differentDevice
                        : differentBrowser
                }
            } else {
                candidates = remaining
            }

            // `candidates` can only be empty when all remaining entries share
            // both families with the previous entry. In that final fallback,
            // keep the shuffled order rather than dropping a usable UA.
            let pool = candidates.isEmpty ? remaining : candidates
            guard let selected = pool.randomElement(),
                  let removeIndex = remaining.firstIndex(of: selected) else {
                break
            }
            remaining.remove(at: removeIndex)
            order.append(selected)
            previous = catalog[selected]
        }
        return order
    }
}

extension BrowserUserAgent {
    var browserFamily: String {
        name.split(separator: " ").first.map(String.init) ?? "Unknown"
    }

    var deviceFamily: String {
        value.contains("(iPad;") ? "iPad" : "iPhone"
    }
}
