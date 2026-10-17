//
//  LibraryLocation.swift
//  Considered
//
//  Where the writing lives. By default ~/Documents/Considered inside the app
//  container; the writer can point it at any folder (an iCloud Drive folder keeps
//  every Mac in sync). The choice is remembered with a security-scoped bookmark.
//

import Foundation
import AppKit

final class LibraryLocation {
    static let shared = LibraryLocation()

    static let folderName = "Considered"
    private let bookmarkKey = "libraryBookmark"
    private let fileManager = FileManager.default
    private var accessedURL: URL?

    private(set) var rootURL: URL

    private init() {
        rootURL = LibraryLocation.defaultURL
        if let resolved = resolveBookmark() {
            rootURL = resolved
        }
        ensureExists(rootURL)
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    var isUsingDefault: Bool {
        rootURL.standardizedFileURL == LibraryLocation.defaultURL.standardizedFileURL
    }

    var isInICloudDrive: Bool {
        rootURL.path.contains("/Library/Mobile Documents/")
    }

    /// Shown in the library header, e.g. "iCloud Drive › Writing".
    var friendlyPath: String {
        let path = rootURL.path
        if let range = path.range(of: "/Library/Mobile Documents/com~apple~CloudDocs") {
            let rest = path[range.upperBound...]
            return "iCloud Drive" + rest.replacingOccurrences(of: "/", with: " › ")
        }
        let home = LibraryLocation.realHomeDirectory.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// The user's real home directory, not the sandbox container.
    static var realHomeDirectory: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var iCloudDriveURL: URL? {
        let url = realHomeDirectory.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Asks the writer for a folder. Returns the new root, or nil if they cancelled.
    func chooseFolder(startingInICloud: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Keep My Writing Here"
        panel.message = startingInICloud
            ? "Choose or create a folder in iCloud Drive. Your writing will sync to every Mac signed in to your iCloud account."
            : "Choose a folder for your writing. Everything stays as plain Markdown files."
        if startingInICloud, let iCloud = LibraryLocation.iCloudDriveURL {
            panel.directoryURL = iCloud
        }
        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        setRoot(url)
        return url
    }

    func useDefault() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        stopAccessing()
        rootURL = LibraryLocation.defaultURL
        ensureExists(rootURL)
    }

    private func setRoot(_ url: URL) {
        stopAccessing()
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        } catch {
            print("Error creating library bookmark: \(error)")
        }
        if url.startAccessingSecurityScopedResource() {
            accessedURL = url
        }
        rootURL = url
        ensureExists(rootURL)
    }

    private func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            if url.startAccessingSecurityScopedResource() {
                accessedURL = url
            }
            if isStale, let refreshed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
            }
            return url
        } catch {
            print("Error resolving library bookmark, falling back to default: \(error)")
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return nil
        }
    }

    private func stopAccessing() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    private func ensureExists(_ url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                print("Error creating library directory: \(error)")
            }
        }
    }

    /// Copies writing (pieces, versions, videos) from one library into another without overwriting anything.
    func copyLibrary(from source: URL, to destination: URL) -> Int {
        guard source.standardizedFileURL != destination.standardizedFileURL,
              let items = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else {
            return 0
        }
        var copied = 0
        for item in items {
            let name = item.lastPathComponent
            let isPiece = item.pathExtension == "md" && name.hasPrefix("[")
            let isManagedFolder = name == "Versions" || name == "Videos"
            guard isPiece || isManagedFolder else { continue }
            let target = destination.appendingPathComponent(name)
            if isManagedFolder {
                copied += mergeDirectory(item, into: target)
            } else if !fileManager.fileExists(atPath: target.path) {
                if (try? fileManager.copyItem(at: item, to: target)) != nil {
                    copied += 1
                }
            }
        }
        return copied
    }

    private func mergeDirectory(_ source: URL, into destination: URL) -> Int {
        if !fileManager.fileExists(atPath: destination.path) {
            return (try? fileManager.copyItem(at: source, to: destination)) != nil ? 1 : 0
        }
        guard let children = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else {
            return 0
        }
        var copied = 0
        for child in children {
            let target = destination.appendingPathComponent(child.lastPathComponent)
            if !fileManager.fileExists(atPath: target.path),
               (try? fileManager.copyItem(at: child, to: target)) != nil {
                copied += 1
            }
        }
        return copied
    }

    func countPieces(in url: URL) -> Int {
        let items = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension == "md" && $0.lastPathComponent.hasPrefix("[") }.count
    }
}
