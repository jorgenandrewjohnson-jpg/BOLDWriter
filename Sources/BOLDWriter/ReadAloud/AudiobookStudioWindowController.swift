import AppKit
import SwiftUI

@MainActor
enum AudiobookStudioWindowController {
    private final class WindowDelegate: NSObject, NSWindowDelegate {
        let key: ObjectIdentifier
        init(key: ObjectIdentifier) { self.key = key }
        func windowWillClose(_ notification: Notification) {
            AudiobookStudioWindowController.windows[key] = nil
        }
    }

    private struct Entry {
        var window: NSWindow
        var delegate: WindowDelegate
    }

    private static var windows: [ObjectIdentifier: Entry] = [:]

    static func show(
        document: BOLDWriterDocument,
        editor: EditorController,
        reader: ReadAloudManager,
        sourceURL: URL?
    ) {
        let key = ObjectIdentifier(document)
        if let entry = windows[key] {
            let window = entry.window
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Audiobook Studio — \(document.metadata.title)"
        window.minSize = NSSize(width: 1000, height: 680)
        window.isReleasedWhenClosed = false
        let studio = AudiobookStudioView(
            document: document,
            editor: editor,
            reader: reader,
            sourceURL: sourceURL,
            onClose: { window.performClose(nil) }
        )
        window.contentViewController = NSHostingController(rootView: studio)
        window.center()
        let delegate = WindowDelegate(key: key)
        window.delegate = delegate
        windows[key] = Entry(window: window, delegate: delegate)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
