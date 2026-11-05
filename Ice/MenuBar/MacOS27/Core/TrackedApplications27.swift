//
//  TrackedApplications27.swift
//  Ice
//

import Foundation

/// Pure rules for MenuBarAgent's own list of applications allowed in the menu bar.
///
/// macOS 27 has a switch per application, "Allow in the Menu Bar" in System Settings >
/// Control Center. MenuBarAgent keeps it in the `trackedApplications` preference of the
/// `group.com.apple.controlcenter` group container: data holding a binary property list, which
/// is a Swift `[TrackedApplicationLocation: TrackedApplication]` encoded by `Codable` — a flat
/// array that alternates key, value, key, value (measured on macOS 27.0.1, 2026-10-22). A key
/// is `{"bundle": {"_0": "<bundle id>"}}`, or `{"adhocBinary": {"_0": {"relative": "file:///…"}}}`
/// for a binary not signed by a team. A value is `{"location": <its key>, "menuItemLocations":
/// [<key>, …], "isAllowed": <Bool>}`.
///
/// `location` is the application the switch belongs to. `menuItemLocations` lists the programs
/// whose items the switch governs, and the switch hides only those. MenuBarAgent files a program
/// under the application responsible for it: a helper started from a terminal or by another
/// application lands under that application's switch. That can leave an application's switch
/// listing only some other program, and then turning it off does not hide its own item (seen on
/// 2026-11-05: ChatGPT's switch listed only `/private/tmp/prs-workflow-record`).
///
/// Only bundle keys are ever read or changed here. Every other key, and everything in a value
/// besides `isAllowed`, is passed back exactly as it came: MenuBarAgent wrote it. The single
/// exception is ``addingSource(_:toSwitch:in:)``, which the user asks for explicitly to put an
/// application's own item back under its own switch.
enum TrackedApplications27 {
    /// A program whose items a switch can govern, in the form MenuBarAgent writes in
    /// `menuItemLocations`: the bundle of a team-signed program, or the executable of one that is not.
    enum Source: Hashable, CustomStringConvertible {
        case bundle(String)
        case adhocBinary(path: String)

        init?(key: Any) {
            guard let key = key as? [String: Any], key.count == 1 else {
                return nil
            }
            if let id = (key["bundle"] as? [String: Any])?["_0"] as? String {
                self = .bundle(id)
                return
            }
            if let relative = ((key["adhocBinary"] as? [String: Any])?["_0"] as? [String: Any])?["relative"] as? String,
               let url = URL(string: relative), url.isFileURL {
                self = .adhocBinary(path: url.path)
                return
            }
            return nil
        }

        /// The key as MenuBarAgent writes it.
        var key: [String: Any] {
            switch self {
            case .bundle(let id):
                ["bundle": ["_0": id]]
            case .adhocBinary(let path):
                ["adhocBinary": ["_0": ["relative": URL(fileURLWithPath: path).absoluteString]]]
            }
        }

        var description: String {
            switch self {
            case .bundle(let id): id
            case .adhocBinary(let path): path
            }
        }
    }

    /// The programs each bundle's switch governs.
    static func sources(in array: [Any]) -> [String: [Source]] {
        var result = [String: [Source]]()
        for entry in entries(in: array) {
            guard
                let bundleID = entry.bundleID,
                let value = array[entry.valueIndex] as? [String: Any],
                let locations = value["menuItemLocations"] as? [Any]
            else {
                continue
            }
            result[bundleID, default: []].append(contentsOf: locations.compactMap(Source.init(key:)))
        }
        return result
    }

    /// The bundle whose switch governs the program, or `nil` if no switch lists it.
    static func switchGoverning(_ source: Source, in array: [Any]) -> String? {
        for entry in entries(in: array) {
            guard
                let bundleID = entry.bundleID,
                let value = array[entry.valueIndex] as? [String: Any],
                let locations = value["menuItemLocations"] as? [Any],
                locations.contains(where: { Source(key: $0) == source })
            else {
                continue
            }
            return bundleID
        }
        return nil
    }

    /// The list with the program added to the bundle's switch, or `nil` if there is no such
    /// switch or it already governs the program.
    static func addingSource(_ source: Source, toSwitch bundleID: String, in array: [Any]) -> [Any]? {
        guard
            let entry = entries(in: array).first(where: { $0.bundleID == bundleID }),
            var value = array[entry.valueIndex] as? [String: Any]
        else {
            return nil
        }
        var locations = value["menuItemLocations"] as? [Any] ?? []
        guard !locations.contains(where: { Source(key: $0) == source }) else {
            return nil
        }
        locations.append(source.key)
        value["menuItemLocations"] = locations
        var result = array
        result[entry.valueIndex] = value
        return result
    }

    /// One key and value pair of the list.
    struct Entry: Equatable {
        /// The bundle identifier of the key, or `nil` for a key that is not a bundle key.
        let bundleID: String?

        /// The value's `isAllowed`, or `nil` if it has none.
        let isAllowed: Bool?

        /// Where the value stands in the flat array; its key is the element before it.
        let valueIndex: Int
    }

    /// The pairs of the flat array, in order. An unpaired element at the end is not an entry.
    static func entries(in array: [Any]) -> [Entry] {
        stride(from: 0, to: array.count - 1, by: 2).map { keyIndex in
            let value = array[keyIndex + 1] as? [String: Any]
            return Entry(
                bundleID: bundleID(ofKey: array[keyIndex]),
                isAllowed: value?["isAllowed"] as? Bool,
                valueIndex: keyIndex + 1
            )
        }
    }

    /// The bundle identifier a key names, or `nil` if it is not a bundle key.
    static func bundleID(ofKey key: Any) -> String? {
        guard
            let key = key as? [String: Any],
            key.count == 1,
            let bundle = key["bundle"] as? [String: Any]
        else {
            return nil
        }
        return bundle["_0"] as? String
    }

    /// The current `isAllowed` of each bundle in the list.
    ///
    /// Should a bundle appear twice, which MenuBarAgent has not been seen to write, it counts as
    /// allowed if either entry is.
    static func allowedStates(in array: [Any]) -> [String: Bool] {
        var states = [String: Bool]()
        for entry in entries(in: array) {
            guard let bundleID = entry.bundleID, let isAllowed = entry.isAllowed else {
                continue
            }
            states[bundleID] = (states[bundleID] ?? false) || isAllowed
        }
        return states
    }

    /// The list with `isAllowed` set for the given bundles, and the bundles it actually changed.
    ///
    /// Only the values under a bundle key for one of the identifiers are touched, and only their
    /// `isAllowed`; a value that is already as asked, or that has no `isAllowed` at all, is left
    /// alone. Everything else, the order included, comes back as it was.
    static func settingAllowed(_ allowed: Bool, for bundleIDs: Set<String>, in array: [Any]) -> (array: [Any], changed: Set<String>) {
        guard !bundleIDs.isEmpty else {
            return (array, [])
        }
        var result = array
        var changed = Set<String>()
        for entry in entries(in: array) {
            guard
                let bundleID = entry.bundleID,
                bundleIDs.contains(bundleID),
                let isAllowed = entry.isAllowed,
                isAllowed != allowed,
                var value = array[entry.valueIndex] as? [String: Any]
            else {
                continue
            }
            value["isAllowed"] = allowed
            result[entry.valueIndex] = value
            changed.insert(bundleID)
        }
        return (result, changed)
    }

    /// Decodes the preference's data into the flat array, or `nil` if it is not one.
    static func decode(_ data: Data) -> [Any]? {
        try? PropertyListSerialization.propertyList(from: data, format: nil) as? [Any]
    }

    /// Encodes the flat array the way MenuBarAgent stores it: as a binary property list.
    static func encode(_ array: [Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: array, format: .binary, options: 0)
    }
}
