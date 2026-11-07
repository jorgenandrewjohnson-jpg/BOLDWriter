import Foundation
import XCTest
@testable import BOLDWriter

final class PSDNativeGroupFolderTests: XCTestCase {
    private func group(
        _ name:String="Group",
        visible:Bool=true
    )->CoverLayer {
        var layer =
            CoverLayer(
                kind:.group,
                name:name,
                frame:
                    CoverRect(
                        x:0,
                        y:0,
                        width:1,
                        height:1
                    )
            )

        layer.visible =
            visible

        return layer
    }

    private func member(
        _ name:String,
        groupID:UUID?=nil
    )->CoverLayer {
        var layer =
            CoverLayer(
                kind:.image,
                name:name,
                frame:
                    CoverRect(
                        x:0,
                        y:0,
                        width:1,
                        height:1
                    )
            )

        layer.groupID =
            groupID

        return layer
    }

    private func artwork(
        _ source:CoverLayer,
        byte:UInt8
    )->PSDExporter.Layer {
        PSDExporter.Layer(
            id:
                source.id,
            name:
                source.name,
            top:
                1,
            left:
                2,
            bottom:
                4,
            right:
                6,
            opacity:
                173,
            visible:
                source.visible,
            blendKey:
                "mul ",
            clipping:
                1,
            transparencyLocked:
                true,
            channels:
                [
                    PSDExporter.Channel(
                        id:-1,
                        data:
                            Data(
                                [
                                    byte,
                                    byte &+ 1,
                                ]
                            )
                    ),
                    PSDExporter.Channel(
                        id:0,
                        data:
                            Data(
                                [
                                    byte &+ 2,
                                ]
                            )
                    ),
                ]
        )
    }

    private func markerIndexes(
        _ data:Data,
        marker:[UInt8]
    )->[Int] {
        let bytes =
            [UInt8](
                data
            )

        guard !marker.isEmpty,
              bytes.count >= marker.count
        else {
            return []
        }

        var indexes:[Int] =
            []

        for index in 0...(bytes.count - marker.count) {
            if Array(
                bytes[
                    index..<(index + marker.count)
                ]
            ) == marker
            {
                indexes.append(
                    index
                )
            }
        }

        return indexes
    }

    private func uint32(
        _ bytes:[UInt8],
        at index:Int
    )->UInt32 {
        (
            UInt32(
                bytes[
                    index
                ]
            )
            << 24
        )
        | (
            UInt32(
                bytes[
                    index + 1
                ]
            )
            << 16
        )
        | (
            UInt32(
                bytes[
                    index + 2
                ]
            )
            << 8
        )
        | UInt32(
            bytes[
                index + 3
            ]
        )
    }

    private func sectionDividerTypes(
        _ data:Data
    )->[UInt32] {
        let bytes =
            [UInt8](
                data
            )

        let marker =
            Array(
                "8BIMlsct".utf8
            )

        return markerIndexes(
            data,
            marker:
                marker
        )
        .compactMap {
            index in

            guard index + 16
                    <= bytes.count
            else {
                return nil
            }

            let length =
                uint32(
                    bytes,
                    at:
                        index + 8
                )

            guard length >= 4
            else {
                return nil
            }

            return uint32(
                bytes,
                at:
                    index + 12
            )
        }
    }

    private func utf16BE(
        _ value:String
    )->Data {
        var data =
            Data()

        for unit in value.utf16 {
            data.append(
                UInt8(
                    (
                        unit
                        >> 8
                    )
                    & 0xff
                )
            )

            data.append(
                UInt8(
                    unit
                    & 0xff
                )
            )
        }

        return data
    }

    func testOneGroupProducesStartMembersEnd() {
        let folder =
            group(
                "Folder"
            )

        let first =
            member(
                "First",
                groupID:
                    folder.id
            )

        let second =
            member(
                "Second",
                groupID:
                    folder.id
            )

        let firstArtwork =
            artwork(
                first,
                byte:10
            )

        let secondArtwork =
            artwork(
                second,
                byte:20
            )

        let result =
            PSDExporter
                .nativeGroupFolderLayers(
                    projectLayers:
                        [
                            first,
                            second,
                            folder,
                        ],
                    candidates:
                        [
                            first,
                            second,
                        ],
                    artworkLayers:
                        [
                            firstArtwork,
                            secondArtwork,
                        ]
                )

        XCTAssertEqual(
            result.count,
            4
        )

        XCTAssertEqual(
            result[0]
                .sectionDividerType,
            3
        )

        XCTAssertEqual(
            result[0].name,
            "</Layer group>"
        )

        XCTAssertEqual(
            result[1],
            firstArtwork
        )

        XCTAssertEqual(
            result[2],
            secondArtwork
        )

        XCTAssertEqual(
            result[3]
                .sectionDividerType,
            1
        )

        XCTAssertEqual(
            result[3].name,
            "Folder"
        )
    }

    func testSyntheticFolderRecordsContainNoRasterChannels() {
        let folder =
            group()

        let start =
            PSDExporter
                .nativeGroupStartLayer(
                    folder
                )

        let end =
            PSDExporter
                .nativeGroupEndLayer(
                    folder
                )

        XCTAssertTrue(
            start.channels.isEmpty
        )

        XCTAssertTrue(
            end.channels.isEmpty
        )

        XCTAssertEqual(
            start.top,
            0
        )

        XCTAssertEqual(
            start.left,
            0
        )

        XCTAssertEqual(
            start.bottom,
            0
        )

        XCTAssertEqual(
            start.right,
            0
        )
    }

    func testGroupStartUsesGroupVisibility() {
        let folder =
            group(
                "Hidden",
                visible:false
            )

        let start =
            PSDExporter
                .nativeGroupStartLayer(
                    folder
                )

        let end =
            PSDExporter
                .nativeGroupEndLayer(
                    folder
                )

        XCTAssertFalse(
            start.visible
        )

        XCTAssertFalse(
            end.visible
        )
    }

    func testMemberMetadataRemainsUnchanged() {
        let folder =
            group()

        let source =
            member(
                "Member",
                groupID:
                    folder.id
            )

        let original =
            artwork(
                source,
                byte:30
            )

        let result =
            PSDExporter
                .nativeGroupFolderLayers(
                    projectLayers:
                        [
                            source,
                            folder,
                        ],
                    candidates:
                        [
                            source,
                        ],
                    artworkLayers:
                        [
                            original,
                        ]
                )

        XCTAssertEqual(
            result[1],
            original
        )

        XCTAssertEqual(
            result[1].opacity,
            173
        )

        XCTAssertEqual(
            result[1].blendKey,
            "mul "
        )

        XCTAssertEqual(
            result[1].clipping,
            1
        )

        XCTAssertTrue(
            result[1]
                .transparencyLocked
        )

        XCTAssertEqual(
            result[1].channels,
            original.channels
        )
    }

    func testTwoSiblingGroupsProduceIndependentFolderRanges() {
        let firstGroup =
            group(
                "First Group"
            )

        let secondGroup =
            group(
                "Second Group"
            )

        let a =
            member(
                "A",
                groupID:
                    firstGroup.id
            )

        let b =
            member(
                "B",
                groupID:
                    firstGroup.id
            )

        let c =
            member(
                "C",
                groupID:
                    secondGroup.id
            )

        let d =
            member(
                "D",
                groupID:
                    secondGroup.id
            )

        let result =
            PSDExporter
                .nativeGroupFolderLayers(
                    projectLayers:
                        [
                            a,
                            b,
                            c,
                            d,
                            firstGroup,
                            secondGroup,
                        ],
                    candidates:
                        [
                            a,
                            b,
                            c,
                            d,
                        ],
                    artworkLayers:
                        [
                            artwork(a,byte:1),
                            artwork(b,byte:2),
                            artwork(c,byte:3),
                            artwork(d,byte:4),
                        ]
                )

        XCTAssertEqual(
            result.map(
                \.sectionDividerType
            ),
            [
                3,
                nil,
                nil,
                1,
                3,
                nil,
                nil,
                1,
            ]
        )

        XCTAssertEqual(
            result[3].name,
            "First Group"
        )

        XCTAssertEqual(
            result[7].name,
            "Second Group"
        )
    }

    func testUngroupedLayersRemainExactlyInOriginalStream() {
        let first =
            member(
                "First"
            )

        let second =
            member(
                "Second"
            )

        let artworkLayers =
            [
                artwork(
                    first,
                    byte:9
                ),
                artwork(
                    second,
                    byte:19
                ),
            ]

        let result =
            PSDExporter
                .nativeGroupFolderLayers(
                    projectLayers:
                        [
                            first,
                            second,
                        ],
                    candidates:
                        [
                            first,
                            second,
                        ],
                    artworkLayers:
                        artworkLayers
                )

        XCTAssertEqual(
            result,
            artworkLayers
        )
    }

    func testOrphanGroupIDDoesNotCreateFolderRecords() {
        let missingGroupID =
            UUID()

        let source =
            member(
                "Orphan",
                groupID:
                    missingGroupID
            )

        let original =
            artwork(
                source,
                byte:77
            )

        let result =
            PSDExporter
                .nativeGroupFolderLayers(
                    projectLayers:
                        [
                            source,
                        ],
                    candidates:
                        [
                            source,
                        ],
                    artworkLayers:
                        [
                            original,
                        ]
                )

        XCTAssertEqual(
            result,
            [
                original,
            ]
        )
    }

    func testNoncontiguousGroupDoesNotReorderLayers() {
        let folder =
            group()

        let first =
            member(
                "First",
                groupID:
                    folder.id
            )

        let outside =
            member(
                "Outside"
            )

        let second =
            member(
                "Second",
                groupID:
                    folder.id
            )

        let originals =
            [
                artwork(
                    first,
                    byte:1
                ),
                artwork(
                    outside,
                    byte:2
                ),
                artwork(
                    second,
                    byte:3
                ),
            ]

        let result =
            PSDExporter
                .nativeGroupFolderLayers(
                    projectLayers:
                        [
                            first,
                            outside,
                            second,
                            folder,
                        ],
                    candidates:
                        [
                            first,
                            outside,
                            second,
                        ],
                    artworkLayers:
                        originals
                )

        XCTAssertEqual(
            result,
            originals
        )

        XCTAssertFalse(
            result.contains {
                $0.sectionDividerType
                    != nil
            }
        )
    }

    func testLayerAndMaskDataWritesLsctStartAndEnd() throws {
        let folder =
            group(
                "Folder"
            )

        let start =
            PSDExporter
                .nativeGroupStartLayer(
                    folder
                )

        let end =
            PSDExporter
                .nativeGroupEndLayer(
                    folder
                )

        let data =
            try PSDExporter
                .layerAndMaskData(
                    layers:
                        [
                            start,
                            end,
                        ]
                )

        XCTAssertEqual(
            sectionDividerTypes(
                data
            ),
            [
                1,
                3,
            ]
        )
    }

    func testLsctPayloadUsesBigEndianUInt32() throws {
        let folder =
            group()

        let data =
            try PSDExporter
                .layerAndMaskData(
                    layers:
                        [
                            PSDExporter
                                .nativeGroupStartLayer(
                                    folder
                                ),
                        ]
                )

        let marker =
            Array(
                "8BIMlsct".utf8
            )

        let indexes =
            markerIndexes(
                data,
                marker:
                    marker
            )

        XCTAssertEqual(
            indexes.count,
            1
        )

        let bytes =
            [UInt8](
                data
            )

        let index =
            try XCTUnwrap(
                indexes.first
            )

        XCTAssertEqual(
            Array(
                bytes[
                    (index + 8)..<(index + 12)
                ]
            ),
            [
                0,
                0,
                0,
                4,
            ]
        )

        XCTAssertEqual(
            Array(
                bytes[
                    (index + 12)..<(index + 16)
                ]
            ),
            [
                0,
                0,
                0,
                1,
            ]
        )
    }

    func testUngroupedLayerRecordDoesNotWriteLsct() throws {
        let source =
            member(
                "Normal"
            )

        let data =
            try PSDExporter
                .layerAndMaskData(
                    layers:
                        [
                            artwork(
                                source,
                                byte:15
                            ),
                        ]
                )

        XCTAssertTrue(
            sectionDividerTypes(
                data
            )
            .isEmpty
        )
    }

    func testUnicodeGroupNameUsesExistingLuniEncoding() throws {
        let folder =
            group(
                "Grüp Ω"
            )

        let data =
            try PSDExporter
                .layerAndMaskData(
                    layers:
                        [
                            PSDExporter
                                .nativeGroupStartLayer(
                                    folder
                                ),
                        ]
                )

        XCTAssertFalse(
            markerIndexes(
                data,
                marker:
                    Array(
                        "8BIMluni".utf8
                    )
            )
            .isEmpty
        )

        let expectedName =
            utf16BE(
                folder.name
            )

        XCTAssertFalse(
            markerIndexes(
                data,
                marker:
                    [UInt8](
                        expectedName
                    )
            )
            .isEmpty
        )
    }

    func testBoundingDividerWritesTypeThree() throws {
        let folder =
            group()

        let data =
            try PSDExporter
                .layerAndMaskData(
                    layers:
                        [
                            PSDExporter
                                .nativeGroupEndLayer(
                                    folder
                                ),
                        ]
                )

        XCTAssertEqual(
            sectionDividerTypes(
                data
            ),
            [
                3,
            ]
        )
    }
}
