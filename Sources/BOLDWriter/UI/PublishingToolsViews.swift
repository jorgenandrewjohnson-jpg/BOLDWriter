import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PublishingTOCCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var mode: PublishingTOCMode = .printBook
    @State var depth = 3
    @State var title = "Contents"
    @State var showTitle = true
    @State var leader: PublishingTOCLeader = .dots
    @State var suppressTopLevelPageNumbers = false
    @State var fontName = "Georgia"
    @State var fontSize = 12.0
    @State var boldTopLevel = true
    @State var indentationPerLevel = 18.0
    @State var lineSpacing = 3.0
    @State var numberAlignment = "right"
    var onInsert: (PublishingTOCSettings) -> Void
    var onUpdate: (PublishingTOCSettings) -> Void

    private var settings: PublishingTOCSettings {
        var value=PublishingTOCSettings(fieldID:UUID(),mode:mode,maximumHeadingLevel:depth)
        value.title=title; value.showTitle=showTitle; value.leader=leader
        value.suppressTopLevelPageNumbers=suppressTopLevelPageNumbers; value.fontName=fontName; value.fontSize=fontSize; value.boldTopLevel=boldTopLevel; value.indentationPerLevel=indentationPerLevel; value.lineSpacing=lineSpacing; value.numberAlignment=numberAlignment
        return value
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Table of Contents").font(.title2.bold())
            Picker("Style",selection:$mode) { ForEach(PublishingTOCMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            Form {
                Picker("Heading depth",selection:$depth) { ForEach(1...6,id:\.self) { Text("Heading 1–\($0)").tag($0) } }
                Toggle("Show title",isOn:$showTitle)
                if showTitle { TextField("Title",text:$title) }
                if mode != .kindle {
                    Picker("Leader",selection:$leader) { ForEach(PublishingTOCLeader.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                    Picker("Page-number alignment",selection:$numberAlignment) { Text("Right").tag("right");Text("Left").tag("left") }
                    Toggle("Suppress page number for Heading 1",isOn:$suppressTopLevelPageNumbers)
                    TextField("Font",text:$fontName)
                    HStack { Text("Size"); Slider(value:$fontSize,in:8...24,step:0.5); Text("\(fontSize, specifier:"%.1f") pt") }
                    Toggle("Bold top level",isOn:$boldTopLevel)
                    HStack { Text("Indent per level"); Slider(value:$indentationPerLevel,in:8...40,step:1); Text("\(indentationPerLevel, specifier:"%.0f") pt") }
                    HStack { Text("Line spacing"); Slider(value:$lineSpacing,in:0...12,step:1); Text("\(lineSpacing, specifier:"%.0f") pt") }
                }
            }
            GroupBox("Preview") {
                VStack(alignment:.leading,spacing:4) {
                    if showTitle { Text(title).font(.headline) }
                    Text("Chapter One" + (mode == .kindle ? "" : (leader.glyph.isEmpty ? "     1" : "  \(String(repeating:leader.glyph,count:22))  1")))
                    Text("    First Section" + (mode == .kindle ? "" : "     4")).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(8)
            }
            HStack {
                Button("Update Selected TOC") { onUpdate(settings); dismiss() }
                Spacer()
                Button("Cancel",role:.cancel) { dismiss() }
                Button("Insert") { onInsert(settings); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width:520)
    }
}
