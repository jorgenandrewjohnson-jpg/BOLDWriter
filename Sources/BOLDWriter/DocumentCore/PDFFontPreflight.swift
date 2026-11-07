import CoreGraphics
import Foundation

struct PDFFontEmbeddingIssue: Hashable {
    let pageNumber: Int
    let fontName: String
}

/// Inspect page font resources in the PDF actually produced for print. This is
/// a native Core Graphics implementation of the embedding check used in DTP
/// preflight workflows; no Scribus GPL code is incorporated.
enum PDFFontPreflight {
    static func unembeddedPageFonts(in data: Data) -> [PDFFontEmbeddingIssue] {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider), document.numberOfPages > 0 else { return [] }
        var issues: [PDFFontEmbeddingIssue] = []
        for number in 1...document.numberOfPages {
            guard let page = document.page(at: number),
                  let resources = inheritedResources(for: page) else { continue }
            inspect(resources: resources, pageNumber: number, depth: 0, issues: &issues)
        }
        return Array(Set(issues)).sorted {
            $0.pageNumber == $1.pageNumber ? $0.fontName < $1.fontName : $0.pageNumber < $1.pageNumber
        }
    }

    /// A page can place text inside a Form XObject. Its font dictionary belongs
    /// to the form rather than the page; bound recursion for malformed PDF cycles.
    private static func inspect(resources: CGPDFDictionaryRef, pageNumber: Int, depth: Int,
                                issues: inout [PDFFontEmbeddingIssue]) {
        guard depth < 16 else { return }
        if let fonts = dictionary(resources, "Font") {
            for key in keys(fonts) {
                guard let font = dictionary(fonts, key), !isEmbedded(font) else { continue }
                var base: UnsafePointer<CChar>?
                let name = CGPDFDictionaryGetName(font, "BaseFont", &base) && base != nil
                    ? String(cString: base!) : key
                issues.append(.init(pageNumber: pageNumber, fontName: String(name.prefix(100))))
            }
        }
        guard let xObjects = dictionary(resources, "XObject") else { return }
        for key in keys(xObjects) {
            var stream: CGPDFStreamRef?
            guard CGPDFDictionaryGetStream(xObjects, key, &stream), let stream,
                  let streamDictionary = CGPDFStreamGetDictionary(stream) else { continue }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(streamDictionary, "Subtype", &subtype),
                  let subtype, String(cString: subtype) == "Form",
                  let formResources = dictionary(streamDictionary, "Resources") else { continue }
            inspect(resources: formResources, pageNumber: pageNumber, depth: depth + 1, issues: &issues)
        }
    }

    private static func keys(_ dictionary: CGPDFDictionaryRef) -> [String] {
        var names: [String] = []
        withUnsafeMutablePointer(to: &names) { pointer in
            CGPDFDictionaryApplyFunction(dictionary, { key, _, info in
                guard let info else { return }
                info.assumingMemoryBound(to: [String].self).pointee.append(String(cString: key))
            }, pointer)
        }
        return names.sorted()
    }

    private static func inheritedResources(for page: CGPDFPage) -> CGPDFDictionaryRef? {
        var node: CGPDFDictionaryRef? = page.dictionary
        for _ in 0..<32 {
            guard let current = node else { return nil }
            if let resources = dictionary(current, "Resources") { return resources }
            node = dictionary(current, "Parent")
        }
        return nil
    }

    private static func dictionary(_ parent: CGPDFDictionaryRef, _ key: String) -> CGPDFDictionaryRef? {
        var value: CGPDFDictionaryRef?
        return CGPDFDictionaryGetDictionary(parent, key, &value) ? value : nil
    }

    private static func isEmbedded(_ font: CGPDFDictionaryRef) -> Bool {
        var subtype: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(font, "Subtype", &subtype),
           let subtype, String(cString: subtype) == "Type3" { return true }
        var descriptorFont = font
        var descendants: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(font, "DescendantFonts", &descendants), let descendants {
            var first: CGPDFDictionaryRef?
            if CGPDFArrayGetDictionary(descendants, 0, &first), let first { descriptorFont = first }
        }
        guard let descriptor = dictionary(descriptorFont, "FontDescriptor") else { return false }
        for key in ["FontFile", "FontFile2", "FontFile3"] {
            var stream: CGPDFStreamRef?
            if CGPDFDictionaryGetStream(descriptor, key, &stream), stream != nil { return true }
        }
        return false
    }
}
