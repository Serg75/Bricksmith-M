//
//  LDrawPartBrowserLimitTests.swift
//  LDrawFeaturesTests
//
//  Tests for the part browser's list under a parts limit: hidden and dimmed
//  parts, the color filter, inventory rows with their counts, and the Sets
//  group.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawInventory

@Suite("Part browser under a parts limit")
final class LDrawPartBrowserLimitTests {

    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("LDrawPartBrowserLimitTests-\(UUID().uuidString)", isDirectory: true)

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Fixtures

    private func code(_ value: Int32) -> LDrawColorT { LDrawColorT(rawValue: value)! }

    /// Three bricks and a primitive.
    private func library() -> LDrawPartLibrary {
        let records: [String: [String: String]] = [
            "3001.dat": [PART_NUMBER_KEY: "3001.dat", PART_NAME_KEY: "Brick  2 x  4", PART_CATEGORY_KEY: "Brick"],
            "3002.dat": [PART_NUMBER_KEY: "3002.dat", PART_NAME_KEY: "Brick  2 x  3", PART_CATEGORY_KEY: "Brick"],
            "3003.dat": [PART_NUMBER_KEY: "3003.dat", PART_NAME_KEY: "Brick  2 x  2", PART_CATEGORY_KEY: "Brick"],
            "4-4cyli.dat": [PART_NUMBER_KEY: "4-4cyli.dat", PART_NAME_KEY: "Cylinder 1.0",
                            PART_CATEGORY_KEY: Category_Primitives],
        ]
        let catalog: [String: Any] = [
            PARTS_CATALOG_KEY: [
                "Brick": ["3001.dat", "3002.dat", "3003.dat"].map { [PART_NUMBER_KEY: $0] },
                Category_Primitives: [[PART_NUMBER_KEY: "4-4cyli.dat"]],
            ],
            PARTS_LIST_KEY: records,
        ]
        let library = LDrawPartLibrary()
        library.setPartCatalog(catalog)
        return library
    }

    /// 3001 came red in 2026 and black in 2019, 3002 blue in 2026. Set
    /// 42115-1 holds two red 3001 and a spare, a blue 3002, and a red part the
    /// library lacks.
    private func session(_ limit: LDrawPartLimit) throws -> LDrawPartLimitSession {
        let store = LDrawInventoryStore(folderURL: folder)
        let builder = LDrawPartAvailabilityBuilder()
        builder.notePartNumber("3001", colorID: 4, year: 2026, inDatabaseSet: false)
        builder.notePartNumber("3001", colorID: 0, year: 2019, inDatabaseSet: false)
        builder.notePartNumber("3002", colorID: 1, year: 2026, inDatabaseSet: false)
        try store.saveAvailability(builder.availability(with: nil))
        try store.saveRebrickableIdentityData(LDrawPartIdentity.rebrickableData(
            withPartLinks: nil, colorLinks: [0: 0, 1: 1, 4: 4], relations: nil, knownPartNumbers: nil))

        func item(_ part: String, _ color: Int, _ quantity: UInt, spares: UInt = 0) -> LDrawInventoryItem {
            LDrawInventoryItem(rebrickablePartNumber: part, rebrickableColorID: color, ldrawPartName: nil,
                               ldrawColorCode: code(-1), quantity: quantity, spareQuantity: spares)
        }
        try store.saveSetInventory(LDrawSetInventory(setNumber: "42115-1", name: "Test Set", year: 2026,
                                                     themeName: nil, imageURL: nil,
                                                     items: [item("3001", 4, 2, spares: 1), item("3002", 1, 1),
                                                             item("99999", 4, 1)],
                                                     fetchDate: nil, source: nil))

        let session = LDrawPartLimitSession(store: store)
        session.currentYear = 2026
        session.limit = limit
        return session
    }

    /// A model of four red 3001 and one blue 3002.
    private func usage() -> LDrawPartUsage {
        let file = LDrawFile()
        let model = LDrawMPDModel.model() as! LDrawMPDModel
        model.setModelName("main.ldr")
        let step = model.addStep()
        for (name, color) in [("3001.dat", 4), ("3001.dat", 4), ("3001.dat", 4), ("3001.dat", 4), ("3002.dat", 1)] {
            let part = LDrawPart()
            part.setDisplayName(name, parse: false, in: nil)
            let ldrawColor = LDrawColor()
            ldrawColor.setColorCode(code(Int32(color)))
            part.setLDrawColor(ldrawColor)
            step.add(part as LDrawDirective)
        }
        file.addSubmodel(model)
        return LDrawPartUsage(file: file)
    }

    private func browser(_ session: LDrawPartLimitSession?, category: String = Category_All) -> LDrawPartBrowserModel {
        let model = LDrawPartBrowserModel(partLibrary: library())
        model.limitSession = session
        model.currentCategory = category
        return model
    }

    private func names(_ model: LDrawPartBrowserModel) -> Set<String> {
        Set(model.filteredParts.compactMap { ($0 as? [String: Any])?[PART_NUMBER_KEY] as? String })
    }

    private func row(_ model: LDrawPartBrowserModel, _ name: String) throws -> [String: Any] {
        try #require(model.filteredParts.compactMap { $0 as? [String: Any] }
            .first { ($0[PART_NUMBER_KEY] as? String ?? $0[LDrawPartBrowserLEGONumberKey] as? String) == name })
    }

    // MARK: - Available now

    @Test("Available now lists only the parts made now, or every part with the rest dimmed")
    func hideAndDim() throws {
        let model = browser(try session(LDrawPartLimit.availableNow()))

        model.reloadFilter()
        #expect(names(model) == ["3001.dat", "3002.dat"])
        #expect(model.showsInventoryRows == false)

        model.currentCategory = Category_Primitives
        model.reloadFilter()
        #expect(names(model) == ["4-4cyli.dat"])

        model.currentCategory = Category_All
        model.hidesDisallowedParts = false
        model.reloadFilter()
        #expect(names(model) == ["3001.dat", "3002.dat", "3003.dat", "4-4cyli.dat"])
        #expect(model.state(forRecord: try row(model, "3003.dat")) == .dimmed)
        #expect(model.state(forRecord: try row(model, "3001.dat")) == .normal)
    }

    @Test("A color filter keeps the parts made in that color, and the strip shows a part's colors")
    func colorFilter() throws {
        let model = browser(try session(LDrawPartLimit.availableNow()))

        model.colorFilter = 4
        model.reloadFilter()
        #expect(names(model) == ["3001.dat"])

        model.colorFilter = 0
        model.reloadFilter()
        #expect(names(model).isEmpty)

        model.colorFilter = 1
        model.hidesDisallowedParts = false
        model.reloadFilter()
        #expect(names(model) == ["3002.dat"])

        #expect(model.filterColorCodes() == [1, 4])
        let chips = model.colorChips(forPartNamed: "3001.dat")
        #expect(chips.map { $0.colorCode.rawValue } == [4])
        #expect(chips.allSatisfy { $0.hasCount == false && $0.record == nil })
        #expect(model.status(forPartNamed: "3001.dat", colorCode: code(0)) == .notInColor)
    }

    @Test("No limit filters nothing and offers no colors")
    func noLimit() throws {
        let model = browser(try session(LDrawPartLimit.none()))
        model.reloadFilter()
        #expect(names(model).count == 4)
        #expect(model.activeTable == nil)
        #expect(model.filterColorCodes() == nil)
        #expect(model.colorChips(forPartNamed: "3001.dat").isEmpty)
        #expect(model.status(forPartNamed: "3003.dat", colorCode: code(4)) == .allowed)
    }

    // MARK: - Inventories

    @Test("An inventory's rows count what the model uses against what it holds")
    func inventoryRows() throws {
        let model = browser(try session(LDrawPartLimit.inventory("42115-1")))
        model.partUsage = usage()
        model.reloadFilter()

        #expect(model.showsInventoryRows)
        #expect(model.filteredParts.count == 3)

        let red = try row(model, "3001.dat")
        #expect(red[LDrawPartBrowserCountTextKey] as? String == "4 / 3")
        #expect(red[LDrawPartBrowserLeftKey] as? Int == -1)
        #expect(red[LDrawPartBrowserSparesKey] as? Int == 1)
        #expect(red[LDrawPartBrowserColorCodeKey] as? Int == 4)
        #expect(model.state(forRecord: red) == .over)

        let blue = try row(model, "3002.dat")
        #expect(blue[LDrawPartBrowserCountTextKey] as? String == "1 / 1")
        #expect(model.state(forRecord: blue) == .allUsed)

        let missing = try row(model, "99999")
        #expect(missing[PART_NUMBER_KEY] == nil)
        #expect(model.state(forRecord: missing) == .noPart)

        // What is left sorts the problems first.
        let left = NSSortDescriptor(key: LDrawPartBrowserLeftKey, ascending: true)
        let sorted = (model.filteredParts as NSArray).sortedArray(using: [left]) as! [[String: Any]]
        #expect(sorted.first?[PART_NUMBER_KEY] as? String == "3001.dat")

        let chips = model.colorChips(forPartNamed: "3001.dat")
        #expect(chips.count == 1)
        #expect(chips.first?.hasCount == true)
        #expect(chips.first?.leftCount == -1)
        #expect(chips.first?.record != nil)
    }

    @Test("With an inventory as the limit, Primitives still list the library's primitives")
    func inventoryPrimitives() throws {
        let model = browser(try session(LDrawPartLimit.inventory("42115-1")), category: Category_Primitives)
        model.reloadFilter()

        #expect(model.showsInventoryRows == false)
        #expect(names(model) == ["4-4cyli.dat"])
    }

    @Test("A selection comes back to the same part in the same color")
    func selectionKeepsColor() {
        let black: [String: Any] = [PART_NUMBER_KEY: "3001.dat", LDrawPartBrowserColorCodeKey: 0]
        let red: [String: Any] = [PART_NUMBER_KEY: "3001.dat", LDrawPartBrowserColorCodeKey: 4]
        let records = [black, red]
        #expect(LDrawPartBrowserModel.index(ofRecord: red, inRecords: records) == 1)
        #expect(LDrawPartBrowserModel.index(ofRecord: [PART_NUMBER_KEY: "3001.dat"], inRecords: records) == 0)
        #expect(LDrawPartBrowserModel.index(ofRecord: nil, inRecords: records) == NSNotFound)
    }

    @Test("Inventory rows follow the category, the color filter and the search")
    func inventoryFilters() throws {
        let model = browser(try session(LDrawPartLimit.inventory("42115-1")), category: "Brick")
        model.reloadFilter()
        #expect(names(model) == ["3001.dat", "3002.dat"])

        model.colorFilter = 1
        model.reloadFilter()
        #expect(names(model) == ["3002.dat"])
        #expect(model.filterColorCodes() == [1, 4])

        model.colorFilter = nil
        model.currentCategory = Category_All
        model.searchString = "99999"
        model.reloadFilter()
        #expect(model.filteredParts.count == 1)
    }

    @Test("Listing every part with an inventory as the limit shows the library, dimmed")
    func inventoryShowAll() throws {
        let model = browser(try session(LDrawPartLimit.inventory("42115-1")))
        model.hidesDisallowedParts = false
        model.reloadFilter()
        #expect(model.showsInventoryRows == false)
        #expect(names(model).count == 4)
        #expect(model.state(forRecord: try row(model, "3003.dat")) == .dimmed)
    }

    // MARK: - Sets group

    @Test("The Sets group lists the store's sets, and a set's rows show with no limit")
    func setsGroup() throws {
        let session = try session(LDrawPartLimit.none())
        let model = browser(session)
        let category = LDrawPartBrowserModel.category(forInventoryIdentifier: "42115-1")

        let groups = model.categoryHierarchy().compactMap { $0 as? [String: Any] }
        let sets = try #require(groups.first { $0[CategoryNameKey] as? String == "Sets" })
        let children = try #require(sets[CategoryChildrenKey] as? [[String: Any]])
        #expect(children.map { $0[CategoryNameKey] as? String } == [category])
        #expect(children.first?[CategoryDisplayNameKey] as? String == "42115-1 Test Set")
        #expect(groups.firstIndex { $0[CategoryNameKey] as? String == "Sets" } == 2)

        #expect(model.hasCategory(category))
        #expect(model.hasCategory(LDrawPartBrowserModel.category(forInventoryIdentifier: "1-1")) == false)
        #expect(model.displayName(forCategory: category) == "42115-1 Test Set")
        #expect(LDrawPartBrowserModel.inventoryIdentifier(forCategory: category) == "42115-1")

        model.currentCategory = category
        model.reloadFilter()
        #expect(model.showsInventoryRows)
        #expect(model.filteredParts.count == 3)
        #expect(model.activeTable?.limit.inventoryIdentifier == "42115-1")
    }

    @Test("Without sets there is no Sets group")
    func noSetsGroup() {
        let session = LDrawPartLimitSession(store: LDrawInventoryStore(folderURL: folder))
        let groups = browser(session).categoryHierarchy().compactMap { $0 as? [String: Any] }
        #expect(groups.contains { $0[CategoryNameKey] as? String == "Sets" } == false)
    }
}
