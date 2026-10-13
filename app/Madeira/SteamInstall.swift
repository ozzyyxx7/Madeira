// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2026 125hz
// Madeira Converter Exception: see LICENSE-EXCEPTION.md

import Foundation

// Where Madeira's own Steam downloads live, and how one is read and removed
// (docs/STEAM_LIBRARY.md). Foundation only, so tests/host/check-steam-library.py
// compiles this file as it is.
//
// A download goes into Madeira Dock's own Steam library folder,
// C:\Program Files (x86)\Steam\steamapps, as `common/<installdir>` plus Steam's
// `appmanifest_<appid>.acf` install record. That is exactly the layout
// Madeira Dock's discovery (MadeiraDock.games) reads and Valve's client, which
// Dock starts the game through, understands: a game is "installed" for Dock
// once its record says so, and the record is written last.

enum SteamInstallPaths {
    /// The library folder, relative to drive_c (the value `DockGame.library` has).
    static let libraryRelative = "Program Files (x86)/Steam/steamapps"

    static func steamApps(drive: URL) -> URL { drive.appendingPathComponent(libraryRelative, isDirectory: true) }
    static func common(drive: URL) -> URL { steamApps(drive: drive).appendingPathComponent("common", isDirectory: true) }

    /// Whether an install (its drive-relative library folder) is in the library
    /// Madeira downloads into, and so can be updated or removed here.
    static func isManaged(library: String) -> Bool {
        library.caseInsensitiveCompare(libraryRelative) == .orderedSame
    }
}

enum SteamInstallFiles {
    /// The `buildid` the install record of an app states, or nil when there is
    /// no readable record.
    static func buildID(appID: Int, steamApps: URL) -> Int? {
        guard let state = record(appID: appID, steamApps: steamApps) else { return nil }
        return state["buildid"]?.string.flatMap { Int($0) }
    }

    /// Language written by Steam for the installed game, if present.
    static func language(appID: Int, steamApps: URL) -> String? {
        record(appID: appID, steamApps: steamApps)?["UserConfig"]?["language"]?.string
    }

    /// The install size the record states (`SizeOnDisk`, bytes), or nil.
    static func sizeOnDisk(appID: Int, steamApps: URL) -> Int64? {
        guard let state = record(appID: appID, steamApps: steamApps),
              let size = state["SizeOnDisk"]?.string.flatMap({ Int64($0) }), size > 0 else { return nil }
        return size
    }

    /// Removes an app's install: its folder under `common`, its record, its
    /// resume journal and the records of the apps that own its shared depots
    /// (those describe the same folder). Only paths strictly inside
    /// `steamApps/common` are removed.
    nonisolated static func delete(appID: Int, folderName: String, steamApps: URL) {
        let fm = FileManager.default
        let common = steamApps.appendingPathComponent("common", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        let folder = common.appendingPathComponent(safeFolderName(folderName)).resolvingSymlinksInPath().standardizedFileURL
        if folder.path.hasPrefix(common.path + "/"), folder.deletingLastPathComponent().path == common.path {
            try? fm.removeItem(at: folder)
        }
        let recordURL = steamApps.appendingPathComponent("appmanifest_\(appID).acf")
        if let state = record(appID: appID, steamApps: steamApps) {
            for (_, owner) in (state["SharedDepots"]?.fields ?? [:]).sorted(by: { $0.key < $1.key }).prefix(64) {
                guard let ownerID = owner.string.flatMap({ Int($0) }), ownerID > 0, ownerID != appID,
                      let ownerState = record(appID: ownerID, steamApps: steamApps),
                      let dir = ownerState["installdir"]?.string,
                      safeFolderName(dir).caseInsensitiveCompare(safeFolderName(folderName)) == .orderedSame
                else { continue }
                try? fm.removeItem(at: steamApps.appendingPathComponent("appmanifest_\(ownerID).acf"))
            }
        }
        try? fm.removeItem(at: recordURL)
        try? fm.removeItem(at: steamApps.appendingPathComponent("downloading/\(appID)", isDirectory: true))
    }

    /// Validates a manifest path and folds directory spelling to the first
    /// one seen (case-insensitively). Returns nil for anything that could
    /// escape the install folder.
    nonisolated static func safeRelativePath(_ name: String, folded: inout [String: String]) -> String? {
        let parts = name.replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty, parts.count <= 64, name.utf8.count < 1024,
              !parts.contains(where: { $0 == "." || $0 == ".." || $0.contains(":") ||
                  $0.unicodeScalars.contains(where: { $0.value < 0x20 }) }) else { return nil }
        var built: [String] = []
        for (index, part) in parts.enumerated() {
            if index == parts.count - 1 { built.append(part); break }
            let key = (built + [part]).joined(separator: "/").lowercased()
            if let existing = folded[key] {
                built = existing.split(separator: "/").map(String.init)
            } else {
                built.append(part)
                folded[key] = built.joined(separator: "/")
            }
        }
        return built.joined(separator: "/")
    }

    /// Install folders come from app metadata; keep them to one safe component.
    nonisolated static func safeFolderName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
        guard !cleaned.isEmpty, cleaned != ".", cleaned != "..", !cleaned.contains(":"),
              !cleaned.unicodeScalars.contains(where: { $0.value < 0x20 }) else { return "app" }
        return cleaned
    }

    /// The `AppState` block of `appmanifest_<appid>.acf` when the file is
    /// readable, bounded, and names this app.
    private static func record(appID: Int, steamApps: URL) -> SteamValue? {
        let url = steamApps.appendingPathComponent("appmanifest_\(appID).acf")
        guard let data = try? Data(contentsOf: url), data.count <= 1 << 20,
              var parser = try? SteamKeyValues(data), let root = try? parser.read(),
              let state = root["AppState"], state["appid"]?.string == String(appID) else { return nil }
        return state
    }
}

/// Valve's Windows client and Source games also read language from the Wine
/// registry. The install manifest selects content, but does not by itself set
/// those runtime values in a headless Dock session. Apply the installed game's
/// language before Wine starts, while its registry is still on disk.
enum SteamLaunchLanguage {
    static func valid(_ code: String) -> Bool {
        !code.isEmpty && code.utf8.count <= 32 && code.utf8.allSatisfy { (97...122).contains($0) }
    }

    static func apply(appID: Int, steamApps: URL, prefix: URL) throws -> String? {
        guard let language = SteamInstallFiles.language(appID: appID, steamApps: steamApps)?.lowercased(),
              valid(language) else { return nil }
        let file = prefix.appendingPathComponent("user.reg")
        let old = try String(contentsOf: file, encoding: .utf8)
        guard old.hasPrefix("WINE REGISTRY Version ") else { return nil }
        let updated = registry(old, language: language, now: Int(Date().timeIntervalSince1970))
        if updated != old { try Data(updated.utf8).write(to: file, options: .atomic) }
        return language
    }

    /// Preserve unrelated registry values and only update Valve's language
    /// values. Source's own key is needed for games such as Portal even when
    /// their Steam appmanifest already says `koreana`.
    static func registry(_ text: String, language: String, now: Int) -> String {
        guard valid(language) else { return text }
        var lines = text.components(separatedBy: "\n")
        for path in ["Software\\Valve\\Steam", "Software\\Valve\\Source"] {
            let header = "[" + path.replacingOccurrences(of: "\\", with: "\\\\") + "]"
            let value = "\"Language\"=\"\(language)\""
            if let start = lines.firstIndex(where: { $0.caseInsensitiveCompare(header) == .orderedSame ||
                $0.lowercased().hasPrefix(header.lowercased() + " ") }) {
                var end = start + 1
                while end < lines.count, !lines[end].hasPrefix("[") { end += 1 }
                if let index = (start + 1..<end).first(where: {
                    $0 < lines.count && lines[$0].lowercased().hasPrefix("\"language\"=")
                }) {
                    lines[index] = value
                } else {
                    var at = end
                    while at > start + 1, lines[at - 1].isEmpty { at -= 1 }
                    lines.insert(value, at: at)
                }
            } else {
                while lines.last == "" { lines.removeLast() }
                lines += ["", header + " \(now)", value, ""]
            }
        }
        return lines.joined(separator: "\n")
    }
}
