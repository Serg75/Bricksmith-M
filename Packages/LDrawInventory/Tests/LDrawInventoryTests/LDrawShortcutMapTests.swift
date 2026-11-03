//
//  LDrawShortcutMapTests.swift
//  LDrawInventoryTests
//
//  Tests for reading the pieces of LDraw shortcuts.
//
//  Created by Sergey Slobodenyuk on 2026-10-28.
//

import Testing
import Foundation
import LDrawCore
import LDrawInventory

@Suite("Shortcut map")
struct LDrawShortcutMapTests {

    // MARK: - Fixtures

    /// Part files as the library has them, cut to their headers and references.
    static let files: [String: String] = [
        "73983.dat": """
            0 Hinge Plate  1 x  4 (Complete)
            0 Name: 73983.dat
            0 !LDRAW_ORG Shortcut UPDATE 2004-03

            1 16 0 0 0 1 0 0 0 1 0 0 0 1 2429.dat
            1 16 0 0 0 1 0 0 0 1 0 0 0 1 2430.dat
            """,
        "2429c01.dat": """
            0 ~Moved to 73983
            0 Name: 2429c01.dat
            0 !LDRAW_ORG Part UPDATE 2004-03

            1 16 0 0 0 1 0 0 0 1 0 0 0 1 73983.dat
            """,
        "973c01.dat": """
            0 Minifig Torso with Arms and Yellow Hands
            0 Name: 973c01.dat
            0 !LDRAW_ORG Shortcut UPDATE 2020-02

            1 16 0 0 0 1 0 0 0 1 0 0 0 1 973.dat
            1 16 -15.552 9 0 0.985 -0.17 0 0.17 0.985 0 0 0 1 3818.dat
            1 16 15.552 9 0 0.985 0.17 0 -0.17 0.985 0 0 0 1 3819.dat
            1 14 -23.69 26.774 -9.898 0.985 -0.12 0.12 0.17 0.696 -0.696 0 0.707 0.707 3820.dat
            1 14 23.69 26.774 -9.898 0.985 0.12 -0.12 -0.17 0.696 -0.696 0 0.707 0.707 3820.dat
            """,
        "3815c01.dat": """
            0 Minifig Hips and Legs
            0 Name: 3815c01.dat
            0 !LDRAW_ORG Shortcut UPDATE 2002-01

            1 16 0 0 0 1 0 0 0 1 0 0 0 1 3815.dat
            1 16 0 12 0 1 0 0 0 1 0 0 0 1 3816.dat
            1 16 0 12 0 1 0 0 0 1 0 0 0 1 3817.dat
            """,
        "970c00.dat": """
            0 ~Moved to 3815c01
            0 Name: 970c00.dat
            0 !LDRAW_ORG Part UPDATE 2010-01

            1 16 0 0 0 1 0 0 0 1 0 0 0 1 3815c01.dat
            """,
        "minifig.dat": """
            0 Minifig
            0 Name: minifig.dat
            0 !LDRAW_ORG Unofficial_Shortcut

            1 4 0 0 0 1 0 0 0 1 0 0 0 1 973c01.dat
            1 1 0 32 0 1 0 0 0 1 0 0 0 1 3815c01.dat
            1 14 0 -24 0 1 0 0 0 1 0 0 0 1 3626b.dat
            """,
        "3062a.dat": """
            0 ~Moved to 3062b
            0 Name: 3062a.dat
            0 !LDRAW_ORG Part UPDATE 2005-01

            1 16 0 0 0 1 0 0 0 1 0 0 0 1 3062b.dat
            """,
        "3062b.dat": """
            0 Brick  1 x  1 Round with Hollow Stud
            0 Name: 3062b.dat
            0 !LDRAW_ORG Part UPDATE 2005-01

            1 16 0 0 0 1 0 0 0 1 0 0 0 1 s/3062bs01.dat
            4 16 1 0 1 -1 0 1 -1 0 -1 1 0 -1
            """,
        "loop.dat": """
            0 A shortcut that places itself
            0 !LDRAW_ORG Shortcut

            1 16 0 0 0 1 0 0 0 1 0 0 0 1 loop.dat
            """,
    ]

    /// A map over the fixtures that notes each name it reads.
    private func map(_ files: [String: String] = LDrawShortcutMapTests.files) -> (LDrawShortcutMap, Reads) {
        let reads = Reads()
        let map = LDrawShortcutMap(fileReader: { name in
            reads.names.append(name)
            return files[name]
        })
        return (map, reads)
    }

    final class Reads {
        var names: [String] = []
    }

    private func pieces(_ map: LDrawShortcutMap, _ name: String) -> [String]? {
        map.pieces(ofPartNamed: name)?.map { "\($0.partName)/\($0.colorCode.rawValue)" }
    }

    // MARK: - Tests

    @Test("A shortcut lists its pieces in file order, color 16 kept for the assembly's")
    func hinge() {
        let (map, _) = map()
        #expect(pieces(map, "73983.dat") == ["2429.dat/16", "2430.dat/16"])
        #expect(pieces(map, "973c01.dat") == ["973.dat/16", "3818.dat/16", "3819.dat/16", "3820.dat/14",
                                              "3820.dat/14"])
    }

    @Test("Shortcuts inside a shortcut open, and their pieces take the placing color")
    func nested() {
        let (map, _) = map()
        #expect(pieces(map, "minifig.dat") == ["973.dat/4", "3818.dat/4", "3819.dat/4", "3820.dat/14",
                                               "3820.dat/14", "3815.dat/1", "3816.dat/1", "3817.dat/1",
                                               "3626b.dat/14"])
    }

    @Test("A moved part follows its new name when that is a shortcut")
    func moved() {
        let (map, _) = map()
        #expect(pieces(map, "2429c01.dat") == ["2429.dat/16", "2430.dat/16"])
        #expect(pieces(map, "970c00.dat") == ["3815.dat/16", "3816.dat/16", "3817.dat/16"])
        #expect(map.pieces(ofPartNamed: "3062a.dat") == nil)
    }

    @Test("A part that is not a shortcut has no pieces, and its references are not read")
    func plainPart() {
        let (map, reads) = map()
        #expect(map.pieces(ofPartNamed: "3062b.dat") == nil)
        #expect(map.pieces(ofPartNamed: "3001.dat") == nil)
        #expect(reads.names == ["3062b.dat", "3001.dat"])
    }

    @Test("Names are matched without case or extension, and each file is read once")
    func names() {
        let (map, reads) = map()
        #expect(pieces(map, "73983.DAT") == ["2429.dat/16", "2430.dat/16"])
        #expect(pieces(map, "73983") == ["2429.dat/16", "2430.dat/16"])
        #expect(map.pieces(ofPartNamed: "  ") == nil)
        #expect(reads.names.filter { $0 == "73983.dat" }.count == 1)
    }

    @Test("Windows line endings and a byte order mark read the same")
    func lineEndings() {
        let text = "\u{FEFF}" + Self.files["73983.dat"]!.replacingOccurrences(of: "\n", with: "\r\n")
        let (map, _) = map(["73983.dat": text])
        #expect(pieces(map, "73983.dat") == ["2429.dat/16", "2430.dat/16"])
    }

    @Test("A shortcut that places itself does not loop")
    func loop() {
        let (map, _) = map()
        #expect(pieces(map, "loop.dat") == ["loop.dat/16"])
    }
}
