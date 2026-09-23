//
//  ShadowConnectivityTests.swift
//  LDrawConnectivityTests
//
//  Tests for connectors read from the LDCad shadow library. Expected values
//  are worked out by hand from the fixture's shadow files.
//
//  Created by Sergey Slobodenyuk on 2026-09-20.
//

import Testing
import Foundation
import LDrawCore
import LDrawConnectivity

@Suite("Connectors from the shadow library")
struct ShadowConnectivityTests {

    private static let up = (0.0, -1.0, 0.0)

    private func set(_ partName: String) throws -> LDrawConnectorSet {
        try #require(ConnectivityFixtures.shadowConnectorSet(partName))
    }

    private func sections(_ set: LDrawConnectorSet, _ connector: LDrawConnector) -> [LDrawConnectorSection] {
        (0..<Int(connector.sectionCount)).map {
            set.section(at: UInt(Int(connector.sectionOffset) + $0))
        }
    }

    /// A male stud with one round section, radius 6 and length 4.
    private func isPlainStud(_ set: LDrawConnectorSet, _ connector: LDrawConnector) -> Bool {
        let profile = sections(set, connector)

        return connector.gender == .male && profile.count == 1
            && profile[0].shape == .round && profile[0].radius == 6 && profile[0].length == 4
    }


    // MARK: - What the library says about a part

    @Test("A 2 x 4 brick has eight stud holes on its underside, in one record")
    func brick2x4Holes() throws {
        let brick = try set("3001.dat")
        let holes = try #require(brick.connectors.first { $0.gender == .female })
        var expected = Set<ConnectorPoint>()

        for x in [-30.0, -10, 10, 30] {
            for z in [-10.0, 10] {
                expected.insert(ConnectorPoint(x, 24, z, axis: Self.up))
            }
        }

        #expect(brick.connectors.filter { $0.gender == .female }.count == 1)
        #expect(holes.grid.countX == 4)
        #expect(holes.grid.countZ == 2)
        #expect(holes.grid.centeredX)
        #expect(holes.grid.centeredZ)
        #expect(holes.provenance == .inherited)
        #expect(sections(brick, holes) == [LDrawConnectorSection(radius: 6, length: 20, shape: .round)])
        #expect(Set(holes.points.map { ConnectorPoint($0, axis: holes.axis) }) == expected)
    }

    @Test("A grid of one row along Z yields one row of connectors")
    func singleRowGrid() throws {
        let bracket = try set("99207.dat")
        let holes = try #require(bracket.connectors.first {
            $0.gender == .female && $0.grid.countX == 2
        })

        #expect(holes.grid.countZ == 1)
        #expect(Set(holes.points.map { ConnectorPoint($0, axis: holes.axis) }) == [
            ConnectorPoint(-10, 8, 0, axis: Self.up),
            ConnectorPoint(10, 8, 0, axis: Self.up),
        ])
    }

    @Test("A profile of several sections is kept in order")
    func multipleSections() throws {
        let plate = try set("3062b.dat")
        let hole = try #require(plate.connectors.first {
            $0.gender == .female && $0.provenance == .shadow
        })

        #expect(sections(plate, hole) == [
            LDrawConnectorSection(radius: 6, length: 20, shape: .round),
            LDrawConnectorSection(radius: 4, length: 8, shape: .round),
        ])
        #expect(hole.caps == LDrawConnectorCaps.none)
    }

    @Test("A Technic brick's cross holes are centered, slide, and lie across each other")
    func technicHoles() throws {
        let brick = try set("4733.dat")
        let holes = brick.connectors.filter { $0.centered }

        #expect(holes.count == 2)
        for hole in holes {
            #expect(hole.slide)
            #expect(hole.gender == .female)
            #expect(sections(brick, hole) == [LDrawConnectorSection(radius: 4, length: 28, shape: .round)])
            #expect(ConnectorPoint(hole.position.x, hole.position.y, hole.position.z,
                                   axis: (0, 0, 0)) == ConnectorPoint(0, 10, 0, axis: (0, 0, 0)))
        }
        #expect(Set(holes.map { ConnectorPoint($0) }) == [
            ConnectorPoint(0, 10, 0, axis: (0, 0, 1)),
            ConnectorPoint(0, 10, 0, axis: (-1, 0, 0)),
        ])
    }


    // MARK: - The rules of the walk

    @Test("A meta that is commented out is not read")
    func commentedMetaIsOff() throws {
        // stud4.dat's female tube is commented out in the shadow library,
        // because a brick's tubes sit between studs rather than under them.
        #expect(try set("stud4.dat").connectorCount == 0)
    }

    @Test("SNAP_INCL brings another file's connectors")
    func include() throws {
        let stud = try set("stud10.dat")
        let male = try #require(stud.connectors.first)

        #expect(stud.connectorCount == 1)
        #expect(ConnectorPoint(male) == ConnectorPoint(0, 0, 0, axis: Self.up))
        #expect(male.provenance == .inherited)
    }

    @Test("A part that both includes a subpart and uses it keeps one set of connectors")
    func includeDoesNotDouble() throws {
        // 3003's shadow file includes s/3003s01.dat, which its geometry also
        // references, so every connector is found twice and kept once.
        let brick = try set("3003.dat")

        #expect(brick.connectors.filter { $0.gender == .female }.count == 2)
        #expect(brick.connectors.filter { isPlainStud(brick, $0) }.count == 4)
    }

    @Test("SNAP_CLEAR drops everything a part inherited")
    func clearAll() throws {
        // 6141 clears the plain stud from its geometry and defines its own.
        let plate = try set("6141.dat")

        #expect(plate.connectorCount == 3)
        for connector in plate.connectors {
            #expect(connector.provenance == .shadow)
        }
        #expect(plate.connectors.filter { isPlainStud(plate, $0) }.isEmpty)
    }

    @Test("SNAP_CLEAR with an id drops only what carries that name")
    func clearByIdentifier() throws {
        // 3941 replaces the axle hole inside it with a deeper profile of its
        // own, and keeps its four studs and its stud holes.
        let brick = try set("3941.dat")
        let axleHoles = brick.connectors.filter { connector in
            sections(brick, connector).contains { $0.shape == .axle }
        }

        #expect(brick.connectors.filter { isPlainStud(brick, $0) }.count == 4)
        #expect(axleHoles.count == 1)
        #expect(sections(brick, try #require(axleHoles.first)) == [
            LDrawConnectorSection(radius: 6, length: 4, shape: .round),
            LDrawConnectorSection(radius: 6, length: 20, shape: .axle),
        ])
    }


    // MARK: - Scaled and mirrored references

    @Test("A stretched tube makes a longer connector, and a negative scale turns it over",
          arguments: zip(["3004.dat", "3023b.dat"], [20.0, 4.0]))
    func scaledTube(part: String, length: Double) throws {
        // stud3.dat says scale=YOnly, and both parts place it with a negative
        // Y scale: -5 in the brick, -1 in the plate.
        let piece = try set(part)
        let tube = try #require(piece.connectors.first { connector in
            sections(piece, connector).contains { $0.radius == 4 }
        })

        #expect(ConnectorPoint(tube) == ConnectorPoint(0, 4, 0, axis: (0, 1, 0)))
        #expect(sections(piece, tube) == [LDrawConnectorSection(radius: 4, length: length, shape: .round)])
    }

    @Test("A stud keeps its size inside a scaled reference")
    func studDoesNotScale() throws {
        // The same brick scales stud3 by -5 without touching its studs.
        let brick = try set("3004.dat")

        #expect(brick.connectors.filter { isPlainStud(brick, $0) }.count == 2)
    }


    // MARK: - Provenance

    @Test("Every derived stud is found through the shadow library as well", arguments:
        ["3005", "3004", "3003", "3001", "3024", "3023b", "3022", "3020",
         "3070b", "3069b", "3794b", "15573", "3062b", "3941",
         "3660", "3665", "44728", "99207", "87087", "4733", "3040b", "3298",
         "3037", "10a"])
    func shadowFindsEveryDerivedStud(part: String) throws {
        // 6141 and 4073 are left out, because their shadow files clear the
        // plain stud.
        let shadow = try set(part + ".dat")
        let primitive = try #require(ConnectivityFixtures.connectorSet(part + ".dat"))

        #expect(Set(primitive.connectors.flatMap(\.connectorPoints))
                .isSubset(of: Set(shadow.connectors.filter { isPlainStud(shadow, $0) }
                                                   .flatMap(\.connectorPoints))))
    }

    @Test("The stud under an inverted slope is where the shadow library puts it")
    func invertedSlope() throws {
        // 3665 uses stud2a stretched to twice its height. The derived stud is
        // at the primitive's origin, and the shadow library also adds one at
        // the far end.
        let slope = try set("3665.dat")
        let studs = Set(slope.connectors.filter { isPlainStud(slope, $0) }.flatMap(\.connectorPoints))

        #expect(studs == [
            ConnectorPoint(0, 0, 0, axis: Self.up),
            ConnectorPoint(0, 4, -20, axis: Self.up),
            ConnectorPoint(0, 0, -20, axis: Self.up),
        ])
    }

    @Test("A part that is one reference to another has that part's connectors")
    func aliasPart() throws {
        // 4073 is a single reference to 6141, whose shadow file clears the
        // studs it inherits, so the clearing reaches 4073 too.
        let round = try set("4073.dat")

        #expect(round.connectorCount == 3)
        #expect(round.connectors.allSatisfy { $0.provenance == .inherited })
        #expect(round.connectors.filter { isPlainStud(round, $0) }.isEmpty)
    }

    @Test("A part's own metas are its own, and a subpart's are inherited")
    func provenance() throws {
        let brick = try set("4733.dat")
        let own = brick.connectors.filter { $0.provenance == .shadow }

        #expect(own.count == 3)
        #expect(brick.connectors.filter { $0.provenance == .inherited }.count == 5)
        #expect(brick.connectors.allSatisfy { $0.provenance != .primitive })
    }

    @Test("Without the shadow library a part still has its derived studs")
    func withoutShadowLibrary() throws {
        let brick = try #require(ConnectivityFixtures.connectorSet("3001.dat"))

        #expect(brick.connectorCount == 8)
        #expect(brick.connectors.allSatisfy { $0.provenance == .primitive })
    }

    @Test("A library with only the internal folder set still finds parts")
    func internalFolderOnly() throws {
        let paths = LDrawPaths()

        paths.setInternalLDrawPath(ConnectivityFixtures.ldraw.path)

        let library = LDrawConnectorLibrary(paths: paths,
                                            shadowLibraryPath: ConnectivityFixtures.shadow.path)

        #expect(try #require(library.connectorSet(forPartNamed: "3001.dat")).connectorCount == 9)
    }

    @Test("A folder written with a trailing slash is read all the same")
    func trailingSlash() throws {
        let paths = LDrawPaths()

        paths.setPreferredLDrawPath(ConnectivityFixtures.ldraw.path + "/")

        let library = LDrawConnectorLibrary(paths: paths,
                                            shadowLibraryPath: ConnectivityFixtures.shadow.path)

        // Nine means the shadow file was found: eight studs and one record of
        // stud holes.
        #expect(try #require(library.connectorSet(forPartNamed: "3001.dat")).connectorCount == 9)
    }

    @Test("Pointing the library somewhere else forgets what it built")
    func changingTheShadowPath() throws {
        let library = LDrawConnectorLibrary(paths: ConnectivityFixtures.fixturePaths(),
                                            shadowLibraryPath: ConnectivityFixtures.shadow.path)
        let withShadow = try #require(library.connectorSet(forPartNamed: "3001.dat"))

        library.shadowLibraryPath = nil

        let without = try #require(library.connectorSet(forPartNamed: "3001.dat"))

        #expect(withShadow.connectorCount == 9)
        #expect(without.connectorCount == 8)
    }
}


extension LDrawConnector {
    /// Every grid point of the record.
    var points: [Point3] {
        (0..<LDrawConnectorPointCount(self)).map { LDrawConnectorPointAtIndex(self, $0) }
    }

    var connectorPoints: [ConnectorPoint] {
        points.map { ConnectorPoint($0, axis: axis) }
    }
}


extension ConnectorPoint {
    init(_ point: Point3, axis: Vector3) {
        self.init(point.x, point.y, point.z, axis: (axis.x, axis.y, axis.z))
    }

    init(_ point: Point3, axis: (Double, Double, Double)) {
        self.init(point.x, point.y, point.z, axis: axis)
    }
}


extension LDrawConnectorSection: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.radius == rhs.radius && lhs.length == rhs.length && lhs.shape == rhs.shape
    }
}
