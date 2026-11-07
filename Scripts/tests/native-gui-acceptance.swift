import AppKit
import ApplicationServices
import CryptoKit
import Foundation
import Vision

/// Native, accessibility-driven acceptance for the real BOLD Writer app.
/// Every action is scoped to an exact app bundle/PID and followed by an
/// accessibility-state check and a genuine macOS screenshot. Coordinate input
/// is used only for dragging inside the bounds of the identified 3D viewport.
struct NativeGUIAcceptance {
    struct Failure: Error, CustomStringConvertible {
        let description: String
        let category: String

        init(description: String, category: String = "automation_or_application_state") {
            self.description = description
            self.category = category
        }
    }

    let appURL: URL
    let bundleID: String
    let expectedRevision: String
    let inputURL: URL
    let outputURL: URL
    let timeout: TimeInterval
    let expectedProofPages: Int
    let inspectOnly: Bool
    let manuscriptOnly: Bool
    let floatingImageKeyboard: Bool
    let proofOnly: Bool
    let automationScriptURL: URL?
    let scenarioID: String
    var pid: pid_t = 0
    var appElement: AXUIElement!
    var eventLog: [[String: Any]] = []
    var screenshotEvidence: [[String: Any]] = []
    var initialInputIdentity: [String: Any] = [:]
    var finalInputIdentity: [String: Any] = [:]
    var executableIdentity: [String: Any] = [:]
    var startupResolutionSeconds: Double = 0
    var startupMode = "not-started"
    var documentWasAlreadyOpen = false

    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        func value(_ key: String, default fallback: String? = nil) throws -> String {
            guard let i = args.firstIndex(of: key), args.indices.contains(i + 1) else {
                if let fallback { return fallback }
                throw Failure(description: "Missing required argument \(key)")
            }
            return args[i + 1]
        }
        let app = URL(fileURLWithPath: try value("--app")).standardizedFileURL
        let id = try value("--bundle-id")
        let rev = try value("--revision")
        let input = URL(fileURLWithPath: try value("--input")).standardizedFileURL
        let output = URL(fileURLWithPath: try value("--output")).standardizedFileURL
        let seconds = TimeInterval(try value("--timeout", default: "240")) ?? 240
        let proofPages = Int(try value("--proof-pages", default: "391")) ?? 391
        let inspectOnly = args.contains("--inspect-only")
        let manuscriptOnly = args.contains("--manuscript-only")
        let floatingImageKeyboard = args.contains("--floating-image-keyboard")
        let proofOnly = args.contains("--proof-only")
        let automationScript = args.firstIndex(of: "--automation-script").flatMap { args.indices.contains($0 + 1) ? URL(fileURLWithPath: args[$0 + 1]).standardizedFileURL : nil }
        let scenario = try value("--scenario", default: "integrated-default")
        var runner = NativeGUIAcceptance(appURL: app, bundleID: id, expectedRevision: rev,
                                         inputURL: input, outputURL: output, timeout: seconds,
                                         expectedProofPages: proofPages,
                                         inspectOnly: inspectOnly, manuscriptOnly: manuscriptOnly,
                                         floatingImageKeyboard: floatingImageKeyboard,
                                         proofOnly: proofOnly,
                                         automationScriptURL: automationScript,
                                         scenarioID: scenario)
        do {
            try runner.run()
        } catch {
            try? runner.writeFailure(error)
            throw error
        }
    }

    func plist(_ key: String) throws -> String {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: infoURL)
        guard let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let value = dictionary[key] as? String else {
            throw Failure(description: "Missing \(key) in \(infoURL.path)")
        }
        return value
    }

    mutating func run() throws {
        guard inputURL.path.hasPrefix("/"), FileManager.default.fileExists(atPath: inputURL.path) else {
            throw Failure(description: "Input proof is missing: \(inputURL.path)")
        }
        guard !FileManager.default.fileExists(atPath: outputURL.path),
              outputURL.path != inputURL.path, !outputURL.path.hasPrefix(inputURL.path + "/") else {
            throw Failure(description: "Evidence output must be a new path outside the input document")
        }
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let executableURL = appURL.appendingPathComponent("Contents/MacOS/BOLD Writer")
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw Failure(description: "App executable is missing at \(appURL.path)", category: "candidate_identity")
        }
        let actualBundleID = try plist("CFBundleIdentifier")
        guard actualBundleID == bundleID else {
            throw Failure(description: "Bundle ID mismatch: expected \(bundleID), got \(try plist("CFBundleIdentifier"))")
        }
        let actualRevision = try plist("BOLDWriterSourceRevision")
        guard actualRevision == expectedRevision else {
            throw Failure(description: "Revision mismatch: expected \(expectedRevision), got \(actualRevision)", category: "candidate_identity")
        }
        let executableData = try Data(contentsOf: executableURL, options: [.mappedIfSafe])
        let architectureOutput = try runTool("/usr/bin/lipo", arguments: ["-archs", executableURL.path])
        let uuidOutput = try runTool("/usr/bin/dwarfdump", arguments: ["--uuid", executableURL.path])
        executableIdentity = ["path": appURL.path, "bundleID": actualBundleID, "sourceRevision": actualRevision,
                              "sourceDiffSHA256": (try? plist("BOLDWriterSourceDiffSHA256")) ?? NSNull(),
                              "sourceTreeFingerprint": (try? plist("BOLDWriterSourceTreeFingerprint")) ?? NSNull(),
                              "version": try plist("CFBundleShortVersionString"),
                              "executableSHA256": sha256(executableData),
                              "architectures": architectureOutput.trimmingCharacters(in: .whitespacesAndNewlines),
                              "machOUUIDs": uuidOutput.trimmingCharacters(in: .whitespacesAndNewlines)]
        guard AXIsProcessTrusted() else {
            throw Failure(description: "Accessibility permission is unavailable for the invoking Terminal process. Enable Accessibility for Terminal in System Settings > Privacy & Security > Accessibility; this harness does not change TCC settings.", category: "environment_accessibility_permission")
        }
        initialInputIdentity = try artifactIdentity(inputURL)
        try prepareIsolatedCandidatePreferences()
        try startOrResolveApp()
        try record("identified", extra: ["pid": pid, "bundleID": bundleID,
                                          "bundlePath": appURL.path,
                                          "revision": expectedRevision,
                                          "version": try plist("CFBundleShortVersionString"),
                                          "startupMode": startupMode,
                                          "startupResolutionSeconds": startupResolutionSeconds])
        if windows().contains(where: { title($0).localizedCaseInsensitiveContains(inputURL.lastPathComponent) }) {
            try capture("00-start")
        } else {
            try record("startup-window-not-test-document", extra: ["recovery": "Open the disposable document; unrelated or stale app windows are not treated as the test target"])
        }
        let documentOpenStart = ProcessInfo.processInfo.systemUptime
        try openDocument()
        try waitForWindow(containing: inputURL.lastPathComponent, timeout: timeout)
        try focusInputDocumentWindow(timeout: 10)
        let documentOpenSeconds = ProcessInfo.processInfo.systemUptime - documentOpenStart
        try record("document-open", extra: ["document": inputURL.path,
                                              "documentWasAlreadyOpen": documentWasAlreadyOpen,
                                              "documentOpenObservedSeconds": documentOpenSeconds])
        // BOLD Writer restores the last workspace when a document is reopened.
        // The manuscript editor is absent from AX while Cover Creator is active,
        // so normalize the workspace before taking document-content snapshots.
        try ensureManuscriptWorkspace(timeout: 30)
        try record("first-editable-state", extra: ["secondsFromOpenRequest": ProcessInfo.processInfo.systemUptime - documentOpenStart,
                                                     "stateEvidence": "AXTextArea:Document editor"])
        try capture("01-manuscript")
        try writeJSON(accessibilitySnapshot(), to: outputURL.appendingPathComponent("AX-01-manuscript.json"))
        if inspectOnly {
            // Capture the next manuscript viewport as well. This lets layout
            // acceptance inspect the affected physical page in the production
            // editor rather than relying only on the first visible page.
            try scrollManuscript(to: 0.2)
            Thread.sleep(forTimeInterval: 0.4)
            try record("inspect-page-down")
            try capture("02-manuscript-page-down")
            try writeJSON(accessibilitySnapshot(), to: outputURL.appendingPathComponent("AX-02-manuscript-page-down.json"))
            try closeInputDocumentWindow(saveBeforeClose: false)
            let report: [String: Any] = ["scenarioID": scenarioID, "status": "PASS_INSPECTION", "application": executableIdentity.merging(["pid": pid]) { _, new in new }, "input": inputURL.path, "inputIdentityBefore": initialInputIdentity, "inputIdentityAfter": finalInputIdentity, "evidenceDirectory": outputURL.path, "screenshots": screenshotEvidence, "steps": eventLog]
            try writeJSON(report, to: outputURL.appendingPathComponent("REPORT.json"))
            print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]), encoding: .utf8)!)
            return
        }

        if floatingImageKeyboard {
            try verifyFloatingImageKeyboardMovement()
            try closeInputDocumentWindow(saveBeforeClose: false)
            let report: [String: Any] = ["status": "PASS_FLOATING_IMAGE_KEYBOARD_GUI",
                                         "application": executableIdentity.merging(["pid": pid]) { _, new in new },
                                         "input": inputURL.path, "inputIdentityBefore": initialInputIdentity, "inputIdentityAfter": finalInputIdentity, "evidenceDirectory": outputURL.path, "screenshots": screenshotEvidence, "steps": eventLog]
            try writeJSON(report, to: outputURL.appendingPathComponent("REPORT.json"))
            print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]), encoding: .utf8)!)
            return
        }

        try verifyEditorUndoRedoSaveReopen()
        if let automationScriptURL {
            try verifyAutomationStudioScript(at: automationScriptURL)
            try closeInputDocumentWindow(saveBeforeClose: false)
            let report: [String: Any] = ["scenarioID": scenarioID, "status": "PASS_AUTOMATION_STUDIO_GUI", "application": executableIdentity.merging(["pid": pid]) { _, new in new }, "input": inputURL.path, "inputIdentityBefore": initialInputIdentity, "inputIdentityAfter": finalInputIdentity, "automationScript": automationScriptURL.path, "evidenceDirectory": outputURL.path, "screenshots": screenshotEvidence, "steps": eventLog]
            try writeJSON(report, to: outputURL.appendingPathComponent("REPORT.json"))
            print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]), encoding: .utf8)!)
            return
        }
        if manuscriptOnly {
            try closeInputDocumentWindow(saveBeforeClose: false)
            let report: [String: Any] = ["scenarioID": scenarioID, "status": "PASS_MANUSCRIPT_GUI", "application": executableIdentity.merging(["pid": pid]) { _, new in new }, "input": inputURL.path, "inputIdentityBefore": initialInputIdentity, "inputIdentityAfter": finalInputIdentity, "evidenceDirectory": outputURL.path, "screenshots": screenshotEvidence, "steps": eventLog]
            try writeJSON(report, to: outputURL.appendingPathComponent("REPORT.json"))
            print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]), encoding: .utf8)!)
            return
        }
        try ensureManuscriptWorkspace(timeout: 30)
        try clickNamed(["Insert"], identifierContains: [])
        try clickNamed(["Check My Book"], identifierContains: [])
        try waitForAccessibleText(prefix: "Book health status:", timeout: 240)
        try record("book-health-open", extra: ["evidence": "visible health report in native application"])
        try capture("02-book-health")
        try writeJSON(accessibilitySnapshot(), to: outputURL.appendingPathComponent("AX-02-book-health.json"))
        try clickNamed(["Inspect Print Proof"], identifierContains: [])
        // The Book Health sheet itself contains an "Inspect Print Proof" button.
        // Waiting for the substring "Print Proof" falsely treated that button
        // as the proof viewer. Require the viewer's unique page-navigation field.
        _ = try waitForControl(description: "Go to proof page", role: "AXTextField", timeout: 30)
        try record("exact-print-proof-open", extra: ["source": "BookHealthCheckReport.productionPDFData"])
        try capture("03-print-proof-page-1")
        try writeJSON(accessibilitySnapshot(), to: outputURL.appendingPathComponent("AX-03-print-proof.json"))
        let middleProofPage = max(1, expectedProofPages / 2)
        try navigateProof(to: middleProofPage)
        try capture("03-print-proof-page-\(middleProofPage)")
        try navigateProof(to: expectedProofPages)
        try capture("03-print-proof-page-\(expectedProofPages)")
        if proofOnly {
            try clickNamed(["Done"], identifierContains: [])
            try waitForAccessibleText(prefix: "Book health status:", timeout: 15)
            try clickNamed(["Done"], identifierContains: [])
            try ensureManuscriptWorkspace(timeout: 30)
            try closeInputDocumentWindow(saveBeforeClose: false)
            let report: [String: Any] = ["scenarioID": scenarioID, "status": "PASS_PRINT_PROOF_GUI",
                "application": executableIdentity.merging(["pid": pid]) { _, new in new },
                "input": inputURL.path, "inputIdentityBefore": initialInputIdentity,
                "inputIdentityAfter": finalInputIdentity, "proofPagesRequested": [1, middleProofPage, expectedProofPages],
                "evidenceDirectory": outputURL.path, "screenshots": screenshotEvidence,
                "steps": eventLog,
                "note": "Viewer transitions and requested page state were verified; captured proof images require independent visual inspection for page content and geometry."]
            try writeJSON(report, to: outputURL.appendingPathComponent("REPORT.json"))
            print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
            return
        }
        try clickNamed(["Done"], identifierContains: [])
        try waitForAnyWindowState(["Book health status", "Check My Book"], timeout: 15)
        try clickNamed(["Done"], identifierContains: [])
        try waitForAnyWindowState(["Document editor"], timeout: 30)
        try record("book-health-and-proof-closed")

        try clickNamed(["3D Studio", "Book Studio"], identifierContains: ["workspace", "studio"])
        try waitForAnyWindowState(["3D book preview", "bookstudio.viewport", "Book Views"], timeout: 30)
        try record("studio-entered")
        // The native document persists its last physical-book pose. Normalize
        // it explicitly so "closed" and "open" acceptance steps are actions
        // with observable state changes, rather than assumptions about the
        // previous GUI session.
        try clickNamed(["Closed"], identifierContains: [])
        try waitForControlValue(description: "Closed", value: "1", role: "AXRadioButton", timeout: 20)
        try record("book-closed")
        try capture("02-3d-studio")

        try drag3DViewport()
        try record("studio-rotated")
        try capture("03-rotated")

        try clickNamed(["Open Book", "Reading"], identifierContains: [])
        try waitForControlValue(description: "Open Book", value: "1", role: "AXRadioButton", timeout: 20)
        try hotkey(key: 53, flags: []) // Close a menu if the native control opened one.
        try record("book-open")
        try capture("04-open-book")

        var beforeNext = try spreadSummary()
        if let visiblePages = try? spreadPages(from: beforeNext), visiblePages.0 > 1 {
            // A native document may restore the last 3D spread from its
            // saved presentation state. Normalize to the first spread before
            // checking that the forward control changes the rendered page;
            // otherwise a valid last-page state has Next Spread disabled.
            try clickNamed(["First spread"], identifierContains: [])
            beforeNext = try waitForSpreadChange(from: beforeNext, timeout: 20)
        }
        try clickNamed(["Next Spread"], identifierContains: [])
        let afterNext = try waitForSpreadChange(from: beforeNext, timeout: 20)
        try record("page-navigation", extra: ["before": beforeNext, "after": afterNext])
        try capture("05-next-spread")

        let pageCount = try extractPageCount(from: afterNext)
        guard pageCount > 1 else {
            throw Failure(description: "3D Studio exposed only \(pageCount) manuscript page")
        }
        // Exact page-number navigation is verified in the PDF proof above.
        // In 3D, verify the explicit endpoint controls instead of simulating
        // hundreds of animated page turns to reach the middle of a long book.
        let atLastSpread = try spreadSummary()
        try clickNamed(["Last spread"], identifierContains: [])
        let lastSpread = try waitForSpreadChange(from: atLastSpread, timeout: 30)
        try record("studio-last-spread", extra: ["spread": lastSpread, "pageCount": pageCount])
        try capture("studio-last-spread")
        try clickNamed(["First spread"], identifierContains: [])
        let firstSpread = try waitForSpreadChange(from: lastSpread, timeout: 30)
        try record("studio-first-spread", extra: ["spread": firstSpread, "pageCount": pageCount])
        try capture("studio-first-spread")

        try clickNamed(["Hardcover"], identifierContains: [])
        try waitForControlValue(description: "Hardcover", value: "1", role: "AXRadioButton", timeout: 20)
        try record("hardcover-preview")
        try capture("06-hardcover")
        try clickNamed(["Softcover"], identifierContains: [])
        try waitForControlValue(description: "Softcover", value: "1", role: "AXRadioButton", timeout: 20)
        try record("paperback-preview")
        try capture("06-paperback")

        try clickNamed(["Cover Creator"], identifierContains: ["cover"])
        try waitForAnyWindowState(["Cover panels", "Layers", "Full Wrap"], timeout: 30)
        try record("cover-creator-return")
        try capture("07-cover-creator")
        try writeJSON(accessibilitySnapshot(), to: outputURL.appendingPathComponent("AX-07-cover-creator.json"))
        try closeInputDocumentWindow(saveBeforeClose: true)

        let report: [String: Any] = ["scenarioID": scenarioID, "status": "PARTIAL_GUI_ACCEPTANCE",
                                     "application": executableIdentity.merging(["pid": pid]) { _, new in new },
                                     "input": inputURL.path, "inputIdentityBefore": initialInputIdentity,
                                     "inputIdentityAfter": finalInputIdentity, "evidenceDirectory": outputURL.path,
                                     "screenshots": screenshotEvidence, "steps": eventLog,
                                     "note": "Manuscript/cover PDF export and independent PDF reopen are not performed by this harness version and remain separate acceptance gates."]
        try writeJSON(report, to: outputURL.appendingPathComponent("REPORT.json"))
        print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    }

    mutating func ensureManuscriptWorkspace(timeout seconds: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(seconds)
        var lastTransitionError: String?
        var transitionRequested = false
        while Date() < deadline {
            let currentElements = activeElements()
            let proofFieldPresent = currentElements.contains {
                string($0, kAXRoleAttribute as String) == "AXTextField"
                    && string($0, kAXDescriptionAttribute as String) == "Go to proof page"
            }
            let healthSheetPresent = currentElements.contains {
                string($0, kAXRoleAttribute as String) == "AXStaticText"
                    && string($0, kAXValueAttribute as String).hasPrefix("Book health status:")
            }
            if proofFieldPresent || healthSheetPresent {
                try clickNamed(["Done"], identifierContains: [])
                Thread.sleep(forTimeInterval: 0.15)
                continue
            }
            if currentElements.contains(where: {
                string($0, kAXRoleAttribute as String) == "AXTextArea"
                    && string($0, kAXDescriptionAttribute as String) == "Document editor"
            }) {
                try record("manuscript-workspace-ready", extra: ["stateEvidence": "AXTextArea:Document editor",
                                                                  "workspaceTransitionRequested": transitionRequested])
                return
            }
            let manuscriptTab = currentElements.first(where: {
                [string($0, kAXTitleAttribute as String), string($0, kAXDescriptionAttribute as String), string($0, "AXIdentifier")]
                    .contains { $0.caseInsensitiveCompare("Manuscript") == .orderedSame }
                    && ["AXButton", "AXRadioButton", "AXTabGroup"].contains(string($0, kAXRoleAttribute as String))
            })
            if manuscriptTab != nil && !transitionRequested {
                do {
                    try clickNamed(["Manuscript"], identifierContains: ["workspace"])
                    transitionRequested = true
                } catch { lastTransitionError = String(describing: error) }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        let visible = activeElements().filter {
            ["AXButton", "AXRadioButton", "AXTabGroup"].contains(string($0, kAXRoleAttribute as String))
        }.map { [string($0, kAXRoleAttribute as String), string($0, kAXTitleAttribute as String),
                 string($0, kAXDescriptionAttribute as String), string($0, "AXIdentifier")]
            .filter { !$0.isEmpty }.joined(separator: " | ") }
        throw Failure(description: "Manuscript workspace did not become ready within \(seconds)s. Window=\(windowSummary()); visible workspace controls=\(visible); last transition error=\(lastTransitionError ?? "none")", category: "application_state_or_accessibility")
    }

    mutating func focusInputDocumentWindow(timeout seconds: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            guard let documentWindow = windows().first(where: {
                title($0).localizedCaseInsensitiveContains(inputURL.lastPathComponent)
            }) else {
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
            if activeWindow().map({ title($0).localizedCaseInsensitiveContains(inputURL.lastPathComponent) }) == true {
                return
            }
            _ = AXUIElementPerformAction(documentWindow, kAXRaiseAction as CFString)
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw Failure(description: "The target document window \(inputURL.lastPathComponent) did not become the active AX window; current windows=\(windowSummary())", category: "automation_window_resolution")
    }

    /// Isolated app bundles have a fresh defaults domain, so their first-run
    /// welcome sheet can cover an already-open document during GUI acceptance.
    /// Suppress only that introductory sheet for temporary nonproduction app
    /// identities; never mutate the installed BOLD Writer preference domain.
    func prepareIsolatedCandidatePreferences() throws {
        guard appURL.path.hasPrefix("/tmp/"), bundleID != "com.boldwriter.app" else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", bundleID, "didShowWelcome", "-bool", "true"]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown defaults error"
            throw Failure(description: "Could not prepare isolated-candidate welcome preference: \(error)")
        }
    }

    mutating func verifyFloatingImageKeyboardMovement() throws {
        let metadataURL = inputURL.appendingPathComponent("metadata.json")
        let sourceText = try editorText()
        let sourceHash = SHA256.hash(data: Data(sourceText.utf8)).map { String(format: "%02x", $0) }.joined()
        let imageRecord = try floatingImageRecord(at: metadataURL)
        let imageID = try requiredString(imageRecord, "id")
        let initialX = try requiredNumber(imageRecord, "x")
        let initialY = try requiredNumber(imageRecord, "y")
        guard try requiredString(imageRecord, "wrapping") == "none",
              (imageRecord["positionLocked"] as? Bool) == false else {
            throw Failure(description: "Keyboard acceptance fixture must contain an unlocked No Wrap floating image")
        }

        let selectedScreenPoint = try clickVisibleFixtureImage()
        guard let focused = focusedElement(), string(focused, kAXRoleAttribute as String) == "AXTextArea",
              string(focused, kAXDescriptionAttribute as String) == "Document editor" else {
            throw Failure(description: "Canvas image click did not leave Document editor as the focused responder")
        }
        try record("floating-image-canvas-click", extra: ["imageID": imageID,
                                                            "imageScreenPoint": ["x": selectedScreenPoint.x, "y": selectedScreenPoint.y],
                                                            "focusedRole": string(focused, kAXRoleAttribute as String),
                                                            "focusedDescription": string(focused, kAXDescriptionAttribute as String)])
        if let inspectorTab = activeElements().first(where: {
            string($0, kAXRoleAttribute as String) == "AXRadioButton"
                && string($0, kAXDescriptionAttribute as String) == "Inspector"
        }), (try? copy(inspectorTab, kAXEnabledAttribute as String) as? NSNumber)?.boolValue == false {
            // A collapsed right sidebar leaves its tab picker present but
            // disabled in AX. Open the sidebar through its distinct, labeled
            // control, then wait for the actual tab to become actionable.
            try clickNamed(["Toggle AI, Inspector, and History sidebar"], identifierContains: [])
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                let refreshed = activeElements().first(where: {
                    string($0, kAXRoleAttribute as String) == "AXRadioButton"
                        && string($0, kAXDescriptionAttribute as String) == "Inspector"
                })
                if (try? copy(refreshed ?? inspectorTab, kAXEnabledAttribute as String) as? NSNumber)?.boolValue == true { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        try clickNamed(["Inspector"], identifierContains: [])
        _ = try waitForElement(identifier: "floatingImageKeyboardHelp", timeout: 10)
        guard activeElements().contains(where: { string($0, kAXValueAttribute as String) == (imageRecord["assetName"] as? String ?? "") }) else {
            throw Failure(description: "Canvas selection did not resolve to the fixture image in the visible image inspector")
        }
        try capture("image-keyboard-selected")
        try writeJSON(accessibilitySnapshot(), to: outputURL.appendingPathComponent("AX-image-selected.json"))

        func activateCanvas() throws {
            _ = try clickVisibleFixtureImage()
            guard let focus = focusedElement(), string(focus, kAXRoleAttribute as String) == "AXTextArea",
                  string(focus, kAXDescriptionAttribute as String) == "Document editor" else {
                throw Failure(description: "Canvas click did not restore the manuscript editor as keyboard responder")
            }
            guard activeElements().contains(where: { string($0, kAXDescriptionAttribute as String) == "Inspector" && string($0, kAXValueAttribute as String) == "1" }) else {
                throw Failure(description: "Image canvas focus changed the active sidebar away from Inspector")
            }
        }

        func assertGeometry(_ x: Double, _ y: Double, step: String) throws {
            try hotkey(key: 1, flags: .maskCommand)
            try waitForStoredGeometry(metadataURL: metadataURL, imageID: imageID, x: x, y: y, timeout: 8)
            let currentText = try editorText()
            let currentHash = SHA256.hash(data: Data(currentText.utf8)).map { String(format: "%02x", $0) }.joined()
            guard currentHash == sourceHash else { throw Failure(description: "Image movement changed manuscript characters at \(step): \(sourceHash) -> \(currentHash)") }
            try record(step, extra: ["imageID": imageID, "expectedX": x, "expectedY": y,
                                     "persisted": true, "manuscriptTextSHA256": currentHash,
                                     "inspectorStillSelected": activeElements().contains(where: { string($0, "AXIdentifier") == "floatingImageKeyboardHelp" })])
            try capture(step)
        }

        let moves: [(String, CGKeyCode, CGEventFlags, Double, Double)] = [
            ("image-arrow-right-plus-1pt", 124, [], initialX + 1, initialY),
            ("image-arrow-left-minus-1pt", 123, [], initialX, initialY),
            ("image-arrow-down-plus-1pt", 125, [], initialX, initialY + 1),
            ("image-arrow-up-minus-1pt", 126, [], initialX, initialY),
            ("image-shift-right-plus-10pt", 124, .maskShift, initialX + 10, initialY),
            ("image-option-right-plus-0.1pt", 124, .maskAlternate, initialX + 10.1, initialY),
            ("image-shift-option-left-option-takes-precedence", 123, [.maskShift, .maskAlternate], initialX + 10, initialY)
        ]
        for (name, key, flags, x, y) in moves {
            try activateCanvas()
            try hotkey(key: key, flags: flags)
            try assertGeometry(x, y, step: name)
        }

        try activateCanvas()
        try hotkey(key: 124, flags: .maskCommand)
        try assertGeometry(initialX + 10, initialY, step: "command-right-left-to-editor")

        // A locked image remains selectable but ignores canvas movement.
        try setInspectorCheckbox(label: "Lock Position", value: true)
        try activateCanvas()
        try hotkey(key: 124, flags: [])
        try assertGeometry(initialX + 10, initialY, step: "locked-image-arrow-no-op")
        try setInspectorCheckbox(label: "Lock Position", value: false)
        try activateCanvas()

        // The simple Automatic text flow control is the primary user path:
        // on means text exclusion around the image; off restores an overlay.
        try setInspectorCheckbox(label: "Automatic text flow", value: true)
        try hotkey(key: 1, flags: .maskCommand)
        try waitForStoredWrapping(metadataURL: metadataURL, imageID: imageID, wrapping: "square", timeout: 8)
        let flowed = try floatingImageRecord(at: metadataURL)
        guard try requiredString(flowed, "wrapping") == "square" else {
            throw Failure(description: "Automatic text flow did not enable Square wrapping in the saved native image record")
        }
        try record("automatic-text-flow-enabled", extra: ["wrapping": "square", "manuscriptTextSHA256": sourceHash])
        try capture("automatic-text-flow-enabled")
        try setInspectorCheckbox(label: "Automatic text flow", value: false)
        try hotkey(key: 1, flags: .maskCommand)
        try waitForStoredWrapping(metadataURL: metadataURL, imageID: imageID, wrapping: "none", timeout: 8)
        let overlay = try floatingImageRecord(at: metadataURL)
        guard try requiredString(overlay, "wrapping") == "none" else {
            throw Failure(description: "Turning Automatic text flow off did not restore No Wrap overlay behavior")
        }
        try record("automatic-text-flow-disabled-overlay", extra: ["wrapping": "none", "manuscriptTextSHA256": sourceHash])
        try capture("automatic-text-flow-disabled-overlay")
        try setInspectorCheckbox(label: "Automatic text flow", value: true)
        try hotkey(key: 1, flags: .maskCommand)
        try waitForStoredWrapping(metadataURL: metadataURL, imageID: imageID, wrapping: "square", timeout: 8)
        try record("automatic-text-flow-set-for-reopen", extra: ["wrapping": "square"])

        // Escape clears image keyboard mode; a subsequent arrow advances the
        // text insertion point and leaves image geometry untouched.
        try activateCanvas()
        try hotkey(key: 53, flags: [])
        let beforeCaret = selectedTextRange()
        try hotkey(key: 124, flags: [])
        let afterCaret = selectedTextRange()
        guard beforeCaret != nil, afterCaret != nil else {
            throw Failure(description: "Escape did not expose a manuscript insertion point; before=\(String(describing: beforeCaret)), after=\(String(describing: afterCaret))")
        }
        // AX sometimes reports a stale insertion range when a text caret sits
        // at a line boundary. Prove the responder with a reversible one-letter
        // edit, then restore and compare the exact source text.
        try typeText("X")
        let typedText = try editorText()
        guard typedText.count == sourceText.count + 1, typedText.contains("X") else {
            throw Failure(description: "After Escape, keyboard typing did not reach the manuscript editor")
        }
        try hotkey(key: 6, flags: .maskCommand)
        let undoDeadline = Date().addingTimeInterval(3)
        var restoredText = try editorText()
        while restoredText != sourceText && Date() < undoDeadline {
            Thread.sleep(forTimeInterval: 0.05)
            restoredText = try editorText()
        }
        guard restoredText == sourceText else {
            throw Failure(description: "Undo after the Escape typing probe did not restore the exact manuscript within 3s; observed UTF-16 length \((restoredText as NSString).length), expected \((sourceText as NSString).length)")
        }
        let finalRecord = try floatingImageRecord(at: metadataURL)
        guard abs(try requiredNumber(finalRecord, "x") - (initialX + 10)) < 0.011,
              abs(try requiredNumber(finalRecord, "y") - initialY) < 0.011,
              (try editorText()) == sourceText else {
            throw Failure(description: "Escape/text-caret navigation changed image geometry or manuscript text")
        }
        try record("escape-restores-text-caret", extra: ["selectionBefore": beforeCaret as Any,
                                                           "selectionAfter": afterCaret as Any,
                                                           "imageX": initialX + 10,
                                                           "imageY": initialY,
                                                           "typingReachedEditor": true,
                                                           "undoRestoredText": true,
                                                           "manuscriptTextSHA256": sourceHash])
        try capture("image-keyboard-caret-restored")

        try hotkey(key: 1, flags: .maskCommand)
        try hotkey(key: 13, flags: .maskCommand)
        let closeDeadline = Date().addingTimeInterval(15)
        while Date() < closeDeadline && windows().contains(where: { title($0).contains(inputURL.lastPathComponent) }) {
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard !windows().contains(where: { title($0).contains(inputURL.lastPathComponent) }) else {
            throw Failure(description: "Could not close image-keyboard fixture before reopening")
        }
        try reopenDisposableDocumentDirectly()
        try waitForWindow(containing: inputURL.lastPathComponent, timeout: 30)
        try focusInputDocumentWindow(timeout: 10)
        let reopened = try floatingImageRecord(at: metadataURL)
        guard abs(try requiredNumber(reopened, "x") - (initialX + 10)) < 0.011,
              abs(try requiredNumber(reopened, "y") - initialY) < 0.011,
              try requiredString(reopened, "id") == imageID,
              try requiredString(reopened, "wrapping") == "square",
              try editorText() == sourceText else {
            throw Failure(description: "Saved/reopened image ID, expected geometry, or manuscript text did not persist")
        }
        try record("image-keyboard-save-reopen", extra: ["imageID": imageID,
                                                           "x": initialX + 10, "y": initialY,
                                                           "manuscriptTextSHA256": sourceHash])
        try capture("image-keyboard-reopened")
    }

    mutating func reopenDisposableDocumentDirectly() throws {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.addsToRecentItems = false
        let semaphore = DispatchSemaphore(value: 0)
        var openError: Error?
        NSWorkspace.shared.open([inputURL], withApplicationAt: appURL, configuration: config) { _, error in
            openError = error
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 20) == .success else {
            throw Failure(description: "Timed out opening the verified disposable document directly in the isolated candidate")
        }
        if let openError {
            throw Failure(description: "Launch Services could not reopen disposable document in candidate: \(openError)")
        }
        try record("document-reopen-requested-directly", extra: ["document": inputURL.path, "application": appURL.path])
    }

    func floatingImageRecord(at metadataURL: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: metadataURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = root["floatingImages"] as? [[String: Any]], images.count == 1 else {
            throw Failure(description: "Expected exactly one floating-image record in disposable native fixture")
        }
        return images[0]
    }

    func requiredString(_ record: [String: Any], _ key: String) throws -> String {
        guard let value = record[key] as? String else { throw Failure(description: "Fixture image metadata is missing string \(key)") }
        return value
    }

    func requiredNumber(_ record: [String: Any], _ key: String) throws -> Double {
        guard let value = record[key] as? NSNumber else { throw Failure(description: "Fixture image metadata is missing numeric \(key)") }
        return value.doubleValue
    }

    mutating func waitForStoredGeometry(metadataURL: URL, imageID: String, x: Double, y: Double, timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var last: [String: Any] = [:]
        while Date() < deadline {
            if let record = try? floatingImageRecord(at: metadataURL), (record["id"] as? String) == imageID {
                last = record
                let storedX = (record["x"] as? NSNumber)?.doubleValue ?? .nan
                let storedY = (record["y"] as? NSNumber)?.doubleValue ?? .nan
                if abs(storedX - x) < 0.011 && abs(storedY - y) < 0.011 { return }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw Failure(description: "Saved image geometry did not reach X=\(x), Y=\(y); last metadata=\(last)")
    }

    mutating func waitForStoredWrapping(metadataURL: URL, imageID: String, wrapping: String,
                                        timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var last: String?
        while Date() < deadline {
            if let record = try? floatingImageRecord(at: metadataURL),
               (record["id"] as? String)?.caseInsensitiveCompare(imageID) == .orderedSame,
               let current = record["wrapping"] as? String {
                last = current
                if current == wrapping { return }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw Failure(description: "Saved image wrapping did not reach \(wrapping); last metadata=\(last ?? "unavailable")")
    }

    mutating func clickVisibleFixtureImage() throws -> CGPoint {
        try activateAndVerify()
        guard let editor = activeElements().first(where: {
            string($0, kAXRoleAttribute as String) == "AXTextArea"
                && string($0, kAXDescriptionAttribute as String) == "Document editor"
        }), let editorPosition = try copy(editor, kAXPositionAttribute as String),
              let editorSize = try copy(editor, kAXSizeAttribute as String),
              let window = activeWindow(), let windowPosition = try copy(window, kAXPositionAttribute as String),
              let windowSize = try copy(window, kAXSizeAttribute as String) else {
            throw Failure(description: "Cannot target image: accessible manuscript editor or active window frame is unavailable")
        }
        var origin = CGPoint.zero, size = CGSize.zero, windowOrigin = CGPoint.zero, windowFrameSize = CGSize.zero
        guard AXValueGetValue(editorPosition as! AXValue, .cgPoint, &origin),
              AXValueGetValue(editorSize as! AXValue, .cgSize, &size),
              AXValueGetValue(windowPosition as! AXValue, .cgPoint, &windowOrigin),
              AXValueGetValue(windowSize as! AXValue, .cgSize, &windowFrameSize) else {
            throw Failure(description: "Cannot decode accessible editor/window geometry")
        }
        // The NSTextView AX frame includes the ruler/text-container origin and
        // can shift when the inspector opens or the page is scrolled. Locate
        // the fixture artwork in a screenshot of the already-verified target
        // window only. Never capture unrelated windows or the full desktop.
        let screenshotName = "canvas-hit-test"
        try capture(screenshotName)
        let screenshotURL = outputURL.appendingPathComponent(screenshotName + ".png")
        guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: screenshotURL)) else {
            throw Failure(description: "Could not decode the target-window screenshot for image hit testing", category: "automation_screenshot")
        }
        let scaleX = CGFloat(bitmap.pixelsWide) / max(1, windowFrameSize.width)
        let scaleY = CGFloat(bitmap.pixelsHigh) / max(1, windowFrameSize.height)
        guard abs(scaleX - scaleY) < 0.02 else { throw Failure(description: "Window screenshot/Accessibility scale is inconsistent: \(scaleX) x \(scaleY)", category: "automation_screenshot") }
        let visibleEditor = CGRect(origin: origin, size: size).intersection(CGRect(origin: windowOrigin, size: windowFrameSize))
        let minX = max(0, Int((visibleEditor.minX - windowOrigin.x) * scaleX))
        let maxX = min(bitmap.pixelsWide, Int((visibleEditor.maxX - windowOrigin.x) * scaleX))
        let minY = max(0, Int((visibleEditor.minY - windowOrigin.y) * scaleY))
        let maxY = min(bitmap.pixelsHigh, Int((visibleEditor.maxY - windowOrigin.y) * scaleY))
        var count = 0, x0 = bitmap.pixelsWide, y0 = bitmap.pixelsHigh, x1 = 0, y1 = 0
        if minX < maxX, minY < maxY {
            for py in minY..<maxY {
                for px in minX..<maxX {
                    guard let color = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.redComponent > 0.85 && color.greenComponent > 0.25
                        && color.greenComponent < 0.75 && color.blueComponent < 0.3 {
                        count += 1; x0 = min(x0, px); x1 = max(x1, px); y0 = min(y0, py); y1 = max(y1, py)
                    }
                }
            }
        }
        guard count > 500, x1 - x0 >= 30, y1 - y0 >= 25 else {
            throw Failure(description: "Fixture artwork was not visible in the manuscript screenshot; orangePixels=\(count), bounds=[\(x0),\(y0),\(x1),\(y1)], editor=\(visibleEditor)")
        }
        let target = CGPoint(x: windowOrigin.x + (CGFloat(x0 + x1) / 2) / scaleX,
                             y: windowOrigin.y + (CGFloat(y0 + y1) / 2) / scaleY)
        guard visibleEditor.contains(target), let source = CGEventSource(stateID: .hidSystemState),
              let moved = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: target, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: target, mouseButton: .left) else {
            throw Failure(description: "Refusing image click outside visible editor frame: target=\(target), visible=\(visibleEditor)")
        }
        // Move the unpressed pointer first. Without this event, AppKit may see
        // the first cursor displacement inside mouse-down tracking as a drag,
        // which changes image position before the keyboard test begins.
        moved.post(tap: .cghidEventTap)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.12)
        return target
    }

    func selectedTextRange() -> [Int]? {
        guard let editor = activeElements().first(where: {
            string($0, kAXRoleAttribute as String) == "AXTextArea"
                && string($0, kAXDescriptionAttribute as String) == "Document editor"
        }), let referenceRef = try? copy(editor, kAXSelectedTextRangeAttribute as String) else { return nil }
        let reference = referenceRef as! AXValue
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(reference, .cfRange, &range) else { return nil }
        return [range.location, range.length]
    }

    mutating func setInspectorCheckbox(label: String, value expected: Bool) throws {
        try activateAndVerify()
        guard let labelElement = activeElements().first(where: {
            string($0, kAXRoleAttribute as String) == "AXStaticText"
                && string($0, kAXValueAttribute as String) == label
        }), let labelPosition = try copy(labelElement, kAXPositionAttribute as String) else {
            throw Failure(description: "Inspector label \(label) is not currently exposed to Accessibility")
        }
        var labelOrigin = CGPoint.zero
        guard AXValueGetValue(labelPosition as! AXValue, .cgPoint, &labelOrigin) else {
            throw Failure(description: "Could not read inspector label geometry for \(label)")
        }
        func associatedCheckbox() -> AXUIElement? {
            activeElements().first(where: { element in
                guard string(element, kAXRoleAttribute as String) == "AXCheckBox",
                      let position = try? copy(element, kAXPositionAttribute as String) else { return false }
                var origin = CGPoint.zero
                guard AXValueGetValue(position as! AXValue, .cgPoint, &origin) else { return false }
                return abs(origin.y - labelOrigin.y) <= 8 && origin.x > labelOrigin.x
            })
        }
        let checkbox = associatedCheckbox()
        guard let checkbox else { throw Failure(description: "No accessible checkbox is associated with inspector label \(label)") }
        let before = string(checkbox, kAXValueAttribute as String)
        let desired = expected ? "1" : "0"
        if before == desired { return }
        let result = AXUIElementPerformAction(checkbox, kAXPressAction as CFString)
        guard result == .success else { throw Failure(description: "AXPress failed (\(result.rawValue)) for \(label) checkbox") }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if let refreshed = associatedCheckbox(), string(refreshed, kAXValueAttribute as String) == desired {
                try record("inspector-checkbox-\(label)", extra: ["before": before, "after": desired,
                                                                     "label": label,
                                                                     "verifiedAtLabelPosition": ["x": labelOrigin.x, "y": labelOrigin.y]])
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw Failure(description: "Inspector checkbox \(label) did not reach value \(desired)")
    }


    mutating func verifyAutomationStudioScript(at scriptURL: URL) throws {
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let oldToken = "From Eden To Armageddon"
        let newToken = "BOLD-AUTOMATION-NEW"
        let initialText = try editorText()
        guard initialText.contains(oldToken) else { throw Failure(description: "Disposable document does not contain the known unique test title") }
        try clickNamed(["Automation Studio"], identifierContains: ["workspace"])
        try waitForAnyWindowState(["Automation Studio", "BOLD Script"], timeout: 20)
        try capture("02-automation-studio")
        try writeJSON(accessibilitySnapshot(), to: outputURL.appendingPathComponent("AX-02-automation-studio.json"))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(script, forType: .string)
        try clickNamed(["Paste From Clipboard"], identifierContains: [])
        try clickNamed(["Validate Script"], identifierContains: [])
        try clickNamed(["Preview Changes"], identifierContains: [])
        let previewDeadline = Date().addingTimeInterval(10)
        while Date() < previewDeadline {
            let visible = activeElements().map { string($0, kAXValueAttribute as String) + " " + string($0, kAXTitleAttribute as String) }.joined(separator: "\n")
            if visible.localizedCaseInsensitiveContains("planned edits") { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        try capture("03-automation-preview")
        try writeJSON(accessibilitySnapshot(), to: outputURL.appendingPathComponent("AX-03-automation-preview.json"))
        guard activeElements().contains(where: {
            string($0, kAXTitleAttribute as String).localizedCaseInsensitiveContains("Apply Changes")
                || string($0, kAXDescriptionAttribute as String).localizedCaseInsensitiveContains("Apply Changes")
        }) else {
            throw Failure(description: "Automation Studio did not expose the Apply Changes approval after preview")
        }
        try clickNamed(["Manuscript"], identifierContains: ["workspace"])
        guard try editorText() == initialText else { throw Failure(description: "The manuscript changed before author approval") }
        try record("automation-validated-and-previewed", extra: ["documentUnchangedBeforeApproval": true])
        try clickNamed(["Automation Studio"], identifierContains: ["workspace"])
        try clickNamed(["Apply Changes"], identifierContains: [])
        try clickNamed(["Manuscript"], identifierContains: ["workspace"])
        let changedText = try editorText()
        guard changedText.contains(newToken), !changedText.contains(oldToken) else {
            throw Failure(description: "Approved automation did not apply the expected exact replacement")
        }
        try record("automation-applied", extra: ["expectedTextFound": true])
        try capture("04-automation-applied")
        try clickNamed(["Automation Studio"], identifierContains: ["workspace"])
        try clickNamed(["Undo Automation"], identifierContains: [])
        try clickNamed(["Manuscript"], identifierContains: ["workspace"])
        guard try editorText() == initialText else { throw Failure(description: "Undo Automation did not restore the exact pre-automation manuscript") }
        try record("automation-undo-verified", extra: ["exactOriginalTextRestored": true])
        try capture("05-automation-undone")
        try hotkey(key: 6, flags: [.maskCommand, .maskShift])
        let redoDeadline = Date().addingTimeInterval(10)
        while Date() < redoDeadline {
            if try editorText().contains(newToken) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard try editorText().contains(newToken) else { throw Failure(description: "Native Redo did not restore the approved automation") }
        try hotkey(key: 1, flags: .maskCommand)
        Thread.sleep(forTimeInterval: 1)
        try record("automation-redo-and-save-verified")
        try hotkey(key: 13, flags: .maskCommand)
        let closeDeadline = Date().addingTimeInterval(15)
        while Date() < closeDeadline && windows().contains(where: { title($0).contains(inputURL.lastPathComponent) }) { Thread.sleep(forTimeInterval: 0.2) }
        guard !windows().contains(where: { title($0).contains(inputURL.lastPathComponent) }) else { throw Failure(description: "Could not close disposable project after automation save") }
        try openDocument()
        try waitForWindow(containing: inputURL.lastPathComponent, timeout: 60)
        try focusInputDocumentWindow(timeout: 10)
        guard try editorText().contains(newToken) else { throw Failure(description: "Saved automation was absent after reopening the native project") }
        try record("automation-save-reopen-verified", extra: ["expectedTextFound": true])
        try capture("06-automation-reopened")
    }

    mutating func startOrResolveApp() throws {
        let start = ProcessInfo.processInfo.systemUptime
        var match = runningApp()
        startupMode = match == nil ? "launched-by-harness" : "reused-existing-exact-instance"
        if match == nil {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            let semaphore = DispatchSemaphore(value: 0)
            var launchError: Error?
            var launchedPID: pid_t = 0
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, error in
                if let error { launchError = error }
                if let app { launchedPID = app.processIdentifier }
                semaphore.signal()
            }
            guard semaphore.wait(timeout: .now() + 30) == .success else {
                throw Failure(description: "Timed out launching exact candidate at \(appURL.path)")
            }
            if let launchError { throw launchError }
            pid = launchedPID
            // NSWorkspace's launch completion can precede registration in
            // `runningApplications`. Resolve the exact PID/path with a bounded
            // retry instead of treating that normal launch race as a failed
            // app launch. This matters especially on a first launch, when
            // AppKit may already be presenting its document-open panel.
            let registrationDeadline = Date().addingTimeInterval(20)
            while match == nil && Date() < registrationDeadline {
                if let launched = NSRunningApplication(processIdentifier: launchedPID),
                   launched.bundleIdentifier == bundleID,
                   launched.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path
                    == appURL.resolvingSymlinksInPath().standardizedFileURL.path {
                    match = launched
                } else {
                    match = runningApp()
                }
                if match == nil { Thread.sleep(forTimeInterval: 0.25) }
            }
        }
        guard let app = match else { throw Failure(description: "Could not resolve a running instance from exact bundle path \(appURL.path)") }
        pid = app.processIdentifier
        guard app.bundleIdentifier == bundleID,
              app.bundleURL?.standardizedFileURL.path == appURL.path else {
            throw Failure(description: "Resolved process does not match the requested app bundle")
        }
        appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 2)
        try activateAndVerify()
        startupResolutionSeconds = ProcessInfo.processInfo.systemUptime - start
    }

    func runningApp() -> NSRunningApplication? {
        // LaunchServices can briefly omit a live, frontmost process from its
        // shared enumeration (notably while first-launch document panels are
        // registering). Once we have the PID, resolve that exact process
        // directly before falling back to the global list.
        if let byPID = NSRunningApplication(processIdentifier: pid),
           !byPID.isTerminated,
           byPID.bundleIdentifier == bundleID,
           byPID.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path
            == appURL.resolvingSymlinksInPath().standardizedFileURL.path {
            return byPID
        }
        return NSWorkspace.shared.runningApplications.first {
            !$0.isTerminated
                && $0.bundleIdentifier == bundleID
                && $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path
                    == appURL.resolvingSymlinksInPath().standardizedFileURL.path
        }
    }

    mutating func activateAndVerify() throws {
        guard let app = runningApp() else { throw Failure(description: "Target app exited or no longer matches its PID and bundle path; process diagnostics: \(processDescription())") }
        // `isActive` can remain true after the harness or another application
        // takes the foreground. Always request activation unless LaunchServices
        // confirms this exact PID is already the frontmost application.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            _ = app.activate(options: [.activateAllWindows])
            // activate() can return while LaunchServices still leaves a
            // previously active application behind the current foreground
            // app. `open -a` is a supported LaunchServices foreground request
            // and does not require Apple Events automation permission.
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", appURL.path]
                try process.run()
                process.waitUntilExit()
            }
        }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let active = NSWorkspace.shared.frontmostApplication,
               active.processIdentifier == pid,
               let exact = NSRunningApplication(processIdentifier: pid),
               !exact.isTerminated,
               exact.bundleIdentifier == bundleID,
               exact.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path
                == appURL.resolvingSymlinksInPath().standardizedFileURL.path { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw Failure(description: "Target app could not be activated or verified as frontmost. \(processDescription())")
    }

    func processDescription() -> String {
        let app = runningApp()
        let process = NSRunningApplication(processIdentifier: pid)
        return "pid=\(pid), bundle=\(app?.bundleIdentifier ?? process?.bundleIdentifier ?? "<not-running>"), path=\(app?.bundleURL?.path ?? process?.bundleURL?.path ?? "<none>"), terminated=\(process?.isTerminated.description ?? "unknown"), active=\(app?.isActive.description ?? process?.isActive.description ?? "false")"
    }

    func windows() -> [AXUIElement] {
        guard appElement != nil else { return [] }
        return (try? copy(appElement, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
    }

    func copy(_ element: AXUIElement, _ name: String) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard error == .success else { return nil }
        return value
    }

    func string(_ element: AXUIElement, _ name: String) -> String {
        guard let v = try? copy(element, name) ?? nil else { return "" }
        if let value = v as? String { return value }
        if let value = v as? NSNumber { return value.stringValue }
        return ""
    }

    func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let v = try? copy(element, kAXChildrenAttribute as String) ?? nil else { return [] }
        return v as? [AXUIElement] ?? []
    }

    func allElements(_ roots: [AXUIElement], limit: Int = 4000) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var stack = Array(roots.reversed())
        while let element = stack.popLast(), result.count < limit {
            result.append(element)
            let kids = children(element)
            if !kids.isEmpty { stack.append(contentsOf: kids.reversed()) }
        }
        return result
    }

    func title(_ window: AXUIElement) -> String { string(window, kAXTitleAttribute as String) }

    func activeWindow() -> AXUIElement? {
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused) == .success,
           let focused { return unsafeBitCast(focused, to: AXUIElement.self) }
        var main: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &main) == .success,
           let main { return unsafeBitCast(main, to: AXUIElement.self) }
        return windows().first
    }

    func activeElements() -> [AXUIElement] { activeWindow().map { allElements([$0]) } ?? [] }

    mutating func verifyEditorUndoRedoSaveReopen() throws {
        guard let editor = activeElements().first(where: {
            string($0, kAXRoleAttribute as String) == "AXTextArea"
                && string($0, kAXDescriptionAttribute as String) == "Document editor"
        }), let original = try copy(editor, kAXValueAttribute as String) as? String else {
            throw Failure(description: "The manuscript editor and its accessible text value were not available")
        }
        let initialHash = SHA256.hash(data: Data(original.utf8)).map { String(format: "%02x", $0) }.joined()
        try clickElementCenter(editor, expectedRole: "AXTextArea", expectedDescription: "Document editor")
        guard let focused = focusedElement(),
              string(focused, kAXRoleAttribute as String) == "AXTextArea",
              string(focused, kAXDescriptionAttribute as String) == "Document editor" else {
            throw Failure(description: "Refusing to type: confirmed focus is not Document editor; focused role=\(focusedElement().map { string($0,kAXRoleAttribute as String) } ?? "<none>"), description=\(focusedElement().map { string($0,kAXDescriptionAttribute as String) } ?? "<none>")")
        }
        var selection = CFRange(location: (original as NSString).length, length: 0)
        guard let selectionValue = AXValueCreate(.cfRange, &selection) else {
            throw Failure(description: "Could not create a native accessibility text-selection range")
        }
        let selected = AXUIElementSetAttributeValue(editor, kAXSelectedTextRangeAttribute as CFString, selectionValue)
        guard selected == .success else { throw Failure(description: "Could not place the insertion point at manuscript end (AXError \(selected.rawValue))") }
        let marker = " BOLD-GUI-UNDO-REDO-\(UUID().uuidString)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(marker, forType: .string)
        let firstEditStart = ProcessInfo.processInfo.systemUptime
        try hotkey(key: 9, flags: .maskCommand)
        try waitForEditorText(contains: marker, present: true, timeout: 10)
        try record("first-accepted-edit", extra: ["marker": marker,
                                                    "latencySeconds": ProcessInfo.processInfo.systemUptime - firstEditStart,
                                                    "beforeUTF16Length": selection.location,
                                                    "afterUTF16Length": (try editorText()).utf16.count])
        try capture("01-manuscript-edited")
        try hotkey(key: 6, flags: .maskCommand)
        try waitForEditorText(contains: marker, present: false, timeout: 10)
        try record("manuscript-undo-verified")
        try hotkey(key: 6, flags: [.maskCommand, .maskShift])
        try waitForEditorText(contains: marker, present: true, timeout: 10)
        try record("manuscript-redo-verified")
        try hotkey(key: 6, flags: .maskCommand)
        try waitForEditorText(contains: marker, present: false, timeout: 10)
        guard try editorText() == original else { throw Failure(description: "Undo did not restore the exact original accessible manuscript text") }
        try hotkey(key: 1, flags: .maskCommand)
        Thread.sleep(forTimeInterval: 2)
        try record("manuscript-save-after-undo", extra: ["accessibleTextSHA256": initialHash])
        try capture("01-manuscript-saved")

        try hotkey(key: 13, flags: .maskCommand)
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline && windows().contains(where: { title($0).contains(inputURL.lastPathComponent) }) {
            Thread.sleep(forTimeInterval: 0.2)
        }
        guard !windows().contains(where: { title($0).contains(inputURL.lastPathComponent) }) else {
            throw Failure(description: "Cmd+W did not close the disposable manuscript window")
        }
        let reopenStart = ProcessInfo.processInfo.systemUptime
        try openDocument()
        try waitForWindow(containing: inputURL.lastPathComponent, timeout: 60)
        try focusInputDocumentWindow(timeout: 10)
        let reopenObservedSeconds = ProcessInfo.processInfo.systemUptime - reopenStart
        let reopened = try editorText()
        let reopenedHash = SHA256.hash(data: Data(reopened.utf8)).map { String(format: "%02x", $0) }.joined()
        guard reopenedHash == initialHash else { throw Failure(description: "Save/reopen changed accessible manuscript text: before \(initialHash), after \(reopenedHash)") }
        try record("manuscript-reopen-verified", extra: ["accessibleTextSHA256": reopenedHash,
                                                              "matchesBeforeEdit": reopenedHash == initialHash,
                                                              "reopenObservedSeconds": reopenObservedSeconds])
        try capture("01-manuscript-reopened")
    }

    mutating func closeInputDocumentWindow(saveBeforeClose: Bool) throws {
        guard let window = windows().first(where: { title($0).contains(inputURL.lastPathComponent) }) else {
            throw Failure(description: "Refusing to close a window that is not the verified disposable input: \(inputURL.lastPathComponent)")
        }
        if saveBeforeClose {
            try hotkey(key: 1, flags: .maskCommand) // Save the disposable document before releasing its renderer.
            Thread.sleep(forTimeInterval: 0.4)
        }
        var closeReference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &closeReference) == .success,
              let closeReference else {
            throw Failure(description: "Verified disposable document window has no accessible close control")
        }
        let closeResult = AXUIElementPerformAction(unsafeBitCast(closeReference, to: AXUIElement.self), kAXPressAction as CFString)
        guard closeResult == .success else {
            throw Failure(description: "Could not close verified disposable document window; AXError \(closeResult.rawValue)")
        }
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if !windows().contains(where: { title($0).contains(inputURL.lastPathComponent) }) {
                try record("document-closed", extra: ["document": inputURL.path, "savedBeforeClose": saveBeforeClose])
                finalInputIdentity = try artifactIdentity(inputURL)
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw Failure(description: "The disposable document window remained after the native close action; inspect any save/recovery dialog before retrying")
    }

    func editorText() throws -> String {
        guard let editor = activeElements().first(where: { string($0, kAXDescriptionAttribute as String) == "Document editor" }),
              let text = try copy(editor, kAXValueAttribute as String) as? String else {
            throw Failure(description: "Accessible manuscript text could not be read from the active document window")
        }
        return text
    }

    func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    func clickElementCenter(_ element: AXUIElement, expectedRole: String, expectedDescription: String) throws {
        guard let window = activeWindow() else { throw Failure(description: "The target document window is unavailable") }
        // Ask Accessibility to focus the actual editor first. Some SwiftUI
        // TextEditor instances do not expose AXPress, so this settable focus
        // attribute is preferred; coordinate fallback below is confined to
        // the editor's visible bounds inside this exact application window.
        _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              string(element, kAXRoleAttribute as String) == expectedRole,
              string(element, kAXDescriptionAttribute as String) == expectedDescription,
              let positionRef = try copy(element, kAXPositionAttribute as String),
              let sizeRef = try copy(element, kAXSizeAttribute as String),
              let windowPositionRef = try copy(window, kAXPositionAttribute as String),
              let windowSizeRef = try copy(window, kAXSizeAttribute as String) else {
            throw Failure(description: "Refusing pointer input: focused application or target accessibility element is wrong")
        }
        var origin = CGPoint.zero, size = CGSize.zero
        var windowOrigin = CGPoint.zero, windowSize = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size),
              AXValueGetValue(windowPositionRef as! AXValue, .cgPoint, &windowOrigin),
              AXValueGetValue(windowSizeRef as! AXValue, .cgSize, &windowSize), size.width > 8, size.height > 8 else {
            throw Failure(description: "Refusing pointer input: manuscript editor has no valid accessible frame")
        }
        // Large-document NSTextViews expose the whole laid-out document, so
        // their AX height may be tens of thousands of points. Restrict the
        // click to the intersection with the verified active document window.
        let visibleEditor = CGRect(origin: origin, size: size).intersection(CGRect(origin: windowOrigin, size: windowSize))
        guard !visibleEditor.isNull, visibleEditor.width > 8, visibleEditor.height > 8 else {
            throw Failure(description: "Refusing pointer input: manuscript editor bounds do not intersect the active document window; editor=\(origin) \(size), window=\(windowOrigin) \(windowSize)")
        }
        let point = CGPoint(x: visibleEditor.midX, y: visibleEditor.midY)
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            throw Failure(description: "Could not construct a click for the confirmed manuscript editor bounds")
        }
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.15)
    }

    mutating func waitForEditorText(contains marker: String, present: Bool, timeout seconds: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if (try? editorText().contains(marker)) == present { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw Failure(description: "The manuscript editor did not verify marker present=\(present) within \(seconds)s")
    }

    func typeText(_ value: String) throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
            throw Failure(description: "Refusing to type because the target app is not frontmost or CGEvent could not be created")
        }
        let units = Array(value.utf16)
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        event.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)!
        up.post(tap: .cghidEventTap)
    }

    mutating func scrollManuscript(to position: Double) throws {
        try activateAndVerify()
        guard let scrollbar = activeElements().first(where: {
            string($0, kAXRoleAttribute as String) == "AXScrollBar"
                && (try? copy($0, kAXEnabledAttribute as String) as? Bool) == true
        }) else {
            throw Failure(description: "Cannot scroll manuscript: the enabled manuscript scroll bar is unavailable")
        }
        let status = AXUIElementSetAttributeValue(scrollbar, kAXValueAttribute as CFString,
                                                  NSNumber(value: min(0.9, max(0.1, position))))
        guard status == .success else {
            throw Failure(description: "Accessibility could not set the manuscript scroll position (AX error \(status.rawValue))")
        }
        Thread.sleep(forTimeInterval: 0.4)
        let actual = string(scrollbar, kAXValueAttribute as String)
        guard let value = Double(actual), abs(value - position) < 0.02 else {
            throw Failure(description: "Manuscript scroll did not reach the requested position; expected \(position), got \(actual)")
        }
    }

    mutating func navigateProof(to page: Int) throws {
        guard (1...expectedProofPages).contains(page) else {
            throw Failure(description: "Proof page \(page) is outside the expected \(expectedProofPages)-page document")
        }
        guard let field = activeElements().first(where: {
            string($0, kAXRoleAttribute as String) == "AXTextField"
                && string($0, kAXDescriptionAttribute as String) == "Go to proof page"
        }) else {
            throw Failure(description: "Proof viewer is not the active Accessibility state; refusing to navigate a page")
        }
        let priorAXSignature = visibleProofContentSignature()
        let priorOCR = try latestProofScreenshotOCR()
        let setValue = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, String(page) as CFTypeRef)
        if setValue != .success {
            // Some AppKit/SwiftUI text fields expose a read-only AX value. Use
            // the element's verified bounds as a fallback, but do not send
            // Return: the proof sheet's default-action Done button can dismiss
            // the viewer. Go is activated exactly once below.
            try clickElementCenter(field, expectedRole: "AXTextField", expectedDescription: "Go to proof page")
            guard let focused = focusedElement(), string(focused, kAXDescriptionAttribute as String) == "Go to proof page" else {
                throw Failure(description: "Proof page field did not take focus; refusing keyboard input", category: "automation_focus")
            }
            try hotkey(key: 0, flags: .maskCommand)
            try typeText(String(page))
        }
        let inputDeadline = Date().addingTimeInterval(3)
        while Date() < inputDeadline {
            if let current = activeElements().first(where: {
                string($0, kAXRoleAttribute as String) == "AXTextField"
                    && string($0, kAXDescriptionAttribute as String) == "Go to proof page"
            }), string(current, kAXValueAttribute as String) == String(page) { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard activeElements().contains(where: {
            string($0, kAXRoleAttribute as String) == "AXTextField"
                && string($0, kAXDescriptionAttribute as String) == "Go to proof page"
                && string($0, kAXValueAttribute as String) == String(page)
        }) else {
            throw Failure(description: "Proof viewer field did not accept page \(page); target viewer/state changed before Go", category: "automation_state_transition")
        }
        try clickNamed(["Go"], identifierContains: [])

        let deadline = Date().addingTimeInterval(10)
        var attempts = 0
        while Date() < deadline {
            let currentField = activeElements().first(where: {
                string($0, kAXRoleAttribute as String) == "AXTextField"
                    && string($0, kAXDescriptionAttribute as String) == "Go to proof page"
            })
            guard currentField != nil else {
                throw Failure(description: "The Print Proof viewer closed or left the active AX state after Go for page \(page). Current windows=\(windowSummary())", category: "application_state_transition")
            }
            let visiblePages = visibleProofPageNumbers()
            let axSignature = visibleProofContentSignature()
            let screenshotName = "proof-page-\(page)-verify-\(attempts)"
            try capture(screenshotName)
            let screenshotURL = outputURL.appendingPathComponent(screenshotName + ".png")
            let ocr = try proofScreenshotOCR(at: screenshotURL)
            let ocrChanged = !ocr.isEmpty && ocr != priorOCR
            let contentChanged = !axSignature.isEmpty && axSignature != priorAXSignature
            let sameSinglePage = page == 1 && expectedProofPages == 1 && !ocr.isEmpty
            if visiblePages.contains(page) || contentChanged || ocrChanged || sameSinglePage {
                let verification: String
                if visiblePages.contains(page) { verification = "visible AX page label" }
                else if contentChanged { verification = "visible PDF text accessibility signature changed" }
                else if ocrChanged { verification = "window screenshot OCR signature changed" }
                else { verification = "single-page proof canvas contains OCR-recognized text; screenshot retained for visual review" }
                try record("proof-page-\(page)", extra: ["pageEntry": page, "visiblePages": visiblePages,
                                                               "pageCount": expectedProofPages,
                                                               "verification": verification,
                                                               "ocrCharacterCount": ocr.count,
                                                               "screenshot": screenshotURL.path,
                                                               "screenshotSHA256": try fileSHA256(screenshotURL)])
                return
            }
            attempts += 1
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw Failure(description: "Print Proof stayed open but page \(page) could not be verified from visible page labels or page-content OCR. Windows=\(windowSummary())", category: "automation_page_render_unverified")
    }

    func latestProofScreenshotOCR() throws -> String {
        let file = outputURL.appendingPathComponent("03-print-proof-page-1.png")
        guard FileManager.default.fileExists(atPath: file.path) else { return "" }
        return try proofScreenshotOCR(at: file)
    }

    func proofScreenshotOCR(at url: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure(description: "Could not decode the target-window proof screenshot for OCR: \(url.path)", category: "automation_screenshot")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        var lines: [(midY: Double, minX: Double, text: String)] = []
        for observation in request.results ?? [] {
            let box = observation.boundingBox
            guard box.midX >= 0.15, box.midX <= 0.88, box.midY >= 0.12, box.midY <= 0.86,
                  let text = observation.topCandidates(1).first?.string else { continue }
            lines.append((Double(box.midY), Double(box.minX), text))
        }
        lines.sort { lhs, rhs in lhs.midY == rhs.midY ? lhs.minX < rhs.minX : lhs.midY > rhs.midY }
        return lines.map { $0.text }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fileSHA256(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return sha256(data)
    }

    func visibleProofPageNumbers() -> [Int] {
        let expression = try! NSRegularExpression(pattern: #"Page\s*•\s*(\d+)"#)
        guard let window = activeWindow(),
              let positionRef = try? copy(window, kAXPositionAttribute as String),
              let sizeRef = try? copy(window, kAXSizeAttribute as String) else { return [] }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return [] }
        let visibleWindow = CGRect(origin: origin, size: size)
        return Array(Set(activeElements().flatMap { element -> [Int] in
            guard ["AXStaticText", "AXButton", "AXImage"].contains(string(element, kAXRoleAttribute as String)),
                  let framePositionRef = try? copy(element, kAXPositionAttribute as String),
                  let frameSizeRef = try? copy(element, kAXSizeAttribute as String) else { return [] }
            var frameOrigin = CGPoint.zero, frameSize = CGSize.zero
            guard AXValueGetValue(framePositionRef as! AXValue, .cgPoint, &frameOrigin),
                  AXValueGetValue(frameSizeRef as! AXValue, .cgSize, &frameSize),
                  visibleWindow.intersects(CGRect(origin: frameOrigin, size: frameSize)) else { return [] }
            let text = string(element, kAXValueAttribute as String) + " " + string(element, kAXTitleAttribute as String)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return expression.matches(in: text, range: range).compactMap { match in
                guard let numberRange = Range(match.range(at: 1), in: text) else { return nil }
                return Int(text[numberRange])
            }
        })).sorted()
    }

    func visibleProofContentSignature() -> String {
        guard let window = activeWindow(),
              let positionRef = try? copy(window, kAXPositionAttribute as String),
              let sizeRef = try? copy(window, kAXSizeAttribute as String) else { return "no-proof-window" }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return "invalid-proof-window" }
        let visibleWindow = CGRect(origin: origin, size: size)
        let visibleText = activeElements().compactMap { element -> String? in
            guard string(element, kAXRoleAttribute as String) == "AXStaticText",
                  let framePositionRef = try? copy(element, kAXPositionAttribute as String),
                  let frameSizeRef = try? copy(element, kAXSizeAttribute as String) else { return nil }
            var frameOrigin = CGPoint.zero, frameSize = CGSize.zero
            guard AXValueGetValue(framePositionRef as! AXValue, .cgPoint, &frameOrigin),
                  AXValueGetValue(frameSizeRef as! AXValue, .cgSize, &frameSize),
                  visibleWindow.intersects(CGRect(origin: frameOrigin, size: frameSize)) else { return nil }
            let value = string(element, kAXValueAttribute as String)
            guard !value.isEmpty, !value.hasPrefix("Page Page •") else { return nil }
            return value
        }
        return SHA256.hash(data: Data(visibleText.joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    func accessibilitySnapshot() -> [String: Any] {
        let rows = activeElements().map { element -> [String: Any] in
            let isDocumentEditor = string(element, kAXRoleAttribute as String) == "AXTextArea"
                && string(element, kAXDescriptionAttribute as String) == "Document editor"
            let rawValue = isDocumentEditor ? "" : string(element, kAXValueAttribute as String)
            let value: Any = isDocumentEditor
                ? "<omitted; editor text is hashed by the scenario>"
                : rawValue.count > 512 ? String(rawValue.prefix(512)) + "…" : rawValue
            var row: [String: Any] = ["role": string(element, kAXRoleAttribute as String),
             "title": string(element, kAXTitleAttribute as String),
             "description": string(element, kAXDescriptionAttribute as String),
             "identifier": string(element, "AXIdentifier"),
             "value": value,
             "enabled": (try? copy(element, kAXEnabledAttribute as String) as? NSNumber)?.boolValue as Any? ?? NSNull()]
            if !isDocumentEditor && rawValue.count > 512 { row["valueSHA256"] = sha256(Data(rawValue.utf8)); row["valueCharacterCount"] = rawValue.count }
            if let pRef = try? copy(element, kAXPositionAttribute as String),
               let sRef = try? copy(element, kAXSizeAttribute as String) {
                let p = pRef as! AXValue, s = sRef as! AXValue
                var point = CGPoint.zero, size = CGSize.zero
                if AXValueGetValue(p, .cgPoint, &point), AXValueGetValue(s, .cgSize, &size) {
                    row["frame"] = [point.x, point.y, size.width, size.height]
                }
            }
            return row
        }
        return ["application": executableIdentity.merging(["pid": pid]) { _, new in new },
                "window": activeWindow().map(title) ?? "<none>", "elements": rows]
    }

    mutating func openDocument() throws {
        if windows().contains(where: { title($0).contains(inputURL.lastPathComponent) }) {
            documentWasAlreadyOpen = true
            try record("disposable-document-already-open", extra: ["document": inputURL.path])
            return
        }
        if !windows().contains(where: { title($0) == "Open" }) {
            try hotkey(key: 31, flags: .maskCommand)
            try waitForWindow(containing: "Open", timeout: 15)
        }
        try hotkey(key: 5, flags: [.maskCommand, .maskShift])
        let field = try waitForElement(identifier: "PathTextField", timeout: 10)
        let setError = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, inputURL.path as CFTypeRef)
        guard setError == .success else { throw Failure(description: "Could not set the native Go to Folder path field (AXError \(setError.rawValue))") }
        try hotkey(key: 36, flags: [])
        _ = try waitForElement(identifier: "OKButton", timeout: 15)
        let selected = allElements(windows()).contains {
            [string($0, kAXTitleAttribute as String), string($0, kAXDescriptionAttribute as String),
             string($0, "AXIdentifier"), string($0, kAXValueAttribute as String)]
                .contains { $0.contains(inputURL.lastPathComponent) }
        }
        guard selected else { throw Failure(description: "Open panel did not expose the selected disposable proof name; refusing to activate Open") }
        let open = try waitForElement(identifier: "OKButton", timeout: 5)
        let result = AXUIElementPerformAction(open, kAXPressAction as CFString)
        guard result == .success else { throw Failure(description: "Native Open button action failed with AXError \(result.rawValue)") }
        try record("open-panel-submitted", extra: ["selected": inputURL.lastPathComponent,
                                                    "userSelectedAccess": true])
    }

    mutating func clickNamed(_ names: [String], identifierContains: [String]) throws {
        try activateAndVerify()
        let elements = activeElements()
        let actionableRoles: Set<String> = ["AXButton", "AXMenuButton", "AXRadioButton", "AXCheckBox", "AXPopUpButton", "AXMenuItem", "AXTabGroup"]
        func matches(_ element: AXUIElement, exact: Bool) -> Bool {
            let semanticValues = [string(element, kAXTitleAttribute as String),
                                  string(element, kAXDescriptionAttribute as String),
                                  string(element, "AXIdentifier")]
            let searchableValues = semanticValues + [string(element, kAXHelpAttribute as String)]
            let nameMatch = names.contains { name in
                (exact ? semanticValues : searchableValues).contains {
                    exact ? $0.caseInsensitiveCompare(name) == .orderedSame : $0.localizedCaseInsensitiveContains(name)
                }
            }
            let idMatch = identifierContains.contains { needle in semanticValues.contains { $0.localizedCaseInsensitiveContains(needle) } }
            return actionableRoles.contains(string(element, kAXRoleAttribute as String)) && (nameMatch || idMatch)
        }
        guard let initialTarget = elements.first(where: { matches($0, exact: true) })
                ?? elements.first(where: { matches($0, exact: false) }) else {
            try capture("failure-missing-control")
            throw Failure(description: "Could not find accessible control \(names.joined(separator: ", ")). Current windows: \(windowSummary())", category: "accessibility_control_missing")
        }
        let role = string(initialTarget, kAXRoleAttribute as String)
        let targetLabel = [string(initialTarget, kAXTitleAttribute as String), string(initialTarget, kAXDescriptionAttribute as String), string(initialTarget, "AXIdentifier")].filter { !$0.isEmpty }.joined(separator: " | ")
        var target = initialTarget
        let enabledDeadline = Date().addingTimeInterval(30)
        while let enabled = try? copy(target, kAXEnabledAttribute as String) as? NSNumber,
              !enabled.boolValue, Date() < enabledDeadline {
            // SwiftUI reports AXPress success even when a transition guard
            // makes a control a no-op. Wait for its actual enabled state,
            // refreshing the reference because views can be rebuilt.
            Thread.sleep(forTimeInterval: 0.1)
            let refreshed = activeElements().first { element in
                actionableRoles.contains(string(element, kAXRoleAttribute as String))
                    && [string(element, kAXTitleAttribute as String),
                        string(element, kAXDescriptionAttribute as String),
                        string(element, "AXIdentifier")].contains { $0 == targetLabel || targetLabel.contains($0) }
            }
            if let refreshed { target = refreshed }
        }
        if let enabled = try? copy(target, kAXEnabledAttribute as String) as? NSNumber,
           !enabled.boolValue {
            throw Failure(description: "Control stayed disabled for 30s: \(targetLabel)", category: "accessibility_control_disabled")
        }
        let selected = (try? copy(target, kAXSelectedAttribute as String) as? NSNumber)?.boolValue == true
        let selectedRadio = role == "AXRadioButton" && string(target, kAXValueAttribute as String) == "1"
        if selected || selectedRadio {
            try record("control-already-selected", extra: ["role": role, "control": targetLabel])
            return
        }
        var result = AXUIElementPerformAction(target, kAXPressAction as CFString)
        if result != .success {
            // Accessibility references can go stale after menus/workspace changes.
            for _ in 1...2 {
                Thread.sleep(forTimeInterval: 0.3)
                let refreshed = activeElements().first { element in
                    guard actionableRoles.contains(string(element, kAXRoleAttribute as String)) else { return false }
                    let values = [string(element, kAXTitleAttribute as String), string(element, kAXDescriptionAttribute as String),
                                  string(element, kAXHelpAttribute as String), string(element, "AXIdentifier")]
                    return names.contains { name in values.contains { $0.localizedCaseInsensitiveContains(name) } }
                        || identifierContains.contains { needle in values.contains { $0.localizedCaseInsensitiveContains(needle) } }
                }
                if let refreshed { result = AXUIElementPerformAction(refreshed, kAXPressAction as CFString) }
                if result == .success { break }
            }
        }
        if result != .success, runningApp() == nil {
            throw Failure(description: "The target application exited while pressing \(targetLabel) (AX error \(result.rawValue)); process diagnostics: \(processDescription())", category: "application_exit")
        }
        guard result == .success else { throw Failure(description: "AXPress failed (\(result.rawValue)) on \(targetLabel)", category: "accessibility_action_failed") }
        try record("control-pressed", extra: ["role": role, "control": targetLabel])
    }

    mutating func waitForElement(identifier: String, timeout seconds: TimeInterval) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let found = activeElements().first(where: { string($0, "AXIdentifier") == identifier }) { return found }
            if runningApp() == nil { throw Failure(description: "App process exited while waiting for \(identifier): \(processDescription())") }
            Thread.sleep(forTimeInterval: 0.25)
        }
        try capture("timeout-\(identifier)")
        throw Failure(description: "Timed out after \(seconds)s waiting for accessibility ID \(identifier). Windows: \(windowSummary()); process: \(processDescription())")
    }

    mutating func waitForWindow(containing token: String, timeout seconds: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if windows().contains(where: { title($0).localizedCaseInsensitiveContains(token) }) { return }
            if runningApp() == nil { throw Failure(description: "App process exited while waiting for window '\(token)': \(processDescription())") }
            Thread.sleep(forTimeInterval: 0.25)
        }
        try capture("timeout-window")
        throw Failure(description: "Timed out waiting for window containing '\(token)'. Current windows: \(windowSummary()); process: \(processDescription())")
    }

    mutating func waitForControl(description: String, role: String, timeout seconds: TimeInterval) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let found = activeElements().first(where: {
                string($0, kAXRoleAttribute as String) == role
                    && string($0, kAXDescriptionAttribute as String) == description
            }) { return found }
            if runningApp() == nil { throw Failure(description: "App exited while waiting for \(role):\(description): \(processDescription())", category: "application_exit") }
            Thread.sleep(forTimeInterval: 0.15)
        }
        try capture("timeout-control-\(description.replacingOccurrences(of: " ", with: "-"))")
        throw Failure(description: "Timed out waiting for unique control role=\(role), description=\(description); windows=\(windowSummary())", category: "application_state_or_accessibility")
    }

    mutating func waitForAccessibleText(prefix: String, timeout seconds: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if activeElements().contains(where: {
                string($0, kAXRoleAttribute as String) == "AXStaticText"
                    && string($0, kAXValueAttribute as String).hasPrefix(prefix)
            }) { return }
            if runningApp() == nil { throw Failure(description: "App exited while waiting for visible text '\(prefix)': \(processDescription())", category: "application_exit") }
            Thread.sleep(forTimeInterval: 0.2)
        }
        try capture("timeout-text-\(prefix.replacingOccurrences(of: " ", with: "-"))")
        throw Failure(description: "Timed out waiting for visible static text prefix '\(prefix)' in current window; titles=\(windowSummary())", category: "application_state_or_accessibility")
    }

    mutating func waitForAnyWindowState(_ needles: [String], timeout seconds: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let elements = activeElements()
            if elements.contains(where: { e in
                let role = string(e, kAXRoleAttribute as String)
                let stable = [string(e,kAXTitleAttribute as String), string(e,kAXDescriptionAttribute as String), string(e,"AXIdentifier")]
                let shortValue = role == "AXStaticText" || role == "AXTextField" ? [string(e,kAXValueAttribute as String)] : []
                return (stable + shortValue).contains { value in needles.contains { value.localizedCaseInsensitiveContains($0) } }
            }) { return }
            if runningApp() == nil { throw Failure(description: "App process exited during UI state wait: \(processDescription())") }
            Thread.sleep(forTimeInterval: 0.3)
        }
        try capture("timeout-state")
        throw Failure(description: "Timed out waiting for UI evidence \(needles). Windows: \(windowSummary())")
    }

    func windowSummary() -> String { windows().map(title).joined(separator: "; ") }

    mutating func drag3DViewport() throws {
        try activateAndVerify()
        let visible = activeElements()
        let missingCover = visible.contains {
            string($0, kAXRoleAttribute as String) == "AXStaticText"
                && string($0, kAXValueAttribute as String).localizedCaseInsensitiveContains("No Print Full Wrap Cover")
        }
        if missingCover {
            throw Failure(description: "3D Studio opened, but this disposable document has no valid print full-wrap cover; create/import one before testing the physical renderer", category: "fixture_precondition_missing")
        }
        guard let viewport = visible.first(where: { string($0,"AXIdentifier") == "bookstudio.viewport" }) else {
            throw Failure(description: "3D Studio opened but the real viewport is absent from the target app accessibility tree; inspect the saved target-window screenshot to distinguish a missing fixture precondition from an application failure", category: "application_state_or_accessibility")
        }
        guard let positionRef = try copy(viewport,kAXPositionAttribute as String),
              let sizeRef = try copy(viewport,kAXSizeAttribute as String) else {
            throw Failure(description: "The 3D viewport has no accessible bounds; refusing coordinate input")
        }
        let positionValue = positionRef as! AXValue
        let sizeValue = sizeRef as! AXValue
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionValue,.cgPoint,&origin), AXValueGetValue(sizeValue,.cgSize,&size), size.width > 250, size.height > 250 else {
            throw Failure(description: "The 3D viewport frame is invalid; refusing coordinate input")
        }
        try capture("02-3d-before-rotation")
        let start = CGPoint(x: origin.x + size.width * 0.52, y: origin.y + size.height * 0.54)
        let end = CGPoint(x: start.x + min(120, size.width * 0.2), y: start.y + min(55, size.height * 0.12))
        try mouseDrag(from: start, to: end)
        Thread.sleep(forTimeInterval: 1)
        guard runningApp() != nil, windows().contains(where: { title($0).localizedCaseInsensitiveContains("3D") || allElements([$0]).contains(where: { string($0,"AXIdentifier") == "bookstudio.viewport" }) }) else {
            throw Failure(description: "The 3D Studio window disappeared after the rotation gesture")
        }
        try capture("03-rotated")
        try record("viewport-drag", extra: ["viewportFrame": [origin.x, origin.y, size.width, size.height],
                                            "from": [start.x,start.y], "to": [end.x,end.y],
                                            "verification": "target app and viewport remained present after drag"])
    }

    func element(descriptionContains needle: String, role expectedRole: String? = nil) -> AXUIElement? {
        activeElements().first { element in
            (expectedRole == nil || string(element, kAXRoleAttribute as String) == expectedRole!)
                && string(element, kAXDescriptionAttribute as String).localizedCaseInsensitiveContains(needle)
        }
    }

    func spreadSummary() throws -> String {
        guard let summary = activeElements().first(where: {
            string($0, kAXRoleAttribute as String) == "AXStaticText"
                && string($0, kAXValueAttribute as String).localizedCaseInsensitiveContains("Spread")
                && string($0, kAXValueAttribute as String).localizedCaseInsensitiveContains("of")
        }) else { throw Failure(description: "Current accessibility state has no manuscript spread/page-count label") }
        return string(summary, kAXValueAttribute as String)
    }

    func extractPageCount(from summary: String) throws -> Int {
        let regex = try NSRegularExpression(pattern: "\\bof\\s+(\\d+)\\b", options: [.caseInsensitive])
        let ns = summary as NSString
        guard let match = regex.firstMatch(in: summary, range: NSRange(location: 0, length: ns.length)),
              let value = Int(ns.substring(with: match.range(at: 1))), value > 0 else {
            throw Failure(description: "Could not read page count from native spread label: \(summary)")
        }
        return value
    }

    mutating func waitForSpreadChange(from previous: String, timeout seconds: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let current = try? spreadSummary(), current != previous { return current }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw Failure(description: "Spread navigation did not change the visible page state from '\(previous)'")
    }

    mutating func navigateToPage(_ page: Int, expectedCount: Int) throws -> String {
        guard (1...expectedCount).contains(page) else {
            throw Failure(description: "Requested page \(page) is outside 1...\(expectedCount)")
        }
        var current = try spreadSummary()
        guard try extractPageCount(from: current) == expectedCount else {
            throw Failure(description: "Expected \(expectedCount) pages, observed \(current)")
        }
        if page == 1 {
            if current.localizedCaseInsensitiveContains("inside cover") { return current }
            try clickNamed(["First spread"], identifierContains: [])
            return try waitForSpreadChange(from: current, timeout: 20)
        }
        if page == expectedCount {
            if let pages = try? spreadPages(from: current), pages.1 == expectedCount { return current }
            try clickNamed(["Last spread"], identifierContains: [])
            return try waitForSpreadChange(from: current, timeout: 20)
        }
        // Start a middle-page check at the first spread, then exercise the
        // actual forward page-turn control. Direct endpoint buttons are used
        // for first/final pages because they are explicit, accessible controls.
        if !current.localizedCaseInsensitiveContains("inside cover") {
            try clickNamed(["First spread"], identifierContains: [])
            current = try waitForSpreadChange(from: current, timeout: 20)
        }
        if current.localizedCaseInsensitiveContains("inside cover") {
            try clickNamed(["Next Spread"], identifierContains: [])
            current = try waitForSpreadChange(from: current, timeout: 8)
            Thread.sleep(forTimeInterval: 0.65)
        }
        // The visible page-entry field exposes AXValue but is not a functional
        // editor in the installed SwiftUI view: setting AXValue succeeds while
        // the rendered spread stays put. Use the actual Previous/Next Spread
        // controls and require the native page label to change after every step.
        // This is slower than pretending an AX assignment navigated, but tests
        // the advertised customer control and leaves a verifiable trace.
        for _ in 0..<expectedCount {
            let pair = try spreadPages(from: current)
            if pair.0 <= page && page <= pair.1 { return current }
            let direction = page < pair.0 ? "Previous Spread" : "Next Spread"
            try clickNamed([direction], identifierContains: [])
            current = try waitForSpreadChange(from: current, timeout: 8)
            // `moveSpread` updates the label at transition start, then disables
            // all navigation for 520 ms while the leaf animation is active.
            // Wait through that explicit guard before asking for another step.
            Thread.sleep(forTimeInterval: 0.65)
            guard try extractPageCount(from: current) == expectedCount else {
                throw Failure(description: "Page count changed during navigation: \(current)")
            }
        }
        throw Failure(description: "Page \(page) was not reached after \(expectedCount) verified spread transitions; current=\(current)")
    }

    func spreadPages(from summary: String) throws -> (Int, Int) {
        let regex = try NSRegularExpression(pattern: "·\\s*(\\d+)\\s*/\\s*(\\d+)\\s+of\\s+\\d+", options: [])
        let ns = summary as NSString
        guard let match = regex.firstMatch(in: summary, range: NSRange(location: 0, length: ns.length)),
              let first = Int(ns.substring(with: match.range(at: 1))),
              let second = Int(ns.substring(with: match.range(at: 2))) else {
            throw Failure(description: "Could not read visible page pair from spread label: \(summary)")
        }
        return (first, second)
    }

    mutating func waitForControlValue(description: String, value expected: String, role: String, timeout seconds: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let control = element(descriptionContains: description, role: role), string(control,kAXValueAttribute as String) == expected { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        let actual = element(descriptionContains: description, role: role).map { string($0,kAXValueAttribute as String) } ?? "<missing>"
        throw Failure(description: "Control '\(description)' value did not become \(expected); observed \(actual)")
    }

    func hotkey(key: CGKeyCode, flags: CGEventFlags) throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw Failure(description: "Refusing keyboard event because the target app is not frontmost")
        }
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            throw Failure(description: "Could not create keyboard event")
        }
        down.flags = flags; up.flags = flags
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }

    func mouseDrag(from: CGPoint, to: CGPoint) throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw Failure(description: "Refusing mouse event because the target app is not frontmost")
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else { throw Failure(description: "Could not create mouse event source") }
        func event(_ type: CGEventType, _ p: CGPoint, _ button: CGMouseButton) throws {
            guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { throw Failure(description: "Could not create mouse gesture event") }
            e.post(tap: .cghidEventTap)
        }
        try event(.mouseMoved, from, .left); try event(.leftMouseDown, from, .left)
        for step in 1...6 {
            let t = CGFloat(step) / 6
            try event(.leftMouseDragged, CGPoint(x: from.x + (to.x-from.x)*t, y: from.y + (to.y-from.y)*t), .left)
        }
        try event(.leftMouseUp, to, .left)
    }

    mutating func capture(_ name: String) throws {
        try activateAndVerify()
        guard let axWindow = activeWindow() else {
            throw Failure(description: "No focused or main Accessibility window exists for target PID \(pid)", category: "automation_window_resolution")
        }
        let axTitle = title(axWindow)
        let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let owned = onScreen.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid }
        // Modal proof/health windows can have an empty AX title while the
        // process still owns several document windows. Prefer the exact
        // disposable document window before falling back to the AX title;
        // otherwise an equally sized stale window could be captured.
        let documentMatches = owned.filter { row in
            let name = row[kCGWindowName as String] as? String ?? ""
            return name.localizedCaseInsensitiveContains(inputURL.lastPathComponent)
        }
        let accessibilityMatches = owned.filter { row in
            let name = row[kCGWindowName as String] as? String ?? ""
            return !axTitle.isEmpty && (name == axTitle || name.localizedCaseInsensitiveContains(axTitle) || axTitle.localizedCaseInsensitiveContains(name))
        }
        let candidates: [[String: Any]]
        if !documentMatches.isEmpty {
            candidates = documentMatches
        } else if !accessibilityMatches.isEmpty {
            candidates = accessibilityMatches
        } else if owned.count == 1 {
            candidates = owned
        } else {
            let names = owned.map { $0[kCGWindowName as String] as? String ?? "<untitled>" }
            throw Failure(description: "Refusing ambiguous screenshot: neither the disposable document title nor AX title matched an on-screen window; owned windows=\(names)", category: "automation_window_resolution")
        }
        guard let selected = candidates.max(by: { windowArea($0) < windowArea($1) }),
              let windowNumber = selected[kCGWindowNumber as String] as? NSNumber,
              windowNumber.uint32Value != 0 else {
            let names = owned.map { $0[kCGWindowName as String] as? String ?? "<untitled>" }
            throw Failure(description: "Could not resolve an on-screen CGWindow owned by PID \(pid) for AX window '\(axTitle)'. Owned windows=\(names)", category: "automation_window_resolution")
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw Failure(description: "Target app lost foreground before scoped screenshot capture", category: "automation_focus")
        }
        let path = outputURL.appendingPathComponent(name + ".png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-l", windowNumber.stringValue, path.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path), !data.isEmpty else {
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw Failure(description: "Window-only macOS screenshot failed for \(name), CGWindowID=\(windowNumber), AX title='\(axTitle)': \(error)", category: "environment_screenshot")
        }
        let row: [String: Any] = ["file": path.path, "sha256": sha256(data), "bytes": data.count,
                                  "pid": pid, "bundleID": bundleID, "windowID": windowNumber.uint32Value,
                                  "axWindowTitle": axTitle, "cgWindowTitle": selected[kCGWindowName as String] as? String ?? "",
                                  "requestedDocument": inputURL.lastPathComponent,
                                  "windowMatch": !documentMatches.isEmpty ? "disposable-document-title" : (!accessibilityMatches.isEmpty ? "accessibility-title" : "single-target-process-window"),
                                  "captureScope": "target-window-only"]
        screenshotEvidence.append(row)
        try writeJSON(["application": ["pid": pid, "bundleID": bundleID, "revision": expectedRevision],
                       "screenshots": screenshotEvidence], to: outputURL.appendingPathComponent("SCREENSHOTS.json"))
    }

    func windowArea(_ row: [String: Any]) -> Double {
        guard let bounds = row[kCGWindowBounds as String] as? [String: NSNumber] else { return 0 }
        return (bounds["Width"]?.doubleValue ?? 0) * (bounds["Height"]?.doubleValue ?? 0)
    }

    func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func runTool(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw Failure(description: "\(executable) \(arguments.joined(separator: " ")) failed: \(String(data: errorData, encoding: .utf8) ?? "")", category: "candidate_identity")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func artifactIdentity(_ url: URL) throws -> [String: Any] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw Failure(description: "Acceptance input disappeared before hashing: \(url.path)", category: "fixture_integrity")
        }
        if !isDirectory.boolValue {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return ["path": url.path, "kind": "file", "bytes": data.count, "sha256": sha256(data)]
        }
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])
        var files: [(String, String, Int)] = []
        while let child = enumerator?.nextObject() as? URL {
            let values = try child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let data = try Data(contentsOf: child, options: [.mappedIfSafe])
            files.append((String(child.path.dropFirst(url.path.count + 1)), sha256(data), data.count))
        }
        files.sort { $0.0 < $1.0 }
        let canonical = files.map { "\($0.0)\0\($0.1)\0\($0.2)\n" }.joined()
        return ["path": url.path, "kind": "directory-package", "fileCount": files.count,
                "bytes": files.reduce(0) { $0 + $1.2 }, "sha256": sha256(Data(canonical.utf8)),
                "files": files.map { ["path": $0.0, "sha256": $0.1, "bytes": $0.2] }]
    }

    mutating func record(_ name: String, extra: [String: Any] = [:]) throws {
        try activateAndVerify()
        var row: [String: Any] = ["scenarioID": scenarioID, "step": name,
                                  "expectedState": name, "observedState": activeWindow().map(title) ?? "<none>",
                                  "time": ISO8601DateFormatter().string(from: Date()),
                                  "pid": pid, "bundleID": bundleID, "bundlePath": appURL.path,
                                  "sourceRevision": expectedRevision, "frontmost": true,
                                  "activeWindow": activeWindow().map(title) ?? "<none>",
                                  "windowTitles": windows().map(title)]
        extra.forEach { row[$0.key] = $0.value }
        eventLog.append(row)
        try writeJSON(["scenarioID": scenarioID, "application": executableIdentity.merging(["pid": pid]) { _, new in new },
                       "inputIdentityBefore": initialInputIdentity, "events": eventLog], to: outputURL.appendingPathComponent("TRACE.json"))
    }

    mutating func writeFailure(_ error: Error) throws {
        let appIsFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        if appIsFrontmost, runningApp() != nil {
            try? writeJSON(accessibilitySnapshot(), to: outputURL.appendingPathComponent("AX-failure.json"))
        }
        var screenshot: String?
        if appIsFrontmost, runningApp() != nil {
            let name = "failure-\(Int(Date().timeIntervalSince1970))"
            if (try? capture(name)) != nil { screenshot = name + ".png" }
        }
        let report: [String: Any] = [
            "scenarioID": scenarioID,
            "status": "FAILED",
            "failureAssessment": "Requires human triage using category, trace, AX snapshot, and target-window screenshot; harness does not label every timeout a product defect.",
            "application": executableIdentity.merging(["pid": pid]) { _, new in new },
            "failure": String(describing: error),
            "failureClassification": (error as? Failure)?.category ?? "unexpected_harness_error",
            "inputIdentityBefore": initialInputIdentity,
            "inputIdentityAfter": finalInputIdentity,
            "processDiagnostics": processDescription(),
            "windowTitles": windowSummary(),
            "appFrontmost": appIsFrontmost,
            "failureScreenshot": screenshot as Any? ?? NSNull(),
            "screenshots": screenshotEvidence,
            "steps": eventLog
        ]
        try writeJSON(report, to: outputURL.appendingPathComponent("REPORT.json"))
    }

    func writeJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: jsonSafe(object), options: [.prettyPrinted,.sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    func jsonSafe(_ value: Any) -> Any {
        if let number = value as? NSNumber {
            return number.doubleValue.isFinite ? number : NSNull()
        }
        if let values = value as? [Any] { return values.map(jsonSafe) }
        if let values = value as? [String: Any] {
            return values.mapValues(jsonSafe)
        }
        return value
    }
}

do { try NativeGUIAcceptance.main() }
catch {
    FileHandle.standardError.write(Data("GUI ACCEPTANCE FAILED: \(error)\n".utf8))
    exit(2)
}
