import AppKit

@MainActor
enum CommentPrompt {
    static func show(title: String, initialText: String = "", confirmTitle: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 340, height: 100))
        editor.string = initialText
        editor.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        editor.isRichText = false
        editor.drawsBackground = true
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 5, height: 5)
        let scroll = NSScrollView(frame: editor.frame)
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = editor
        alert.accessoryView = scroll
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return editor.string
    }
}
