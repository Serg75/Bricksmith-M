//
//  LDrawPartReplacementsTests.swift
//  LDrawFeaturesTests
//
//  Tests for the parts that can take the place of a part, and how each would
//  stand against the limit.
//
//  Created by Sergey Slobodenyuk on 2026-11-03.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawInventory

@Suite("Part replacements")
struct LDrawPartReplacementsTests {

    // MARK: - Fixtures

    private static let black: Int32 = 0
    private static let red: Int32 = 4
    private static let gray: Int32 = 71
    private static let main: Int32 = 16

    /// 2555 has the molds 12825 and 15712, and 15712 the alternate 93794, which the library lacks. 3069b
    /// has two prints, and one of them a print of its own.
    private let identity: LDrawPartIdentity = {
        let relations = [["M", "12825", "2555"], ["M", "15712", "2555"], ["A", "93794", "15712"],
                         ["P", "3069bpr0002", "3069b"], ["P", "3069bpr0010", "3069b"],
                         ["P", "3069bpr0010a", "3069bpr0010"]]
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: [0: 0, 4: 4, 71: 71],
                                                     relations: relations, knownPartNumbers: nil,
                                                     rubberPartNumbers: nil)
        return LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)
    }()

    private let library: (String) -> Bool = { $0 != "93794.dat" }

    private func color(_ code: Int32) -> LDrawColor {
        let color = LDrawColor()
        color.setColorCode(LDrawColorT(rawValue: code)!)
        return color
    }

    private func part(_ name: String, _ code: Int32 = LDrawPartReplacementsTests.black) -> LDrawPart {
        let part = LDrawPart()
        part.setDisplayName(name, parse: false, in: nil)
        part.setLDrawColor(color(code))
        return part
    }

    /// A file of one model, or of a main model and the submodel it places. The caller keeps the file,
    /// because names resolve through it.
    private func file(_ parts: [LDrawDirective], submodel: [LDrawDirective] = []) -> LDrawFile {
        let file = LDrawFile()
        for (name, directives) in [("main.ldr", parts), ("sub.ldr", submodel)] where !directives.isEmpty {
            let model = LDrawMPDModel.model() as! LDrawMPDModel
            model.setModelName(name)
            let step = model.addStep()
            for directive in directives {
                step.add(directive)
            }
            file.addSubmodel(model)
        }
        return file
    }

    /// The set holds 12825 in red and gray, and one black print of 3069b. Molds count apart.
    private func table(_ change: (LDrawMutablePartLimit) -> Void = { _ in }) -> LDrawPartLimitTable {
        let items = [("12825", 4, 2), ("12825", 71, 4), ("3069bpr0002", 0, 1)].map { part, colorID, quantity in
            LDrawInventoryItem(rebrickablePartNumber: part, rebrickableColorID: colorID, ldrawPartName: nil,
                               ldrawColorCode: LDrawColorT(rawValue: -1)!, quantity: UInt(quantity),
                               spareQuantity: 0)
        }
        let limit = LDrawPartLimit.inventory("set").mutableCopy() as! LDrawMutablePartLimit
        limit.matchesMoldVariants = false
        limit.warnsOnly = true
        change(limit)
        return LDrawPartLimitTable(limit: limit.copy() as! LDrawPartLimit, availability: nil, items: items,
                                   identity: identity, year: 2026)
    }

    private func replacements(_ parts: [LDrawPart], in file: LDrawFile,
                              table: LDrawPartLimitTable?) -> [String] {
        let report = table.map { LDrawPartLimitCheck.report(for: file, table: $0) }
        let found = LDrawPartReplacements.replacements(for: parts, report: report, usage: LDrawPartUsage(file: file),
                                                       identity: identity, libraryHasPart: library)
        return found.map { replacement in
            var text = (replacement.setsColor ? "" : "~") + replacement.partName + "/\(replacement.colorCode.rawValue)"
            switch replacement.status {
            case .allowed: break
            case .noData: text += " no data"
            case .tooMany: text += " too many"
            case .notInColor: text += " not in color"
            case .notAvailable: text += " not available"
            @unknown default: text += " ?"
            }
            if replacement.usedCount != NSNotFound {
                text += " \(replacement.usedCount) of \(replacement.ownedCount)"
            }
            return text
        }
    }

    // MARK: - Tests

    @Test("Without a limit, molds the library has come first, then the plain part, and no prints")
    func noLimit() {
        let tile = part("2555.dat")
        let print = part("3069bpr0010a.dat")
        let file = file([tile, print])

        #expect(replacements([tile], in: file, table: nil) == ["~12825.dat/0", "~15712.dat/0"])
        #expect(replacements([print], in: file, table: nil) == ["~3069b.dat/0"])
    }

    @Test("A mold not made in the parts' color is offered in each color the set has it in, those first")
    func otherColors() {
        let tile = part("2555.dat")
        let file = file([tile])

        #expect(replacements([tile], in: file, table: table())
                == ["12825.dat/4 1 of 2", "12825.dat/71 1 of 4", "~12825.dat/0 not in color",
                    "~15712.dat/0 not available"])
    }

    @Test("A color the part is not made in is not kept when the limit does more than warn")
    func strict() {
        let tile = part("2555.dat")
        let file = file([tile])

        #expect(replacements([tile], in: file, table: table { $0.warnsOnly = false })
                == ["12825.dat/4 1 of 2", "12825.dat/71 1 of 4", "~15712.dat/0 not available"])
    }

    @Test("A replacement past what the set holds is too many, and comes after those that fit")
    func tooMany() {
        let tile = part("2555.dat")
        let file = file([tile, part("12825.dat", Self.red), part("12825.dat", Self.red)])

        #expect(replacements([tile], in: file, table: table())
                == ["12825.dat/71 1 of 4", "12825.dat/4 too many 3 of 2", "~12825.dat/0 not in color",
                    "~15712.dat/0 not available"])
    }

    @Test("With any mold, the parts already count with the mold that replaces them")
    func anyMold() {
        let tile = part("2555.dat", Self.red)
        let file = file([tile, part("12825.dat", Self.red)])

        #expect(replacements([tile], in: file, table: table { $0.matchesMoldVariants = true })
                == ["~12825.dat/4 2 of 2", "~15712.dat/4 2 of 2"])
    }

    @Test("A part in a submodel placed twice stands for two, and in color 16 keeps its color")
    func submodel() {
        let tile = part("2555.dat", Self.main)
        let file = file([part("sub.ldr", Self.gray), part("sub.ldr", Self.gray)], submodel: [tile])

        #expect(replacements([tile], in: file, table: table())
                == ["~12825.dat/71 2 of 4", "~15712.dat/71 not available"])
    }

    @Test("A part in color 16 in a submodel placed in two colors is checked like parts that differ in color")
    func submodelInTwoColors() {
        let tile = part("2555.dat", Self.main)
        let file = file([part("sub.ldr", Self.gray), part("sub.ldr", Self.red)], submodel: [tile])

        #expect(replacements([tile], in: file, table: table()) == ["~12825.dat/-1", "~15712.dat/-1 not available"])
    }

    @Test("A related part is offered by another linked name when the library lacks the first")
    func otherLibraryName() {
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: ["12825.dat": "12825", "12825old.dat": "12825"],
                                                     colorLinks: nil, relations: [["M", "12825", "2555"]],
                                                     knownPartNumbers: nil, rubberPartNumbers: nil)
        let identity = LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)
        let tile = part("2555.dat")
        let found = LDrawPartReplacements.replacements(for: [tile], report: nil, usage: nil, identity: identity,
                                                       libraryHasPart: { $0 != "12825.dat" })

        #expect(found.map(\.partName) == ["12825old.dat"])
    }

    @Test("A print's plain part, and a plain part's prints the limit allows")
    func prints() {
        let plain = part("3069b.dat")
        let print = part("3069bpr0010.dat")
        let file = file([plain, print])

        #expect(replacements([plain], in: file, table: table()) == ["~3069bpr0002.dat/0 1 of 1"])
        #expect(replacements([print], in: file, table: table()) == ["~3069b.dat/0 not available"])
    }

    @Test("A replacement's line says how many the model would use, or why the limit does not allow it")
    func lines() {
        let tile = part("2555.dat")
        let file = file([tile])
        let table = table()
        let report = LDrawPartLimitCheck.report(for: file, table: table)
        let found = LDrawPartReplacements.replacements(for: [tile], report: report, usage: LDrawPartUsage(file: file),
                                                       identity: identity, libraryHasPart: library)

        // The tests have no color names, so the line for not in color is left out.
        let lines = found.filter { $0.status != .notInColor }.map {
            LDrawPartLimitPresentation.line(for: $0, table: table, store: nil)
        }
        #expect(lines == ["Uses 1 of 2 in Missing Inventory", "Uses 1 of 4 in Missing Inventory",
                          "Not in Missing Inventory"])
    }

    @Test("Parts that differ in color keep their colors; parts that differ in name have none")
    func mixed() {
        let black = part("2555.dat")
        let red = part("2555.DAT", Self.red)
        let brick = part("3001.dat")
        let file = file([black, red, brick])

        #expect(replacements([black, red], in: file, table: table())
                == ["~12825.dat/-1", "~15712.dat/-1 not available"])
        #expect(replacements([black, brick], in: file, table: table()).isEmpty)
        #expect(replacements([brick], in: file, table: table()).isEmpty)
    }
}
