import Foundation
import XCTest
@testable import DayGhibli

@MainActor
final class ImagePruningTests: XCTestCase {
    func testKeepsTwoCurrentAndTwoPreviousImages() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try makeDirectory("Wallpapers", in: root)
        let retained = try ["current-left.jpg", "current-right.jpg", "previous-left.jpg", "previous-right.jpg"]
            .map { try makeFile($0, in: cache) }
        _ = try makeFile("older-left.jpg", in: cache)
        _ = try makeFile("older-right.jpg", in: cache)

        try await ImageStore(directory: cache).prune(keeping: Set(retained))

        XCTAssertEqual(try Set(FileManager.default.contentsOfDirectory(atPath: cache.path)),
                       Set(retained.map(\.lastPathComponent)))
    }

    func testSharedImageAndEquivalentPathsAreKeptOnce() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try makeDirectory("Wallpapers", in: root)
        let shared = try makeFile("shared.jpg", in: cache)
        let alias = root.appendingPathComponent("shared-alias.jpg")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: shared)
        let relativeComponents = cache.appendingPathComponent("unused/../shared.jpg")
        _ = try makeFile("older.jpg", in: cache)

        try await ImageStore(directory: cache).prune(keeping: Set([alias, alias, relativeComponents, relativeComponents]))

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cache.path), ["shared.jpg"])
        XCTAssertEqual(try Data(contentsOf: shared), Data("fixture".utf8))
    }

    func testLeavesExternalFilesSymbolicLinksDirectoriesAndNonJPEGFilesUntouched() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try makeDirectory("Wallpapers", in: root)
        let current = try makeFile("current.jpg", in: cache)
        let stale = try makeFile("older.jpg", in: cache)
        let external = try makeFile("external.jpg", in: root)
        let externalDirectory = try makeDirectory("external-folder", in: root)
        let externalNested = try makeFile("external-nested.jpg", in: externalDirectory)
        let link = cache.appendingPathComponent("external-link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        let brokenLink = cache.appendingPathComponent("broken-link.jpg")
        try FileManager.default.createSymbolicLink(at: brokenLink,
            withDestinationURL: root.appendingPathComponent("missing.jpg"))
        let directoryLink = cache.appendingPathComponent("folder-link.jpg")
        try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: externalDirectory)
        let nestedDirectory = try makeDirectory("subdirectory.jpg", in: cache)
        let nested = try makeFile("nested.jpg", in: nestedDirectory)
        let notes = try makeFile("notes.txt", in: cache)

        try await ImageStore(directory: cache).prune(keeping: [current, external])

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        for file in [current, external, externalNested, nested, notes] {
            XCTAssertEqual(try Data(contentsOf: file), Data("fixture".utf8))
        }
        for symbolicLink in [link, brokenLink, directoryLink] {
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: symbolicLink.path)[.type]
                as? FileAttributeType, .typeSymbolicLink)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedDirectory.path))
    }

    func testMissingCacheDirectoryNeedsNoCleanup() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("missing-cache", isDirectory: true)

        try await ImageStore(directory: missing).prune(keeping: [])

        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testDoesNotFollowSymbolicCacheRoot() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let externalDirectory = try makeDirectory("external-folder", in: root)
        let external = try makeFile("external.jpg", in: externalDirectory)
        let cacheLink = root.appendingPathComponent("Wallpapers", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: cacheLink, withDestinationURL: externalDirectory)

        try await ImageStore(directory: cacheLink).prune(keeping: [])

        XCTAssertEqual(try Data(contentsOf: external), Data("fixture".utf8))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayGhibli-Pruning-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeDirectory(_ name: String, in parent: URL) throws -> URL {
        let directory = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeFile(_ name: String, in directory: URL) throws -> URL {
        let file = directory.appendingPathComponent(name)
        try Data("fixture".utf8).write(to: file)
        return file
    }
}
