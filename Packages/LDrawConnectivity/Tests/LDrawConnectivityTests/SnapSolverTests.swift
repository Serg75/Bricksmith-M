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
               owner: UInt32 = 1, slide: Bool = false, centered: Bool = false) -> LDrawWorldConnector {
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
                               centered: centered, slide: slide)
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

    @Test("A second beam goes on the free length of an axle, but not over the first")
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

        #expect(free.snapped)                   // past the first beam
        #expect(over.snapped == false)          // where the first beam already is
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

        // Nothing may take the hold over: only a placement scoring twice as
        // well as the held one could.
        scene.solver.switchMargin = 2.0
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
