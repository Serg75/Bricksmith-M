//
//  LDrawStepPartListModelBuilderTests.swift
//  UnitTests
//
//  Tests for the throwaway model the parts list hands to its 3D view.
//
//  The fixtures use the identity view transform, so a part's expected position
//  is its cell center in layout LDU.
//
//  Created by Sergey Slobodenyuk on 2026-09-10.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures

@Suite("The parts list's synthetic model")
struct LDrawStepPartListModelBuilderTests {

    // MARK: - Fixtures

    private func entry(_ name: String,
                       width: Double = 20,
                       height: Double = 20,
                       missing: Bool = false,
                       submodel: Bool = false) -> LDrawStepPartListEntry {
        LDrawStepPartListEntry(partName: name,
                               displayTitle: name,
                               color: nil,
                               quantity: 1,
                               modelBounds: Box3(min: Point3(x: 0, y: 0, z: 0),
                                                 max: Point3(x: width, y: height, z: 20)),
                               isMissing: missing,
                               isSubmodel: submodel)
    }

    private func layout(_ entries: [LDrawStepPartListEntry]) -> LDrawStepPartListLayout {
        var constraint = LDrawStepPartListLayout.defaultConstraint()
        constraint.mode = .width
        constraint.inches = 2.0

        return LDrawStepPartListLayout.layout(forEntries: entries,
                                              constraint: constraint,
                                              viewTransform: IdentityMatrix4,
                                              metrics: LDrawStepPartListLayout.defaultMetrics())
    }

    private func parts(of model: LDrawModel) -> [LDrawPart] {
        model.steps().compactMap { $0 as? LDrawStep }
            .flatMap { $0.subdirectives() }
            .compactMap { $0 as? LDrawPart }
    }

    // MARK: - Membership

    /// A broken reference has nothing to draw, so it gets no part. A submodel
    /// gets a part like any other entry.
    @Test("Every entry but a broken reference gets exactly one part")
    func onlyBrokenReferencesAreSkipped() {
        let packed = layout([entry("3001.dat"),
                             entry("gone.dat", missing: true),
                             entry("wheel.ldr", submodel: true)])

        let model = LDrawStepPartListModelBuilder.model(forLayout: packed, viewTransform: IdentityMatrix4, submodelsFrom: nil)
        let drawable = packed.placements.filter { LDrawStepPartListModelBuilder.isDrawablePlacement($0) }

        #expect(parts(of: model).count == 2)
        #expect(Set(parts(of: model).map { $0.referenceName() }) == ["3001.dat", "wheel.ldr"])
        #expect(drawable.count == parts(of: model).count)
        // The layout still keeps room for all three.
        #expect(packed.placements.count == 3)
    }

    @Test("An empty layout gives an empty model, not nil")
    func emptyLayoutGivesEmptyModel() {
        let packed = layout([])
        let model = LDrawStepPartListModelBuilder.model(forLayout: packed, viewTransform: IdentityMatrix4, submodelsFrom: nil)

        #expect(parts(of: model).isEmpty)
    }

    // MARK: - Submodels

    /// The document a step belongs to, with one submodel in it.
    private func document(withSubmodel name: String) -> (file: LDrawFile, submodel: LDrawMPDModel) {
        let file = LDrawFile()
        let main = LDrawMPDModel.model() as! LDrawMPDModel
        main.setModelName("main.ldr")
        let sub = LDrawMPDModel.model() as! LDrawMPDModel
        sub.setModelName(name)
        file.addSubmodel(main)
        file.addSubmodel(sub)
        return (file, sub)
    }

    /// The icon model is thrown away on every repack, so the submodel it draws
    /// must stay in the document, and the icon model must stay out of it.
    @Test("A submodel reference draws the document's own submodel")
    func submodelsResolveToTheDocument() throws {
        let fixture = document(withSubmodel: "wheel.ldr")
        let packed = layout([entry("wheel.ldr", submodel: true)])

        let model = LDrawStepPartListModelBuilder.model(forLayout: packed,
                                                        viewTransform: IdentityMatrix4,
                                                        submodelsFrom: fixture.file)
        let part = try #require(parts(of: model).first)

        #expect(part.referenceName() == "wheel.ldr")
        #expect(part.referencedMPDSubmodel() === fixture.submodel)

        #expect(fixture.submodel.enclosingDirective() === fixture.file)
        #expect(fixture.file.model(withName: "wheel.ldr") === fixture.submodel)
        #expect(fixture.file.submodels().count == 2)
        #expect(model.enclosingFile() == nil)
    }

    @Test("An unknown submodel name falls back to a plain reference")
    func unknownSubmodelsFallBack() throws {
        let fixture = document(withSubmodel: "wheel.ldr")
        let packed = layout([entry("axle.ldr", submodel: true)])

        let model = LDrawStepPartListModelBuilder.model(forLayout: packed,
                                                        viewTransform: IdentityMatrix4,
                                                        submodelsFrom: fixture.file)
        let part = try #require(parts(of: model).first)

        #expect(part.referenceName() == "axle.ldr")
        #expect(part.referencedMPDSubmodel() == nil)
    }

    // MARK: - Positioning

    /// An LDraw part's origin sits wherever its author put it, often at a stud,
    /// so the builder recenters on the bounds before placing the part.
    @Test("A part lands centered on its cell whatever its own origin is")
    func partsAreCenteredOnTheirCells() throws {
        let packed = layout([entry("3001.dat", width: 40, height: 24)])
        let placement = try #require(packed.placements.first)

        let model = LDrawStepPartListModelBuilder.model(forLayout: packed, viewTransform: IdentityMatrix4, submodelsFrom: nil)
        let part = try #require(parts(of: model).first)

        let expectedX = (placement.iconFrame.origin.x + placement.iconFrame.size.width / 2) / packed.scale
        let expectedY = (placement.iconFrame.origin.y + placement.iconFrame.size.height / 2) / packed.scale

        // The fixture bounds run 0...40 by 0...24 by 0...20, so the center is
        // (20, 12, 10). The translation is the cell center less that.
        let position = part.position()
        #expect(abs(position.x - (expectedX - 20)) < 0.001)
        #expect(abs(position.y - (expectedY - 12)) < 0.001)

        // Depth is recentered too, so a deep part stays between the camera's
        // near and far planes.
        #expect(abs(position.z - (0 - 10)) < 0.001)
    }

    /// A submodel is measured by its parts, not by one box around them, so the
    /// middle of what was measured is what goes on the cell.
    @Test("A submodel lands centered on what was measured, not on its box")
    func submodelsAreCenteredOnTheirOutline() throws {
        // The box spans 0...200 across, but the parts only fill 120...200.
        let box = Box3(min: Point3(x: 0, y: 0, z: 0), max: Point3(x: 200, y: 20, z: 20))
        var corners: [Point3] = []
        for x in [120.0, 200.0] { for y in [0.0, 20.0] { for z in [0.0, 20.0] {
            corners.append(Point3(x: x, y: y, z: z))
        } } }
        let outline = corners.withUnsafeBufferPointer { Data(buffer: $0) }

        let submodel = LDrawStepPartListEntry(partName: "motor.ldr", displayTitle: "motor.ldr", color: nil,
                                              quantity: 1, modelBounds: box,
                                              isMissing: false, isSubmodel: true)
                           .withOutlinePoints(outline)

        let packed = layout([submodel])
        let placement = try #require(packed.placements.first)
        let model = LDrawStepPartListModelBuilder.model(forLayout: packed, viewTransform: IdentityMatrix4, submodelsFrom: nil)
        let part = try #require(parts(of: model).first)

        let expectedX = (placement.iconFrame.origin.x + placement.iconFrame.size.width / 2) / packed.scale

        // The measured middle is x = 160, not the box's 100.
        #expect(abs(part.position().x - (expectedX - 160)) < 0.001)
    }

    @Test("Two parts land on two different cells")
    func partsDoNotStack() throws {
        let packed = layout([entry("3001.dat"), entry("3002.dat")])
        let model = LDrawStepPartListModelBuilder.model(forLayout: packed, viewTransform: IdentityMatrix4, submodelsFrom: nil)

        let placed = parts(of: model)
        #expect(placed.count == 2)

        let first = try #require(placed.first).position()
        let second = try #require(placed.last).position()

        #expect(first.x != second.x || first.y != second.y)
    }

    // MARK: - Camera

    @Test("The camera centers on the middle of the content")
    func centerPointIsTheMiddleOfTheContent() {
        let packed = layout([entry("3001.dat"), entry("3002.dat"), entry("3003.dat")])
        let center = LDrawStepPartListModelBuilder.centerPoint(forLayout: packed)

        #expect(abs(center.x - packed.contentSize.width / 2 / packed.scale) < 0.001)
        #expect(abs(center.y - packed.contentSize.height / 2 / packed.scale) < 0.001)
        #expect(center.z == 0)
    }
}
