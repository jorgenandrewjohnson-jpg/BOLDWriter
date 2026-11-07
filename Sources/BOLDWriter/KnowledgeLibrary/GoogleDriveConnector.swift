import Foundation

/// Provider boundary for a future consented Drive connector. Milestone 2 ships
/// the offline Takeout provider; this protocol intentionally has no OAuth or
/// network implementation until Google authorization is provisioned.
protocol GoogleDriveConnector: Sendable {
    func children(of selectedFolderID: String, pageToken: String?) async throws -> GoogleDrivePage
    func changes(after cursor: GoogleDriveChangeCursor) async throws -> GoogleDriveChangesPage
    func writeExport(for item: GoogleDriveItem, to destination: URL) async throws
}

struct GoogleDriveItem: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let mimeType: String
    let modifiedTime: Date?
    let webViewURL: URL?
    let parentIDs: [String]
    let revisionID: String?
    let byteCount: Int64?
    let isFolder: Bool

    var supportedExportMIMEType: String? {
        switch mimeType {
        case "application/vnd.google-apps.document": "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "application/vnd.google-apps.presentation", "application/vnd.google-apps.drawing": "application/pdf"
        default: nil
        }
    }
}

struct GoogleDrivePage: Sendable {
    let items: [GoogleDriveItem]
    let nextPageToken: String?
}

struct GoogleDriveChangeCursor: Codable, Hashable, Sendable {
    let selectedFolderID: String
    let pageToken: String
    let capturedAt: Date
}

struct GoogleDriveChangesPage: Sendable {
    let changedItems: [GoogleDriveItem]
    let removedItemIDs: [String]
    let nextPageToken: String?
    let newStartPageToken: String?
}
