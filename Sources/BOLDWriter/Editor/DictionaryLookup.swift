import AppKit
import Foundation

enum DictionaryLookup {
    static func term(
        in string: String,
        selectedRange: NSRange
    ) -> String? {
        let nsString =
            string as NSString

        guard
            selectedRange.location != NSNotFound,
            selectedRange.location <= nsString.length
        else {
            return nil
        }

        if selectedRange.length > 0 {
            let safeLength =
                min(
                    selectedRange.length,
                    nsString.length - selectedRange.location
                )

            guard safeLength > 0 else {
                return nil
            }

            let selected =
                nsString.substring(
                    with:
                        NSRange(
                            location:
                                selectedRange.location,
                            length:
                                safeLength
                        )
                )
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

            return selected.isEmpty
                ? nil
                : selected
        }

        guard nsString.length > 0 else {
            return nil
        }

        guard
            let expression =
                try? NSRegularExpression(
                    pattern:
                        #"\p{L}[\p{L}\p{M}\p{N}'’\-]*|\p{N}+"#
                )
        else {
            return nil
        }

        let caret =
            min(
                selectedRange.location,
                nsString.length
            )

        let matches =
            expression.matches(
                in:
                    string,
                range:
                    NSRange(
                        location:
                            0,
                        length:
                            nsString.length
                    )
            )

        let containing =
            matches.first {
                let range =
                    $0.range

                return caret >= range.location
                    && caret < NSMaxRange(range)
            }

        let immediatelyBefore =
            matches.last {
                NSMaxRange($0.range)
                    == caret
            }

        guard
            let match =
                containing
                ?? immediatelyBefore
        else {
            return nil
        }

        let value =
            nsString.substring(
                with:
                    match.range
            )
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        return value.isEmpty
            ? nil
            : value
    }

    static func dictionaryURL(
        for term: String
    ) -> URL? {
        let trimmed =
            term.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        guard !trimmed.isEmpty else {
            return nil
        }

        var allowed =
            CharacterSet
                .urlPathAllowed

        allowed.remove(
            charactersIn:
                "/?#"
        )

        guard
            let encoded =
                trimmed.addingPercentEncoding(
                    withAllowedCharacters:
                        allowed
                )
        else {
            return nil
        }

        return URL(
            string:
                "dict://\(encoded)"
        )
    }
}

@MainActor
extension EditorController {
    @discardableResult
    func lookUpInDictionary() -> Bool {
        guard
            let textView,
            let term =
                DictionaryLookup.term(
                    in:
                        textView.string,
                    selectedRange:
                        textView.selectedRange()
                ),
            let url =
                DictionaryLookup.dictionaryURL(
                    for:
                        term
                )
        else {
            return false
        }

        return NSWorkspace.shared.open(
            url
        )
    }
}
