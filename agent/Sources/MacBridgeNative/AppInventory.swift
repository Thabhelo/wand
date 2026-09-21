import AppKit
import CoreServices
import MacBridgeCore

/// No paths, documents, or window titles leave the Mac through this catalog.
public enum AppInventory {
    public struct Entry: Sendable {
        public let name: String
        public let bundleID: String
        public let lastOpened: Date?
        public let running: Bool
        let url: URL
    }
    @MainActor private static var cached: [Entry] = []
    @MainActor private static var cachedAt = Date.distantPast
    public static func ordered(_ entries: [Entry]) -> [Entry] {
        entries.sorted {
            if $0.lastOpened != $1.lastOpened { return ($0.lastOpened ?? .distantPast) > ($1.lastOpened ?? .distantPast) }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.bundleID < $1.bundleID : order == .orderedAscending
        }
    }
    @MainActor public static func applications(refresh: Bool = false) async -> [Entry] {
        if !refresh && Date().timeIntervalSince(cachedAt) < 30 { return cached }
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> Entry? in
            guard let id = app.bundleIdentifier, let url = app.bundleURL else { return nil }
            return Entry(name: app.localizedName ?? id, bundleID: id, lastOpened: app.launchDate, running: true, url: url)
        }
        let entries = await Task.detached(priority: .userInitiated) { discover(running: running) }.value
        cached = entries; cachedAt = Date(); return entries
    }
    private static func discover(running: [Entry]) -> [Entry] {
        var urls = Set(running.map(\.url))
        // Spotlight includes apps outside Applications. Directory enumeration covers
        // unindexed installations, without descending inside application bundles.
        if let query = MDQueryCreate(nil, "kMDItemContentType == 'com.apple.application-bundle'" as CFString, nil, nil),
           MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) {
            for i in 0..<min(20000, MDQueryGetResultCount(query)) {
                guard let raw = MDQueryGetResultAtIndex(query, i) else { continue }
                let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
                if let path = MDItemCopyAttribute(item, kMDItemPath) as? String { urls.insert(URL(fileURLWithPath: path)) }
            }
        }
        let roots = ["/Applications", "/System/Applications", "/System/Library/CoreServices", "/Users/Shared", NSHomeDirectory()+"/Applications"]
        for path in roots {
            let root = URL(fileURLWithPath: path)
            guard let scan = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            var visited = 0
            for case let url as URL in scan {
                visited += 1
                if visited > 20000 { break }
                if url.pathExtension.lowercased() == "app" { urls.insert(url); scan.skipDescendants() }
                else if url.pathComponents.count - root.pathComponents.count >= 5 { scan.skipDescendants() }
            }
        }
        var byID: [String: Entry] = [:]
        for url in urls.sorted(by: { $0.path < $1.path }) {
            guard FileManager.default.fileExists(atPath: url.path), let bundle = Bundle(url: url),
                  let id = bundle.bundleIdentifier, id.count <= 200,
                  id.range(of: "^[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil,
                  bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool != true,
                  !url.path.contains(".app/Contents/") else { continue }
            let name = String(((bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent).prefix(160))
            guard !name.isEmpty else { continue }
            let instances = running.filter { $0.bundleID == id }
            let metadata = MDItemCreate(nil, url.path as CFString).flatMap { MDItemCopyAttribute($0, kMDItemLastUsedDate) as? Date }
            let lastOpened = ([metadata] + instances.map(\.lastOpened)).compactMap { $0 }.max()
            let entry = Entry(name: name, bundleID: id, lastOpened: lastOpened, running: !instances.isEmpty, url: url)
            // Prefer the running copy when several installations share an identifier.
            if byID[id] == nil || instances.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) { byID[id] = entry }
        }
        return ordered(Array(byID.values))
    }
    @MainActor public static func page(offset: Int) async -> JSON {
        let entries = await applications(refresh: offset == 0)
        let start = min(max(0, offset), entries.count), end = min(start + 100, entries.count)
        return .object(["apps": .array(entries[start..<end].map { entry in
            .object(["name": .string(entry.name), "bundle_id": .string(entry.bundleID), "last_opened": entry.lastOpened.map { .string(WireTime.text($0)) } ?? .null, "running": .bool(entry.running)])
        }), "next_offset": end < entries.count ? .number(Double(end)) : .null])
    }
    @MainActor public static func resolve(name: String) async throws -> URL {
        let matches = await applications().filter { $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.url.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }
        guard matches.count == 1 else { throw ContractError(code: "app_not_found_or_ambiguous") }
        return matches[0].url
    }
}
