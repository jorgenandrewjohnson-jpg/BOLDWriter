import XCTest
@testable import BOLDWriter

final class CoverLayerLinkingTests: XCTestCase {
    private func layer(
        _ name: String,
        x: Double = 0.1,
        y: Double = 0.1,
        width: Double = 0.2,
        height: Double = 0.2,
        kind: CoverLayerKind = .shape
    ) -> CoverLayer {
        CoverLayer(
            kind: kind,
            name: name,
            frame: CoverRect(
                x: x,
                y: y,
                width: width,
                height: height
            )
        )
    }

    private func pair() -> (
        layers: [CoverLayer],
        firstID: UUID,
        secondID: UUID,
        setID: UUID
    ) {
        var first = layer(
            "First",
            x: 0.1,
            y: 0.15
        )

        var second = layer(
            "Second",
            x: 0.45,
            y: 0.3
        )

        let setID = UUID()

        first.linkSetID = setID
        second.linkSetID = setID

        return (
            [first, second],
            first.id,
            second.id,
            setID
        )
    }

    func testLegacyLayerDecodesWithoutLinkSetID() throws {
        let original = layer("Legacy")

        let encoded =
            try JSONEncoder().encode(original)

        var object =
            try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: encoded
                ) as? [String: Any]
            )

        object.removeValue(
            forKey: "linkSetID"
        )

        let legacy =
            try JSONSerialization.data(
                withJSONObject: object
            )

        let decoded =
            try JSONDecoder().decode(
                CoverLayer.self,
                from: legacy
            )

        XCTAssertNil(decoded.linkSetID)
    }

    func testTwoLayersCanBeLinked() {
        var layers = [
            layer("One"),
            layer("Two"),
        ]

        let ids = Set(layers.map(\.id))

        let setID =
            CoverEditorEngine.linkLayers(
                &layers,
                ids: ids
            )

        XCTAssertNotNil(setID)

        XCTAssertTrue(
            layers.allSatisfy {
                $0.linkSetID == setID
            }
        )
    }

    func testThreeLayersShareOneLinkSet() {
        var layers = [
            layer("One"),
            layer("Two"),
            layer("Three"),
        ]

        let setID =
            CoverEditorEngine.linkLayers(
                &layers,
                ids: Set(layers.map(\.id))
            )

        XCTAssertNotNil(setID)

        XCTAssertEqual(
            Set(layers.compactMap(\.linkSetID)).count,
            1
        )
    }

    func testExistingLinkSetsMerge() {
        var layers = [
            layer("A"),
            layer("B"),
            layer("C"),
            layer("D"),
        ]

        let firstSet = UUID()
        let secondSet = UUID()

        layers[0].linkSetID = firstSet
        layers[1].linkSetID = firstSet
        layers[2].linkSetID = secondSet
        layers[3].linkSetID = secondSet

        let merged =
            CoverEditorEngine.linkLayers(
                &layers,
                ids: [
                    layers[1].id,
                    layers[2].id,
                ]
            )

        XCTAssertNotNil(merged)

        XCTAssertTrue(
            layers.allSatisfy {
                $0.linkSetID == merged
            }
        )
    }

    func testGroupTemplateAndAdjustmentAreNotLinkable() {
        let ordinary = layer("Ordinary")
        let group = layer(
            "Group",
            kind: .group
        )
        let template = layer(
            "Template",
            kind: .template
        )
        let adjustment = layer(
            "Adjustment",
            kind: .adjustment
        )

        let layers = [
            ordinary,
            group,
            template,
            adjustment,
        ]

        let eligible =
            CoverEditorEngine.linkableLayerIDs(
                layers,
                ids: Set(layers.map(\.id))
            )

        XCTAssertEqual(
            eligible,
            [ordinary.id]
        )

        var mutable = layers

        XCTAssertNil(
            CoverEditorEngine.linkLayers(
                &mutable,
                ids: Set(mutable.map(\.id))
            )
        )
    }

    func testEffectiveLinkedIDsExpandTouchedSet() {
        let state = pair()

        XCTAssertEqual(
            CoverEditorEngine.effectiveLinkedLayerIDs(
                state.layers,
                ids: [state.firstID]
            ),
            [
                state.firstID,
                state.secondID,
            ]
        )
    }

    func testUnlinkedLayerDoesNotExpand() {
        let first = layer("First")
        let second = layer("Second")

        XCTAssertEqual(
            CoverEditorEngine.effectiveLinkedLayerIDs(
                [first, second],
                ids: [first.id]
            ),
            [first.id]
        )
    }

    func testUnlinkNormalizesOneMemberRemainder() {
        var state = pair()

        CoverEditorEngine.unlinkLayers(
            &state.layers,
            ids: [state.firstID]
        )

        XCTAssertNil(
            state.layers.first {
                $0.id == state.firstID
            }?.linkSetID
        )

        XCTAssertNil(
            state.layers.first {
                $0.id == state.secondID
            }?.linkSetID
        )
    }

    func testThreeMemberSetRetainsTwoMemberRemainder() {
        var layers = [
            layer("One"),
            layer("Two"),
            layer("Three"),
        ]

        let setID = UUID()

        for index in layers.indices {
            layers[index].linkSetID = setID
        }

        CoverEditorEngine.unlinkLayers(
            &layers,
            ids: [layers[0].id]
        )

        XCTAssertNil(layers[0].linkSetID)
        XCTAssertEqual(layers[1].linkSetID, setID)
        XCTAssertEqual(layers[2].linkSetID, setID)
    }

    func testNormalizeClearsSingletonSet() {
        var only = layer("Only")
        only.linkSetID = UUID()

        var layers = [only]

        CoverEditorEngine.normalizeLayerLinks(
            &layers
        )

        XCTAssertNil(layers[0].linkSetID)
    }

    func testNormalizePreservesRealSet() {
        var state = pair()

        CoverEditorEngine.normalizeLayerLinks(
            &state.layers
        )

        XCTAssertEqual(
            state.layers[0].linkSetID,
            state.setID
        )

        XCTAssertEqual(
            state.layers[1].linkSetID,
            state.setID
        )
    }

    func testLinkedMoveUsesSameDelta() {
        var state = pair()

        let ids =
            CoverEditorEngine.effectiveLinkedLayerIDs(
                state.layers,
                ids: [state.firstID]
            )

        let before = state.layers.map(\.frame)

        CoverEditorEngine.moveLayers(
            &state.layers,
            ids: ids,
            dx: 0.07,
            dy: -0.04
        )

        for index in state.layers.indices {
            XCTAssertEqual(
                state.layers[index].frame.x,
                before[index].x + 0.07,
                accuracy: 0.000001
            )

            XCTAssertEqual(
                state.layers[index].frame.y,
                before[index].y - 0.04,
                accuracy: 0.000001
            )
        }
    }

    func testUnlinkedLayerDoesNotMove() {
        var state = pair()

        let independent =
            layer(
                "Independent",
                x: 0.72,
                y: 0.61
            )

        state.layers.append(independent)

        let ids =
            CoverEditorEngine.effectiveLinkedLayerIDs(
                state.layers,
                ids: [state.firstID]
            )

        let untouched =
            independent.frame

        CoverEditorEngine.moveLayers(
            &state.layers,
            ids: ids,
            dx: 0.05,
            dy: 0.05
        )

        XCTAssertEqual(
            state.layers.last?.frame,
            untouched
        )
    }

    func testLockedLinkedLayerStaysStationary() throws {
        var state = pair()

        let firstBefore =
            try XCTUnwrap(
                state.layers.first {
                    $0.id == state.firstID
                }
            ).frame

        let secondIndex =
            try XCTUnwrap(
                state.layers.firstIndex {
                    $0.id == state.secondID
                }
            )

        let secondBefore =
            state.layers[secondIndex].frame

        state.layers[secondIndex].locked = true

        let ids =
            CoverEditorEngine.effectiveLinkedLayerIDs(
                state.layers,
                ids: [state.firstID]
            )

        CoverEditorEngine.moveLayers(
            &state.layers,
            ids: ids,
            dx: 0.08,
            dy: 0.03
        )

        let firstAfter =
            try XCTUnwrap(
                state.layers.first {
                    $0.id == state.firstID
                }
            ).frame

        let secondAfter =
            try XCTUnwrap(
                state.layers.first {
                    $0.id == state.secondID
                }
            ).frame

        XCTAssertNotEqual(
            firstAfter,
            firstBefore
        )

        XCTAssertEqual(
            secondAfter,
            secondBefore
        )
    }

    func testPositionLockedLinkedLayerStaysStationary() throws {
        var state = pair()

        let secondIndex =
            try XCTUnwrap(
                state.layers.firstIndex {
                    $0.id == state.secondID
                }
            )

        let before =
            state.layers[secondIndex].frame

        state.layers[secondIndex].positionLocked = true

        let ids =
            CoverEditorEngine.effectiveLinkedLayerIDs(
                state.layers,
                ids: [state.firstID]
            )

        CoverEditorEngine.moveLayers(
            &state.layers,
            ids: ids,
            dx: 0.08,
            dy: 0.03
        )

        XCTAssertEqual(
            state.layers[secondIndex].frame,
            before
        )
    }

    func testLinkedScaleUsesAggregateBounds() throws {
        var state = pair()

        let ids =
            CoverEditorEngine.effectiveLinkedLayerIDs(
                state.layers,
                ids: [state.firstID]
            )

        let bounds =
            try XCTUnwrap(
                CoverEditorEngine.transformBounds(
                    state.layers,
                    ids: ids
                )
            )

        let distanceBefore =
            abs(
                state.layers[1].frame.x
                - state.layers[0].frame.x
            )

        CoverEditorEngine.scaleLayers(
            &state.layers,
            ids: ids,
            around: CGPoint(
                x: bounds.midX,
                y: bounds.midY
            ),
            scaleX: 1.5,
            scaleY: 1.5
        )

        let distanceAfter =
            abs(
                state.layers[1].frame.x
                - state.layers[0].frame.x
            )

        XCTAssertGreaterThan(
            distanceAfter,
            distanceBefore
        )
    }

    func testLinkedRotationAffectsBothMembers() throws {
        var state = pair()

        let ids =
            CoverEditorEngine.effectiveLinkedLayerIDs(
                state.layers,
                ids: [state.firstID]
            )

        let bounds =
            try XCTUnwrap(
                CoverEditorEngine.transformBounds(
                    state.layers,
                    ids: ids
                )
            )

        CoverEditorEngine.rotateLayers(
            &state.layers,
            ids: ids,
            around: CGPoint(
                x: bounds.midX,
                y: bounds.midY
            ),
            degrees: 30
        )

        XCTAssertEqual(
            state.layers[0].rotation,
            30,
            accuracy: 0.000001
        )

        XCTAssertEqual(
            state.layers[1].rotation,
            30,
            accuracy: 0.000001
        )
    }

    func testLinkedHorizontalFlipAffectsBothMembers() throws {
        var state = pair()

        let ids =
            CoverEditorEngine.effectiveLinkedLayerIDs(
                state.layers,
                ids: [state.firstID]
            )

        let bounds =
            try XCTUnwrap(
                CoverEditorEngine.transformBounds(
                    state.layers,
                    ids: ids
                )
            )

        CoverEditorEngine.flipLayers(
            &state.layers,
            ids: ids,
            around: bounds.midX,
            horizontal: true
        )

        XCTAssertTrue(
            state.layers[0].flipHorizontal
        )

        XCTAssertTrue(
            state.layers[1].flipHorizontal
        )
    }

    func testDuplicateOneLinkedLayerBecomesUnlinked() throws {
        var state = pair()

        let copied =
            CoverEditorEngine.duplicateLinkedLayers(
                &state.layers,
                ids: [state.firstID]
            )

        XCTAssertEqual(copied.count, 1)

        let duplicate =
            try XCTUnwrap(
                state.layers.first {
                    copied.contains($0.id)
                }
            )

        XCTAssertNil(duplicate.linkSetID)
    }

    func testDuplicateWholeLinkedSetGetsFreshSet() throws {
        var state = pair()

        let copied =
            CoverEditorEngine.duplicateLinkedLayers(
                &state.layers,
                ids: [
                    state.firstID,
                    state.secondID,
                ]
            )

        XCTAssertEqual(copied.count, 2)

        let copies =
            state.layers.filter {
                copied.contains($0.id)
            }

        let sets =
            Set(copies.compactMap(\.linkSetID))

        XCTAssertEqual(sets.count, 1)

        XCTAssertNotEqual(
            try XCTUnwrap(sets.first),
            state.setID
        )
    }

    func testLinkingDoesNotChangeGroupMembership() {
        var first = layer("First")
        var second = layer("Second")

        let groupID = UUID()

        first.groupID = groupID
        second.groupID = nil

        var layers = [
            first,
            second,
        ]

        _ = CoverEditorEngine.linkLayers(
            &layers,
            ids: [
                first.id,
                second.id,
            ]
        )

        XCTAssertEqual(
            layers[0].groupID,
            groupID
        )

        XCTAssertNil(
            layers[1].groupID
        )

        XCTAssertEqual(
            layers[0].linkSetID,
            layers[1].linkSetID
        )
    }

    func testPersistenceRoundTripPreservesLinkSetID() throws {
        var project = CoverProject()

        var first = layer("First")
        var second = layer("Second")

        let setID = UUID()

        first.linkSetID = setID
        second.linkSetID = setID

        project.layers = [
            first,
            second,
        ]

        let data =
            try JSONEncoder().encode(project)

        let decoded =
            try JSONDecoder().decode(
                CoverProject.self,
                from: data
            )

        XCTAssertEqual(
            decoded.layers[0].linkSetID,
            setID
        )

        XCTAssertEqual(
            decoded.layers[1].linkSetID,
            setID
        )
    }

    func testProjectValidationAcceptsValidLinkedLayers() throws {
        var project = CoverProject()

        var first = layer("First")
        var second = layer("Second")

        let setID = UUID()

        first.linkSetID = setID
        second.linkSetID = setID

        project.layers = [
            first,
            second,
        ]

        XCTAssertNoThrow(
            try CoverProject.validate(
                [project]
            )
        )
    }
}
