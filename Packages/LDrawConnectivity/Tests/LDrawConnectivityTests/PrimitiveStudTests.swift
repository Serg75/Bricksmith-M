//
//  PrimitiveStudTests.swift
//  LDrawConnectivityTests
//
//  Tests for male studs found from the stud primitives in a part's geometry.
//
//  Created by Sergey Slobodenyuk on 2026-09-19.
//

import Testing
import Foundation
import LDrawCore
import LDrawConnectivity

@Suite("Male studs from stud primitives")
struct PrimitiveStudTests {

    private static let up = (0.0, -1.0, 0.0)

    private func studs(_ partName: String) throws -> Set<ConnectorPoint> {
        let set = try #require(ConnectivityFixtures.connectorSet(partName))
        let males = set.connectors.filter { $0.gender == .male }
        return Set(males.map(ConnectorPoint.init))
    }

    @Test("Stud count per part", arguments: zip(
        ["3005", "3004", "3003", "3001", "3024", "3023b", "3022", "3020",
         "3070b", "3069b", "3794b", "15573", "3062b", "4073", "6141", "3941",
         "3660", "3665", "44728", "99207", "87087", "4733", "3040b", "3298",
         "3037", "10a"],
        [1, 2, 4, 8, 1, 2, 4, 8,
         0, 0, 1, 1, 1, 1, 1, 4,
         4, 2, 6, 6, 2, 5, 1, 2,
         4, 764]))
    func studCount(part: String, expected: Int) throws {
        let set = try #require(ConnectivityFixtures.connectorSet(part + ".dat"))
        #expect(set.connectors.filter { $0.gender == .male }.count == expected)
    }

    @Test("A 2 x 4 brick has eight studs on its top, pointing up")
    func brick2x4() throws {
        var expected = Set<ConnectorPoint>()
        for x in [-30.0, -10, 10, 30] {
            for z in [-10.0, 10] {
                expected.insert(ConnectorPoint(x, 0, z, axis: Self.up))
            }
        }
        #expect(try studs("3001.dat") == expected)
    }

    @Test("A 1 x 1 brick with studs on four sides has five stud directions")
    func brick1x1FourSides() throws {
        let expected: Set<ConnectorPoint> = [
            ConnectorPoint(0, 0, 0, axis: Self.up),
            ConnectorPoint(-10, 10, 0, axis: (-1, 0, 0)),
            ConnectorPoint(10, 10, 0, axis: (1, 0, 0)),
            ConnectorPoint(0, 10, -10, axis: (0, 0, -1)),
            ConnectorPoint(0, 10, 10, axis: (0, 0, 1)),
        ]
        #expect(try studs("4733.dat") == expected)
    }

    @Test("A bracket's studs lie on two planes with their own directions")
    func bracket() throws {
        let expected: Set<ConnectorPoint> = [
            ConnectorPoint(-10, 0, 0, axis: Self.up),
            ConnectorPoint(10, 0, 0, axis: Self.up),
            ConnectorPoint(-10, -2, -14, axis: (0, 0, -1)),
            ConnectorPoint(10, -2, -14, axis: (0, 0, -1)),
            ConnectorPoint(-10, -22, -14, axis: (0, 0, -1)),
            ConnectorPoint(10, -22, -14, axis: (0, 0, -1)),
        ]
        #expect(try studs("99207.dat") == expected)
    }

    @Test("Primitive studs are marked as such")
    func provenance() throws {
        let set = try #require(ConnectivityFixtures.connectorSet("3001.dat"))
        for stud in set.connectors {
            #expect(stud.provenance == .primitive)
            #expect(stud.kind == .cylinder)
            let section = set.section(at: UInt(stud.sectionOffset))
            #expect(section.radius == 6)
            #expect(section.length == 4)
        }
    }

    @Test("A part's set is built once and shared")
    func cached() throws {
        let first = try #require(ConnectivityFixtures.connectorSet("3001.dat"))
        let again = try #require(ConnectivityFixtures.connectorSet("3001.DAT"))
        #expect(first === again)
    }

    @Test("An unknown part has no set")
    func unknownPart() {
        #expect(ConnectivityFixtures.connectorSet("no-such-part.dat") == nil)
    }
}
