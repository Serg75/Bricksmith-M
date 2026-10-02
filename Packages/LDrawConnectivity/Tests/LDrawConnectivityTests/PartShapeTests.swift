//
//  PartShapeTests.swift
//  LDrawConnectivityTests
//
//  Tests for the solid shapes of parts, and for refusing a placement that
//  puts one part through another by their shapes.
//
//  Created by Sergey Slobodenyuk on 2026-09-28.
//

import Testing
import Foundation
import LDrawCore
import LDrawConnectivity

@Suite("The solid a part fills")
struct PartShapeTests {

    private func shape(_ part: String) -> LDrawPartShape {
        ConnectivityFixtures.withShadow.shape(forPartNamed: part)
    }

    private func at(_ x: Double, _ y: Double, _ z: Double) -> Matrix4 {
        Matrix4Translate(IdentityMatrix4, V3Make(x, y, z))
    }

    /// A solid block from the origin to the given corner, as a part's
    /// triangles.
    private func block(_ x: Float, _ y: Float, _ z: Float) -> LDrawPartShape {
        LDrawPartShape(triangles: { blockTriangles(x, y, z) })
    }

    /// A hinge top turned about its hinge's axis, which runs along X through
    /// (0, 10, 0).
    private func hingeTop(turnedBy degrees: Double) -> Matrix4 {
        let placement = Matrix4Rotate(IdentityMatrix4, V3Make(degrees, 0, 0))
        let hinge = V3MulPointByProjMatrix(V3Make(0, 10, 0), placement)

        return Matrix4Translate(placement, V3Make(-hinge.x, 10 - hinge.y, -hinge.z))
    }

    private func goesInto(_ one: LDrawPartShape, _ placement: Matrix4,
                          _ other: LDrawPartShape, _ otherPlacement: Matrix4) -> Bool {
        let a = LDrawBoxByMatrix(one.bounds, placement)
        let b = LDrawBoxByMatrix(other.bounds, otherPlacement)
        var region = a

        region.min = V3Make(max(a.min.x, b.min.x), max(a.min.y, b.min.y), max(a.min.z, b.min.z))
        region.max = V3Make(min(a.max.x, b.max.x), min(a.max.y, b.max.y), min(a.max.z, b.max.z))

        return one.placed(at: placement, goesInto: other, placedAt: otherPlacement, within: region)
    }

    @Test("A brick is solid in its walls and top, and open underneath")
    func hollowUnderneath() {
        let brick = shape("3001.dat")

        #expect(brick.containsPoint(V3Make(0, 1.5, 0)))             // the top
        #expect(brick.containsPoint(V3Make(38.5, 12.5, 0)))         // an end wall
        #expect(brick.containsPoint(V3Make(10.5, 12.5, 0.5)) == false)   // between the tubes
        #expect(brick.containsPoint(V3Make(0, -10, 0)) == false)    // above it
    }

    @Test("A brick on another's studs does not go into it; sunk 8 LDU it does")
    func brickOnBrick() {
        let brick = shape("3001.dat")

        #expect(goesInto(brick, at(0, -24, 0), brick, IdentityMatrix4) == false)
        #expect(goesInto(brick, at(0, -16, 0), brick, IdentityMatrix4))
        #expect(goesInto(brick, at(80, 0, 0), brick, IdentityMatrix4) == false)     // side by side
    }

    @Test("Thin parts go into each other where they cross, and not where they touch")
    func thinParts() {
        let sheet = block(20, 2, 20)            // no cell of it is 3 cells deep
        let fin = block(2, 20, 20)

        #expect(sheet.insideCellCount > 0)      // its middle layer
        #expect(goesInto(fin, at(9, -9, 0), sheet, IdentityMatrix4))                 // through it
        #expect(goesInto(sheet, at(10, 0, 0), sheet, IdentityMatrix4))               // half over it
        #expect(goesInto(fin, at(9, -20, 0), sheet, IdentityMatrix4) == false)       // standing on it
        #expect(goesInto(sheet, at(0, 2, 0), sheet, IdentityMatrix4) == false)       // lying on it
    }

    @Test("A hinge top clears its base one way round, and goes into it the other")
    func hingeOneWayRound() {
        let base = shape("3937.dat")
        let top = shape("3938.dat")
        let opened = goesInto(top, hingeTop(turnedBy: 45), base, IdentityMatrix4)
        let swung = goesInto(top, hingeTop(turnedBy: -45), base, IdentityMatrix4)

        #expect(goesInto(top, IdentityMatrix4, base, IdentityMatrix4) == false)     // closed
        #expect(opened != swung)
    }

    @Test("A placement that swings a hinge top into its base is refused, though the two are joined")
    func joinedButThrough() throws {
        let baseShape = shape("3937.dat")
        let topShape = shape("3938.dat")
        let topSet = try #require(ConnectivityFixtures.shadowConnectorSet("3938.dat"))
        var fits: [Bool] = []

        for degrees in [45.0, -45.0] {
            let scene = SnapScene()
            let base = try SnapScene.connectors("3937.dat", at: (0, 0, 0), owner: 1)
            var placement = hingeTop(turnedBy: degrees)

            scene.index.setConnectors(base, forOwner: 1)
            scene.index.addBounds(LDrawBoxByMatrix(baseShape.bounds, IdentityMatrix4), shape: baseShape,
                                  placement: IdentityMatrix4, forOwner: 1)

            // Held 2 LDU off its seat.
            placement = Matrix4Translate(placement, V3Make(0, -2, 0))

            let moving = LDrawWorldConnectors(from: topSet, placement: placement, owner: 99)

            scene.solver.addMovingBounds(LDrawBoxByMatrix(topShape.bounds, placement), shape: topShape,
                                         placement: placement)
            fits.append(scene.solver.solution(for: moving, dragDirection: V3Make(0, 0, 0)).snapped)
        }

        #expect(fits.contains(true))
        #expect(fits.contains(false))
    }
}


/// The triangles of a solid block of the given size, from the origin or the
/// given corner, nine floats a triangle.
func blockTriangles(_ x: Float, _ y: Float, _ z: Float, from corner: (Float, Float, Float) = (0, 0, 0)) -> Data {
    let corners: [[Float]] = (0..<8).map {
        [corner.0 + (($0 & 1) != 0 ? x : 0), corner.1 + (($0 & 2) != 0 ? y : 0), corner.2 + (($0 & 4) != 0 ? z : 0)]
    }
    let faces = [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
    var floats: [Float] = []

    for face in faces {
        for corner in [face[0], face[1], face[2], face[0], face[2], face[3]] {
            floats += corners[corner]
        }
    }
    return floats.withUnsafeBytes { Data($0) }
}
