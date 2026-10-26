//
//  LDrawRebrickableCatalogTests.swift
//  LDrawRebrickableTests
//
//  Tests for the set list, the catalog and set imports built from the
//  downloads.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawCore
import LDrawInventory
import LDrawRebrickable

@Suite("Catalog and set imports from the downloads")
struct LDrawRebrickableCatalogTests {

    private func record(_ availability: LDrawPartAvailability, _ part: String, _ color: Int)
        -> LDrawPartAvailabilityRecord? {
        var record = LDrawPartAvailabilityRecord()
        return availability.getRecord(&record, forPartNumber: part, colorID: color) ? record : nil
    }

    private func quantities(_ set: LDrawSetInventory) -> [String: (UInt, UInt)] {
        var result: [String: (UInt, UInt)] = [:]
        for item in set.items {
            let key = "\(item.rebrickablePartNumber ?? "?")/\(item.rebrickableColorID)"
            result[key] = (item.quantity, item.spareQuantity)
        }
        return result
    }

    // MARK: - Set list

    @Test("The set list finds sets by number and by name, newest first")
    func setList() throws {
        let list = try LDrawRebrickableSetList(downloads: RebrickableFixtures.downloads)
        #expect(list.count == 5)

        let lamborghini = try #require(list.set(forNumber: "42115"))
        #expect(lamborghini.name == "Lamborghini Sián FKP 37")
        #expect(lamborghini.year == 2020)
        #expect(lamborghini.themeName == "Technic")
        #expect(lamborghini.partCount == 3696)
        #expect(lamborghini.imageURL != nil)

        #expect(list.set(forNumber: "60000-1")?.name == "Fire Motorcycle, with \"rider\"")
        #expect(list.sets(matching: "6000", limit: 10).map(\.setNumber) == ["60000-1"])
        #expect(list.sets(matching: "sian lamborghini", limit: 10).map(\.setNumber) == ["42115-1"])
        #expect(list.sets(matching: "set", limit: 10).map(\.setNumber) == ["1000-1"])
        #expect(list.sets(matching: "", limit: 10).isEmpty)
    }

    @Test("A set under the Database Sets theme, at any depth, is a Database Set")
    func databaseSets() throws {
        let list = try LDrawRebrickableSetList(downloads: RebrickableFixtures.downloads)
        #expect(list.set(forNumber: "pab-2024-1")?.isDatabaseSet == true)
        #expect(list.set(forNumber: "42115-1")?.isDatabaseSet == false)
        #expect(list.databaseSetNumbers == ["pab-2024-1"])
    }

    // MARK: - Catalog

    @Test("A part counts for its set, the set's minifigures, and the sets that hold the set")
    func catalogYears() throws {
        let catalog = try LDrawRebrickableCatalog(downloads: RebrickableFixtures.downloads)
        let availability = catalog.availability

        let red = try #require(record(availability, "3001", 4))
        #expect(red.firstYear == 2013)  // 60000-1
        #expect(red.lastYear == 2025)   // 10000-1 holds 60000-1
        #expect(red.setCount == 3)      // 42115-1, 60000-1, 10000-1; the spare row does not count again
        #expect(red.onlyInDatabaseSets == false)

        let torso = try #require(record(availability, "973pr0001c01", 1))
        #expect(torso.firstYear == 2013)
        #expect(torso.lastYear == 2025)

        #expect(try #require(record(availability, "3001", 379)).onlyInDatabaseSets == true)
        #expect(record(availability, "3004", -1) == nil)
    }

    @Test("Only a set's newest inventory counts")
    func newestInventory() throws {
        let catalog = try LDrawRebrickableCatalog(downloads: RebrickableFixtures.downloads)
        #expect(record(catalog.availability, "3003", 4)?.lastYear == 1999)
        #expect(record(catalog.availability, "3002", 4)?.setCount == 1)
    }

    @Test("The catalog reads the part relations and every part")
    func relationsAndParts() throws {
        let catalog = try LDrawRebrickableCatalog(downloads: RebrickableFixtures.downloads)
        #expect(catalog.relations == [["M", "3062a", "3062b"], ["P", "3626cpr0001", "3626c"]])
        #expect(catalog.knownPartNumbers.count == 11)
        #expect(catalog.knownPartNumbers.contains("3003"))
    }

    @Test("Saving keeps the part links the store has and adds the rest")
    func saving() throws {
        let store = LDrawInventoryStore(folderURL: RebrickableFixtures.temporaryFolder())
        try store.saveRebrickableIdentityData(LDrawPartIdentity.rebrickableData(
            withPartLinks: ["3626cp01.dat": "3626cpr0001"], colorLinks: nil, relations: nil, knownPartNumbers: nil))

        let catalog = try LDrawRebrickableCatalog(downloads: RebrickableFixtures.downloads)
        try catalog.save(into: store, colorLinks: [4: [4, 324], 14: 14])

        #expect(store.availability()?.partCount == catalog.availability.partCount)
        let identity = store.identity(withCatalogRecords: nil)
        #expect(identity.rebrickablePartNumber(forPartName: "3626cp01.dat") == "3626cpr0001")
        #expect(identity.rebrickablePartNumber(forPartName: "u9999.dat") == nil)
        #expect(identity.rebrickableColorIDs(forColorCode: LDrawColorT(rawValue: 324)!) == [4])
        #expect(identity.poolKey(forRebrickablePartNumber: "3062b", matchesMoldVariants: true,
                                 matchesAnyPrint: false) == "3062a")

        let table = store.table(for: LDrawPartLimit.availableNow(), identity: identity, year: 2026)
        #expect(table.status(forPartNamed: "3001.dat", colorCode: LDrawColorT(rawValue: 4)!) == .allowed)
        #expect(table.status(forPartNamed: "3626cp01.dat", colorCode: LDrawColorT(rawValue: 14)!) == .allowed)
    }

    // MARK: - Set imports

    @Test("A set's import has its parts, spares apart")
    func importSet() throws {
        let list = try LDrawRebrickableSetList(downloads: RebrickableFixtures.downloads)
        let set = try LDrawRebrickableSetImporter.setInventory(number: "42115",
                                                              downloads: RebrickableFixtures.downloads,
                                                              setList: list)
        #expect(set.setNumber == "42115-1")
        #expect(set.name == "Lamborghini Sián FKP 37")
        #expect(set.source == "rebrickable-downloads")
        let parts = quantities(set)
        #expect(parts.count == 3)
        #expect(parts["3001/4"]! == (6, 1))
        #expect(parts["3069b/0"]! == (10, 0))
        #expect(parts["32523/0"]! == (4, 0))
    }

    @Test("A set's minifigures and the sets inside it count, times how often they come")
    func importNested() throws {
        let list = try LDrawRebrickableSetList(downloads: RebrickableFixtures.downloads)
        let motorcycle = quantities(try LDrawRebrickableSetImporter.setInventory(
            number: "60000-1", downloads: RebrickableFixtures.downloads, setList: list))
        #expect(motorcycle["3001/4"]! == (2, 0))
        #expect(motorcycle["3626cpr0001/14"]! == (2, 0))
        #expect(motorcycle["973pr0001c01/1"]! == (1, 0))

        let collection = quantities(try LDrawRebrickableSetImporter.setInventory(
            number: "10000-1", downloads: RebrickableFixtures.downloads, setList: list))
        #expect(collection["3001/4"]! == (4, 0))
        #expect(collection["973pr0001c01/1"]! == (2, 0))
    }

    @Test("Only the newest inventory of a set is imported")
    func importNewest() throws {
        let list = try LDrawRebrickableSetList(downloads: RebrickableFixtures.downloads)
        let parts = quantities(try LDrawRebrickableSetImporter.setInventory(
            number: "1000-1", downloads: RebrickableFixtures.downloads, setList: list))
        #expect(parts["3002/4"]! == (4, 0))
        #expect(parts["3003/4"]! == (2, 0))
        #expect(parts["3004/-1"]! == (3, 0))
    }

    @Test("An unknown set is an error that says so")
    func importUnknown() throws {
        let list = try LDrawRebrickableSetList(downloads: RebrickableFixtures.downloads)
        do {
            _ = try LDrawRebrickableSetImporter.setInventory(number: "99999", downloads: RebrickableFixtures.downloads,
                                                            setList: list)
            Issue.record("An unknown set imported.")
        } catch let error as NSError {
            #expect(error.domain == LDrawRebrickableErrorDomain)
            #expect(error.code == LDrawRebrickableError.notFound.rawValue)
        }
    }
}
