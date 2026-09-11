import Foundation
import XCTest
@testable import NotefyCore

final class MindspaceStorageTests: XCTestCase {
    func testCreatesMindspaceDirectoryForNewUser() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let result = MindspaceStorage.resolveDirectory(in: parent)

        XCTAssertEqual(result.lastPathComponent, "Mindspace")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }

    func testMigratesLegacyDirectoryWithoutLosingNotes() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacy = parent.appendingPathComponent("Notefy_Sessions", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let note = legacy.appendingPathComponent("saved-note.md")
        try Data("kept".utf8).write(to: note)

        let result = MindspaceStorage.resolveDirectory(in: parent)

        XCTAssertEqual(result.lastPathComponent, "Mindspace")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(try String(contentsOf: result.appendingPathComponent("saved-note.md")), "kept")
    }

    func testKeepsExistingMindspaceDirectoryWhenLegacyAlsoExists() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let current = parent.appendingPathComponent("Mindspace", isDirectory: true)
        let legacy = parent.appendingPathComponent("Notefy_Sessions", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)

        let result = MindspaceStorage.resolveDirectory(in: parent)

        XCTAssertEqual(result, current)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testRebasesAssetPathAfterDirectoryMigration() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let current = parent.appendingPathComponent("Mindspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        let capture = current.appendingPathComponent("capture.png")
        try Data("image".utf8).write(to: capture)

        let oldPath = parent
            .appendingPathComponent("Notefy_Sessions", isDirectory: true)
            .appendingPathComponent("capture.png").path
        let repaired = MindspaceStorage.rebasedAssetPath(oldPath, in: current)

        XCTAssertEqual(repaired, capture.path)
    }

    func testExistingAssetPathIsNeverRewritten() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let capture = parent.appendingPathComponent("capture.png")
        try Data("image".utf8).write(to: capture)

        XCTAssertEqual(
            MindspaceStorage.rebasedAssetPath(capture.path, in: parent),
            capture.path
        )
    }
}
