//
//  LDrawColorPanelLimitTests.swift
//  LDrawFeaturesTests
//
//  Tests for the Colors window under a parts limit: the colors the selected
//  parts may take, the filter, and which colors can be picked.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawInventory

@Suite("Colors window under a parts limit")
struct LDrawColorPanelLimitTests {

    private func code(_ value: Int32) -> LDrawColorT { LDrawColorT(rawValue: value)! }

    private func color(_ value: Int32) -> LDrawColor {
        let color = LDrawColor()
        color.setColorCode(code(value))
        var rgba: [Float] = [0.5, 0.5, 0.5, 1]
        color.setColorRGBA(&rgba)
        return color
    }

    /// 3001 came in black and red this year, 3002 only in red.
    private func table(_ change: (LDrawMutablePartLimit) -> Void = { _ in }) -> LDrawPartLimitTable {
        let builder = LDrawPartAvailabilityBuilder()
        builder.notePartNumber("3001", colorID: 0, year: 2026, inDatabaseSet: false)
        builder.notePartNumber("3001", colorID: 4, year: 2026, inDatabaseSet: false)
        builder.notePartNumber("3002", colorID: 4, year: 2026, inDatabaseSet: false)
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: [0: 0, 1: 1, 4: 4],
                                                     relations: nil, knownPartNumbers: nil)
        let limit = LDrawPartLimit.availableNow().mutableCopy() as! LDrawMutablePartLimit
        change(limit)
        return LDrawPartLimitTable(limit: limit.copy() as! LDrawPartLimit, availability: builder.availability(with: nil),
                                   items: nil, identity: LDrawPartIdentity(catalogRecords: nil, rebrickableData: data,
                                                                           overrides: nil),
                                   year: 2026)
    }

    @Test("Several parts may take only the colors they share; an unknown part does not narrow them")
    func allowedColors() {
        let table = table()
        #expect(LDrawColorPanelModel.allowedColorCodes(forPartNames: ["3001.dat"], table: table) == [0, 4])
        #expect(LDrawColorPanelModel.allowedColorCodes(forPartNames: ["3001.dat", "3002.dat"], table: table) == [4])
        #expect(LDrawColorPanelModel.allowedColorCodes(forPartNames: ["3001.dat", "unknown.dat"], table: table)
                == [0, 4])
        #expect(LDrawColorPanelModel.allowedColorCodes(forPartNames: ["unknown.dat"], table: table) == nil)
        #expect(LDrawColorPanelModel.allowedColorCodes(forPartNames: [], table: table) == nil)
        #expect(LDrawColorPanelModel.allowedColorCodes(forPartNames: ["3001.dat"], table: nil) == nil)

        let anyColor = self.table { $0.matchesAnyColor = true }
        #expect(LDrawColorPanelModel.allowedColorCodes(forPartNames: ["3001.dat"], table: anyColor) == nil)
    }

    @Test("The filter keeps the allowed colors, alone, with a material, or with a typed code")
    func predicate() throws {
        let colors = [color(0), color(1), color(4)] as NSArray

        let allowed = try #require(LDrawColorPanelModel.predicate(forSearch: nil, material: .selectedPart,
                                                                   allowedColorCodes: [0, 4]))
        #expect((colors.filtered(using: allowed) as! [LDrawColor]).map { $0.colorCode().rawValue } == [0, 4])

        let solid = try #require(LDrawColorPanelModel.predicate(forSearch: nil, material: .solid,
                                                                 allowedColorCodes: [4]))
        #expect((colors.filtered(using: solid) as! [LDrawColor]).map { $0.colorCode().rawValue } == [4])

        let typed = try #require(LDrawColorPanelModel.predicate(forSearch: "1", material: .all,
                                                                 allowedColorCodes: [0, 4]))
        #expect(colors.filtered(using: typed).isEmpty)

        #expect(LDrawColorPanelModel.predicate(forSearch: nil, material: .limit, allowedColorCodes: nil) == nil)
    }

    @Test("A color the parts are not allowed in cannot be picked, unless the limit only warns")
    func canSelect() {
        #expect(LDrawColorPanelModel.canSelectColorCode(code(4), allowedColorCodes: [0, 4], warnsOnly: false))
        #expect(LDrawColorPanelModel.canSelectColorCode(code(1), allowedColorCodes: [0, 4], warnsOnly: false) == false)
        #expect(LDrawColorPanelModel.canSelectColorCode(code(1), allowedColorCodes: [0, 4], warnsOnly: true))
        #expect(LDrawColorPanelModel.canSelectColorCode(code(1), allowedColorCodes: nil, warnsOnly: false))
        #expect(LDrawColorPanelModel.canSelectColorCode(code(16), allowedColorCodes: [0, 4], warnsOnly: false))
    }
}
