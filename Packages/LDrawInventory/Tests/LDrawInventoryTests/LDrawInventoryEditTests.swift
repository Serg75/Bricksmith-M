//
//  LDrawInventoryEditTests.swift
//  LDrawInventoryTests
//
//  Tests for editing a combined inventory, the order lists show the store's
//  inventories in, and the small rules a limit's hosts share.
//
//  Created by Sergey Slobodenyuk on 2026-11-03.
//

import Testing
import Foundation
import LDrawCore
import LDrawInventory

@Suite("Inventory edits and shared limit rules")
final class LDrawInventoryEditTests {

    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("LDrawInventoryEditTests-\(UUID().uuidString)", isDirectory: true)

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func item(_ part: String, _ colorID: Int, _ quantity: UInt, spares: UInt = 0,
                      ldraw: String? = nil, code: Int32 = -1) -> LDrawInventoryItem {
        LDrawInventoryItem(rebrickablePartNumber: part, rebrickableColorID: colorID, ldrawPartName: ldraw,
                           ldrawColorCode: LDrawColorT(rawValue: code)!, quantity: quantity, spareQuantity: spares)
    }

    @Test("Added loose parts add up by part and color, and the counts include spares")
    func addingLooseParts() {
        let inventory = LDrawCombinedInventory(name: "Bin")
            .addingLooseItems([item("3001", 4, 2), item("3001", 1, 1)])
            .addingLooseItems([item("3001", 4, 3, spares: 1), item("3001", 4, 1, ldraw: "3001.dat", code: 4)])

        #expect(inventory.looseItems.count == 3)
        #expect(inventory.looseItems[0].quantity == 5)
        #expect(inventory.looseItems[0].spareQuantity == 1)
        #expect(inventory.loosePartCount == 8)
        #expect(inventory.looseSpareCount == 1)
    }

    @Test("A set's count is set, and 0 takes the set out")
    func settingCounts() {
        let inventory = LDrawCombinedInventory(name: "Bin").settingCount(2, forSet: "42115-1")

        #expect(inventory.setCounts == ["42115-1": 2])
        #expect(inventory.settingCount(0, forSet: "42115-1").setCounts.isEmpty)
        #expect(inventory.settingCount(-1, forSet: "60000-1").setCounts == ["42115-1": 2])
    }

    @Test("A name is trimmed, and a blank one keeps the old name")
    func renaming() {
        let inventory = LDrawCombinedInventory(name: "Bin")

        #expect(inventory.renamed(to: "  Shelf ").name == "Shelf")
        #expect(inventory.renamed(to: " \n").name == "Bin")
    }

    @Test("Lists show the sets, then the combined inventories")
    func listOrder() throws {
        let store = LDrawInventoryStore(folderURL: folder)
        let bin = LDrawCombinedInventory(name: "Bin")
        try store.saveCombinedInventory(bin)
        try store.saveSetInventory(LDrawSetInventory(setNumber: "42115-1", name: "Lamborghini", year: 2020,
                                                     themeName: nil, imageURL: nil, items: [item("3001", 4, 1)],
                                                     fetchDate: nil, source: nil))

        #expect(store.inventoryIdentifiers() == ["42115-1", bin.identifier])
    }

    @Test("A library name is lowercase, with .dat and a backslash before a folder's part")
    func libraryNames() {
        #expect(LDrawPartIdentity.libraryPartName(" 3001 ") == "3001.dat")
        #expect(LDrawPartIdentity.libraryPartName("S/3001s01") == "s\\3001s01.dat")
        #expect(LDrawPartIdentity.libraryPartName("s\\3001s01.dat") == "s\\3001s01.dat")
        #expect(LDrawPartIdentity.libraryPartName("") == nil)
    }

    @Test("Available now starts its years back from this one; 0 is any year")
    func firstYear() {
        let limit = LDrawPartLimit.availableNow().mutableCopy() as! LDrawMutablePartLimit

        limit.yearsBack = 1
        #expect(limit.firstYear(forCurrentYear: 2026) == 2026)
        limit.yearsBack = 5
        #expect(limit.firstYear(forCurrentYear: 2026) == 2022)
        limit.yearsBack = 0
        #expect(limit.firstYear(forCurrentYear: 2026) == Int.min)
    }

    @Test("A part not made in a color cannot be given it, unless the limit only warns")
    func pickingColors() {
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: [1: 1, 4: 4],
                                                     relations: nil, knownPartNumbers: nil, rubberPartNumbers: nil)
        let identity = LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)
        let limit = LDrawPartLimit.inventory("set").mutableCopy() as! LDrawMutablePartLimit
        let red = LDrawColorT(rawValue: 4)!
        let blue = LDrawColorT(rawValue: 1)!

        func table() -> LDrawPartLimitTable {
            LDrawPartLimitTable(limit: limit.copy() as! LDrawPartLimit, availability: nil,
                                items: [item("3001", 4, 2)], identity: identity, year: 2026)
        }

        #expect(table().allowsPickingColorCode(red, forPartNamed: "3001.dat"))
        #expect(table().allowsPickingColorCode(blue, forPartNamed: "3001.dat") == false)
        #expect(table().allowsPickingColorCode(blue, forPartNamed: "3002.dat"))

        limit.warnsOnly = true
        #expect(table().allowsPickingColorCode(blue, forPartNamed: "3001.dat"))
    }

    @Test("A limit is kept with a model file, beside its text; a file with none or with junk has none")
    func limitWithFile() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("model.ldr")
        let text = Data("0 Model\n".utf8)
        try text.write(to: file)
        let limit = LDrawPartLimit.inventory("42115-1").mutableCopy() as! LDrawMutablePartLimit
        limit.includesSpares = false

        #expect(LDrawPartLimit.limit(ofFileAt: file) == nil)

        try limit.write(toFileAt: file)
        #expect(LDrawPartLimit.limit(ofFileAt: file) == limit)
        #expect(try Data(contentsOf: file) == text)

        try LDrawPartLimit.availableNow().write(toFileAt: file)
        #expect(LDrawPartLimit.limit(ofFileAt: file) == LDrawPartLimit.availableNow())

        let junk = Array("not json".utf8)
        _ = setxattr(file.path, LDrawPartLimitFileAttributeName, junk, junk.count, 0, 0)
        #expect(LDrawPartLimit.limit(ofFileAt: file) == nil)
    }
}
