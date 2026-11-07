import Foundation

enum CoverLinkedSmartObjectStatus:
    String,
    Equatable
{
    case current
    case modified
    case unavailable
    case staleBookmarkResolved
}

enum CoverLinkedSmartObjectResourceError:
    LocalizedError
{
    case notLinked
    case missingBookmark
    case bookmarkTooLarge
    case sourceTooLarge
    case persistentAccessUnavailable
    case unavailable

    var errorDescription:
        String?
    {
        switch self {
        case .notLinked:
            return "The Smart Object is not linked to an external source."

        case .missingBookmark:
            return "The linked Smart Object does not contain a usable file bookmark."

        case .bookmarkTooLarge:
            return "The linked Smart Object bookmark exceeds BOLD Writer's safe size limit."

        case .sourceTooLarge:
            return "The linked Smart Object source exceeds BOLD Writer's safe source-size limit."

        case .persistentAccessUnavailable:
            return "BOLD Writer could not save persistent permission for this linked artwork. Reimport it using the file chooser, then save the project again."

        case .unavailable:
            return "The linked Smart Object source is unavailable."
        }
    }
}

struct CoverLinkedSmartObjectSnapshot {
    var url:
        URL

    var data:
        Data

    var bookmarkData:
        Data

    var modificationDate:
        Date?

    var fileSize:
        Int64?

    var bookmarkWasStale:
        Bool
}

enum CoverLinkedSmartObjectResource {
    private static let resourceKeys:
        Set<URLResourceKey> =
        [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey,
        ]

    static func bookmarkData(
        for url: URL
    ) throws -> Data {
        let bookmark:
            Data

        do {
            bookmark =
                try url.bookmarkData(
                    options:
                        [
                            .withSecurityScope
                        ],
                    includingResourceValuesForKeys:
                        nil,
                    relativeTo:
                        nil
                )
        } catch {
#if APP_STORE
            throw CoverLinkedSmartObjectResourceError
                .persistentAccessUnavailable
#else
            bookmark =
                try url.bookmarkData(
                    options:
                        [],
                    includingResourceValuesForKeys:
                        nil,
                    relativeTo:
                        nil
                )
#endif
        }

        guard !bookmark.isEmpty,
              bookmark.count
                <= CoverSmartObjectValidation
                    .maxBookmarkBytes
        else {
            throw CoverLinkedSmartObjectResourceError
                .bookmarkTooLarge
        }

        return bookmark
    }

    static func resolveBookmark(
        _ bookmarkData: Data
    ) throws -> (
        url: URL,
        stale: Bool
    ) {
        guard !bookmarkData.isEmpty
        else {
            throw CoverLinkedSmartObjectResourceError
                .missingBookmark
        }

        guard bookmarkData.count
                <= CoverSmartObjectValidation
                    .maxBookmarkBytes
        else {
            throw CoverLinkedSmartObjectResourceError
                .bookmarkTooLarge
        }

        var stale =
            false

        do {
            let url =
                try URL(
                    resolvingBookmarkData:
                        bookmarkData,
                    options:
                        [
                            .withSecurityScope,
                            .withoutUI,
                        ],
                    relativeTo:
                        nil,
                    bookmarkDataIsStale:
                        &stale
                )

            return (
                url,
                stale
            )
        } catch {
#if APP_STORE
            throw CoverLinkedSmartObjectResourceError
                .persistentAccessUnavailable
#else
            stale =
                false

            let url =
                try URL(
                    resolvingBookmarkData:
                        bookmarkData,
                    options:
                        [
                            .withoutUI
                        ],
                    relativeTo:
                        nil,
                    bookmarkDataIsStale:
                        &stale
                )

            return (
                url,
                stale
            )
#endif
        }
    }

    private static func withSecurityScopedAccess<T>(
        to url: URL,
        _ work: () throws -> T
    ) rethrows -> T {
        let scoped =
            url.startAccessingSecurityScopedResource()

        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try work()
    }

    private static func metadata(
        for url: URL
    ) throws -> (
        modificationDate: Date?,
        fileSize: Int64?
    ) {
        let values =
            try url.resourceValues(
                forKeys:
                    resourceKeys
            )

        if values.isRegularFile == false {
            throw CoverLinkedSmartObjectResourceError
                .unavailable
        }

        let fileSize =
            values.fileSize.map {
                Int64(
                    $0
                )
            }

        return (
            values.contentModificationDate,
            fileSize
        )
    }

    static func snapshot(
        from url: URL
    ) throws -> CoverLinkedSmartObjectSnapshot {
        try withSecurityScopedAccess(
            to:
                url
        ) {
            let metadata =
                try metadata(
                    for:
                        url
                )

            if let fileSize =
                    metadata.fileSize,
               fileSize
                    > Int64(
                        CoverSmartObjectValidation
                            .maxSourceBytes
                    )
            {
                throw CoverLinkedSmartObjectResourceError
                    .sourceTooLarge
            }

            let data =
                try Data(
                    contentsOf:
                        url
                )

            guard !data.isEmpty,
                  data.count
                    <= CoverSmartObjectValidation
                        .maxSourceBytes
            else {
                throw CoverLinkedSmartObjectResourceError
                    .sourceTooLarge
            }

            let bookmark =
                try bookmarkData(
                    for:
                        url
                )

            return CoverLinkedSmartObjectSnapshot(
                url:
                    url,
                data:
                    data,
                bookmarkData:
                    bookmark,
                modificationDate:
                    metadata.modificationDate,
                fileSize:
                    metadata.fileSize,
                bookmarkWasStale:
                    false
            )
        }
    }

    static func resolve(
        _ object: CoverSmartObject
    ) throws -> CoverLinkedSmartObjectSnapshot {
        guard object.storageMode
                == .linked
        else {
            throw CoverLinkedSmartObjectResourceError
                .notLinked
        }

        guard let bookmark =
                object.linkedBookmarkData
        else {
            throw CoverLinkedSmartObjectResourceError
                .missingBookmark
        }

        let resolved =
            try resolveBookmark(
                bookmark
            )

        return try withSecurityScopedAccess(
            to:
                resolved.url
        ) {
            let metadata =
                try metadata(
                    for:
                        resolved.url
                )

            if let fileSize =
                    metadata.fileSize,
               fileSize
                    > Int64(
                        CoverSmartObjectValidation
                            .maxSourceBytes
                    )
            {
                throw CoverLinkedSmartObjectResourceError
                    .sourceTooLarge
            }

            let data =
                try Data(
                    contentsOf:
                        resolved.url
                )

            guard !data.isEmpty,
                  data.count
                    <= CoverSmartObjectValidation
                        .maxSourceBytes
            else {
                throw CoverLinkedSmartObjectResourceError
                    .sourceTooLarge
            }

            let refreshedBookmark:
                Data

            if resolved.stale {
                refreshedBookmark =
                    try bookmarkData(
                        for:
                            resolved.url
                    )
            } else {
                refreshedBookmark =
                    bookmark
            }

            return CoverLinkedSmartObjectSnapshot(
                url:
                    resolved.url,
                data:
                    data,
                bookmarkData:
                    refreshedBookmark,
                modificationDate:
                    metadata.modificationDate,
                fileSize:
                    metadata.fileSize,
                bookmarkWasStale:
                    resolved.stale
            )
        }
    }

    static func status(
        of object: CoverSmartObject
    ) -> CoverLinkedSmartObjectStatus? {
        guard object.storageMode
                == .linked,
              let bookmark =
                object.linkedBookmarkData
        else {
            return nil
        }

        do {
            let resolved =
                try resolveBookmark(
                    bookmark
                )

            return try withSecurityScopedAccess(
                to:
                    resolved.url
            ) {
                let metadata =
                    try metadata(
                        for:
                            resolved.url
                    )

                if object
                    .linkedLastKnownModificationDate
                    != metadata.modificationDate
                    || object
                        .linkedLastKnownFileSize
                        != metadata.fileSize
                {
                    return .modified
                }

                if resolved.stale {
                    return .staleBookmarkResolved
                }

                return .current
            }
        } catch {
            return .unavailable
        }
    }
}
