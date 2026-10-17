//
//  PieceDocument.swift
//  Considered
//
//  The plain-text model behind every piece of writing.
//
//  A piece is an ordinary Markdown file. When it carries any metadata (a title,
//  a stage, a project) that metadata lives in YAML front matter at the top of the
//  file, so the writing stays readable in any editor and portable to tools like
//  iA Writer or Obsidian. A fresh freewrite has no front matter at all.
//

import Foundation

/// Where a piece is in its life: a raw thought, an idea being worked on, or a conclusion.
enum Stage: String, CaseIterable, Identifiable {
    case thought
    case developing
    case considered

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thought: return "Thought"
        case .developing: return "Developing"
        case .considered: return "Considered"
        }
    }

    var explanation: String {
        switch self {
        case .thought: return "Captured as it came."
        case .developing: return "Being questioned and shaped."
        case .considered: return "What I concluded, for now."
        }
    }
}

struct PieceMetadata: Equatable {
    var title: String? = nil
    var stage: Stage = .thought
    var project: String? = nil
    /// "synthesis" marks a piece that draws conclusions across a project.
    var kind: String? = nil
    /// Keys we don't manage, preserved in order so other tools' metadata survives a save.
    var extra: [(key: String, value: String)] = []

    static func == (lhs: PieceMetadata, rhs: PieceMetadata) -> Bool {
        lhs.title == rhs.title &&
        lhs.stage == rhs.stage &&
        lhs.project == rhs.project &&
        lhs.kind == rhs.kind &&
        lhs.extra.map { "\($0.key)=\($0.value)" } == rhs.extra.map { "\($0.key)=\($0.value)" }
    }

    var isEmpty: Bool {
        normalizedTitle == nil && stage == .thought && normalizedProject == nil && kind == nil && extra.isEmpty
    }

    var normalizedTitle: String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedProject: String? {
        guard let project else { return nil }
        let trimmed = project.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isSynthesis: Bool { kind == "synthesis" }
}

enum FrontMatter {
    /// Splits a file into its metadata and the body the writer sees.
    static func parse(_ content: String) -> (metadata: PieceMetadata, body: String) {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else {
            return (PieceMetadata(), normalized)
        }

        let afterOpening = normalized.index(normalized.startIndex, offsetBy: 4)
        let remainder = normalized[afterOpening...]

        let closingRange: Range<String.Index>?
        if remainder.hasPrefix("---\n") || remainder == "---" {
            closingRange = remainder.startIndex..<remainder.index(remainder.startIndex, offsetBy: 3)
        } else if let range = remainder.range(of: "\n---\n") {
            closingRange = range
        } else if remainder.hasSuffix("\n---") {
            closingRange = remainder.index(remainder.endIndex, offsetBy: -4)..<remainder.endIndex
        } else {
            closingRange = nil
        }

        guard let closingRange else {
            return (PieceMetadata(), normalized)
        }

        let header = String(remainder[remainder.startIndex..<closingRange.lowerBound])
        // The blank line written after the closing fence belongs to the front matter, not the body.
        let body = String(remainder[closingRange.upperBound...].drop(while: { $0 == "\n" }))

        var metadata = PieceMetadata()
        for line in header.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let value = unquote(rawValue)
            switch key.lowercased() {
            case "title":
                metadata.title = value.isEmpty ? nil : value
            case "stage":
                metadata.stage = Stage(rawValue: value.lowercased()) ?? .thought
            case "project":
                metadata.project = value.isEmpty ? nil : value
            case "kind":
                metadata.kind = value.isEmpty ? nil : value
            default:
                metadata.extra.append((key: key, value: rawValue))
            }
        }
        return (metadata, body)
    }

    /// Joins metadata and body back into file contents. No metadata means no front matter.
    static func serialize(_ metadata: PieceMetadata, body: String) -> String {
        guard !metadata.isEmpty else {
            return body
        }
        var lines: [String] = ["---"]
        if let title = metadata.normalizedTitle {
            lines.append("title: \(quoteIfNeeded(title))")
        }
        lines.append("stage: \(metadata.stage.rawValue)")
        if let project = metadata.normalizedProject {
            lines.append("project: \(quoteIfNeeded(project))")
        }
        if let kind = metadata.kind {
            lines.append("kind: \(quoteIfNeeded(kind))")
        }
        for item in metadata.extra {
            lines.append("\(item.key): \(item.value)")
        }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n\n" + body
    }

    private static func unquote(_ value: String) -> String {
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        if value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return value
    }

    private static func quoteIfNeeded(_ value: String) -> String {
        let single = value.replacingOccurrences(of: "\n", with: " ")
        let needsQuotes = single.contains(": ") || single.contains(" #") ||
            single.hasPrefix("\"") || single.hasPrefix("'") ||
            single.first.map { "[]{}&*!|>%@`-?,".contains($0) } == true ||
            single.hasSuffix(":")
        guard needsQuotes else { return single }
        let escaped = single
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

enum PieceText {
    static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    /// The title a reader would give this piece: explicit title, first heading, or first line.
    static func displayTitle(body: String, metadata: PieceMetadata) -> String {
        if let title = metadata.normalizedTitle {
            return title
        }
        for line in body.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let stripped = trimmed
                .drop(while: { $0 == "#" || $0 == ">" || $0 == " " })
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !stripped.isEmpty else { continue }
            // Kept whole (up to a sane limit) so [[wiki links]] can match it; the UI truncates.
            return String(stripped.prefix(140))
        }
        return ""
    }

    static func relativeAge(of date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case 2..<14: return "\(days) days ago"
        case 14..<60: return "\(days / 7) weeks ago"
        default:
            let months = days / 30
            return months < 12 ? "\(months) months ago" : (months < 24 ? "a year ago" : "\(months / 12) years ago")
        }
    }
}

// MARK: - Versions

enum VersionKind: String {
    /// The piece as it first stood, kept when it starts being developed.
    case original
    /// Automatically kept when a piece is reopened on a later day and changed.
    case session
    /// Kept by the writer on purpose (⌘S).
    case manual
    /// Kept when the writer marks a piece as considered.
    case conclusion
    /// Kept just before an older version is restored over the current text.
    case beforeRestore = "before-restore"

    var displayName: String {
        switch self {
        case .original: return "Original thought"
        case .session: return "Earlier session"
        case .manual: return "Saved version"
        case .conclusion: return "Conclusion"
        case .beforeRestore: return "Before restoring"
        }
    }
}

struct PieceVersion: Identifiable, Equatable {
    let id: String
    let url: URL
    let savedAt: Date
    let kind: VersionKind
    let label: String?
    let stage: Stage
    let body: String

    var wordCount: Int { PieceText.wordCount(body) }
    var title: String { label ?? kind.displayName }
}

/// Snapshots live beside the writing, in Versions/[entry-base]/, as plain Markdown.
struct VersionStore {
    let root: URL
    private var fileManager: FileManager { .default }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    func directory(forEntryFilename filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        return root.appendingPathComponent("Versions", isDirectory: true).appendingPathComponent(base, isDirectory: true)
    }

    func versions(forEntryFilename filename: String) -> [PieceVersion] {
        let directory = directory(forEntryFilename: filename)
        guard let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "md" }
            .compactMap(readVersion(at:))
            .sorted { $0.savedAt > $1.savedAt }
    }

    func latest(forEntryFilename filename: String) -> PieceVersion? {
        versions(forEntryFilename: filename).first
    }

    @discardableResult
    func save(
        body: String,
        stage: Stage,
        kind: VersionKind,
        label: String? = nil,
        savedAt: Date = Date(),
        forEntryFilename filename: String
    ) -> PieceVersion? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Don't keep two identical snapshots in a row.
        if let latest = latest(forEntryFilename: filename),
           latest.body.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed,
           kind != .conclusion || latest.kind == .conclusion {
            return latest
        }

        let directory = directory(forEntryFilename: filename)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("Error creating versions directory: \(error)")
            return nil
        }

        var stamp = Self.timestampFormatter.string(from: savedAt)
        var url = directory.appendingPathComponent("\(stamp)-\(kind.rawValue).md")
        var suffix = 2
        while fileManager.fileExists(atPath: url.path) {
            stamp = Self.timestampFormatter.string(from: savedAt) + "-\(suffix)"
            url = directory.appendingPathComponent("\(stamp)-\(kind.rawValue).md")
            suffix += 1
        }

        var metadata = PieceMetadata()
        metadata.stage = stage
        metadata.extra.append((key: "version", value: kind.rawValue))
        metadata.extra.append((key: "saved", value: Self.isoFormatter.string(from: savedAt)))
        if let label, !label.isEmpty {
            metadata.title = label
        }
        let content = FrontMatter.serialize(metadata, body: body)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("Error saving version: \(error)")
            return nil
        }
        return readVersion(at: url)
    }

    func deleteAll(forEntryFilename filename: String) {
        let directory = directory(forEntryFilename: filename)
        if fileManager.fileExists(atPath: directory.path) {
            try? fileManager.removeItem(at: directory)
        }
    }

    private func readVersion(at url: URL) -> PieceVersion? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let parsed = FrontMatter.parse(content)
        let kindValue = parsed.metadata.extra.first(where: { $0.key == "version" })?.value ?? ""
        let savedValue = parsed.metadata.extra.first(where: { $0.key == "saved" })?.value ?? ""
        let fallbackDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
        return PieceVersion(
            id: url.lastPathComponent,
            url: url,
            savedAt: Self.isoFormatter.date(from: savedValue) ?? fallbackDate,
            kind: VersionKind(rawValue: kindValue) ?? .manual,
            label: parsed.metadata.normalizedTitle,
            stage: parsed.metadata.stage,
            body: parsed.body
        )
    }
}
