//
//  LDrawPartLimitTests.swift
//  LDrawInventoryTests
//
//  Tests for the limit setting and for the table of what it allows.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawCore
import LDrawInventory

@Suite("Parts limit")
struct LDrawPartLimitTests {

    // MARK: - Fixtures

    private static let red: Int32 = 4
    private static let black: Int32 = 0
    private static let sandBlue: Int32 = 379

    private func color(_ code: Int32) -> LDrawColorT {
        LDrawColorT(rawValue: code)!
    }

    /// Red, black and sand blue link to the same Rebrickable ids; 3062a and 3062b are molds.
    private func identity() -> LDrawPartIdentity {
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil,
                                                     colorLinks: [4: 4, 0: 0, 379: 379],
                                                     relations: [["M", "3062a", "3062b"], ["P", "3001pr0001", "3001"]],
                                                     knownPartNumbers: nil, rubberPartNumbers: nil)
        return LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)
    }

    private func item(_ part: String?, _ colorID: Int, _ quantity: UInt, spares: UInt = 0,
                      ldrawPart: String? = nil, ldrawColor: Int32 = -1) -> LDrawInventoryItem {
        LDrawInventoryItem(rebrickablePartNumber: part, rebrickableColorID: colorID,
                           ldrawPartName: ldrawPart, ldrawColorCode: color(ldrawColor),
                           quantity: quantity, spareQuantity: spares)
    }

    private func limit(_ change: (LDrawMutablePartLimit) -> Void) -> LDrawPartLimit {
        let limit = LDrawPartLimit.none().mutableCopy() as! LDrawMutablePartLimit
        change(limit)
        return limit.copy() as! LDrawPartLimit
    }

    /// 3001 red came in a 2026 set, black only in 2019; 3002 sand blue only through Pick a Brick.
    private func availability() -> LDrawPartAvailability {
        let builder = LDrawPartAvailabilityBuilder()
        builder.notePartNumber("3001", colorID: 4, year: 2026, inDatabaseSet: false)
        builder.notePartNumber("3001", colorID: 0, year: 2019, inDatabaseSet: false)
        builder.notePartNumber("3002", colorID: 379, year: 2025, inDatabaseSet: true)
        builder.notePartNumber("3062b", colorID: 4, year: 2025, inDatabaseSet: false)
        return builder.availability(with: nil)
    }

    private func availableNowTable(_ change: (LDrawMutablePartLimit) -> Void = { _ in }) -> LDrawPartLimitTable {
        let limit = limit { $0.kind = .availableNow; change($0) }
        return LDrawPartLimitTable(limit: limit, availability: availability(), items: nil,
                                   identity: identity(), year: 2026)
    }

    private func inventoryTable(_ items: [LDrawInventoryItem],
                                _ change: (LDrawMutablePartLimit) -> Void = { _ in }) -> LDrawPartLimitTable {
        let limit = limit { $0.kind = .inventory; $0.inventoryIdentifier = "42115-1"; change($0) }
        return LDrawPartLimitTable(limit: limit, availability: nil, items: items, identity: identity(), year: 2026)
    }

    // MARK: - The setting

    @Test("A new limit has the default options")
    func defaults() {
        let limit = LDrawPartLimit.none()
        #expect(limit.kind == .none)
        #expect(limit.isRestricting == false)
        #expect(limit.yearsBack == 5)
        #expect(limit.includesSpares == true)
        #expect(limit.matchesMoldVariants == true)
        #expect(limit.matchesAnyPrint == false)
        #expect(limit.matchesAnyColor == false)
        #expect(limit.warnsOnly == false)
        #expect(limit.countsPickABrickParts == false)
    }

    @Test("A limit reads back what it wrote")
    func roundTrip() {
        let written = limit {
            $0.kind = .inventory
            $0.inventoryIdentifier = "42115-1"
            $0.yearsBack = 10
            $0.includesSpares = false
            $0.matchesAnyPrint = true
            $0.warnsOnly = true
        }
        let read = LDrawPartLimit.fromDictionary(written.dictionaryRepresentation())
        #expect(read == written)
        #expect(read.inventoryIdentifier == "42115-1")
        #expect(read.includesSpares == false)
    }

    @Test("Nil, junk, an unknown kind or an inventory with no identifier read as no limit")
    func junk() {
        #expect(LDrawPartLimit.fromDictionary(nil).kind == .none)
        #expect(LDrawPartLimit.fromDictionary(["kind": "everything"]).kind == .none)
        #expect(LDrawPartLimit.fromDictionary(["kind": "inventory"]).kind == .none)
        #expect(LDrawPartLimit.fromDictionary(["kind": 3]).kind == .none)

        let options = LDrawPartLimit.fromDictionary(["kind": "availableNow", "yearsBack": "x", "warnsOnly": true])
        #expect(options.kind == .availableNow)
        #expect(options.yearsBack == 5)
        #expect(options.warnsOnly == true)
    }

    @Test("A mutable limit copies into an immutable one, and back")
    func copies() {
        let mutable = LDrawPartLimit.availableNow().mutableCopy() as! LDrawMutablePartLimit
        let frozen = mutable.copy() as! LDrawPartLimit
        mutable.yearsBack = 10

        #expect(type(of: frozen) == LDrawPartLimit.self)
        #expect(frozen.yearsBack == 5)
        #expect(frozen != (mutable as LDrawPartLimit))
        #expect((frozen.copy() as AnyObject) === frozen)
    }

    @Test("A limit survives secure coding")
    func secureCoding() throws {
        let written = LDrawPartLimit.inventory("ABC")
        let data = try NSKeyedArchiver.archivedData(withRootObject: written, requiringSecureCoding: true)
        let read = try #require(try NSKeyedUnarchiver.unarchivedObject(ofClass: LDrawPartLimit.self, from: data))
        #expect(read == written)
    }

    // MARK: - No limit

    @Test("No limit allows everything and counts nothing")
    func unrestricted() {
        let table = LDrawPartLimitTable.unrestricted()
        #expect(table.hasData)
        #expect(table.status(forPartNamed: "anything.dat", colorCode: color(16)) == .allowed)
        #expect(table.allowsPartNamed("anything.dat"))
        #expect(table.ownedCount(forPartNamed: "3001.dat", colorCode: color(Self.red)) == NSNotFound)
        #expect(table.colorCodes(forPartNamed: "3001.dat") == nil)
        #expect(table.allowedColorCodes() == nil)
    }

    // MARK: - Available now

    @Test("Available now allows a part in a color from the last two years")
    func availableNow() {
        let table = availableNowTable()
        #expect(table.status(forPartNamed: "3001.dat", colorCode: color(Self.red)) == .allowed)
        #expect(table.status(forPartNamed: "3001.dat", colorCode: color(Self.black)) == .notInColor)
        #expect(table.status(forPartNamed: "3002.dat", colorCode: color(Self.sandBlue)) == .notAvailable)
        #expect(table.status(forPartNamed: "3003.dat", colorCode: color(Self.red)) == .notAvailable)
        #expect(table.colorCodes(forPartNamed: "3001.dat") == [NSNumber(value: Self.red)])
        #expect(table.ownedCount(forPartNamed: "3001.dat", colorCode: color(Self.red)) == NSNotFound)
    }

    @Test("A color with no Rebrickable match has no data")
    func unmatchedColor() {
        let table = availableNowTable()
        #expect(table.status(forPartNamed: "3001.dat", colorCode: color(16)) == .noData)
        #expect(table.matchesColorCode(color(16)) == false)
        #expect(table.matchesColorCode(color(Self.red)))
    }

    @Test("Any year allows every color a part ever came in")
    func anyYear() {
        let table = availableNowTable { $0.yearsBack = 0 }
        #expect(table.status(forPartNamed: "3001.dat", colorCode: color(Self.black)) == .allowed)
        #expect(table.colorCodes(forPartNamed: "3001.dat") == [NSNumber(value: Self.black), NSNumber(value: Self.red)])
    }

    @Test("One year back is this year only")
    func oneYear() {
        let table = availableNowTable { $0.yearsBack = 1 }
        #expect(table.status(forPartNamed: "3001.dat", colorCode: color(Self.red)) == .allowed)
        #expect(table.status(forPartNamed: "3062b.dat", colorCode: color(Self.red)) == .notAvailable)
    }

    @Test("Pick a Brick parts count only when asked")
    func pickABrick() {
        let table = availableNowTable { $0.countsPickABrickParts = true }
        #expect(table.status(forPartNamed: "3002.dat", colorCode: color(Self.sandBlue)) == .allowed)
    }

    @Test("A mold variant is allowed through its pool, unless molds must match")
    func molds() {
        #expect(availableNowTable().status(forPartNamed: "3062a.dat", colorCode: color(Self.red)) == .allowed)
        let strict = availableNowTable { $0.matchesMoldVariants = false }
        #expect(strict.status(forPartNamed: "3062a.dat", colorCode: color(Self.red)) == .notAvailable)
    }

    @Test("Any color allows every color of an allowed part")
    func anyColor() {
        let table = availableNowTable { $0.matchesAnyColor = true }
        #expect(table.status(forPartNamed: "3001.dat", colorCode: color(16)) == .allowed)
        #expect(table.colorCodes(forPartNamed: "3001.dat") == nil)
        #expect(table.allowedColorCodes() == nil)
    }

    @Test("Without a catalog every part has no data")
    func noCatalog() {
        let table = LDrawPartLimitTable(limit: LDrawPartLimit.availableNow(), availability: nil, items: nil,
                                        identity: identity(), year: 2026)
        #expect(table.hasData == false)
        #expect(table.status(forPartNamed: "3001.dat", colorCode: color(Self.red)) == .noData)
        #expect(table.allowsPartNamed("3001.dat") == false)
    }

    @Test("The colors some part is allowed in, lowest first")
    func allowedColors() {
        #expect(availableNowTable().allowedColorCodes() == [NSNumber(value: Self.red)])
        #expect(availableNowTable { $0.countsPickABrickParts = true }.allowedColorCodes()
                == [NSNumber(value: Self.red), NSNumber(value: Self.sandBlue)])
    }

    @Test("Every-code lists add the other LDraw colors each Rebrickable color links to")
    func everyColorCode() {
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: [4: [4, 324]],
                                                     relations: nil, knownPartNumbers: nil, rubberPartNumbers: nil)
        let table = LDrawPartLimitTable(limit: limit { $0.kind = .availableNow }, availability: availability(),
                                        items: nil,
                                        identity: LDrawPartIdentity(catalogRecords: nil, rebrickableData: data,
                                                                    overrides: nil),
                                        year: 2026)
        let both = [NSNumber(value: Self.red), NSNumber(value: 324)]
        #expect(table.colorCodes(forPartNamed: "3001.dat") == [NSNumber(value: Self.red)])
        #expect(table.everyColorCode(forPartNamed: "3001.dat") == both)
        #expect(table.allowedColorCodes() == [NSNumber(value: Self.red)])
        #expect(table.everyAllowedColorCode() == both)
        #expect(table.status(forPartNamed: "3001.dat", colorCode: color(324)) == .allowed)
    }

    @Test("A rubber color is offered and allowed only for a rubber part")
    func rubberColorCodes() {
        let builder = LDrawPartAvailabilityBuilder()
        builder.notePartNumber("3001", colorID: 4, year: 2026, inDatabaseSet: false)
        builder.notePartNumber("3483", colorID: 0, year: 2026, inDatabaseSet: false)
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: [0: [0, 256], 4: [4, 324]],
                                                     relations: nil, knownPartNumbers: nil,
                                                     rubberPartNumbers: ["3483"])
        let identity = LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil,
                                         rubberColorCodes: [256, 324])
        let table = LDrawPartLimitTable(limit: limit { $0.kind = .availableNow },
                                        availability: builder.availability(with: nil),
                                        items: nil, identity: identity, year: 2026)
        let codes = { (codes: [Int32]) in codes.map { NSNumber(value: $0) } }

        #expect(table.everyColorCode(forPartNamed: "3001.dat") == codes([Self.red]))
        #expect(table.everyColorCode(forPartNamed: "3483.dat") == codes([Self.black, 256]))
        #expect(table.everyAllowedColorCode() == codes([Self.black, Self.red, 256]))
        #expect(table.status(forPartNamed: "3001.dat", colorCode: color(324)) == .notInColor)
        #expect(table.status(forPartNamed: "3001.dat", colorCode: color(Self.red)) == .allowed)
        #expect(table.status(forPartNamed: "3483.dat", colorCode: color(256)) == .allowed)
        #expect(table.status(forPartNamed: "3483.dat", colorCode: color(324)) == .notInColor)
        #expect(table.allowsPartNamed("3001.dat", colorCode: color(324)) == false)
    }

    // MARK: - Inventories

    @Test("An inventory counts by pool and color, spares included by default")
    func inventoryCounts() {
        let table = inventoryTable([item("3001", 4, 6, spares: 1), item("3001", 4, 2), item("3062a", 0, 3),
                                    item("3062b", 0, 1)])
        #expect(table.ownedCount(forPartNamed: "3001.dat", colorCode: color(Self.red)) == 9)
        #expect(table.ownedCount(forPartNamed: "3062b.dat", colorCode: color(Self.black)) == 4)
        #expect(table.ownedCount(forPartNamed: "3001.dat", colorCode: color(Self.black)) == 0)
        #expect(table.status(forPartNamed: "3001.dat", colorCode: color(Self.black)) == .notInColor)
        #expect(table.status(forPartNamed: "3002.dat", colorCode: color(Self.red)) == .notAvailable)
    }

    @Test("Spares are left out on request, and a part held only as a spare is then not allowed")
    func noSpares() {
        let table = inventoryTable([item("3001", 4, 6, spares: 1), item("3001", 0, 0, spares: 1),
                                    item("3002", 4, 0, spares: 1)]) { $0.includesSpares = false }
        #expect(table.ownedCount(forPartNamed: "3001.dat", colorCode: color(Self.red)) == 6)
        #expect(table.status(forPartNamed: "3001.dat", colorCode: color(Self.black)) == .notInColor)
        #expect(table.status(forPartNamed: "3002.dat", colorCode: color(Self.red)) == .notAvailable)
        #expect(table.allowsPartNamed("3002.dat") == false)
    }

    @Test("A loose part given in LDraw terms counts with the set's")
    func looseLDrawPart() {
        let table = inventoryTable([item("3001", 4, 2), item(nil, LDrawRebrickableColorNone, 5,
                                                             ldrawPart: "3001.dat", ldrawColor: Self.red)])
        #expect(table.ownedCount(forPartNamed: "3001.dat", colorCode: color(Self.red)) == 7)
        #expect(table.items().count == 1)
        #expect(table.items().first?.quantity == 7)
    }

    @Test("A part in any color counts toward every color of its pool")
    func anyColorItem() {
        let table = inventoryTable([item("3001", LDrawRebrickableColorAny, 2), item("3001", 4, 1)])
        #expect(table.status(forPartNamed: "3001.dat", colorCode: color(Self.sandBlue)) == .allowed)
        #expect(table.ownedCount(forPartNamed: "3001.dat", colorCode: color(Self.red)) == 3)
        #expect(table.ownedCount(forPartNamed: "3001.dat", colorCode: color(Self.black)) == 2)
        #expect(table.colorCodes(forPartNamed: "3001.dat") == nil)
    }

    @Test("Items with no part or no color are kept apart as unmatched")
    func unmatched() {
        let noColor = item("3001", LDrawRebrickableColorNone, 2)
        let unknownColor = item("3002", LDrawRebrickableColorUnknown, 1)
        let table = inventoryTable([noColor, unknownColor, item("3001", 4, 1)])
        #expect(table.unmatchedItems() == [noColor, unknownColor])
        #expect(table.items().count == 1)
    }

    @Test("Rows get LDraw ids and keep the counts apart")
    func rows() throws {
        let table = inventoryTable([item("3001", 4, 6, spares: 1), item("3062b", 0, 2), item("3062a", 0, 1)])
        let rows = table.items()
        #expect(rows.count == 2)

        let brick = try #require(rows.first { $0.rebrickablePartNumber == "3001" })
        #expect(brick.ldrawPartName == "3001.dat")
        #expect(brick.ldrawColorCode.rawValue == Self.red)
        #expect(brick.quantity == 6)
        #expect(brick.spareQuantity == 1)

        let round = try #require(rows.first { $0.rebrickablePartNumber == "3062b" })
        #expect(round.quantity == 3)
    }

    @Test("Any color folds an inventory's colors together")
    func inventoryAnyColor() {
        let table = inventoryTable([item("3001", 4, 6), item("3001", 0, 2)]) { $0.matchesAnyColor = true }
        #expect(table.ownedCount(forPartNamed: "3001.dat", colorCode: color(Self.sandBlue)) == 8)
        #expect(table.items().count == 1)
    }

    @Test("Prints join their plain part on request")
    func anyPrint() {
        let items = [item("3001pr0001", 4, 2)]
        #expect(inventoryTable(items).status(forPartNamed: "3001.dat", colorCode: color(Self.red)) == .notAvailable)
        let lenient = inventoryTable(items) { $0.matchesAnyPrint = true }
        #expect(lenient.ownedCount(forPartNamed: "3001.dat", colorCode: color(Self.red)) == 2)
    }
}
