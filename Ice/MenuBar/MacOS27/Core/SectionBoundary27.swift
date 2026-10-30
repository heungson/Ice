import CoreGraphics

/// Rules shared by physical arrangement, Command-drag adoption and new items.
enum SectionBoundary27 {
    static func section(of bounds: CGRect, arrow: CGRect) -> MacOS27Section? {
        guard bounds.width > 1, bounds.height > 1, arrow.width > 1, arrow.height > 1,
              abs(bounds.midY - arrow.midY) < max(bounds.height, arrow.height)
        else { return nil }
        // MenuBarAgent's neighbouring Accessibility rectangles can overlap.
        // The icon's centre must be outside the arrow, not its entire AX rectangle.
        if bounds.midX < arrow.minX { return .hidden }
        if bounds.midX > arrow.maxX { return .visible }
        return nil
    }

    /// One app can publish several icons; the native visibility switch covers them all.
    /// Keep the whole app visible if any of its icons is on the visible side.
    static func observedSections(items: [(bundleID: String, bounds: CGRect)], arrow: CGRect) -> [String: MacOS27Section] {
        var result = [String: MacOS27Section]()
        for item in items {
            guard let section = section(of: item.bounds, arrow: arrow) else { continue }
            result[item.bundleID] = min(result[item.bundleID] ?? section, section)
        }
        return result
    }

    static func isCorrect(bounds: CGRect, arrow: CGRect, section: MacOS27Section) -> Bool {
        self.section(of: bounds, arrow: arrow) == (section == .visible ? .visible : .hidden)
    }
}
