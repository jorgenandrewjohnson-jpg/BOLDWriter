import AppKit
import UniformTypeIdentifiers

/// Resolve promised file URLs in drag order. AppKit may complete each provider
/// on a different queue; document mutations always receive an ordered batch on main.
@MainActor
enum LocalFileDrop {
    static func decode(_ item: NSSecureCoding?) throws -> URL {
        let url: URL?
        if let value = item as? URL {
            url = value
        } else if let data = item as? Data {
            url = URL(dataRepresentation: data, relativeTo: nil)
        } else {
            url = nil
        }
        guard let url, url.isFileURL else {
            throw WriterError.message("The dropped item did not provide a local file URL.")
        }
        return url
    }

    @discardableResult
    static func load(_ providers: [NSItemProvider],
                     completion: @escaping ([Result<URL, Error>]) -> Void) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { return false }
        loadNext(files, index: 0, results: [], completion: completion)
        return true
    }

    private static func loadNext(_ files: [NSItemProvider], index: Int,
                                 results: [Result<URL, Error>],
                                 completion: @escaping ([Result<URL, Error>]) -> Void) {
        guard index < files.count else { completion(results); return }
        files[index].loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            DispatchQueue.main.async {
                let result: Result<URL, Error>
                if let error { result = .failure(error) }
                else { result = Result { try decode(item) } }
                loadNext(files, index: index + 1, results: results + [result], completion: completion)
            }
        }
    }
}
