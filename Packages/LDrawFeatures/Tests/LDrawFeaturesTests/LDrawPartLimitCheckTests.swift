//
//  LDrawPartLimitCheckTests.swift
//  LDrawFeaturesTests
//
//  Tests for what a model uses and how each part stands against a limit.
//
//  The fixtures are built, not parsed, and run with no part catalog, so no
//  part is reported missing.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawInventory

@Suite("Parts limit check")
struct LDrawPartLimitCheckTests {

    // MARK: - Fixtures

    private static let black: Int32 = 0
    private static let blue: Int32 = 1
    private static let red: Int32 = 4
    private static let main: Int32 = 16

    private func color(_ code: Int32) -> LDrawColor {
        let color = LDrawColor()
        color.setColorCode(LDrawColorT(rawValue: code)!)
        return color
    }

    private func part(_ name: String, _ code: Int32 = LDrawPartLimitCheckTests.red, hidden: Bool = false) -> LDrawPart {
        let part = LDrawPart()
        part.setDisplayName(name, parse: false, in: nil)
        part.setLDrawColor(color(code))
        part.setHidden(hidden)
        return part
    }

    private func bracket(_ text: String) -> LPubCommand {
        let command: LPubCommand = text.contains("SUB") ? LPubPliSubstitute() : LPubPliIgnore()
        command.lPubCommandString = text
        return command
    }

    /// A model in the file. The first one added is the main model. The caller
    /// keeps the file, because names resolve through it.
    @discardableResult
    private func model(_ name: String, in file: LDrawFile, steps: [[LDrawDirective]]) -> LDrawMPDModel {
        let model = LDrawMPDModel.model() as! LDrawMPDModel
        model.setModelName(name)
        for directives in steps {
            let step = model.addStep()
            for directive in directives {
                step.add(directive)
            }
        }
        file.addSubmodel(model)
        return model
    }

    /// Red, blue and black link to the same Rebrickable colors.
    private func identity() -> LDrawPartIdentity {
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: [0: [0, 256], 1: 1, 4: 4],
                                                     relations: nil, knownPartNumbers: nil)
        return LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)
    }

    private func item(_ part: String, _ colorID: Int, _ quantity: UInt, spares: UInt = 0) -> LDrawInventoryItem {
        LDrawInventoryItem(rebrickablePartNumber: part, rebrickableColorID: colorID, ldrawPartName: nil,
                           ldrawColorCode: LDrawColorT(rawValue: -1)!, quantity: quantity, spareQuantity: spares)
    }

    private func inventory(_ items: [LDrawInventoryItem],
                           _ change: (LDrawMutablePartLimit) -> Void = { _ in }) -> LDrawPartLimitTable {
        let limit = LDrawPartLimit.inventory("set").mutableCopy() as! LDrawMutablePartLimit
        change(limit)
        return LDrawPartLimitTable(limit: limit.copy() as! LDrawPartLimit, availability: nil, items: items,
                                   identity: identity(), year: 2026)
    }

    private func usage(_ file: LDrawFile) -> [String] {
        LDrawPartUsage(file: file).copies.map {
            "\($0.partName)/\($0.colorCode.rawValue)" + ($0.isCounted ? "" : " not counted")
        }
    }

    // MARK: - Usage

    @Test("A submodel counts where it is placed, each time, and color 16 takes the placing color down two levels")
    func submodels() {
        let file = LDrawFile()
        model("main.ldr", in: file, steps: [[part("wheel.ldr", Self.blue), part("wheel.ldr", Self.red)],
                                            [part("3001.dat")]])
        model("wheel.ldr", in: file, steps: [[part("hub.ldr", Self.main), part("3002.dat", Self.black)]])
        model("hub.ldr", in: file, steps: [[part("3003.dat", Self.main)]])

        #expect(usage(file) == ["3003.dat/1", "3002.dat/0", "3003.dat/4", "3002.dat/0", "3001.dat/4"])
    }

    @Test("A part in color 16 in the main model keeps color 16")
    func mainColorAtTop() {
        let file = LDrawFile()
        model("main.ldr", in: file, steps: [[part("3001.dat", Self.main)]])
        #expect(usage(file) == ["3001.dat/16"])
    }

    @Test("IGN ranges and subparts are left out; a hidden part counts")
    func ignored() {
        let file = LDrawFile()
        model("main.ldr", in: file, steps: [[
            bracket("PLI BEGIN IGN"), part("3001.dat"), bracket("PLI END"),
            bracket("PART BEGIN IGN"), part("3002.dat"), bracket("PART END"),
            part("3003.dat", hidden: true), part("s\\3001s01.dat"),
        ]])
        #expect(usage(file) == ["3003.dat/4"])
    }

    @Test("A SUB range counts its substitute once, in its own color or the first part's")
    func substitutes() throws {
        let file = LDrawFile()
        let left = part("2429.dat", Self.black)
        let right = part("2430.dat", Self.black)
        model("main.ldr", in: file, steps: [[
            bracket("PLI BEGIN SUB 2429c01.ldr"), left, right, bracket("PLI END"),
            bracket("PLI BEGIN SUB 3001.dat 1"), part("3001.dat"), bracket("PLI END"),
        ]])
        let copies = LDrawPartUsage(file: file).copies
        #expect(copies.map { "\($0.partName)/\($0.colorCode.rawValue)" } == ["2429c01.dat/0", "3001.dat/1"])
        #expect(copies[0].kind == .substitute)
        #expect(copies[0].parts == [left, right])
    }

    @Test("A model nothing places is checked but not counted")
    func unplacedModel() {
        let file = LDrawFile()
        model("main.ldr", in: file, steps: [[part("3001.dat")]])
        model("spare.ldr", in: file, steps: [[part("3002.dat")]])
        #expect(usage(file) == ["3001.dat/4", "3002.dat/4 not counted"])
    }

    @Test("A model that places itself does not loop; the line reads as a part with no match")
    func selfPlacement() {
        let file = LDrawFile()
        model("main.ldr", in: file, steps: [[part("main.ldr"), part("3001.dat")]])
        #expect(usage(file) == ["main.ldr/4", "3001.dat/4"])
    }

    // MARK: - Statuses

    @Test("Copies past the count are too many, in build order")
    func tooMany() throws {
        let file = LDrawFile()
        let bricks = (0..<12).map { _ in part("3001.dat") }
        model("main.ldr", in: file, steps: [Array(bricks[0..<6]), Array(bricks[6..<12])])

        let report = LDrawPartLimitCheck.report(for: file, table: inventory([item("3001", 4, 10)]))
        #expect(bricks.prefix(10).allSatisfy { report.status(for: $0) == .allowed })
        #expect(bricks.suffix(2).allSatisfy { report.status(for: $0) == .tooMany })

        let row = try #require(report.rows.first)
        #expect(row.usedCount == 12)
        #expect(row.ownedCount == 10)
        #expect(row.status == .tooMany)
    }

    @Test("Spares count toward what is owned unless the limit leaves them out")
    func spares() {
        let file = LDrawFile()
        let bricks = (0..<3).map { _ in part("3001.dat") }
        model("main.ldr", in: file, steps: [bricks])

        let withSpares = LDrawPartLimitCheck.report(for: file, table: inventory([item("3001", 4, 2, spares: 1)]))
        #expect(withSpares.status(for: bricks[2]) == .allowed)
        let without = LDrawPartLimitCheck.report(for: file, table: inventory([item("3001", 4, 2, spares: 1)]) {
            $0.includesSpares = false
        })
        #expect(without.status(for: bricks[2]) == .tooMany)
    }

    @Test("A part in a submodel placed twice takes the worst status of its copies")
    func submodelCopies() {
        let file = LDrawFile()
        let inner = part("3001.dat", Self.main)
        model("main.ldr", in: file, steps: [[part("sub.ldr", Self.red), part("sub.ldr", Self.blue)]])
        model("sub.ldr", in: file, steps: [[inner]])

        let report = LDrawPartLimitCheck.report(for: file, table: inventory([item("3001", 4, 5)]))
        #expect(report.status(for: inner) == .notInColor)
        #expect(report.usedCount(forPartNamed: "3001.dat", colorCode: LDrawColorT(rawValue: Self.red)!) == 1)
    }

    @Test("Each kind of problem, and no data, gets its status")
    func kinds() {
        let file = LDrawFile()
        let allowed = part("3001.dat")
        let wrongColor = part("3001.dat", Self.blue)
        let unavailable = part("3002.dat")
        let noColor = part("3001.dat", Self.main)
        model("main.ldr", in: file, steps: [[allowed, wrongColor, unavailable, noColor]])

        let report = LDrawPartLimitCheck.report(for: file, table: inventory([item("3001", 4, 9)]))
        #expect(report.status(for: allowed) == .allowed)
        #expect(report.status(for: wrongColor) == .notInColor)
        #expect(report.status(for: unavailable) == .notAvailable)
        #expect(report.status(for: noColor) == .noData)
        #expect(report.parts(with: .notInColor) == [wrongColor])
    }

    @Test("Colors that are one Rebrickable color share one count")
    func sharedColorCount() {
        let file = LDrawFile()
        let tires = [part("3001.dat", Self.black), part("3001.dat", 256)]
        model("main.ldr", in: file, steps: [tires])

        let report = LDrawPartLimitCheck.report(for: file, table: inventory([item("3001", 0, 1)]))
        #expect(report.status(for: tires[0]) == .allowed)
        #expect(report.status(for: tires[1]) == .tooMany)
        #expect(report.rows.count == 1)
    }

    @Test("No limit allows everything and still counts what is used")
    func noLimit() {
        let file = LDrawFile()
        let bricks = (0..<3).map { _ in part("3001.dat") }
        model("main.ldr", in: file, steps: [bricks])

        let report = LDrawPartLimitCheck.report(for: file, table: LDrawPartLimitTable.unrestricted())
        #expect(bricks.allSatisfy { report.status(for: $0) == .allowed })
        #expect(report.rows.first?.usedCount == 3)
        #expect(report.rows.first.map { $0.ownedCount == NSNotFound } == true)
    }

    // MARK: - Marks

    // Copying a part looks up the shared part library, which package tests do
    // not have, so the copy's status is not tested here.
    @Test("Applying a report sets each part's status and returns only the parts that changed")
    func applying() throws {
        let file = LDrawFile()
        let good = part("3001.dat")
        let bad = part("3002.dat")
        let main = model("main.ldr", in: file, steps: [[good, bad]])
        let table = inventory([item("3001", 4, 1)])

        let changed = LDrawPartLimitCheck.apply(LDrawPartLimitCheck.report(for: file, table: table), to: file)
        #expect(changed == [bad])
        #expect(bad.limitStatus == .notAvailable)
        #expect(good.limitStatus == .allowed)
        #expect(LDrawPartLimitCheck.apply(LDrawPartLimitCheck.report(for: file, table: table), to: file).isEmpty)

        let cleared = LDrawPartLimitCheck.apply(LDrawPartLimitCheck.report(for: file, table: .unrestricted()), to: file)
        #expect(cleared == [bad])
        #expect(bad.limitStatus == .allowed)
        _ = main
    }

    @Test("A container counts the problems inside it and knows the worst")
    func containers() throws {
        let file = LDrawFile()
        let firstStep = [part("3001.dat"), part("3002.dat"), part("3001.dat", Self.main)]
        let main = model("main.ldr", in: file, steps: [firstStep, [part("3001.dat")]])
        let report = LDrawPartLimitCheck.report(for: file, table: inventory([item("3001", 4, 9)]))
        let steps = try #require(main.steps() as? [LDrawStep])

        let first = try #require(steps.first { report.problemCount(in: $0) > 0 })
        #expect(report.problemCount(in: first) == 1)
        #expect(report.worstStatus(in: first) == .notAvailable)
        #expect(report.problemCount(in: main) == 1)
        #expect(report.problemCount(in: try #require(steps.last)) == 0)
    }

    // MARK: - Speed

    @Test("A 5,000-part model is checked quickly")
    func speed() {
        let file = LDrawFile()
        let parts = (0..<5000).map { index in part("300\(index % 5).dat", index % 2 == 0 ? Self.red : Self.blue) }
        model("main.ldr", in: file, steps: stride(from: 0, to: parts.count, by: 50).map { Array(parts[$0..<$0 + 50]) })
        let table = inventory([item("3001", 4, 400), item("3002", 1, 400)])

        let started = Date()
        let report = LDrawPartLimitCheck.report(for: file, table: table)
        _ = LDrawPartLimitCheck.apply(report, to: file)
        let seconds = Date().timeIntervalSince(started)

        print("LIMIT CHECK: 5000 parts in \(Int(seconds * 1000)) ms")
        #expect(seconds < 0.5)
        #expect(report.rows.count == 10)
    }
}
