//
//  LDrawInventoryItemTests.swift
//  LDrawInventoryTests
//
//  Tests for inventory items, set inventories and combined inventories.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawCore
import LDrawInventory

@Suite("Inventory items and inventories")
struct LDrawInventoryItemTests {

    // MARK: - Items

    @Test("An item reads back what it wrote, leaving out ids it does not have")
    func itemRoundTrip() throws {
        let item = LDrawInventoryItem(rebrickablePartNumber: "3001", rebrickableColorID: 4,
                                      ldrawPartName: nil, ldrawColorCode: LDrawColorT(rawValue: -1)!,
                                      quantity: 6, spareQuantity: 1)
        let dictionary = item.dictionaryRepresentation()

        #expect(dictionary["ldrawPart"] == nil)
        #expect(dictionary["ldrawColor"] == nil)
        let read = try #require(LDrawInventoryItem(dictionary: dictionary))
        #expect(read == item)
    }

    @Test("An item with no part, or with nothing in it, does not read")
    func itemJunk() {
        #expect(LDrawInventoryItem(dictionary: ["color": 4, "quantity": 2]) == nil)
        #expect(LDrawInventoryItem(dictionary: ["part": "3001", "quantity": 0]) == nil)
        #expect(LDrawInventoryItem(dictionary: ["part": "3001", "quantity": -2]) == nil)
        #expect(LDrawInventoryItem(dictionary: ["part": "3001", "quantity": true]) == nil)
        #expect(LDrawInventoryItem(dictionary: nil) == nil)
    }

    @Test("A spare-only item reads, and counts multiply and add")
    func itemCounts() throws {
        let dictionary: [String: Any] = ["part": "3001", "color": 4, "quantity": 0, "spares": 1]
        let spare = try #require(LDrawInventoryItem(dictionary: dictionary))
        #expect(spare.quantity == 0)
        #expect(spare.spareQuantity == 1)

        let doubled = spare.adding(quantity: 3, spareQuantity: 0).multiplied(by: 2)
        #expect(doubled.quantity == 6)
        #expect(doubled.spareQuantity == 2)
        #expect(doubled.rebrickablePartNumber == "3001")
    }

    // MARK: - Sets

    @Test("A set number gets its version, and keeps one it has", arguments: [
        ("42115", "42115-1"),
        (" 42115-1 ", "42115-1"),
        ("10295-2", "10295-2"),
        ("fig-000123", "fig-000123"),
        ("BB1171", "bb1171-1"),
    ])
    func normalizedSetNumber(typed: String, expected: String) {
        #expect(LDrawSetInventory.normalizedSetNumber(typed) == expected)
    }

    @Test("An empty set number is nil")
    func emptySetNumber() {
        #expect(LDrawSetInventory.normalizedSetNumber("  ") == nil)
        #expect(LDrawSetInventory.normalizedSetNumber(nil) == nil)
    }

    @Test("A set reads back what it wrote, and counts parts and spares apart")
    func setRoundTrip() throws {
        let items = [
            LDrawInventoryItem(rebrickablePartNumber: "3001", rebrickableColorID: 4, ldrawPartName: nil,
                               ldrawColorCode: LDrawColorT(rawValue: -1)!, quantity: 6, spareQuantity: 0),
            LDrawInventoryItem(rebrickablePartNumber: "3069b", rebrickableColorID: 0, ldrawPartName: "3069b.dat",
                               ldrawColorCode: LDrawColorT(rawValue: 0)!, quantity: 10, spareQuantity: 2),
        ]
        let fetched = Date(timeIntervalSince1970: 1_800_000_000)
        let set = LDrawSetInventory(setNumber: "42115-1", name: "Lamborghini Sián FKP 37", year: 2020,
                                    themeName: "Technic", imageURL: nil, items: items,
                                    fetchDate: fetched, source: "rebrickable-downloads")

        #expect(set.partCount == 16)
        #expect(set.spareCount == 2)

        let read = try #require(LDrawSetInventory(dictionary: set.dictionaryRepresentation()))
        #expect(read.setNumber == "42115-1")
        #expect(read.name == "Lamborghini Sián FKP 37")
        #expect(read.year == 2020)
        #expect(read.themeName == "Technic")
        #expect(read.imageURL == nil)
        #expect(read.items == items)
        #expect(read.fetchDate == fetched)
        #expect(read.source == "rebrickable-downloads")
    }

    @Test("A set skips items that do not read, and needs a number")
    func setJunk() throws {
        let read = try #require(LDrawSetInventory(dictionary: [
            "setNumber": "42115",
            "items": [["part": "3001", "quantity": 1], ["quantity": 3], "junk"],
            "unknown": ["kept": false],
        ]))
        #expect(read.setNumber == "42115-1")
        #expect(read.name == "42115-1")
        #expect(read.items.count == 1)
        #expect(LDrawSetInventory(dictionary: ["name": "No number"]) == nil)
    }

    // MARK: - Combined inventories

    @Test("A combined inventory reads back what it wrote")
    func combinedRoundTrip() throws {
        let loose = LDrawInventoryItem(rebrickablePartNumber: nil, rebrickableColorID: LDrawRebrickableColorNone,
                                       ldrawPartName: "3001.dat", ldrawColorCode: LDrawColorT(rawValue: 4)!,
                                       quantity: 20, spareQuantity: 0)
        let inventory = LDrawCombinedInventory(name: "Technic shelf")
            .replacingSetCounts(["42115-1": 1, "42131-1": 2])
            .replacingLooseItems([loose])

        let read = try #require(LDrawCombinedInventory(dictionary: inventory.dictionaryRepresentation()))
        #expect(read.identifier == inventory.identifier)
        #expect(read.name == "Technic shelf")
        #expect(read.setCounts == ["42115-1": 1, "42131-1": 2])
        #expect(read.looseItems == [loose])
    }

    @Test("A combined inventory drops set counts below one and normalizes set numbers")
    func combinedJunk() throws {
        let read = try #require(LDrawCombinedInventory(dictionary: [
            "identifier": "A",
            "sets": ["42115": 1, "10295-1": 0, "60000-1": "x"],
        ]))
        #expect(read.setCounts == ["42115-1": 1])
        #expect(read.name == "")
        #expect(LDrawCombinedInventory(dictionary: ["name": "No identifier"]) == nil)
    }
}
