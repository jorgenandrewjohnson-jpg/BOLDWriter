import Foundation

/// A nested Word table is preserved as a structured tree and its original XML.
/// The tree permits bounded validation and inspection; the XML retains properties
/// that the current native table editor does not expose.
struct NestedTableSnapshot: Codable, Equatable {
    var xml: String
    var rows: [[NestedTableCellSnapshot]]
}

struct NestedTableCellSnapshot: Codable, Equatable {
    var blocks: [NestedTableBlockSnapshot]
}

struct NestedTableBlockSnapshot: Codable, Equatable {
    var paragraphXML: String? = nil
    var table: NestedTableSnapshot? = nil
}

struct NestedTableAnchor: Codable, Equatable {
    static let placeholder = "[Nested table]"

    var id: UUID = UUID()
    /// UTF-16 offset in the containing cell's text, excluding its final terminator.
    var offset: Int = 0
    var table: NestedTableSnapshot

    var importMarker: String {
        "BOLDNESTEDTABLE" + id.uuidString.replacingOccurrences(of: "-", with: "")
    }
}
