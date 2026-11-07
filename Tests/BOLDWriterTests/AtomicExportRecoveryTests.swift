import AppKit
import CryptoKit
import PDFKit
import XCTest
@testable import BOLDWriter

@MainActor
final class AtomicExportRecoveryTests: XCTestCase {
    private enum InjectedFailure: Error { case failed }

    private func document() -> BOLDWriterDocument {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "Export recovery sentinel", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        return document
    }

    private func stagedFiles(near destination: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: destination.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".\(destination.lastPathComponent).boldwriter-export-") }
    }

    func testFailuresBeforeCommitKeepExistingExportAndRemoveStagingFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("book.pdf")
        let original = Data("previous complete export".utf8)
        try original.write(to: destination)

        let beforeWrite = AtomicExportFileWriter.system
        var failingBeforeWrite = beforeWrite
        failingBeforeWrite.writeStaged = { _, _ in throw InjectedFailure.failed }
        XCTAssertThrowsError(try failingBeforeWrite.write(Data("new complete export".utf8), to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertTrue(try stagedFiles(near: destination).isEmpty)

        var fullDisk = beforeWrite
        fullDisk.writeStaged = { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        XCTAssertThrowsError(try fullDisk.write(Data("new complete export".utf8), to: destination)) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileWriteOutOfSpace)
        }
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertTrue(try stagedFiles(near: destination).isEmpty)

        var partialWrite = beforeWrite
        partialWrite.writeStaged = { data, temporary in
            try Data(data.prefix(8)).write(to: temporary)
            throw InjectedFailure.failed
        }
        XCTAssertThrowsError(try partialWrite.write(Data("new complete export".utf8), to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertTrue(try stagedFiles(near: destination).isEmpty)

        var beforeReplacement = beforeWrite
        beforeReplacement.replace = { _, _ in throw InjectedFailure.failed }
        XCTAssertThrowsError(try beforeReplacement.write(Data("new complete export".utf8), to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertTrue(try stagedFiles(near: destination).isEmpty)
    }

    func testInterruptionImmediatelyAfterReplacementLeavesCompleteNewExport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("book.pdf")
        let original = Data("previous complete export".utf8)
        let replacement = Data("new complete export".utf8)
        try original.write(to: destination)

        var afterReplacement = AtomicExportFileWriter.system
        afterReplacement.replace = { target, staged in
            _ = try FileManager.default.replaceItemAt(target, withItemAt: staged)
            throw InjectedFailure.failed // models termination after the atomic commit point
        }
        XCTAssertThrowsError(try afterReplacement.write(replacement, to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), replacement)
        XCTAssertTrue(try stagedFiles(near: destination).isEmpty)
    }

    func testRepeatedExportFailuresCanBeFollowedBySuccessfulSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("book.pdf")
        let original = Data("previous complete export".utf8)
        try original.write(to: destination)
        let doc = document()

        var failing = AtomicExportFileWriter.system
        failing.writeStaged = { _, _ in throw InjectedFailure.failed }
        for _ in 0..<3 {
            XCTAssertThrowsError(try ExportService.write(.pdf, document: doc, to: destination, using: failing))
            XCTAssertEqual(try Data(contentsOf: destination), original)
            XCTAssertTrue(try stagedFiles(near: destination).isEmpty)
        }

        _ = try ExportService.write(.pdf, document: doc, to: destination)
        let reopened = try XCTUnwrap(PDFDocument(url: destination))
        XCTAssertEqual(reopened.pageCount, 1)
        XCTAssertTrue(reopened.string?.contains("Export recovery sentinel") == true)
        XCTAssertTrue(try stagedFiles(near: destination).isEmpty)
    }

    func testNextExportCleansStagesOnlyWhenTheirOwnerHasExited() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("book.pdf")
        let prefix = ".\(destination.lastPathComponent).boldwriter-export-"
        let abandoned = directory.appendingPathComponent("\(prefix)2000000000-\(UUID().uuidString)")
        let live = directory.appendingPathComponent("\(prefix)\(getpid())-\(UUID().uuidString)")
        try Data("partial abandoned bytes".utf8).write(to: abandoned)
        try Data("active exporter bytes".utf8).write(to: live)

        _ = try ExportService.write(.pdf, document: document(), to: destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path), "A stage owned by an exited PID must be reclaimed on the next export.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: live.path), "A stage owned by a live exporter must not be removed.")
        XCTAssertNotNil(PDFDocument(url: destination))
        try FileManager.default.removeItem(at: live)
        XCTAssertTrue(try stagedFiles(near: destination).isEmpty)
    }

    func testChildProcessTerminationDuringStagedExportPreservesPreviousFile() throws {
        let env = ProcessInfo.processInfo.environment
        if let destinationPath = env["BOLD_ATOMIC_EXPORT_CHILD_DESTINATION"],
           let readyPath = env["BOLD_ATOMIC_EXPORT_CHILD_READY"] {
            let destination = URL(fileURLWithPath: destinationPath)
            var blockedWriter = AtomicExportFileWriter.system
            blockedWriter.writeStaged = { data, staging in
                try Data(data.prefix(128)).write(to: staging)
                try Data("staged".utf8).write(to: URL(fileURLWithPath: readyPath))
                while true { Thread.sleep(forTimeInterval: 0.05) }
            }
            try blockedWriter.write(Data(repeating: 0x41, count: 4_096), to: destination)
            XCTFail("The test worker must be terminated while its staged write is incomplete.")
            return
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("interrupted.pdf")
        let ready = directory.appendingPathComponent("worker-ready")
        let oldCompleteFile = Data("previous complete PDF".utf8)
        try oldCompleteFile.write(to: destination)

        guard CommandLine.arguments.count >= 2, let bundlePath = CommandLine.arguments.last else {
            XCTFail("XCTest did not expose its runner and test bundle paths: \(CommandLine.arguments)")
            return
        }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["-XCTest", "BOLDWriterTests.AtomicExportRecoveryTests/testChildProcessTerminationDuringStagedExportPreservesPreviousFile", bundlePath]
        var childEnvironment = env
        childEnvironment["BOLD_ATOMIC_EXPORT_CHILD_DESTINATION"] = destination.path
        childEnvironment["BOLD_ATOMIC_EXPORT_CHILD_READY"] = ready.path
        child.environment = childEnvironment
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        let deadline = Date().addingTimeInterval(20)
        while !FileManager.default.fileExists(atPath: ready.path), Date() < deadline, child.isRunning {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard FileManager.default.fileExists(atPath: ready.path) else {
            if child.isRunning { child.terminate(); child.waitUntilExit() }
            XCTFail("Isolated export child did not reach its incomplete-staging point; PID=\(child.processIdentifier)")
            return
        }
        let childPID = child.processIdentifier
        let pidStage = try XCTUnwrap(try stagedFiles(near: destination).first { $0.lastPathComponent.contains("-\(childPID)-") })
        XCTAssertLessThan((try Data(contentsOf: pidStage)).count, 4_096)
        XCTAssertEqual(try Data(contentsOf: destination), oldCompleteFile)
        print("BOLD_ATOMIC_FAULT_INJECTION childPID=\(childPID) destination=\(destination.path) staging=\(pidStage.path) priorFileSHA256=\(Self.sha256(oldCompleteFile))")
        child.terminate()
        child.waitUntilExit()
        XCTAssertNotEqual(child.terminationStatus, 0, "Worker was intentionally terminated while writing disposable staged data.")

        XCTAssertEqual(try Data(contentsOf: destination), oldCompleteFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pidStage.path), "Abrupt termination leaves its staging file for safe next-export cleanup.")
        _ = try ExportService.write(.pdf, document: document(), to: destination)
        XCTAssertNotNil(PDFDocument(url: destination))
        XCTAssertTrue(try stagedFiles(near: destination).isEmpty, "Next successful export must reclaim the dead worker's temporary file.")
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
