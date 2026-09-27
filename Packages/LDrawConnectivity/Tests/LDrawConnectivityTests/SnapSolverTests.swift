//
//  SnapSolverTests.swift
//  LDrawConnectivityTests
//
//  Tests for connector mating, snap placement, sliding, holding, turning and
//  the connector index.
//
//  Created by Sergey Slobodenyuk on 2026-09-20.
//

import Testing
import Foundation
import LDrawCore
import LDrawConnectivity

/// A model of placed parts, with a solver to drag parts onto it.
struct SnapScene {
    let index = LDrawConnectorIndex()
    let solver: LDrawSnapSolver

    init() {
        solver = LDrawSnapSolver(connectorIndex: index)
        solver.pointsPerUnit = 1                // one screen point to one LDU
    }

    /// Connectors of a part placed at a point and rotated by the given degrees.
    static func connectors(_ part: String, at position: (Double, Double, Double),
                           turnedBy degrees: (Double, Double, Double) = (0, 0, 0),
                           owner: UInt32) throws -> LDrawWorldConnectors {
        let set = try #require(ConnectivityFixtures.shadowConnectorSet(part))
        var placement = Matrix4Rotate(IdentityMatrix4, V3Make(degrees.0, degrees.1, degrees.2))

        placement = Matrix4Translate(placement, V3Make(position.0, position.1, position.2))

        return LDrawWorldConnectors(from: set, placement: placement, owner: owner)
    }

    @discardableResult
    func place(_ part: String, at position: (Double, Double, Double),
               owner: UInt32) throws -> LDrawWorldConnectors {
        let connectors = try Self.connectors(part, at: position, owner: owner)

        index.setConnectors(connectors, forOwner: owner)

        return connectors
    }

    func drag(_ part: String, to position: (Double, Double, Double),
              turnedBy degrees: (Double, Double, Double) = (0, 0, 0),
              owner: UInt32 = 99,
              direction: Vector3 = V3Make(0, 0, 0)) throws -> LDrawSnapSolution {
        let moving = try Self.connectors(part, at: position, turnedBy: degrees, owner: owner)

        return solver.solution(for: moving, dragDirection: direction)
    }
}


extension Array where Element == LDrawWorldConnector {
    /// The connectors as the index and the solver take them.
    var buffer: LDrawWorldConnectors {
        let connectors = LDrawWorldConnectors()

        forEach { connectors.add($0) }

        return connectors
    }
}


/// The translation of a placement.
func translation(_ matrix: Matrix4) -> (x: Double, y: Double, z: Double) {
    var copy = matrix

    return withUnsafeBytes(of: &copy) { raw in
        let elements = raw.bindMemory(to: Double.self)
        return (elements[12], elements[13], elements[14])
    }
}


func isTurned(_ matrix: Matrix4) -> Bool {
    var copy = matrix

    return withUnsafeBytes(of: &copy) { raw in
        let elements = raw.bindMemory(to: Double.self)
        return elements[0] != 1 || elements[5] != 1 || elements[10] != 1
    }
}


func connector(_ position: (Double, Double, Double), axis: (Double, Double, Double),
               profile: [(radius: Double, length: Double, shape: LDrawSectionShape)]
                   = [(6, 4, .round)],
               kind: LDrawConnectorKind = .cylinder, gender: LDrawConnectorGender,
               owner: UInt32 = 1, slide: Bool = false, centered: Bool = false,
               bothEndsOpen: Bool = false) -> LDrawWorldConnector {
    let empty = LDrawConnectorSection(radius: 0, length: 0, shape: .round)
    var sections = [LDrawConnectorSection](repeating: empty, count: 4)

    for (index, section) in profile.prefix(4).enumerated() {
        sections[index] = LDrawConnectorSection(radius: section.radius, length: section.length,
                                                shape: section.shape)
    }

    return LDrawWorldConnector(position: V3Make(position.0, position.1, position.2),
                               axis: V3Make(axis.0, axis.1, axis.2),
                               length: profile.reduce(0) { $0 + $1.length },
                               sections: (sections[0], sections[1], sections[2], sections[3]),
                               owner: owner, sectionCount: UInt8(min(profile.count, 4)),
                               kind: kind, gender: gender,
                               centered: centered, slide: slide, bothEndsOpen: bothEndsOpen)
}


/// Where a point ends up under a placement.
func landing(_ point: (Double, Double, Double), by matrix: Matrix4) -> (x: Double, y: Double, z: Double) {
    let placed = V3MulPointByProjMatrix(V3Make(point.0, point.1, point.2), matrix)

    return ((placed.x * 1000).rounded() / 1000,
            (placed.y * 1000).rounded() / 1000,
            (placed.z * 1000).rounded() / 1000)
}


/// Whether the two mate, and at what depth.
func mate(_ one: LDrawWorldConnector, _ other: LDrawWorldConnector,
          tolerance: Double = 0.05) -> (holds: Bool, depth: Double) {
    var depth = 0.0
    let holds = LDrawWorldConnectorsMate(one, other, tolerance, &depth)

    return (holds, depth)
}


@Suite("Which connectors can hold each other")
struct ConnectorPairTests {

    @Test("A stud and a stud hole hold each other")
    func studAndHole() {
        let stud = connector((0, 0, 0), axis: (0, -1, 0), gender: .male, owner: 1)
        let hole = connector((0, 0, 0), axis: (0, -1, 0), gender: .female, owner: 2)

        #expect(mate(stud, hole).holds)
    }

    @Test("Two studs do not")
    func twoStuds() {
        let one = connector((0, 0, 0), axis: (0, -1, 0), gender: .male, owner: 1)
        let other = connector((0, 0, 0), axis: (0, -1, 0), gender: .male, owner: 2)

        #expect(mate(one, other).holds == false)
    }

    @Test("A round pin does not enter a cross hole")
    func pinAndAxleHole() {
        let pin = connector((0, 0, 0), axis: (0, -1, 0), profile: [(6, 4, .round)], gender: .male, owner: 1)
        let hole = connector((0, 0, 0), axis: (0, -1, 0), profile: [(6, 4, .axle)], gender: .female, owner: 2)

        #expect(mate(pin, hole).holds == false)
    }

    @Test("A stud enters the square hole under a plate")
    func studAndSquareHole() {
        let stud = connector((0, 0, 0), axis: (0, -1, 0), profile: [(6, 4, .round)], gender: .male, owner: 1)
        let hole = connector((0, 0, 0), axis: (0, -1, 0), profile: [(6, 4, .square)], gender: .female, owner: 2)

        #expect(mate(stud, hole).holds)
    }

    @Test("A stud does not enter a hole of another size")
    func radiusMismatch() {
        let stud = connector((0, 0, 0), axis: (0, -1, 0), profile: [(6, 4, .round)], gender: .male, owner: 1)
        let hole = connector((0, 0, 0), axis: (0, -1, 0), profile: [(4, 4, .round)], gender: .female, owner: 2)

        #expect(mate(stud, hole).holds == false)
    }

    @Test("A clip holds a bar")
    func clipAndBar() {
        let bar = connector((0, 0, 0), axis: (0, -1, 0), kind: .cylinder, gender: .male, owner: 1)
        let clip = connector((0, 0, 0), axis: (0, -1, 0), kind: .clip, gender: .female, owner: 2)

        #expect(mate(bar, clip).holds)
    }

    @Test("Whether two connectors hold each other does not depend on whose they are")
    func ownerIsNotPartOfMating() {
        // Shapes decide whether two could hold; the solver decides which
        // pairs are worth offering, and never offers a part its own. The
        // connectors inside a group of parts mate with each other, which is
        // how the ones nothing can reach are found.
        let stud = connector((0, 0, 0), axis: (0, -1, 0), gender: .male, owner: 7)
        let hole = connector((0, 0, 0), axis: (0, -1, 0), gender: .female, owner: 7)

        #expect(mate(stud, hole).holds)
    }

    @Test("A bar reaches the narrow part of a tube that takes a stud at its mouth")
    func deepSection() {
        // 3062b's tube is R 6 for 20, then R 4 for 8.
        let tube = connector((0, 0, 0), axis: (0, -1, 0),
                             profile: [(6, 20, .round), (4, 8, .round)], gender: .female, owner: 2)
        let stud = connector((0, 0, 0), axis: (0, -1, 0), profile: [(6, 4, .round)], gender: .male, owner: 1)
        let bar = connector((0, 0, 0), axis: (0, -1, 0), profile: [(4, 8, .round)], gender: .male, owner: 1)

        #expect(mate(stud, tube).holds)
        #expect(mate(stud, tube).depth == 0)            // the stud stops at the mouth
        #expect(mate(bar, tube).holds)
        #expect(mate(bar, tube).depth == 20)            // the bar reaches the narrow part
    }

    @Test("Connectors that face different ways do not, unless the part may turn")
    func facingApart() {
        let stud = connector((0, 0, 0), axis: (0, -1, 0), gender: .male, owner: 1)
        let hole = connector((0, 0, 0), axis: (1, 0, 0), gender: .female, owner: 2)

        #expect(mate(stud, hole).holds == false)
        #expect(mate(stud, hole, tolerance: .pi).holds)
    }
}


@Suite("The connectors a group of parts still offers")
struct StillFreeTests {

    private func stillFree(_ connectors: [LDrawWorldConnector]) -> [LDrawWorldConnector] {
        let free = connectors.buffer.connectorsStillFree(0.05)

        return (0..<free.count).map { free.connector(at: $0) }
    }

    @Test("A stud with a hole on it, and that hole, are past reaching")
    func mateeachOtherInside() {
        // A plate sitting on one stud of a brick, both inside the same group.
        let taken = connector((0, 0, 0), axis: (0, -1, 0), profile: [(6, 4, .round)], gender: .male)
        let onIt = connector((0, 0, 0), axis: (0, -1, 0), profile: [(6, 20, .round)], gender: .female)
        let free = connector((20, 0, 0), axis: (0, -1, 0), profile: [(6, 4, .round)], gender: .male)

        let left = stillFree([taken, onIt, free])

        #expect(left.count == 1)
        #expect(left.first?.position.x == 20)
    }

    @Test("A connector that slides keeps what is left of its run")
    func slidingRunsAreKept() {
        // An axle through a beam is held over part of its length and is still
        // free over the rest.
        let axle = connector((0, 0, 0), axis: (1, 0, 0), profile: [(4, 60, .round)],
                             gender: .male, slide: true)
        let beam = connector((0, 0, 0), axis: (1, 0, 0), profile: [(4, 28, .round)],
                             gender: .female, slide: true)

        #expect(stillFree([axle, beam]).count == 2)
    }

    @Test("Connectors that meet nothing are all kept")
    func nothingInside() {
        let studs = (0..<4).map {
            connector((Double($0) * 20, 0, 0), axis: (0, -1, 0), gender: .male)
        }

        #expect(stillFree(studs).count == 4)
    }
}


@Suite("Where a dragged part lands")
struct SnapSolverTests {

    @Test("A brick laid on a brick is held by all eight studs at once")
    func wholeConnection() throws {
        let scene = SnapScene()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        let solution = try scene.drag("3001.dat", to: (0, -22, 0))

        #expect(solution.snapped)
        #expect(solution.voteCount == 8)
        #expect(translation(solution.transform) == (0, -2, 0))
        #expect(isTurned(solution.transform) == false)
    }

    @Test("A plate over one stud lands on that stud")
    func oneStud() throws {
        let scene = SnapScene()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        // 3024's hole is 8 LDU below its origin, so this holds the plate
        // 3 LDU beside the stud at (10, 0, 10).
        let solution = try scene.drag("3024.dat", to: (13, -8, 10))

        #expect(solution.snapped)
        #expect(solution.voteCount == 1)
        #expect(translation(solution.transform) == (-3, 0, 0))
    }

    @Test("A part is never held by its own connectors")
    func ownConnectorsIgnored() throws {
        let scene = SnapScene()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        #expect(try scene.drag("3001.dat", to: (0, -22, 0), owner: 1).snapped == false)
    }

    @Test("A tile's top is flat, so nothing lands on it")
    func tileTopIsFlat() throws {
        let onPlate = SnapScene()
        let onTile = SnapScene()

        try onPlate.place("3024.dat", at: (0, 0, 0), owner: 1)
        try onTile.place("3070b.dat", at: (0, 0, 0), owner: 1)

        // The same drag, onto the top of a plate and onto the top of a tile.
        let landed = try onPlate.drag("3024.dat", to: (0, -8, 0))
        let refused = try onTile.drag("3024.dat", to: (0, -8, 0))

        #expect(landed.snapped)
        #expect(translation(landed.transform) == (0, 0, 0))

        // A tile has no stud on top, so the plate can only land below it.
        #expect(translation(refused.transform).y > 0)
    }

    @Test("A part left in the index does not take its own place")
    func ownConnectorsDoNotBlock() throws {
        let scene = SnapScene()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)
        try scene.place("3001.dat", at: (0, -24, 0), owner: 2)

        // Owner 2 is dragged while it is still in the index, back onto the
        // studs it is standing on.
        let solution = try scene.drag("3001.dat", to: (0, -24 + 2, 0), owner: 2)

        #expect(solution.snapped)
        #expect(solution.voteCount == 8)
    }

    @Test("Two plates cannot sit on one stud")
    func oneStudHoldsOnePart() throws {
        let scene = SnapScene()

        scene.solver.acquireDistance = 10       // the next stud over is 20 away
        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)
        try scene.place("3070b.dat", at: (10, -8, 10), owner: 2)

        // A tile covers the stud at (10, 0, 10). The next stud over is free.
        let taken = try scene.drag("3024.dat", to: (10, -8, 10))
        let free = try scene.drag("3024.dat", to: (-10, -8, 10))

        #expect(taken.snapped == false)
        #expect(free.snapped)
    }

    @Test("A stud does not go into a stud hole from its closed end")
    func closedEnd() {
        let index = LDrawConnectorIndex()
        let solver = LDrawSnapSolver(connectorIndex: index)

        solver.pointsPerUnit = 1
        solver.allowsRotation = false
        index.setConnectors([connector((0, 0, 0), axis: (0, -1, 0), gender: .female, owner: 1)].buffer,
                            forOwner: 1)

        let upsideDown = [connector((0, -2, 0), axis: (0, 1, 0), gender: .male, owner: 2)].buffer

        #expect(solver.solution(for: upsideDown, dragDirection: V3Make(0, 0, 0)).snapped == false)
    }
}


@Suite("Connectors that slide along each other")
struct SnapSlideTests {

    /// A hole 28 long, centered on the origin and running along X.
    private func hole(slides: Bool) -> LDrawWorldConnectors {
        [connector((0, 0, 0), axis: (1, 0, 0), profile: [(4, 28, .round)],
                   gender: .female, owner: 1, slide: slides, centered: true)].buffer
    }

    /// An axle 60 long, running along X.
    private func axle(at position: (Double, Double, Double), slides: Bool) -> LDrawWorldConnectors {
        [connector(position, axis: (1, 0, 0), profile: [(4, 60, .round)],
                   gender: .male, owner: 2, slide: slides)].buffer
    }

    /// A short pin, 4 long.
    private func pin(at position: (Double, Double, Double), along axis: (Double, Double, Double),
                     slides: Bool = false) -> LDrawWorldConnectors {
        [connector(position, axis: axis, profile: [(4, 4, .round)],
                   gender: .male, owner: 2, slide: slides)].buffer
    }

    @Test("A hole centered on its middle is found from its mouth")
    func centeredHoleIsFoundAtItsMouth() throws {
        let index = LDrawConnectorIndex()
        let solver = LDrawSnapSolver(connectorIndex: index)

        solver.pointsPerUnit = 4        // zoomed in: 10 LDU of reach, and the
                                        // hole's middle is 14 from its mouth
        index.setConnectors([connector((0, 0, 0), axis: (1, 0, 0), profile: [(4, 28, .round)],
                                       gender: .female, owner: 1, centered: true)].buffer,
                            forOwner: 1)

        // A pin held 2 LDU off the hole's mouth, which is at (-14, 0, 0).
        let solution = solver.solution(for: pin(at: (-14, 2, 0), along: (1, 0, 0)),
                                       dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped)
        #expect(translation(solution.transform) == (0, -2, 0))
    }

    @Test("A pin at the far end of a long hole still finds it, zoomed in")
    func farEndOfALongHole() throws {
        let index = LDrawConnectorIndex()
        let solver = LDrawSnapSolver(connectorIndex: index)

        solver.pointsPerUnit = 4        // zoomed in: 10 LDU of reach, against
                                        // a hole 28 long
        index.setConnectors(hole(slides: true), forOwner: 1)

        // Held near the hole's far end, 2 LDU off its line. The hole's mouth
        // is 26 LDU away, far outside the reach.
        let solution = solver.solution(for: pin(at: (12, 2, 0), along: (1, 0, 0), slides: true),
                                       dragDirection: V3Make(0, 0, 0))

        // Moved onto the line, and 2 LDU back so the pin stays inside the hole.
        #expect(solution.snapped)
        #expect(translation(solution.transform) == (-2, -2, 0))
    }

    @Test("A hole with an axle through it is not offered to another axle")
    func takenAlongTheRun() throws {
        let index = LDrawConnectorIndex()
        let solver = LDrawSnapSolver(connectorIndex: index)

        solver.pointsPerUnit = 1
        index.setConnectors(hole(slides: true), forOwner: 1)
        index.setConnectors(axle(at: (-32, 0, 0), slides: true), forOwner: 2)

        // The first axle's mouth is not at the hole's mouth, but it still
        // fills the hole.
        let solution = solver.solution(for: [connector((-30, 2, 0), axis: (1, 0, 0),
                                                                 profile: [(4, 60, .round)],
                                                                 gender: .male, owner: 3,
                                                                 slide: true)].buffer,
                                       dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped == false)
    }

    @Test("A second beam goes on the free length of an axle, and stops against the first")
    func twoBeamsOnOneAxle() throws {
        let index = LDrawConnectorIndex()
        let solver = LDrawSnapSolver(connectorIndex: index)

        solver.pointsPerUnit = 1

        // An axle 60 long lying along X from the origin, with a beam on its
        // first 28.
        index.setConnectors([connector((0, 0, 0), axis: (1, 0, 0), profile: [(4, 60, .round)],
                                       gender: .male, owner: 1, slide: true)].buffer, forOwner: 1)
        index.setConnectors([connector((0, 0, 0), axis: (1, 0, 0), profile: [(4, 28, .round)],
                                       gender: .female, owner: 2, slide: true)].buffer, forOwner: 2)

        func beam(at position: (Double, Double, Double)) -> LDrawWorldConnectors {
            [connector(position, axis: (1, 0, 0), profile: [(4, 28, .round)],
                       gender: .female, owner: 3, slide: true)].buffer
        }

        let free = solver.solution(for: beam(at: (34, 2, 0)), dragDirection: V3Make(0, 0, 0))

        solver.releaseHold()

        let over = solver.solution(for: beam(at: (10, 2, 0)), dragDirection: V3Make(0, 0, 0))

        #expect(free.snapped)                                   // past the first beam
        #expect(over.snapped)
        #expect(translation(over.transform) == (18, -2, 0))     // pushed off the first beam
    }

    @Test("A hole open at both ends takes an axle from either end")
    func eitherEnd() throws {
        let index = LDrawConnectorIndex()
        let solver = LDrawSnapSolver(connectorIndex: index)

        solver.pointsPerUnit = 1
        solver.allowsRotation = false
        index.setConnectors([connector((0, 0, 0), axis: (1, 0, 0), profile: [(4, 28, .round)],
                                       gender: .female, owner: 1, slide: true, centered: true,
                                       bothEndsOpen: true)].buffer, forOwner: 1)

        // An axle pointing the other way, 2 LDU off the hole's line.
        let axle = [connector((20, 2, 0), axis: (-1, 0, 0), profile: [(4, 60, .round)],
                              gender: .male, owner: 2, slide: true, bothEndsOpen: true)].buffer
        let solution = solver.solution(for: axle, dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped)
        #expect(isTurned(solution.transform) == false)
        #expect(translation(solution.transform) == (0, -2, 0))
    }

    @Test("A part that has to turn is seated at the mouth, not slid")
    func noSlidingWhileTurning() throws {
        let index = LDrawConnectorIndex()
        let solver = LDrawSnapSolver(connectorIndex: index)

        solver.pointsPerUnit = 1
        index.setConnectors(hole(slides: true), forOwner: 1)

        // An axle lying across the hole, 4 LDU above its mouth.
        let across = [connector((-14, 4, 0), axis: (0, 1, 0), profile: [(4, 60, .round)],
                                gender: .male, owner: 2, slide: true)].buffer
        let solution = solver.solution(for: across, dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped)
        #expect(isTurned(solution.transform))
        #expect(landing((-14, 4, 0), by: solution.transform) == (-14, 0, 0))
    }

    @Test("An axle keeps the depth the finger is holding it at")
    func axleSlides() throws {
        let index = LDrawConnectorIndex()
        let solver = LDrawSnapSolver(connectorIndex: index)

        solver.pointsPerUnit = 1
        index.setConnectors(hole(slides: true), forOwner: 1)

        // Held 2 LDU off the axis, and 6 LDU along it from the fixed depth.
        let solution = solver.solution(for: axle(at: (-20, 2, 0), slides: true),
                                       dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped)
        #expect(translation(solution.transform) == (0, -2, 0))      // onto the axis, not along it
    }

    @Test("A part that does not slide is pulled to its depth")
    func withoutSliding() throws {
        let index = LDrawConnectorIndex()
        let solver = LDrawSnapSolver(connectorIndex: index)

        solver.pointsPerUnit = 1
        index.setConnectors(hole(slides: false), forOwner: 1)

        let solution = solver.solution(for: axle(at: (-20, 2, 0), slides: false),
                                       dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped)
        #expect(translation(solution.transform) == (6, -2, 0))      // back to the hole's mouth
    }
}


@Suite("Looking along the line of sight through the finger")
struct SightTests {

    /// A line looking straight down through a point, from high above it.
    private func lookingDown(at x: Double, _ z: Double, holding grab: (Double, Double, Double)) -> LDrawSightLine {
        LDrawSightLine(origin: V3Make(x, -1000, z), direction: V3Make(0, 1, 0),
                       grab: V3Make(grab.0, grab.1, grab.2), surface: .infinity)
    }

    @Test("A placement far below the part, but under the finger, is found")
    func depthDoesNotCount() throws {
        let scene = SnapScene()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        // 500 LDU above the brick, far past any reach measured in the model,
        // but right over it on screen.
        let moving = try SnapScene.connectors("3001.dat", at: (0, -500, 0), owner: 99)
        let solution = scene.solver.solution(for: moving,
                                             alongSight: lookingDown(at: 0, 0, holding: (0, -500, 0)),
                                             dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped)
        #expect(solution.voteCount == 8)
        #expect(landing((0, 0, 0), by: solution.transform).y == 476)     // down onto its studs
    }

    @Test("The nearest surface under the finger wins over one behind it")
    func nearestWins() throws {
        let scene = SnapScene()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)           // low
        try scene.place("3001.dat", at: (0, -100, 0), owner: 2)        // high, in front of it

        let moving = try SnapScene.connectors("3001.dat", at: (0, -500, 0), owner: 99)
        let solution = scene.solver.solution(for: moving,
                                             alongSight: lookingDown(at: 0, 0, holding: (0, -500, 0)),
                                             dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped)
        #expect(landing((0, 0, 0), by: solution.transform).y == 376)     // onto the high one
    }

    @Test("A placement well to the side of the finger is not taken")
    func besideIsNotUnder() throws {
        let scene = SnapScene()

        try scene.place("3001.dat", at: (400, 0, 0), owner: 1)

        let moving = try SnapScene.connectors("3001.dat", at: (0, -500, 0), owner: 99)
        let solution = scene.solver.solution(for: moving,
                                             alongSight: lookingDown(at: 0, 0, holding: (0, -500, 0)),
                                             dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped == false)
    }

    /// A free brick low down, and in front of it a brick whose studs are all
    /// capped with tiles, so nothing can land on it.
    private func cappedInFront() throws -> SnapScene {
        let scene = SnapScene()
        var owner: UInt32 = 3

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)
        try scene.place("3001.dat", at: (0, -100, 0), owner: 2)

        for x in [-30.0, -10, 10, 30] {
            for z in [-10.0, 10] {
                try scene.place("3070b.dat", at: (x, -108, z), owner: owner)
                owner += 1
            }
        }
        return scene
    }

    @Test("A surface whose studs are all taken does not stop the search for one behind it")
    func takenSurfaceIsPassedOver() throws {
        let scene = try cappedInFront()
        let moving = try SnapScene.connectors("3001.dat", at: (0, -500, 0), owner: 99)
        let solution = scene.solver.solution(for: moving,
                                             alongSight: lookingDown(at: 0, 0, holding: (0, -500, 0)),
                                             dragDirection: V3Make(0, 0, 0))

        // The capped studs are passed over, and the next free place along the
        // line is under the capped brick, its studs up in the brick's holes.
        #expect(solution.snapped)
        #expect(solution.voteCount == 8)
        #expect(landing((0, 0, 0), by: solution.transform).y == 424)
    }

    @Test("A part does not land out of sight, behind what the finger sees")
    func hiddenIsNotTaken() throws {
        let scene = try cappedInFront()
        let moving = try SnapScene.connectors("3001.dat", at: (0, -500, 0), owner: 99)
        var sight = lookingDown(at: 0, 0, holding: (0, -500, 0))

        // The finger sees the tops of the tiles. Under the capped brick, and
        // on the low one, the part would be behind them.
        sight.surface = 1000 - 108

        #expect(scene.solver.solution(for: moving, alongSight: sight,
                                      dragDirection: V3Make(0, 0, 0)).snapped == false)
    }

    @Test("Across the screen, the reach is measured from the finger")
    func reachIsOnScreen() throws {
        let scene = SnapScene()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        // A 1x1 plate held by its one hole. The brick's last stud is at 30:
        // the finger 15 past it is in the 22 pt reach, 30 past it is not.
        let near = try SnapScene.connectors("3024.dat", at: (45, -500, 0), owner: 99)
        let far = try SnapScene.connectors("3024.dat", at: (60, -500, 0), owner: 99)

        let taken = scene.solver.solution(for: near,
                                          alongSight: lookingDown(at: 45, 0, holding: (45, -500, 0)),
                                          dragDirection: V3Make(0, 0, 0))

        scene.solver.releaseHold()

        let passed = scene.solver.solution(for: far,
                                           alongSight: lookingDown(at: 60, 0, holding: (60, -500, 0)),
                                           dragDirection: V3Make(0, 0, 0))

        #expect(taken.snapped)
        #expect(passed.snapped == false)
    }

    /// An axle 60 long along X from the origin, with a wheel on it from 20 to
    /// 40, both open at both ends.
    private func axleWithAWheel() -> SnapScene {
        let scene = SnapScene()

        scene.index.setConnectors([connector((0, 0, 0), axis: (1, 0, 0), profile: [(6, 60, .axle)],
                                             gender: .male, owner: 1, slide: true,
                                             bothEndsOpen: true)].buffer, forOwner: 1)
        scene.index.setConnectors([connector((20, 0, 0), axis: (1, 0, 0), profile: [(6, 20, .axle)],
                                             gender: .female, owner: 2, slide: true,
                                             bothEndsOpen: true)].buffer, forOwner: 2)
        return scene
    }

    /// A disc 10 thick with an axle hole, facing the far end of the axle.
    private func disc(at position: (Double, Double, Double)) -> LDrawWorldConnectors {
        [connector(position, axis: (-1, 0, 0), profile: [(6, 10, .axle)], gender: .female,
                   owner: 99, slide: true, bothEndsOpen: true)].buffer
    }

    @Test("A disc slides along an axle to come under the finger")
    func slidesUnderTheFinger() throws {
        let scene = axleWithAWheel()

        // Held above the axle by its outer face, and seen at a slant: the
        // line of sight meets the axle at 55.
        let direction = V3Normalize(V3Make(1, 1, 0))
        let sight = LDrawSightLine(origin: V3Sub(V3Make(5, -50, 0), V3MulScalar(direction, 1000)),
                                   direction: direction, grab: V3Make(5, -50, 0), surface: .infinity)
        let solution = scene.solver.solution(for: disc(at: (5, -50, 0)), alongSight: sight,
                                             dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped)
        #expect(landing((5, -50, 0), by: solution.transform) == (55, 0, 0))
    }

    @Test("A disc pushed along an axle seen end on stops at the wheel")
    func stopsAtTheWheel() throws {
        let scene = axleWithAWheel()

        // Looking along the axle from its far end, holding the disc so deep
        // that it would sit in the wheel.
        let sight = LDrawSightLine(origin: V3Make(1000, 0, 0), direction: V3Make(-1, 0, 0),
                                   grab: V3Make(42, 0, 0), surface: .infinity)
        let solution = scene.solver.solution(for: disc(at: (42, 0, 0)), alongSight: sight,
                                             dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped)
        #expect(landing((42, 0, 0), by: solution.transform) == (50, 0, 0))
    }
}


@Suite("Refusing a placement that is through another part")
struct ClashTests {

    /// The space a plate or brick of this size fills, from its origin: LDraw
    /// parts have their origin on the top face.
    private func bounds(width: Double, height: Double, depth: Double,
                        at position: (Double, Double, Double)) -> Box3 {
        V3BoundsFromPoints(V3Make(position.0 - width / 2, position.1, position.2 - depth / 2),
                           V3Make(position.0 + width / 2, position.1 + height, position.2 + depth / 2))
    }

    @Test("A wide plate does not land through a small one beside it")
    func doesNotSwallowASmallPlate() throws {
        let scene = SnapScene()
        let field = try SnapScene.connectors("10a.dat", at: (0, 0, 0), owner: 1)
        let small = try SnapScene.connectors("3024.dat", at: (0, -8, 0), owner: 2)

        scene.index.setConnectors(field, bounds: bounds(width: 480, height: 8, depth: 640,
                                                        at: (0, 0, 0)), forOwner: 1)
        scene.index.setConnectors(small, bounds: bounds(width: 20, height: 8, depth: 20,
                                                        at: (0, -8, 0)), forOwner: 2)

        // A 2x4 plate over the small one, resting on its stud. Landing on the
        // baseplate instead would hold it on more studs, but drive it through
        // the small plate.
        let moving = try SnapScene.connectors("3020.dat", at: (0, -16, 0), owner: 99)

        scene.solver.addMovingBounds(bounds(width: 80, height: 8, depth: 40, at: (0, -16, 0)))

        let solution = scene.solver.solution(for: moving, dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped)
        #expect(landing((0, 0, 0), by: solution.transform).y == 0)      // stays on the small plate
    }

    @Test("A plate goes onto the small plate under the finger, not onto more studs beside it")
    func smallPartUnderTheFinger() throws {
        let scene = SnapScene()
        let brick = try SnapScene.connectors("3001.dat", at: (0, 0, 0), owner: 1)
        let small = try SnapScene.connectors("3024.dat", at: (-10, -8, -10), owner: 2)

        scene.index.setConnectors(brick, bounds: bounds(width: 80, height: 24, depth: 40,
                                                        at: (0, 0, 0)), forOwner: 1)
        scene.index.setConnectors(small, bounds: bounds(width: 20, height: 8, depth: 20,
                                                        at: (-10, -8, -10)), forOwner: 2)

        // A 2x4 plate at the height of the brick's studs, held over one of its
        // holes, with the finger over the 1x1 plate. The brick offers four
        // studs a stud's width away.
        let moving = try SnapScene.connectors("3020.dat", at: (0, -8, 0), owner: 99)
        let sight = LDrawSightLine(origin: V3Make(-10, -1000, -10), direction: V3Make(0, 1, 0),
                                   grab: V3Make(-10, -8, -10), surface: 1000 - 8)

        scene.solver.addMovingBounds(bounds(width: 80, height: 8, depth: 40, at: (0, -8, 0)))

        let solution = scene.solver.solution(for: moving, alongSight: sight, dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped)
        #expect(solution.voteCount == 1)
        #expect(landing((-10, -8, -10), by: solution.transform) == (-10, -16, -10))
    }

    @Test("Without bounds the same placement is allowed")
    func withoutBoundsItGoesThrough() throws {
        let scene = SnapScene()

        try scene.place("10a.dat", at: (0, 0, 0), owner: 1)
        try scene.place("3024.dat", at: (0, -8, 0), owner: 2)

        let moving = try SnapScene.connectors("3020.dat", at: (0, -16, 0), owner: 99)
        let solution = scene.solver.solution(for: moving, dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped)
        #expect(landing((0, 0, 0), by: solution.transform).y == 8)      // down onto the baseplate
    }

    @Test("Parts that hold each other may share as much space as they like")
    func joinedPartsMayOverlap() throws {
        let scene = SnapScene()
        let field = try SnapScene.connectors("3001.dat", at: (0, 0, 0), owner: 1)

        // A box far taller than the brick, as a hinge or a clip reaches into
        // the part it holds.
        scene.index.setConnectors(field, bounds: bounds(width: 80, height: 24, depth: 40,
                                                        at: (0, -48, 0)), forOwner: 1)

        let moving = try SnapScene.connectors("3001.dat", at: (0, -28, 0), owner: 99)

        scene.solver.clearMovingBounds()
        scene.solver.addMovingBounds(bounds(width: 80, height: 24, depth: 40, at: (0, -28, 0)))

        // The boxes overlap by 20, far more than a stud, but the placement is
        // what joins the two.
        let solution = scene.solver.solution(for: moving, dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped)
        #expect(solution.voteCount == 8)
    }

    @Test("A part can go back where it was built, whatever its box overlaps there")
    func goesBackWhereItWasBuilt() throws {
        let scene = SnapScene()
        let field = try SnapScene.connectors("10a.dat", at: (0, 0, 0), owner: 1)
        let beside = try SnapScene.connectors("3024.dat", at: (35, -8, 0), owner: 2)

        scene.index.setConnectors(field, bounds: bounds(width: 480, height: 8, depth: 640,
                                                        at: (0, 0, 0)), forOwner: 1)
        // A part whose box reaches 20 LDU into the brick's, not joined to it,
        // as a slope's box covers space its shape leaves free.
        scene.index.setConnectors(beside, bounds: bounds(width: 40, height: 24, depth: 20,
                                                         at: (40, -24, 0)), forOwner: 2)

        let moving = try SnapScene.connectors("3001.dat", at: (0, -24, 0), owner: 99)

        scene.solver.clearMovingBounds()
        scene.solver.addMovingBounds(bounds(width: 80, height: 24, depth: 40, at: (0, -24, 0)))

        let refused = scene.solver.solution(for: moving, dragDirection: V3Make(0, 0, 0))

        scene.solver.releaseHold()
        scene.solver.excusePartsItOverlaps()                // where the drag began

        let home = scene.solver.solution(for: moving, dragDirection: V3Make(0, 0, 0))

        #expect(refused.snapped == false || landing((0, 0, 0), by: refused.transform) != (0, 0, 0))
        #expect(home.snapped)
        #expect(landing((0, 0, 0), by: home.transform) == (0, 0, 0))
    }

    @Test("A part it overlapped where it was built still blocks it anywhere else")
    func excusedOnlyWhereItWasBuilt() throws {
        let scene = SnapScene()
        let field = try SnapScene.connectors("10a.dat", at: (0, 0, 0), owner: 1)
        let beside = try SnapScene.connectors("3024.dat", at: (35, -8, 0), owner: 2)

        scene.solver.acquireDistance = 10       // only the placement one stud over
        scene.index.setConnectors(field, bounds: bounds(width: 480, height: 8, depth: 640,
                                                        at: (0, 0, 0)), forOwner: 1)
        scene.index.setConnectors(beside, bounds: bounds(width: 40, height: 24, depth: 20,
                                                         at: (40, -24, 0)), forOwner: 2)

        scene.solver.clearMovingBounds()
        scene.solver.addMovingBounds(bounds(width: 80, height: 24, depth: 40, at: (0, -24, 0)))
        scene.solver.excusePartsItOverlaps()

        // One stud further into the other part's box.
        let moving = try SnapScene.connectors("3001.dat", at: (20, -24, 0), owner: 99)

        scene.solver.clearMovingBounds()
        scene.solver.addMovingBounds(bounds(width: 80, height: 24, depth: 40, at: (20, -24, 0)))

        #expect(scene.solver.solution(for: moving, dragDirection: V3Make(0, 0, 0)).snapped == false)
    }

    @Test("Every part of a large submodel is tested for clashes")
    func everyPartIsTested() throws {
        let scene = SnapScene()
        let field = try SnapScene.connectors("10a.dat", at: (0, 0, 0), owner: 1)
        let beside = try SnapScene.connectors("3024.dat", at: (35, -8, 0), owner: 2)

        scene.index.setConnectors(field, bounds: bounds(width: 480, height: 8, depth: 640,
                                                        at: (0, 0, 0)), forOwner: 1)
        scene.index.setConnectors(beside, bounds: bounds(width: 40, height: 24, depth: 20,
                                                         at: (40, -24, 0)), forOwner: 2)

        // 600 parts, of which only the last reaches into the other part.
        let moving = try SnapScene.connectors("3001.dat", at: (0, -24, 0), owner: 99)

        scene.solver.clearMovingBounds()
        for _ in 0..<599 {
            scene.solver.addMovingBounds(bounds(width: 20, height: 8, depth: 20, at: (-30, -24, 0)))
        }
        scene.solver.addMovingBounds(bounds(width: 80, height: 24, depth: 40, at: (0, -24, 0)))

        let solution = scene.solver.solution(for: moving, dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped == false || landing((0, 0, 0), by: solution.transform) != (0, 0, 0))
    }

    @Test("A thing made of parts fits into the gap between them")
    func fitsIntoAGap() throws {
        let scene = SnapScene()
        let field = try SnapScene.connectors("10a.dat", at: (0, 0, 0), owner: 1)

        scene.index.setConnectors(field, bounds: bounds(width: 480, height: 8, depth: 640,
                                                       at: (0, 0, 0)), forOwner: 1)

        // Two bricks 100 apart with a bar over them, as a submodel's parts
        // stand: one box around all three covers the gap, the parts do not.
        let over = LDrawWorldConnectors()

        over.add(try SnapScene.connectors("3001.dat", at: (-100, -24, 0), owner: 2))
        over.add(try SnapScene.connectors("3001.dat", at: (100, -24, 0), owner: 2))
        scene.index.setConnectors(over, forOwner: 2)
        scene.index.addBounds(bounds(width: 80, height: 24, depth: 40, at: (-100, -24, 0)),
                              forOwner: 2)
        scene.index.addBounds(bounds(width: 80, height: 24, depth: 40, at: (100, -24, 0)),
                              forOwner: 2)

        // A brick into the gap between them, on the baseplate.
        let moving = try SnapScene.connectors("3001.dat", at: (0, -28, 0), owner: 99)

        scene.solver.clearMovingBounds()
        scene.solver.addMovingBounds(bounds(width: 80, height: 24, depth: 40, at: (0, -28, 0)))

        let solution = scene.solver.solution(for: moving, dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped)
        #expect(solution.voteCount == 8)
    }

    @Test("A part still lands on one it touches")
    func touchingIsNotClashing() throws {
        let scene = SnapScene()
        let field = try SnapScene.connectors("10a.dat", at: (0, 0, 0), owner: 1)

        scene.index.setConnectors(field, bounds: bounds(width: 480, height: 8, depth: 640,
                                                        at: (0, 0, 0)), forOwner: 1)

        // A brick just above the baseplate: its studs stand in the brick's
        // holes, which is how parts hold each other.
        let moving = try SnapScene.connectors("3001.dat", at: (0, -28, 0), owner: 99)

        scene.solver.addMovingBounds(bounds(width: 80, height: 24, depth: 40, at: (0, -28, 0)))

        let solution = scene.solver.solution(for: moving, dragDirection: V3Make(0, 0, 0))

        #expect(solution.snapped)
        #expect(solution.voteCount == 8)
    }
}


@Suite("Riding the surface under a part")
struct RestingDropTests {

    private let reach = 240.0                   // ten bricks

    @Test("A part held above a brick falls to its studs")
    func fallsToTheStuds() throws {
        let scene = SnapScene()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        let above = try SnapScene.connectors("3001.dat", at: (0, -24 - 80, 0), owner: 99)

        #expect(scene.solver.restingDrop(for: above, within: reach) == 80)
    }

    @Test("A part already resting stays where it is")
    func restingStays() throws {
        let scene = SnapScene()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        let resting = try SnapScene.connectors("3001.dat", at: (0, -24, 0), owner: 99)

        #expect(scene.solver.restingDrop(for: resting, within: reach) == 0)
    }

    @Test("A part over nothing keeps its height")
    func overNothing() throws {
        let scene = SnapScene()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        // Well to the side of the brick, where no stud is under it.
        let away = try SnapScene.connectors("3001.dat", at: (400, -100, 0), owner: 99)

        #expect(scene.solver.restingDrop(for: away, within: reach) == 0)
    }

    @Test("A part rests on the highest thing under it")
    func restsOnTheHighest() throws {
        let scene = SnapScene()

        try scene.place("3024.dat", at: (0, 0, 0), owner: 1)        // a plate, top at 0
        try scene.place("3001.dat", at: (20, -48, 0), owner: 2)     // a brick standing higher

        // A plate high above both. Its holes are 8 LDU under its origin, at
        // -140, and the brick's studs are at -48, so it stops on the brick
        // after 92 and not on the plate's studs at 0.
        let above = try SnapScene.connectors("3020.dat", at: (10, -148, 0), owner: 99)

        #expect(scene.solver.restingDrop(for: above, within: reach) == 92)
    }

    @Test("A part sliding onto a brick is lifted onto its studs")
    func risesOntoABrick() throws {
        let scene = SnapScene()

        try scene.place("10a.dat", at: (0, 0, 0), owner: 1)          // a baseplate, studs at 0
        try scene.place("3001.dat", at: (0, -24, 0), owner: 2)      // a brick standing on it

        // A plate at plate height, its holes at 0, slid over the brick.
        let sunk = try SnapScene.connectors("3020.dat", at: (0, -8, 0), owner: 99)

        #expect(scene.solver.restingDrop(for: sunk, within: reach) == -24)
    }

    @Test("A stud with a part already on it is passed over")
    func coveredStudsAreSkipped() throws {
        let scene = SnapScene()

        try scene.place("10a.dat", at: (0, 0, 0), owner: 1)
        try scene.place("3001.dat", at: (0, -24, 0), owner: 2)      // on the baseplate
        try scene.place("3001.dat", at: (0, -48, 0), owner: 3)      // and another on that

        // Over the stack at baseplate level: the lower brick's studs are
        // covered, so the plate rises to the top of the stack, not into it.
        let sunk = try SnapScene.connectors("3020.dat", at: (0, -8, 0), owner: 99)

        #expect(scene.solver.restingDrop(for: sunk, within: reach) == -48)
    }

    @Test("A part does not rest on itself")
    func notOnItself() throws {
        let scene = SnapScene()
        let alone = try SnapScene.connectors("3001.dat", at: (0, -100, 0), owner: 1)

        scene.index.setConnectors(alone, forOwner: 1)

        #expect(scene.solver.restingDrop(for: alone, within: reach) == 0)
    }
}


@Suite("Drawing a part down onto what is under it")
struct SnapDropTests {

    /// A scene that draws a part down onto what is under it, as a host that
    /// places by dropping would set it.
    private func dropping() -> SnapScene {
        let scene = SnapScene()

        scene.solver.dropReach = 120       // five bricks

        return scene
    }

    @Test("A part held well above a brick lands on it")
    func fallsOntoABrick() throws {
        let scene = dropping()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        // 80 LDU up is 80 points at this zoom, far past the 40 pt release, and
        // within the drop.
        let solution = try scene.drag("3001.dat", to: (0, -24 - 80, 0))

        #expect(solution.snapped)
        #expect(solution.voteCount == 8)
        #expect(landing((0, 0, 0), by: solution.transform).y == 80)     // the whole way down
    }

    @Test("Without the drop the same part stays in the air")
    func staysUpWithoutTheDrop() throws {
        let scene = SnapScene()                 // the drop reach is 0 by default

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        #expect(try scene.drag("3001.dat", to: (0, -24 - 80, 0)).snapped == false)
    }

    @Test("A part below is not drawn up")
    func doesNotRise() throws {
        let scene = dropping()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        // The same distance under the brick, where its studs are out of reach.
        #expect(try scene.drag("3001.dat", to: (0, 80, 0)).snapped == false)
    }

    @Test("A near placement still wins over a long drop")
    func nearnessStillCounts() throws {
        let scene = dropping()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)
        try scene.place("3001.dat", at: (200, -24 - 200, 0), owner: 2)

        // Beside the brick that is high up, and far above the low one.
        let solution = try scene.drag("3001.dat", to: (200, -24 - 200 - 24 - 4, 0))

        #expect(solution.snapped)
        #expect(landing((0, 0, 0), by: solution.transform).y == 4)      // onto the near brick
    }
}


@Suite("Holding a placement and letting it go")
struct SnapHysteresisTests {

    @Test("A placement is taken up close, kept while it is pulled, and let go")
    func acquireHoldRelease() throws {
        let scene = SnapScene()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        let acquired = try scene.drag("3001.dat", to: (0, -24 - 15, 0))
        let held = try scene.drag("3001.dat", to: (0, -24 - 30, 0))
        let released = try scene.drag("3001.dat", to: (0, -24 - 45, 0))

        #expect(acquired.snapped)                       // 15 pt: inside the 22 pt reach
        #expect(held.snapped)                           // 30 pt: past it, but held
        #expect(translation(held.transform) == (0, 30, 0))
        #expect(released.snapped == false)              // 45 pt: past the 40 pt release
    }

    @Test("A placement is not taken up from beyond the reach")
    func acquireNeedsCloseness() throws {
        let scene = SnapScene()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        #expect(try scene.drag("3001.dat", to: (0, -24 - 30, 0)).snapped == false)
    }

    @Test("A finger shaking between two answers does not flicker")
    func noFlicker() throws {
        let scene = SnapScene()
        var landings: [Double] = []

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        // Halfway between two stud rows, where both placements score the same,
        // with small jitter across the middle.
        for jitter in [0.0, 0.4, -0.4, 0.3, -0.5, 0.2, -0.3] {
            let solution = try scene.drag("3001.dat", to: (10 + jitter, -24, 0))

            #expect(solution.snapped)
            landings.append((10 + jitter + translation(solution.transform).x).rounded())
        }

        #expect(Set(landings) == [landings[0]])
    }

    @Test("A placement the part agrees with better takes over")
    func switchesForAClearlyBetterOne() throws {
        let scene = SnapScene()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        // First held by one stud at the end of the brick, then moved to where
        // all eight studs match.
        let single = try scene.drag("3001.dat", to: (60, -24 + 6, 0))
        let whole = try scene.drag("3001.dat", to: (2, -24, 0))

        #expect(single.snapped)
        #expect(whole.snapped)
        #expect(whole.voteCount == 8)
    }

    @Test("A held placement with fewer connectors is still kept")
    func holdSurvivesARicherNeighbor() throws {
        let scene = SnapScene()

        // Nothing may take the hold over: only a placement 100 LDU nearer
        // could.
        scene.solver.switchMargin = 100
        scene.solver.acquireDistance = 10       // the four-stud placement is 20 away
        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        // Two studs deep over the end of the brick, then nudged towards the
        // four-stud placement 20 LDU away.
        let acquired = try scene.drag("3001.dat", to: (60, -24, 0))
        let nudged = try scene.drag("3001.dat", to: (44, -24, 0))

        #expect(acquired.snapped)
        #expect(acquired.voteCount == 2)
        #expect(nudged.snapped)
        #expect(nudged.voteCount == 2)                  // still the placement it holds
        #expect(landing((0, 0, 0), by: nudged.transform).x == 16)
    }

    @Test("A part slid along a brick moves one stud at a time")
    func oneStudAtATime() throws {
        let scene = SnapScene()
        var landings: [Double] = []

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        // A 1x1 plate slid along the brick's back row, 1 LDU a step.
        for x in stride(from: -30.0, through: 30.0, by: 1.0) {
            let solution = try scene.drag("3024.dat", to: (x, -8, -10))

            #expect(solution.snapped)

            let landed = x + translation(solution.transform).x

            if landings.last != landed {
                landings.append(landed)
            }
        }

        #expect(landings == [-30, -10, 10, 30])
    }

    @Test("A placement keeps its number while it is held, and another gets its own")
    func placementIsNamed() throws {
        let scene = SnapScene()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        // The same landing from two positions, then a landing one stud over.
        let near = try scene.drag("3001.dat", to: (2, -24, 0))
        let again = try scene.drag("3001.dat", to: (6, -24, 0))
        let over = try scene.drag("3001.dat", to: (60, -24 + 6, 0))

        #expect(near.snapped && again.snapped && over.snapped)
        #expect(near.placement == again.placement)
        #expect(over.placement != near.placement)
    }

    @Test("Letting go forgets the placement")
    func releaseHold() throws {
        let scene = SnapScene()

        try scene.place("3001.dat", at: (0, 0, 0), owner: 1)

        #expect(try scene.drag("3001.dat", to: (0, -24 - 15, 0)).snapped)

        scene.solver.releaseHold()

        #expect(try scene.drag("3001.dat", to: (0, -24 - 30, 0)).snapped == false)
    }
}


@Suite("Turning a part to meet a connector")
struct SnapRotationTests {

    @Test("A plate turns onto a stud on the side of a brick")
    func sideStud() throws {
        let scene = SnapScene()

        scene.solver.acquireDistance = 12       // the brick's top stud is 14 away
        try scene.place("4733.dat", at: (0, 0, 0), owner: 1)

        // The stud at (10, 10, 0) points along +X, and the plate's hole,
        // 8 LDU under its origin, points up. The plate can only reach the
        // stud by turning.
        let solution = try scene.drag("3024.dat", to: (10, 2, 0))

        // The distance is how far the middle of the plate's connectors moves
        // while it turns, not how far the hole moves. That middle sits 4 LDU
        // from the plate's origin, so a quarter turn carries it 4 * sqrt(2).
        #expect(solution.snapped)
        #expect(isTurned(solution.transform))
        #expect(abs(solution.distance - 4 * 2.0.squareRoot()) < 0.001)
    }

    @Test("A part is not turned further than it may be")
    func turnIsCapped() throws {
        let scene = SnapScene()

        scene.solver.maximumTurn = 50 * Double.pi / 180     // under the right angle this needs
        scene.solver.acquireDistance = 12
        try scene.place("4733.dat", at: (0, 0, 0), owner: 1)

        #expect(try scene.drag("3024.dat", to: (10, 2, 0)).snapped == false)
    }

    @Test("A part is not turned when it is told not to be")
    func rotationCanBeRefused() throws {
        let scene = SnapScene()

        scene.solver.allowsRotation = false
        scene.solver.acquireDistance = 12
        try scene.place("4733.dat", at: (0, 0, 0), owner: 1)

        #expect(try scene.drag("3024.dat", to: (10, 2, 0)).snapped == false)
    }
}


@Suite("The connector index")
struct ConnectorIndexTests {

    @Test("A part's connectors go in and come out again")
    func addAndRemove() throws {
        let index = LDrawConnectorIndex()
        let brick = try SnapScene.connectors("3001.dat", at: (0, 0, 0), owner: 1)

        index.setConnectors(brick, forOwner: 1)
        #expect(index.connectorCount == 16)             // eight studs, eight holes
        #expect(index.ownerCount == 1)

        index.removeOwner(1)
        #expect(index.connectorCount == 0)
        #expect(index.ownerCount == 0)
    }

    @Test("Giving an owner new connectors replaces the ones it had")
    func replace() throws {
        let index = LDrawConnectorIndex()

        index.setConnectors(try SnapScene.connectors("3001.dat", at: (0, 0, 0), owner: 1), forOwner: 1)
        index.setConnectors(try SnapScene.connectors("3024.dat", at: (0, 0, 0), owner: 1), forOwner: 1)

        #expect(index.connectorCount == 2)              // one stud, one hole
    }

    @Test("A query answers with what reaches into the box, once each")
    func query() throws {
        let index = LDrawConnectorIndex()
        var box = V3BoundsFromPoints(V3Make(-15, -5, -15), V3Make(15, 5, 15))

        index.setConnectors(try SnapScene.connectors("3001.dat", at: (0, 0, 0), owner: 1), forOwner: 1)

        // The four middle studs are in the box, and the four stud holes above
        // them reach into it, from y = 24 up to y = 4. Each is found once,
        // though it spans several cells.
        #expect(index.connectors(inBox: box, excludingOwner: 0).count == 8)

        box = V3BoundsFromPoints(V3Make(-100, -100, -100), V3Make(100, 100, 100))
        #expect(index.connectors(inBox: box, excludingOwner: 1).count == 0)
    }

    @Test("A long run is held all the way along, and found at its far end")
    func longRun() throws {
        let index = LDrawConnectorIndex()

        // An axle 16 studs long, standing up: 320 LDU through 40 cells.
        index.setConnectors([connector((0, 0, 0), axis: (0, 1, 0), profile: [(4, 320, .round)],
                                       gender: .male, owner: 1, slide: true)].buffer, forOwner: 1)

        let atTheFarEnd = V3BoundsFromPoints(V3Make(-1, 310, -1), V3Make(1, 318, 1))
        let beyondIt = V3BoundsFromPoints(V3Make(-1, 330, -1), V3Make(1, 338, 1))

        #expect(index.connectors(inBox: atTheFarEnd, excludingOwner: 0).count > 0)
        #expect(index.connectors(inBox: beyondIt, excludingOwner: 0).count == 0)

        index.removeOwner(1)
        #expect(index.connectors(inBox: atTheFarEnd, excludingOwner: 0).count == 0)
    }

    @Test("A run at an angle is held in the cells it crosses")
    func slantedRun() throws {
        let index = LDrawConnectorIndex()
        let across = (1.0 / 3.0.squareRoot(), 1.0 / 3.0.squareRoot(), 1.0 / 3.0.squareRoot())

        // A diagonal run through the corners of the cells.
        index.setConnectors([connector((0, 0, 0), axis: across, profile: [(4, 60, .round)],
                                       gender: .male, owner: 1)].buffer, forOwner: 1)

        let midway = V3BoundsFromPoints(V3Make(30, 30, 30), V3Make(32, 32, 32))

        #expect(index.connectors(inBox: midway, excludingOwner: 0).count > 0)

        index.removeOwner(1)
        #expect(index.connectorCount == 0)
        #expect(index.connectors(inBox: midway, excludingOwner: 0).count == 0)
    }

    @Test("The index keeps what it was given, not what the caller adds later")
    func indexTakesASnapshot() throws {
        let index = LDrawConnectorIndex()
        let brick = try SnapScene.connectors("3001.dat", at: (0, 0, 0), owner: 1)

        index.setConnectors(brick, forOwner: 1)
        brick.add(try SnapScene.connectors("3001.dat", at: (0, -24, 0), owner: 1))

        #expect(index.connectorCount == 16)

        index.removeOwner(1)
        #expect(index.connectorCount == 0)
    }

    @Test("A baseplate's studs are all indexed")
    func baseplate() throws {
        let index = LDrawConnectorIndex()

        index.setConnectors(try SnapScene.connectors("10a.dat", at: (0, 0, 0), owner: 1), forOwner: 1)

        #expect(index.connectorCount >= 764)
    }
}
