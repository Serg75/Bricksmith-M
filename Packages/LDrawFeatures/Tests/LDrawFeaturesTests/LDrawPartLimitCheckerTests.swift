//
//  LDrawPartLimitCheckerTests.swift
//  LDrawFeaturesTests
//
//  Tests for what hosts show of a parts limit: a file's check with its badges
//  and summary, the text about problems, the limits a menu offers, and the
//  Part Browser's and Colors window's rules.
//
//  The fixtures are built, not parsed, and run with no part library.
//
//  Created by Sergey Slobodenyuk on 2026-11-03.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawInventory

// Badges show only while parts are marked, which is a setting for the whole
// process.
@Suite("What hosts show of a parts limit", .serialized)
final class LDrawPartLimitCheckerTests {

    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("LDrawPartLimitCheckerTests-\(UUID().uuidString)", isDirectory: true)
    private let markStyle = LDrawPart.limitMarkStyle()

    init() {
        LDrawPart.setLimitMarkStyle(.stripes)
    }

    deinit {
        LDrawPart.setLimitMarkStyle(markStyle)
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Fixtures

    private static let red = LDrawColorT(rawValue: 4)!
    private static let blue = LDrawColorT(rawValue: 1)!

    private func part(_ name: String, _ code: LDrawColorT = LDrawPartLimitCheckerTests.red) -> LDrawPart {
        let part = LDrawPart()
        let color = LDrawColor()
        color.setColorCode(code)
        part.setDisplayName(name, parse: false, in: nil)
        part.setLDrawColor(color)
        return part
    }

    private func item(_ part: String, _ colorID: Int, _ quantity: UInt, spares: UInt = 0) -> LDrawInventoryItem {
        LDrawInventoryItem(rebrickablePartNumber: part, rebrickableColorID: colorID, ldrawPartName: nil,
                           ldrawColorCode: LDrawColorT(rawValue: -1)!, quantity: quantity, spareQuantity: spares)
    }

    /// A store holding set 42115-1, with two red 3001, and the color links.
    private func store() throws -> LDrawInventoryStore {
        let store = LDrawInventoryStore(folderURL: folder)
        try store.saveRebrickableIdentityData(LDrawPartIdentity.rebrickableData(
            withPartLinks: nil, colorLinks: [1: 1, 4: 4], relations: nil, knownPartNumbers: nil,
            rubberPartNumbers: nil))
        try store.saveSetInventory(LDrawSetInventory(setNumber: "42115-1", name: "Test Set", year: 2026,
                                                     themeName: nil, imageURL: nil,
                                                     items: [item("3001", 4, 2, spares: 1)],
                                                     fetchDate: nil, source: nil))
        return store
    }

    /// Four red 3001, one blue 3001 and one red 3002, in one step. The set
    /// holds three red 3001 with its spare.
    private func file() -> (LDrawFile, LDrawMPDModel, [LDrawPart]) {
        let file = LDrawFile()
        let model = LDrawMPDModel.model() as! LDrawMPDModel
        let parts = [part("3001.dat"), part("3001.dat"), part("3001.dat"), part("3001.dat"),
                     part("3001.dat", Self.blue), part("3002.dat")]
        let step = model.addStep()
        model.setModelName("main.ldr")
        for part in parts {
            step.add(part as LDrawDirective)
        }
        file.addSubmodel(model)
        return (file, model, parts)
    }

    private func session(_ store: LDrawInventoryStore, _ limit: LDrawPartLimit) -> LDrawPartLimitSession {
        let session = LDrawPartLimitSession(store: store)
        session.currentYear = 2026
        session.limit = limit
        return session
    }

    // MARK: - The check

    @Test("A check finds each problem, worst first, and badges the parts and the model")
    func check() throws {
        let store = try store()
        let table = session(store, LDrawPartLimit.inventory("42115-1")).table
        let (file, model, parts) = file()
        let checker = LDrawPartLimitChecker(file: file)

        #expect(checker.check(against: table))
        #expect(checker.showsMarks)
        #expect(checker.summaryStatuses().map { $0.intValue }
                == [LDrawPartLimitStatus.notAvailable.rawValue, LDrawPartLimitStatus.notInColor.rawValue,
                    LDrawPartLimitStatus.tooMany.rawValue])

        let summary = checker.summaryBadge()
        #expect(summary.count == 3)
        #expect(summary.symbolName == "exclamationmark.triangle.fill")
        #expect(summary.tint == .notAvailable)
        #expect(checker.summaryToolTip() == "Parts that break the parts limit")

        // A part within the limit would ask the part library, which tests do
        // not have, whether it is missing.
        #expect(checker.badge(for: model).count == 3)
        #expect(checker.badge(for: parts[3]).symbolName == "plus.circle.fill")
        #expect(checker.badge(for: parts[4]).symbolName == "exclamationmark.circle.fill")
        #expect(checker.toolTip(for: model, store: store) == "3 parts break the parts limit.")
        #expect(checker.line(for: parts[5], store: store) == "Not in 42115-1 Test Set")
        #expect(checker.line(for: parts[3], store: store) == "Uses 4 of 3 in 42115-1 Test Set")
    }

    @Test("Without a limit the earlier marks are cleared once, then nothing is checked")
    func noLimit() throws {
        let store = try store()
        let (file, _, parts) = file()
        let checker = LDrawPartLimitChecker(file: file)

        #expect(checker.check(against: session(store, LDrawPartLimit.inventory("42115-1")).table))
        #expect(checker.check(against: LDrawPartLimitTable.unrestricted()))
        #expect(parts.allSatisfy { $0.limitStatus == .allowed })
        #expect(checker.showsMarks == false)
        #expect(checker.summaryBadge().count == 0)

        #expect(checker.check(against: LDrawPartLimitTable.unrestricted()) == false)
        #expect(checker.report == nil)
    }

    // MARK: - Text

    @Test("A limit's title, and Missing Inventory for one the store lacks")
    func titles() throws {
        let store = try store()

        #expect(LDrawPartLimitPresentation.title(forLimit: LDrawPartLimit.none(), store: store) == "All Parts")
        #expect(LDrawPartLimitPresentation.title(forLimit: LDrawPartLimit.availableNow(), store: store)
                == "Available Now")
        #expect(LDrawPartLimitPresentation.title(forLimit: LDrawPartLimit.inventory("42115-1"), store: store)
                == "42115-1 Test Set")
        #expect(LDrawPartLimitPresentation.title(forLimit: LDrawPartLimit.inventory("60000-1"), store: store)
                == "Missing Inventory")
        #expect(LDrawPartLimitPresentation.statusTitle(for: .tooMany) == "Too many")
        #expect(LDrawPartLimitPresentation.summary(for: .notAvailable, count: 3) == "3 not available")
    }

    @Test("Menus offer All Parts, Available Now, then the sets and inventories")
    func choosableLimits() throws {
        let store = try store()
        let bin = LDrawCombinedInventory(name: "Bin")
        try store.saveCombinedInventory(bin)
        let session = session(store, LDrawPartLimit.none())

        #expect(session.choosableLimits(withOptionsOf: session.limit).map { $0.inventoryIdentifier ?? "\($0.kind.rawValue)" }
                == ["0", "1", "42115-1", bin.identifier])
        #expect(session.needsPartsData)
        #expect(LDrawPartLimitSession(store: LDrawInventoryStore(folderURL: folder.appendingPathComponent("empty")))
                    .needsPartsData == false)
    }

    // MARK: - A limit per model

    @Test("Each limit gets its own table, kept until the data changes; the default's is the session's")
    func tablePerLimit() throws {
        let store = try store()
        let session = session(store, LDrawPartLimit.none())
        let set = LDrawPartLimit.inventory("42115-1")
        let table = session.table(for: set)

        #expect(table.limit.kind == .inventory)
        #expect(session.table(for: set) === table)
        #expect(session.table(for: LDrawPartLimit.none()) === session.table)
        #expect(session.restrictingTable(for: LDrawPartLimit.none()) == nil)
        #expect(session.restrictingTable(for: set) != nil)
        #expect(session.table(for: LDrawPartLimit.inventory("60000-1")).limit.kind == .none)

        try store.saveCombinedInventory(LDrawCombinedInventory(name: "Bin"))
        #expect(session.table(for: set) !== table)
    }

    @Test("Menus and a set's table keep a model's options; a model's limit needs the parts data")
    func optionsPerModel() throws {
        let empty = LDrawPartLimitSession(store: LDrawInventoryStore(folderURL: folder.appendingPathComponent("empty")))
        let model = LDrawPartLimit.availableNow().mutableCopy() as! LDrawMutablePartLimit
        model.warnsOnly = true

        #expect(empty.choosableLimits(withOptionsOf: model).allSatisfy { $0.warnsOnly })
        #expect(empty.needsPartsData == false)
        _ = empty.table(for: model)
        #expect(empty.needsPartsData)

        let full = session(try store(), LDrawPartLimit.none())
        #expect(full.table(forInventoryIdentifier: "42115-1", withOptionsOf: model)?.limit.warnsOnly == true)
        #expect(full.table(forInventoryIdentifier: "60000-1", withOptionsOf: model) == nil)
    }

    @Test("The Part Browser follows the limit it is given, else the session's")
    func browserLimit() throws {
        let model = LDrawPartBrowserModel(partLibrary: LDrawPartLibrary())
        model.limitSession = session(try store(), LDrawPartLimit.none())
        model.reloadFilter()
        #expect(model.activeTable == nil)

        model.limit = LDrawPartLimit.inventory("42115-1")
        model.reloadFilter()
        #expect(model.activeTable?.limit.inventoryIdentifier == "42115-1")
    }

    // MARK: - Part Browser and Colors window

    @Test("An inventory row brings its color; elsewhere a part not made in the color cannot go in")
    func insertion() throws {
        let store = try store()
        let model = LDrawPartBrowserModel(partLibrary: LDrawPartLibrary())
        let blue = LDrawColor()
        blue.setColorCode(Self.blue)
        model.limitSession = session(store, LDrawPartLimit.inventory("42115-1"))
        model.reloadFilter()

        #expect(LDrawPartBrowserModel.colorCode(forRecord: [LDrawPartBrowserColorCodeKey: 4],
                                                currentColorCode: Self.blue) == Self.red)
        #expect(LDrawPartBrowserModel.colorCode(forRecord: nil, currentColorCode: Self.blue) == Self.blue)
        #expect(model.insertionProblem(forRecord: [PART_NUMBER_KEY: "3001.dat"], currentColor: blue)?
                    .hasPrefix("The inventory has none in") == true)
        #expect(model.insertionProblem(forRecord: [PART_NUMBER_KEY: "3001.dat", LDrawPartBrowserColorCodeKey: 4],
                                       currentColor: blue) == nil)
        #expect(model.limitBarText(forCategory: nil) == "Parts of 42115-1 Test Set")
        #expect(model.toolTip(forRecord: [LDrawPartBrowserCountTextKey: "1 / 3", PART_NUMBER_KEY: "3001.dat",
                                          LDrawPartBrowserOwnedKey: 3, LDrawPartBrowserSparesKey: 1],
                              inCountColumn: true) == "2 + 1 spare")
    }

    @Test("Available now names its years in the browser's bar")
    func availableNowBar() throws {
        let store = try store()
        let builder = LDrawPartAvailabilityBuilder()
        builder.notePartNumber("3001", colorID: 4, year: 2026, inDatabaseSet: false)
        try store.saveAvailability(builder.availability(with: nil))
        let limit = LDrawPartLimit.availableNow().mutableCopy() as! LDrawMutablePartLimit
        let model = LDrawPartBrowserModel(partLibrary: LDrawPartLibrary())
        let session = session(store, limit.copy() as! LDrawPartLimit)
        model.limitSession = session

        limit.yearsBack = 5
        session.limit = limit.copy() as! LDrawPartLimit
        model.reloadFilter()
        #expect(model.limitBarText(forCategory: nil) == "Parts made in 2022–2026")

        limit.yearsBack = 1
        session.limit = limit.copy() as! LDrawPartLimit
        model.reloadFilter()
        #expect(model.limitBarText(forCategory: nil) == "Parts made in 2026")
    }

    @Test("The Colors window counts only the parts that narrow its colors")
    func colorsFooter() throws {
        let table = session(try store(), LDrawPartLimit.inventory("42115-1")).table

        #expect(LDrawColorPanelModel.footer(forPartNames: ["3001.dat", "3001.dat", "3002.dat"], table: table)
                == "1 color for 3001.dat (3001)")
        #expect(LDrawColorPanelModel.footer(forPartNames: ["3002.dat"], table: table) == nil)
        #expect(LDrawColorPanelModel.limitPartNames(forSelectedPartNames: [], hasSelection: false,
                                                    browserPartName: "3001.dat") == ["3001.dat"])
        #expect(LDrawColorPanelModel.limitPartNames(forSelectedPartNames: [], hasSelection: true,
                                                    browserPartName: "3001.dat").isEmpty)
        #expect(LDrawColorPanelModel.randomColorTest(for: nil) == nil)
    }

    @Test("Randomize Colors gives a part only colors it is made in")
    func randomColors() throws {
        let table = session(try store(), LDrawPartLimit.inventory("42115-1")).table
        let test = try #require(LDrawColorPanelModel.randomColorTest(for: table))
        let red = LDrawColor()
        let blue = LDrawColor()
        red.setColorCode(Self.red)
        blue.setColorCode(Self.blue)

        #expect(test(part("3001.dat"), red))
        #expect(test(part("3001.dat"), blue) == false)
        #expect(test(LDrawLine(), blue))
    }

    // MARK: - Hand matches

    @Test("A typed match is saved; blank text changes nothing; a part the library lacks is refused")
    func handMatch() throws {
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: [4: 4], relations: nil,
                                                     knownPartNumbers: ["3001"], rubberPartNumbers: nil)
        let identity = LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)
        let unmatched = try #require(LDrawUnmatchedParts.parts(in: [item("99999", 4, 1)],
                                                               limit: LDrawPartLimit.inventory("set"),
                                                               identity: identity,
                                                               libraryHasPart: { _ in false }).first)
        let library: (String) -> Bool = { $0 == "s\\3001s01.dat" }

        #expect(try LDrawUnmatchedParts.overrides(["a": "b"], matching: unmatched, to: " ",
                                                  libraryHasPart: library) == ["a": "b"])
        #expect(try LDrawUnmatchedParts.overrides(nil, matching: unmatched, to: "S/3001s01",
                                                  libraryHasPart: library) == ["s/3001s01": "99999"])
        #expect(throws: (any Error).self) {
            try LDrawUnmatchedParts.overrides(nil, matching: unmatched, to: "4711", libraryHasPart: library)
        }
    }
}
