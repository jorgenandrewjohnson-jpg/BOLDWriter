import AppKit

struct FootnoteContinuation: Equatable {
    var id: UUID
    var number: Int
    var remaining: String
}

struct PageFootnoteFragment: Equatable {
    var id: UUID
    var number: Int
    var text: String
    var continued: Bool
    var height: CGFloat
}

struct PageFootnotePlan: Equatable {
    var fragments: [PageFootnoteFragment] = []
    var outgoing: [FootnoteContinuation] = []
    var reservedHeight: CGFloat = 0
}

/// Derived layout only. No page ownership or continuation cache enters the document format.
enum PageFootnotes {
    static let font = NSFont.systemFont(ofSize: 10.5)
    static var lineHeight: CGFloat { ceil(font.boundingRectForFont.height + 2) }
    static var separatorHeight: CGFloat { ceil(lineHeight * 0.7) + 0.5 + ceil(lineHeight * 0.6) }
    static var noteGap: CGFloat { ceil(lineHeight * 0.25) }

    static func notes(on range: NSRange, from notes: [Footnote]) -> [(Footnote, Int)] {
        notes.enumerated().compactMap { index, note in
            NSLocationInRange(note.location, range) ? (note, index + 1) : nil
        }
    }

    static func plan(
        geometry: PageGeometry,
        references: [(Footnote, Int)],
        incoming: [FootnoteContinuation]
    ) throws -> PageFootnotePlan {
        guard !references.isEmpty || !incoming.isEmpty else { return PageFootnotePlan() }
        let maximum = max(lineHeight + separatorHeight,
                          geometry.contentSize.height - max(72, geometry.contentSize.height * 0.35))
        var available = maximum - separatorHeight
        var plan = PageFootnotePlan()
        let width = geometry.contentSize.width
        let minimumNew = CGFloat(references.count) * (lineHeight + noteGap)

        func append(_ item: FootnoteContinuation, continued: Bool, protected: CGFloat) -> FootnoteContinuation? {
            let gap = plan.fragments.isEmpty ? 0 : noteGap
            let allowance = available - protected - gap
            guard allowance >= lineHeight else { return item }
            let label = "\(item.number). " + (continued ? "(continued) " : "")
            let body = item.remaining as NSString
            let count = fittingPrefix(of: body, after: label, width: width, height: allowance)
            guard count > 0 || body.length == 0 else { return item }
            let consumed = body.substring(to: count)
            let rendered = label + consumed
            let height = measuredHeight(rendered, width: width)
            guard height <= allowance + 0.5 else { return item }
            available -= gap + height
            plan.fragments.append(PageFootnoteFragment(id: item.id, number: item.number,
                                                        text: rendered, continued: continued, height: height))
            if count < body.length {
                return FootnoteContinuation(id: item.id, number: item.number,
                                            remaining: body.substring(from: count))
            }
            return nil
        }

        // Continuations precede new references, but may not consume the first
        // line required by a reference on this physical page.
        for item in incoming {
            if let remainder = append(item, continued: true, protected: minimumNew) {
                plan.outgoing.append(remainder)
            }
        }
        for (index, pair) in references.enumerated() {
            let (note, number) = pair
            let item = FootnoteContinuation(id: note.id, number: number, remaining: note.text)
            let protected = CGFloat(references.count - index - 1) * (lineHeight + noteGap)
            let before = plan.fragments.count
            if let remainder = append(item, continued: false, protected: protected) {
                plan.outgoing.append(remainder)
            }
            guard plan.fragments.count > before else {
                throw WriterError.message("Too many footnotes begin on one page to fit a note line beneath the manuscript.")
            }
        }
        plan.reservedHeight = separatorHeight
            + plan.fragments.map(\.height).reduce(0, +)
            + CGFloat(max(0, plan.fragments.count - 1)) * noteGap
        return plan
    }

    private static func measuredHeight(_ value: String, width: CGFloat) -> CGFloat {
        let bounds = (value as NSString).boundingRect(
            with: NSSize(width: max(1, width), height: 100_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return max(lineHeight, ceil(bounds.height))
    }

    private static func fittingPrefix(of body: NSString, after label: String,
                                      width: CGFloat, height: CGFloat) -> Int {
        var low = 0
        var high = min(body.length, 256)
        while high < body.length,
              measuredHeight(label + body.substring(to: high), width: width) <= height + 0.5 {
            low = high
            high = min(body.length, high * 2)
        }
        while low < high {
            let middle = low + (high - low + 1) / 2
            if measuredHeight(label + body.substring(to: middle), width: width) <= height + 0.5 {
                low = middle
            } else {
                high = middle - 1
            }
        }
        // Avoid splitting a UTF-16 surrogate pair at a page boundary.
        if low > 0 && low < body.length {
            let last = body.character(at: low - 1)
            let next = body.character(at: low)
            if (0xD800...0xDBFF).contains(last) && (0xDC00...0xDFFF).contains(next) {
                low = measuredHeight(label + body.substring(to: low + 1), width: width) <= height + 0.5
                    ? low + 1 : low - 1
            }
        }
        return low
    }

    static func draw(_ plan: PageFootnotePlan, in geometry: PageGeometry) {
        guard !plan.fragments.isEmpty else { return }
        let x = geometry.contentOrigin.x
        let top = geometry.contentOrigin.y + geometry.contentSize.height - plan.reservedHeight
        let ruleY = top + ceil(lineHeight * 0.7)
        NSColor.darkGray.setStroke()
        let rule = NSBezierPath()
        rule.lineWidth = 0.5
        rule.move(to: NSPoint(x: x, y: ruleY))
        rule.line(to: NSPoint(x: x + geometry.contentSize.width / 3, y: ruleY))
        rule.stroke()
        var y = top + separatorHeight
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
        for fragment in plan.fragments {
            (fragment.text as NSString).draw(
                with: NSRect(x: x, y: y, width: geometry.contentSize.width, height: fragment.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            )
            y += fragment.height + noteGap
        }
    }
}
