//
//  LDrawInventoryStoreTests.swift
//  LDrawInventoryTests
//
//  Tests for the store's files.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawCore
import LDrawInventory

@Suite("Inventory store")
final class LDrawInventoryStoreTests {

    private let folder: URL

    init() {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LDrawInventoryStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Fixtures

    private func store() -> LDrawInventoryStore {
        LDrawInventoryStore(folderURL: folder)
    }

    private func item(_ part: String, _ colorID: Int, _ quantity: UInt, spares: UInt = 0) -> LDrawInventoryItem {
        LDrawInventoryItem(rebrickablePartNumber: part, rebrickableColorID: colorID, ldrawPartName: nil,
                           ldrawColorCode: LDrawColorT(rawValue: -1)!, quantity: quantity, spareQuantity: spares)
    }

    private func set(_ number: String, _ items: [LDrawInventoryItem]) -> LDrawSetInventory {
        LDrawSetInventory(setNumber: number, name: "Set \(number)", year: 2025, themeName: nil, imageURL: nil,
                          items: items, fetchDate: nil, source: nil)
    }

    private func identity() -> LDrawPartIdentity {
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: [4: 4],
                                                     relations: nil, knownPartNumbers: nil, rubberPartNumbers: nil)
        return LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)
    }

    // MARK: - Tests

    @Test("An empty folder holds nothing")
    func empty() {
        let store = store()
        #expect(store.combinedInventories().isEmpty)
        #expect(store.setNumbers().isEmpty)
        #expect(store.availability() == nil)
        #expect(store.rebrickableIdentityData() == nil)
        #expect(store.identityOverrides().isEmpty)
    }

    @Test("Sets are saved, read by a new store, and removed")
    func sets() throws {
        try store().saveSetInventory(set("42115-1", [item("3001", 4, 6)]))
        try store().saveSetInventory(set("10295-1", [item("3002", 4, 1)]))

        let reader = store()
        #expect(reader.setNumbers() == ["10295-1", "42115-1"])
        #expect(reader.setInventory(forNumber: "42115")?.items.count == 1)

        try reader.removeSetInventory(forNumber: "42115-1")
        #expect(reader.setNumbers() == ["10295-1"])
        #expect(store().setNumbers() == ["10295-1"])
    }

    @Test("Combined inventories are added, replaced, sorted by name and removed")
    func combinedInventories() throws {
        let writer = store()
        let technic = LDrawCombinedInventory(name: "Technic")
        let city = LDrawCombinedInventory(name: "City")
        try writer.saveCombinedInventory(technic)
        try writer.saveCombinedInventory(city)
        try writer.saveCombinedInventory(technic.renamed(to: "Technic shelf"))

        let reader = store()
        #expect(reader.combinedInventories().map(\.name) == ["City", "Technic shelf"])
        #expect(reader.combinedInventory(withIdentifier: technic.identifier)?.name == "Technic shelf")

        try reader.removeCombinedInventory(withIdentifier: city.identifier)
        #expect(store().combinedInventories().map(\.name) == ["Technic shelf"])
    }

    @Test("A combined inventory's items are its sets times their counts, plus loose parts")
    func items() throws {
        let store = store()
        try store.saveSetInventory(set("42115-1", [item("3001", 4, 6, spares: 1)]))
        let inventory = LDrawCombinedInventory(name: "Shelf")
            .replacingSetCounts(["42115-1": 2, "99999-1": 1])
            .replacingLooseItems([item("3001", 4, 3)])
        try store.saveCombinedInventory(inventory)

        let items = try #require(store.items(forInventoryIdentifier: inventory.identifier))
        #expect(items.map(\.quantity) == [12, 3])
        #expect(items.map(\.spareQuantity) == [2, 0])
        #expect(store.items(forInventoryIdentifier: "42115-1")?.count == 1)
        #expect(store.items(forInventoryIdentifier: "nothing") == nil)

        let table = store.table(for: LDrawPartLimit.inventory(inventory.identifier),
                                identity: identity(), year: 2026)
        #expect(table.ownedCount(forPartNamed: "3001.dat", colorCode: LDrawColorT(rawValue: 4)!) == 17)
    }

    @Test("A limit on an inventory the store does not have falls back to no limit, keeping its options")
    func resolvedLimit() {
        let mutable = LDrawPartLimit.inventory("gone").mutableCopy() as! LDrawMutablePartLimit
        mutable.warnsOnly = true
        let resolved = store().resolvedLimit(mutable)
        #expect(resolved.kind == .none)
        #expect(resolved.warnsOnly == true)
        #expect(store().resolvedLimit(LDrawPartLimit.availableNow()).kind == .availableNow)
    }

    @Test("The catalog and identity data are saved and read back")
    func catalogAndIdentity() throws {
        let builder = LDrawPartAvailabilityBuilder()
        builder.notePartNumber("3001", colorID: 4, year: 2026, inDatabaseSet: false)
        try store().saveAvailability(builder.availability(with: nil))
        try store().saveRebrickableIdentityData(LDrawPartIdentity.rebrickableData(
            withPartLinks: ["3001p11.dat": "3001pr0001"], colorLinks: [4: 4], relations: nil, knownPartNumbers: nil,
            rubberPartNumbers: nil))
        try store().saveIdentityOverrides(["u9001.dat": "3001"])

        let reader = store()
        #expect(reader.availability()?.partNumbers() == ["3001"])
        let identity = reader.identity(withCatalogRecords: nil)
        #expect(identity.rebrickablePartNumber(forPartName: "3001p11.dat") == "3001pr0001")
        #expect(identity.rebrickablePartNumber(forPartName: "u9001.dat") == "3001")

        let table = reader.table(for: LDrawPartLimit.availableNow(), identity: identity, year: 2026)
        #expect(table.status(forPartNamed: "u9001.dat", colorCode: LDrawColorT(rawValue: 4)!) == .allowed)
    }

    @Test("A file of a newer version reads the keys it knows")
    func newerVersion() throws {
        let file: [String: Any] = [
            "version": 9,
            "future": ["anything": true],
            "inventories": [["identifier": "A", "name": "Shelf", "sets": [:], "loose": [], "color": "red"]],
        ]
        let data = try JSONSerialization.data(withJSONObject: file)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent("inventories.json"))

        #expect(store().combinedInventories().map(\.name) == ["Shelf"])
    }

    @Test("An unreadable inventories file is moved aside before a save, not written over")
    func unreadableInventories() throws {
        let damaged = Data("{\"version\": 1, \"inventories\": [ ,]}".utf8)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try damaged.write(to: folder.appendingPathComponent("inventories.json"))

        let store = store()
        #expect(store.combinedInventories().isEmpty)
        try store.saveCombinedInventory(LDrawCombinedInventory(name: "Shelf"))

        let kept = try Data(contentsOf: folder.appendingPathComponent("inventories.unreadable.json"))
        #expect(kept == damaged)
        #expect(self.store().combinedInventories().map(\.name) == ["Shelf"])
    }

    @Test("An unreadable hand matches file is moved aside, and a second one gets its own name")
    func unreadableOverrides() throws {
        let url = folder.appendingPathComponent("identity-overrides.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        try store().saveIdentityOverrides(["x.dat": "1234"])
        try Data("[]".utf8).write(to: url)

        let store = store()
        #expect(store.identityOverrides().isEmpty)
        try store.saveIdentityOverrides(["y.dat": "5678"])

        for name in ["identity-overrides.unreadable.json", "identity-overrides.unreadable 2.json"] {
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path))
        }
        #expect(store.identityOverrides() == ["y.dat": "5678"])
    }

    @Test("Saving posts a change")
    func notification() throws {
        let store = store()
        var posts = 0
        let observer = NotificationCenter.default.addObserver(forName: .LDrawInventoryStoreDidChange,
                                                              object: store, queue: nil) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        try store.saveSetInventory(set("42115-1", []))
        try store.saveCombinedInventory(LDrawCombinedInventory(name: "Shelf"))
        #expect(posts == 2)
    }
}
