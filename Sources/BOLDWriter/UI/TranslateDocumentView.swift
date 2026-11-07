import AppKit
import Foundation
import SwiftUI
import Translation

struct DocumentTranslationLanguage:
    Identifiable,
    Hashable {

    let id: String
    let name: String

    static let catalog: [Self] = [
        .init(id: "ar", name: "Arabic"),
        .init(id: "zh-Hans", name: "Chinese (Simplified)"),
        .init(id: "zh-Hant", name: "Chinese (Traditional)"),
        .init(id: "nl", name: "Dutch"),
        .init(id: "en", name: "English"),
        .init(id: "fr", name: "French"),
        .init(id: "de", name: "German"),
        .init(id: "hi", name: "Hindi"),
        .init(id: "id", name: "Indonesian"),
        .init(id: "it", name: "Italian"),
        .init(id: "ja", name: "Japanese"),
        .init(id: "ko", name: "Korean"),
        .init(id: "pl", name: "Polish"),
        .init(id: "pt", name: "Portuguese"),
        .init(id: "ru", name: "Russian"),
        .init(id: "es", name: "Spanish"),
        .init(id: "th", name: "Thai"),
        .init(id: "tr", name: "Turkish"),
        .init(id: "uk", name: "Ukrainian"),
        .init(id: "vi", name: "Vietnamese")
    ]
}

enum DocumentTranslationBuilder {
    static func attributedReplacement(
        source: NSAttributedString,
        translatedText: String
    ) -> NSAttributedString {
        guard
            source.length > 0
        else {
            return NSAttributedString(
                string:
                    translatedText,
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )
        }

        let sourceParagraphs =
            paragraphRanges(
                in:
                    source.string
            )

        let translatedParagraphs =
            translatedText
                .components(
                    separatedBy:
                        "\n"
                )

        guard
            sourceParagraphs.count
                == translatedParagraphs.count
        else {
            return NSAttributedString(
                string:
                    translatedText,
                attributes:
                    visualAttributes(
                        source.attributes(
                            at:
                                0,
                            effectiveRange:
                                nil
                        )
                    )
            )
        }

        let result =
            NSMutableAttributedString()

        for (
            index,
            paragraph
        ) in translatedParagraphs
            .enumerated() {

            let sourceRange =
                sourceParagraphs[index]

            let attributeIndex =
                min(
                    sourceRange.location,
                    source.length - 1
                )

            let attributes =
                visualAttributes(
                    source.attributes(
                        at:
                            attributeIndex,
                        effectiveRange:
                            nil
                    )
                )

            result.append(
                NSAttributedString(
                    string:
                        paragraph,
                    attributes:
                        attributes
                )
            )

            if index
                < translatedParagraphs.count - 1 {

                result.append(
                    NSAttributedString(
                        string:
                            "\n",
                        attributes:
                            attributes
                    )
                )
            }
        }

        return result
    }

    private static func paragraphRanges(
        in string: String
    ) -> [NSRange] {
        let ns =
            string
                as NSString

        guard
            ns.length > 0
        else {
            return [
                NSRange(
                    location:
                        0,
                    length:
                        0
                )
            ]
        }

        var ranges: [NSRange] =
            []

        var location =
            0

        while location < ns.length {
            let range =
                ns.paragraphRange(
                    for:
                        NSRange(
                            location:
                                location,
                            length:
                                0
                        )
                )

            ranges.append(
                range
            )

            let next =
                NSMaxRange(
                    range
                )

            if next <= location {
                break
            }

            location =
                next
        }

        if string.hasSuffix(
            "\n"
        ) {
            ranges.append(
                NSRange(
                    location:
                        ns.length,
                    length:
                        0
                )
            )
        }

        return ranges
    }

    private static func visualAttributes(
        _ source:
            [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        let keys:
            Set<NSAttributedString.Key> = [
                .font,
                .foregroundColor,
                .backgroundColor,
                .paragraphStyle,
                .kern,
                .underlineStyle,
                .underlineColor,
                .strikethroughStyle,
                .strikethroughColor,
                .baselineOffset,
                .ligature,
                .obliqueness,
                .expansion,
                .writingDirection
            ]

        return source.filter {
            keys.contains(
                $0.key
            )
        }
    }
}

@available(macOS 15.0, *)
struct TranslateDocumentView:
    View {

    let source: NSAttributedString
    let onApply:
        (
            NSAttributedString,
            String
        ) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State
    private var targetLanguageID =
        "es"

    @State
    private var configuration:
        TranslationSession
            .Configuration?

    @State
    private var translatedText =
        ""

    @State
    private var isTranslating =
        false

    @State
    private var errorMessage:
        String?

    private var selectedLanguage:
        DocumentTranslationLanguage {

        DocumentTranslationLanguage
            .catalog
            .first {
                $0.id
                    == targetLanguageID
            }
            ?? DocumentTranslationLanguage
                .catalog[0]
    }

    var body:
        some View {

        VStack(
            alignment:
                .leading,
            spacing:
                14
        ) {
            Text(
                "Translate Document"
            )
            .font(
                .title2
                    .bold()
            )

            Text(
                "The source language is detected automatically. Translation uses Apple's system Translation service on this Mac."
            )
            .font(
                .caption
            )
            .foregroundStyle(
                .secondary
            )

            Picker(
                "Translate to",
                selection:
                    $targetLanguageID
            ) {
                ForEach(
                    DocumentTranslationLanguage
                        .catalog
                ) {
                    language in

                    Text(
                        language.name
                    )
                    .tag(
                        language.id
                    )
                }
            }

            HStack {
                Button(
                    "Cancel"
                ) {
                    dismiss()
                }
                .keyboardShortcut(
                    .cancelAction
                )

                Spacer()

                Button {
                    beginTranslation()
                } label: {
                    if isTranslating {
                        ProgressView()
                            .controlSize(
                                .small
                            )
                    } else {
                        Text(
                            translatedText
                                .isEmpty
                                ? "Translate"
                                : "Translate Again"
                        )
                    }
                }
                .disabled(
                    isTranslating
                        || source.length == 0
                )
            }

            if !translatedText
                .isEmpty {

                Divider()

                Text(
                    "Preview"
                )
                .font(
                    .headline
                )

                ScrollView {
                    Text(
                        translatedText
                    )
                    .textSelection(
                        .enabled
                    )
                    .frame(
                        maxWidth:
                            .infinity,
                        alignment:
                            .leading
                    )
                    .padding(
                        10
                    )
                }
                .frame(
                    minHeight:
                        220,
                    maxHeight:
                        380
                )
                .background(
                    Color(
                        nsColor:
                            .textBackgroundColor
                    )
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius:
                            6
                    )
                )

                HStack {
                    Spacer()

                    Button(
                        "Apply Translation"
                    ) {
                        let replacement =
                            DocumentTranslationBuilder
                                .attributedReplacement(
                                    source:
                                        source,
                                    translatedText:
                                        translatedText
                                )

                        onApply(
                            replacement,
                            selectedLanguage.name
                        )

                        dismiss()
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .keyboardShortcut(
                        .defaultAction
                    )
                }
            }

            if let errorMessage {
                Text(
                    errorMessage
                )
                .font(
                    .caption
                )
                .foregroundStyle(
                    .red
                )
                .textSelection(
                    .enabled
                )
            }
        }
        .padding(
            20
        )
        .frame(
            width:
                560
        )
        .translationTask(
            configuration
        ) {
            session in

            guard
                isTranslating
            else {
                return
            }

            do {
                let response =
                    try await session.translate(
                        source.string
                    )

                translatedText =
                    response.targetText

                errorMessage =
                    nil
            } catch {
                translatedText =
                    ""

                errorMessage =
                    error.localizedDescription
            }

            isTranslating =
                false
        }
    }

    private func beginTranslation() {
        translatedText =
            ""

        errorMessage =
            nil

        isTranslating =
            true

        let target =
            Locale.Language(
                identifier:
                    targetLanguageID
            )

        configuration =
            nil

        Task {
            await Task.yield()

            configuration =
                TranslationSession
                    .Configuration(
                        source:
                            nil,
                        target:
                            target
                    )
        }
    }
}

struct TranslateDocumentUnavailableView:
    View {

    @Environment(\.dismiss)
    private var dismiss

    var body:
        some View {

        VStack(
            alignment:
                .leading,
            spacing:
                14
        ) {
            Text(
                "Translate Document"
            )
            .font(
                .title2
                    .bold()
            )

            Text(
                "System document translation requires macOS 15 or later."
            )

            HStack {
                Spacer()

                Button(
                    "Close"
                ) {
                    dismiss()
                }
                .keyboardShortcut(
                    .defaultAction
                )
            }
        }
        .padding(
            20
        )
        .frame(
            width:
                420
        )
    }
}
