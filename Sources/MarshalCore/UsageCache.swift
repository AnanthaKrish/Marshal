import CryptoKit
import Foundation

public enum UsageCache {
    public static var directory: URL { MarshalPaths.directory.appendingPathComponent("usage", isDirectory: true) }
    public static func write(_ sample: UsageSample, directory: URL = directory) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let key = "\(sample.agent):\(sample.session ?? "account")"
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
        let file = directory.appendingPathComponent(name)
        let data = try JSONEncoder().encode(sample)
        try data.write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

/// Passive local readers. Only known Codex chat IDs are matched; unchanged files
/// are skipped and reads are bounded. Unrelated transcript records are discarded.
public actor UsageFiles {
    private let cacheDirectory: URL
    private let codexDirectory: URL
    private var paths: [String: URL] = [:]
    private var signatures: [String: String] = [:]
    private var lastSearch = Date.distantPast
    private var lastIDs: Set<String> = []

    public init(cacheDirectory: URL = UsageCache.directory,
                codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")) {
        self.cacheDirectory = cacheDirectory; self.codexDirectory = codexDirectory
    }

    public func read(sessions: [String], now: Date = .now) -> [UsageSample] {
        let fm = FileManager.default
        var result: [UsageSample] = []
        let files = ((try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? [])
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for file in files.prefix(1000) where file.pathExtension == "json" {
            guard changed(file), let data = try? Data(contentsOf: file), data.count <= 65536,
                  let sample = try? JSONDecoder().decode(UsageSample.self, from: data) else { continue }
            result.append(sample)
        }
        let ids = Set(sessions.filter { UUID(uuidString: $0) != nil })
        if ids != lastIDs || now.timeIntervalSince(lastSearch) > 60 {
            paths = paths.filter { ids.contains($0.key) }
            if !ids.isEmpty, let walker = fm.enumerator(at: codexDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                var visited = 0
                for case let file as URL in walker {
                    visited += 1
                    if visited > 50000 { break }
                    guard file.pathExtension == "jsonl" else { continue }
                    if let id = ids.first(where: { file.lastPathComponent.hasSuffix("\($0).jsonl") }) { paths[id] = file }
                }
            }
            lastIDs = ids; lastSearch = now
        }
        for (id, file) in paths {
            guard changed(file), let sample = Self.latestCodexSample(file: file, session: id) else { continue }
            result.append(sample)
        }
        return result
    }

    private func changed(_ file: URL) -> Bool {
        guard let attrs = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return false }
        let value = "\(attrs.fileSize ?? 0):\(attrs.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        guard signatures[file.path] != value else { return false }
        signatures[file.path] = value
        return true
    }

    public static func latestCodexSample(file: URL, session: String) -> UsageSample? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > 2_097_152 ? end - 2_097_152 : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.read(upToCount: 2_097_152) else { return nil }
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        // An incomplete final record is never treated as a complete update.
        if data.last != 0x0A, !lines.isEmpty { lines.removeLast() }
        for line in lines.reversed() {
            guard line.count <= 65536,
                  line.prefix(350).range(of: Data("\"token_count\"".utf8)) != nil else { continue }
            if let sample = UsageParsing.codexRecord(Data(line), session: session) { return sample }
        }
        return nil
    }
}
