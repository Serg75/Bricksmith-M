//
//  LDrawModelCenteringTests.swift
//  LDrawEditingTests
//
//  Tests for moving a submodel's bottom center to its origin while the models
//  that use it keep their look. Lines stand in for parts, which would need the part
//  library to have bounds.
//
//  Created by Sergey Slobodenyuk on 2026-11-11.
//

import Testing
import Foundation
import LDrawCore
import LDrawEditing

@Suite("Centering a model")
struct LDrawModelCenteringTests {

    // sub.ldr spans (0, -60, 0) to (66, 30, 94), so its bottom center is
    // (33, 30, 47). LDraw's Y axis points down.
    // main.ldr uses it twice, turned 90 and 180 degrees around Y.
    private static let text = """
        0 FILE main.ldr
        0 Main
        0 Name: main.ldr
        1 16 100 -24 50 0 0 1 0 1 0 -1 0 0 sub.ldr
        0 STEP
        1 4 -40 0 0 -1 0 0 0 1 0 0 0 -1 sub.ldr
        0 NOFILE
        0 FILE sub.ldr
        0 sub
        0 Name: sub.ldr
        2 24 0 -60 0 66 30 94
        0 STEP
        1 16 10 0 10 1 0 0 0 1 0 0 0 1 leaf.ldr
        0 NOFILE
        0 FILE leaf.ldr
        0 leaf
        0 Name: leaf.ldr
        2 24 0 0 0 10 0 10
        0 NOFILE
        """

    private struct Fixture {
        let file: LDrawFile
        let main: LDrawMPDModel
        let sub: LDrawMPDModel
        let leaf: LDrawMPDModel
    }

    private func fixture() throws -> Fixture {
        let file = try #require(LDrawFile.parse(fromFileContents: Self.text))
        return Fixture(file: file,
                       main: try #require(file.model(withName: "main.ldr")),
                       sub: try #require(file.model(withName: "sub.ldr")),
                       leaf: try #require(file.model(withName: "leaf.ldr")))
    }

    private func elements<T>(_ type: T.Type, in model: LDrawModel) -> [T] {
        model.steps().flatMap { ($0 as! LDrawStep).subdirectives() }.compactMap { $0 as? T }
    }

    private func transform(_ point: Point3, by part: LDrawPart) -> Point3 {
        V3MulPointByProjMatrix(point, part.transformationMatrix())
    }

    // Every line end of sub.ldr and leaf.ldr, as main.ldr draws them.
    private func drawnPoints(_ fixture: Fixture) -> [Point3] {
        var points: [Point3] = []
        for reference in elements(LDrawPart.self, in: fixture.main) {
            for line in elements(LDrawLine.self, in: fixture.sub) {
                points += [line.vertex1(), line.vertex2()].map { transform($0, by: reference) }
            }
            for leafReference in elements(LDrawPart.self, in: fixture.sub) {
                for line in elements(LDrawLine.self, in: fixture.leaf) {
                    points += [line.vertex1(), line.vertex2()].map {
                        transform(transform($0, by: leafReference), by: reference)
                    }
                }
            }
        }
        return points
    }

    private func isClose(_ a: Point3, _ b: Point3) -> Bool {
        abs(a.x - b.x) < 0.001 && abs(a.y - b.y) < 0.001 && abs(a.z - b.z) < 0.001
    }

    private func center(_ model: LDrawModel, gridSpacing: Float) {
        for move in LDrawStructure.centeringMoves(for: model, gridSpacing: gridSpacing) {
            move.directive.move(by: move.displacement)
        }
    }

    @Test("The shift is the bottom center rounded to the grid, by brick or plate heights up",
          arguments: [(Float(20), V3Make(40, 24, 40)),
                      (Float(10), V3Make(30, 32, 50)),
                      (Float(1), V3Make(33, 30, 47))])
    func shiftFollowsGrid(gridSpacing: Float, expected: Vector3) throws {
        let fixture = try fixture()
        let shift = LDrawStructure.centeringShift(for: fixture.sub, gridSpacing: gridSpacing)
        #expect(V3EqualPoints(shift, expected))
    }

    @Test("The contents move back by the shift and the models that use them look the same")
    func contentsMoveAndUsesKeepTheirLook() throws {
        let fixture = try fixture()
        let before = drawnPoints(fixture)

        center(fixture.sub, gridSpacing: 20)

        let line = try #require(elements(LDrawLine.self, in: fixture.sub).first)
        #expect(V3EqualPoints(line.vertex1(), V3Make(-40, -84, -40)))
        #expect(V3EqualPoints(line.vertex2(), V3Make(26, 6, 54)))
        let leafReference = try #require(elements(LDrawPart.self, in: fixture.sub).first)
        #expect(V3EqualPoints(leafReference.position(), V3Make(-30, -24, -30)))

        let turned = try #require(elements(LDrawPart.self, in: fixture.main).first)
        #expect(isClose(turned.position(), V3Make(140, 0, 10)))

        let after = drawnPoints(fixture)
        #expect(before.count == 8)
        #expect(after.count == before.count)
        #expect(zip(before, after).allSatisfy { isClose($0, $1) })
    }

    @Test("With a fine grid the bottom center lands on the origin")
    func bottomCenterLandsOnOrigin() throws {
        let fixture = try fixture()

        center(fixture.sub, gridSpacing: 1)

        let bounds = LDrawUtilities.boundingBox3(forDirectives: fixture.sub.steps())
        #expect(isClose(bounds.min, V3Make(-33, -90, -47)))
        #expect(isClose(bounds.max, V3Make(33, 0, 47)))
    }

    @Test("Only the centered model's contents and its uses move")
    func otherModelsStay() throws {
        let fixture = try fixture()
        let leafLine = try #require(elements(LDrawLine.self, in: fixture.leaf).first)

        let moves = LDrawStructure.centeringMoves(for: fixture.sub, gridSpacing: 20)

        // Two directives in sub.ldr and two uses in main.ldr.
        #expect(moves.count == 4)
        #expect(moves.contains { $0.directive === leafLine } == false)
    }

    @Test("A centered model has nothing more to move")
    func centeredModelStays() throws {
        let fixture = try fixture()
        center(fixture.sub, gridSpacing: 20)

        #expect(LDrawStructure.canCenter(fixture.sub, gridSpacing: 20) == false)
        #expect(LDrawStructure.centeringMoves(for: fixture.sub, gridSpacing: 20).isEmpty)
    }

    @Test("A model with nothing to measure cannot be centered")
    func emptyModel() throws {
        let model = try #require(LDrawMPDModel.model() as? LDrawMPDModel)
        model.addStep()

        #expect(V3EqualPoints(LDrawStructure.centeringShift(for: model, gridSpacing: 20), ZeroPoint3))
        #expect(LDrawStructure.canCenter(model, gridSpacing: 20) == false)
    }
}
