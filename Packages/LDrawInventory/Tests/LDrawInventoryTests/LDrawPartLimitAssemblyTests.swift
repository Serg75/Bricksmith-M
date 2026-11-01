//
//  LDrawPartLimitAssemblyTests.swift
//  LDrawInventoryTests
//
//  Tests for assemblies in the limit table: a set's hinge against the halves
//  a model places, and a set's minifigure against the parts the Minifigure
//  Generator places.
//
//  Created by Sergey Slobodenyuk on 2026-10-28.
//

import Testing
import Foundation
import LDrawCore
import LDrawInventory

@Suite("Parts limit assemblies")
struct LDrawPartLimitAssemblyTests {

    // MARK: - Fixtures

    private static let black: Int32 = 0
    private static let red: Int32 = 4
    private static let yellow: Int32 = 14
    private static let white: Int32 = 15

    private func color(_ code: Int32) -> LDrawColorT {
        LDrawColorT(rawValue: code)!
    }

    /// The shortcut fixtures, a torso assembly as the library names it, and a stickered brick.
    private func shortcuts() -> LDrawShortcutMap {
        var files = LDrawShortcutMapTests.files
        files["76382p0l.dat"] = """
            0 Minifig Torso with Arms and Hands with Plaid Jacket Pattern
            0 Name: 76382p0l.dat
            0 !LDRAW_ORG Shortcut UPDATE 2024-10
            0 !KEYWORDS Bricklink 973pb2148c01, Rebrickable 973c04h01pr3045

            1 16 0 0 0 1 0 0 0 1 0 0 0 1 973p0l.dat
            1 16 -15.552 9 0 0.985 -0.17 0 0.17 0.985 0 0 0 1 3818.dat
            1 16 15.552 9 0 0.985 0.17 0 -0.17 0.985 0 0 0 1 3819.dat
            1 14 -23.69 26.774 -9.898 0.985 -0.12 0.12 0.17 0.696 -0.696 0 0.707 0.707 3820.dat
            1 14 23.69 26.774 -9.898 0.985 0.12 -0.12 -0.17 0.696 -0.696 0 0.707 0.707 3820.dat
            """
        files["3001d01.dat"] = """
            0 Brick  2 x  4 with Sticker
            0 !LDRAW_ORG Shortcut

            1 16 0 0 0 1 0 0 0 1 0 0 0 1 3001.dat
            1 15 0 0 -10 1 0 0 0 1 0 0 0 1 3001d01s.dat
            """
        return LDrawShortcutMap(fileReader: { files[$0] })
    }

    /// The torso print and its assembly both name the assembly's Rebrickable number, as the
    /// library does. Rebrickable has no part for the sticker.
    private func identity() -> LDrawPartIdentity {
        let records: [[String: Any]] = [
            [PART_NUMBER_KEY: "76382p0l.dat", PART_NAME_KEY: "Minifig Torso with Arms and Hands",
             PART_KEYWORDS_KEY: ["Rebrickable 973c04h01pr3045"]],
            [PART_NUMBER_KEY: "973p0l.dat", PART_NAME_KEY: "Minifig Torso",
             PART_KEYWORDS_KEY: ["Rebrickable 973c04h01pr3045"]],
            [PART_NUMBER_KEY: "3001d01.dat", PART_NAME_KEY: "Brick  2 x  4 with Sticker",
             PART_KEYWORDS_KEY: ["Rebrickable 3001pr9999"]],
        ]
        let known: Set<String> = ["2429", "2430", "73983", "973c04h01pr3045", "3818", "3819", "3820", "3001",
                                  "3001pr9999", "3815", "3816", "3817", "970c00"]
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil,
                                                     colorLinks: [0: 0, 4: 4, 14: 14, 15: 15],
                                                     relations: nil, knownPartNumbers: known)
        return LDrawPartIdentity(catalogRecords: records, rebrickableData: data, overrides: nil)
    }

    private func item(_ part: String, _ colorID: Int, _ quantity: UInt, spares: UInt = 0) -> LDrawInventoryItem {
        LDrawInventoryItem(rebrickablePartNumber: part, rebrickableColorID: colorID, ldrawPartName: nil,
                           ldrawColorCode: color(-1), quantity: quantity, spareQuantity: spares)
    }

    private func inventoryTable(_ items: [LDrawInventoryItem]) -> LDrawPartLimitTable {
        LDrawPartLimitTable(limit: LDrawPartLimit.inventory("set"), availability: nil, items: items,
                            identity: identity(), shortcuts: shortcuts(), year: 2026)
    }

    private func availableNowTable(_ notes: [(String, Int)]) -> LDrawPartLimitTable {
        let builder = LDrawPartAvailabilityBuilder()
        for (part, colorID) in notes {
            builder.notePartNumber(part, colorID: colorID, year: 2026, inDatabaseSet: false)
        }
        return LDrawPartLimitTable(limit: LDrawPartLimit.availableNow(), availability: builder.availability(with: nil),
                                   items: nil, identity: identity(), shortcuts: shortcuts(), year: 2026)
    }

    // MARK: - An inventory

    @Test("A set's hinge counts for the halves a model places")
    func hingeInSet() {
        let table = inventoryTable([item("73983", 4, 6)])
        #expect(table.ownedCount(forPartNamed: "2429.dat", colorCode: color(Self.red)) == 6)
        #expect(table.ownedCount(forPartNamed: "2430.dat", colorCode: color(Self.red)) == 6)
        #expect(table.status(forPartNamed: "2430.dat", colorCode: color(Self.black)) == .notInColor)
        #expect(table.items().map { $0.ldrawPartName } == ["2429.dat", "2430.dat"])
        #expect(table.unmatchedItems().isEmpty)

        // The hinge itself stands as its halves do.
        #expect(table.ownedCount(forPartNamed: "73983.dat", colorCode: color(Self.red)) == 6)
        #expect(table.status(forPartNamed: "73983.dat", colorCode: color(Self.red)) == .allowed)
        #expect(table.status(forPartNamed: "73983.dat", colorCode: color(Self.black)) == .notInColor)
        #expect(table.allowsPartNamed("73983.dat"))
        #expect(table.colorCodes(forPartNamed: "73983.dat") == [4])
    }

    @Test("Halves in a set count for a hinge, as many as the scarcer half")
    func halvesInSet() {
        let table = inventoryTable([item("2429", 4, 3), item("2430", 4, 2)])
        #expect(table.ownedCount(forPartNamed: "73983.dat", colorCode: color(Self.red)) == 2)
        #expect(table.status(forPartNamed: "73983.dat", colorCode: color(Self.red)) == .allowed)
        #expect(table.ownedCount(forPartNamed: "2429c01.dat", colorCode: color(Self.red)) == 2)

        let oneHalf = inventoryTable([item("2429", 4, 3)])
        #expect(oneHalf.status(forPartNamed: "73983.dat", colorCode: color(Self.red)) == .notAvailable)
        #expect(oneHalf.allowsPartNamed("73983.dat") == false)
        #expect(oneHalf.colorCodes(forPartNamed: "73983.dat") == [])
    }

    @Test("A set's minifigure torso counts for the torso, arms and hands the Minifigure Generator places")
    func minifigureTorso() {
        let table = inventoryTable([item("973c04h01pr3045", 4, 1)])
        #expect(table.ownedCount(forPartNamed: "973p0l.dat", colorCode: color(Self.red)) == 1)
        #expect(table.ownedCount(forPartNamed: "3818.dat", colorCode: color(Self.red)) == 1)
        #expect(table.ownedCount(forPartNamed: "3819.dat", colorCode: color(Self.red)) == 1)
        #expect(table.ownedCount(forPartNamed: "3820.dat", colorCode: color(Self.yellow)) == 2)
        #expect(table.status(forPartNamed: "3820.dat", colorCode: color(Self.red)) == .notInColor)

        // Hands are yellow whatever the torso's color.
        #expect(table.status(forPartNamed: "76382p0l.dat", colorCode: color(Self.red)) == .allowed)
        #expect(table.colorCodes(forPartNamed: "76382p0l.dat") == [4])
    }

    @Test("A loose torso print does not make its assembly allowed, since an inventory's pieces decide")
    func looseTorsoPrint() {
        let loose = LDrawInventoryItem(rebrickablePartNumber: nil, rebrickableColorID: LDrawRebrickableColorNone,
                                       ldrawPartName: "973p0l.dat", ldrawColorCode: color(Self.white),
                                       quantity: 1, spareQuantity: 0)
        let table = inventoryTable([item("973c04h01pr3045", 4, 1), loose])
        #expect(table.status(forPartNamed: "76382p0l.dat", colorCode: color(Self.red)) == .allowed)
        #expect(table.status(forPartNamed: "76382p0l.dat", colorCode: color(Self.white)) != .allowed)
        #expect(table.ownedCount(forPartNamed: "76382p0l.dat", colorCode: color(Self.white)) == 0)
        #expect(table.colorCodes(forPartNamed: "76382p0l.dat") == [4])
    }

    @Test("A plain part is not split when a stickered shortcut links to its number")
    func plainPartWithStickeredShortcut() {
        var files = LDrawShortcutMapTests.files
        files["3001.dat"] = "0 Brick  2 x  4\n0 !LDRAW_ORG Part UPDATE 2004-01\n"
        files["3001d02.dat"] = """
            0 Brick  2 x  4 with Sticker
            0 !LDRAW_ORG Shortcut

            1 16 0 0 0 1 0 0 0 1 0 0 0 1 3001.dat
            1 15 0 0 -10 1 0 0 0 1 0 0 0 1 3001d02s.dat
            """
        let records: [[String: Any]] = [[PART_NUMBER_KEY: "3001.dat", PART_NAME_KEY: "Brick  2 x  4"],
                                        [PART_NUMBER_KEY: "3001d02.dat", PART_NAME_KEY: "Brick  2 x  4 with Sticker",
                                         PART_KEYWORDS_KEY: ["Rebrickable 3001"]]]
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: [4: 4, 15: 15],
                                                     relations: nil, knownPartNumbers: ["3001"])
        let identity = LDrawPartIdentity(catalogRecords: records, rebrickableData: data, overrides: nil)
        let table = LDrawPartLimitTable(limit: LDrawPartLimit.inventory("set"), availability: nil,
                                        items: [item("3001", 4, 2)], identity: identity,
                                        shortcuts: LDrawShortcutMap(fileReader: { files[$0] }), year: 2026)

        #expect(table.items().map { $0.ldrawPartName } == ["3001.dat"])
        #expect(identity.partName(forRebrickablePartNumber: "3001") == "3001.dat")
        #expect(table.ownedCount(forPartNamed: "3001.dat", colorCode: color(Self.red)) == 2)
        #expect(table.status(forPartNamed: "3001d02s.dat", colorCode: color(Self.white)) != .allowed)
    }

    @Test("Hips and legs listed under an old name count for the parts")
    func movedAssembly() {
        let table = inventoryTable([item("970c00", 0, 2)])
        #expect(table.ownedCount(forPartNamed: "3815.dat", colorCode: color(Self.black)) == 2)
        #expect(table.ownedCount(forPartNamed: "3817.dat", colorCode: color(Self.black)) == 2)
        #expect(table.ownedCount(forPartNamed: "3815c01.dat", colorCode: color(Self.black)) == 2)
    }

    @Test("A piece Rebrickable does not have counts by its LDraw name")
    func ldrawOnlyPiece() {
        let table = inventoryTable([item("3001pr9999", 4, 1)])
        #expect(table.unmatchedItems().isEmpty)
        #expect(table.ownedCount(forPartNamed: "3001d01s.dat", colorCode: color(Self.white)) == 1)
        #expect(table.status(forPartNamed: "3001d01s.dat", colorCode: color(Self.white)) == .allowed)
        #expect(table.status(forPartNamed: "3001d01.dat", colorCode: color(Self.red)) == .allowed)

        // Another part Rebrickable does not have still has no data.
        #expect(table.status(forPartNamed: "3002d01s.dat", colorCode: color(Self.white)) == .noData)
    }

    @Test("An inventory counts a placed assembly by its pieces; a plain part counts as itself")
    func countedPieces() {
        let table = inventoryTable([item("73983", 4, 1)])
        #expect(table.countedPieces(ofPartNamed: "73983.dat")?.map { $0.partName } == ["2429.dat", "2430.dat"])
        #expect(table.countedPieces(ofPartNamed: "2429.dat") == nil)
    }

    @Test("Without shortcuts an assembly stays one part")
    func noShortcuts() {
        let table = LDrawPartLimitTable(limit: LDrawPartLimit.inventory("set"), availability: nil,
                                        items: [item("73983", 4, 6)], identity: identity(), year: 2026)
        #expect(table.status(forPartNamed: "2429.dat", colorCode: color(Self.red)) == .notAvailable)
        #expect(table.ownedCount(forPartNamed: "73983.dat", colorCode: color(Self.red)) == 6)
        #expect(table.countedPieces(ofPartNamed: "73983.dat") == nil)
    }

    // MARK: - Available now

    @Test("Available now allows the pieces of an assembly that came in a set, in its color")
    func availablePieces() {
        let table = availableNowTable([("73983", 4), ("973c04h01pr3045", 4)])
        #expect(table.status(forPartNamed: "2429.dat", colorCode: color(Self.red)) == .allowed)
        #expect(table.status(forPartNamed: "2430.dat", colorCode: color(Self.black)) == .notInColor)
        #expect(table.status(forPartNamed: "73983.dat", colorCode: color(Self.red)) == .allowed)
        #expect(table.status(forPartNamed: "3820.dat", colorCode: color(Self.yellow)) == .allowed)
        #expect(table.countedPieces(ofPartNamed: "73983.dat") == nil)
    }

    @Test("Available now allows an assembly whose pieces came in sets")
    func availableAssembly() {
        let table = availableNowTable([("2429", 4), ("2430", 4), ("2430", 0)])
        #expect(table.status(forPartNamed: "73983.dat", colorCode: color(Self.red)) == .allowed)
        #expect(table.status(forPartNamed: "73983.dat", colorCode: color(Self.black)) == .notInColor)
        #expect(table.colorCodes(forPartNamed: "73983.dat") == [4])
        #expect(table.allowsPartNamed("73983.dat"))
    }
}
