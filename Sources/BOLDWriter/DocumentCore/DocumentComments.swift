import AppKit

enum DocumentComments {
    static func validate(_ comments: [DocumentComment], textLength: Int) throws {
        var ids = Set<UUID>()
        for comment in comments {
            guard ids.insert(comment.id).inserted,
                  comment.location >= 0,
                  comment.length >= 0,
                  comment.location <= textLength,
                  comment.length <= textLength - comment.location else {
                throw WriterError.message("The document contains malformed comment metadata.")
            }
        }
    }
}
