//
//  LDrawUnmatchedPartsTests.swift
//  LDrawFeaturesTests
//
//  Tests for the parts that match nothing, and for hand matches.
//
//  Created by Sergey Slobodenyuk on 2026-10-28.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawInventory

@Suite("Unmatched parts")
struct LDrawUnmatchedPartsTests {

    // MARK: - Fixtures

    /// Rebrickable knows the plain parts, the hinge halves and one print, which is a print of 3069b.
    private func identity() -> LDrawPartIdentity {
        let records: [[String: Any]] = [
            [PART_NUMBER_KEY: "76382p0l.dat", PART_NAME_KEY: "Minifig Torso with Arms and Hands",
             PART_KEYWORDS_KEY: ["Rebrickable 973c04h01pr3045"]],
        ]
        let known: Set<String> = ["3001", "2429", "2430", "3069b", "3069bpr0020", "3069bpr0101", "973c04h01pr3045"]
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: [4: 4],
                                                     relations: [["P", "3069bpr0020", "3069b"]],
                                                     knownPartNumbers: known)
        return LDrawPartIdentity(catalogRecords: records, rebrickableData: data, overrides: nil)
    }

    private func part(_ name: String) -> LDrawPart {
        let part = LDrawPart()
        let color = LDrawColor()
        color.setColorCode(LDrawColorT(rawValue: 4)!)
        part.setDisplayName(name, parse: false, in: nil)
        part.setLDrawColor(color)
        return part
    }

    private func file(_ names: [String]) -> LDrawFile {
        let file = LDrawFile()
        let model = LDrawMPDModel.model() as! LDrawMPDModel
        let step = model.addStep()
        model.setModelName("main.ldr")
        for name in names {
            step.add(part(name) as LDrawDirective)
        }
        file.addSubmodel(model)
        return file
    }

    private func item(_ part: String, _ quantity: UInt, spares: UInt = 0) -> LDrawInventoryItem {
        LDrawInventoryItem(rebrickablePartNumber: part, rebrickableColorID: 4, ldrawPartName: nil,
                           ldrawColorCode: LDrawColorT(rawValue: -1)!, quantity: quantity, spareQuantity: spares)
    }

    // MARK: - Tests

    @Test("A model's parts with no Rebrickable part are listed, the most used first")
    func modelParts() {
        let hinge = """
            0 Hinge Plate  1 x  4 (Complete)
            0 !LDRAW_ORG Shortcut
            1 16 0 0 0 1 0 0 0 1 0 0 0 1 2429.dat
            1 16 0 0 0 1 0 0 0 1 0 0 0 1 2430.dat
            """
        let stickered = """
            0 Brick  2 x  4 with Sticker
            0 !LDRAW_ORG Shortcut
            1 16 0 0 0 1 0 0 0 1 0 0 0 1 3001.dat
            1 15 0 0 -10 1 0 0 0 1 0 0 0 1 3001d01s.dat
            """
        let shortcuts = LDrawShortcutMap(fileReader: { ["73983.dat": hinge, "3001d01.dat": stickered][$0] })
        let files = [file(["3001.dat", "custom.dat", "73983.dat", "3001d01.dat"]), file(["custom.dat"])]

        let parts = LDrawUnmatchedParts.parts(in: files, identity: identity(), shortcuts: shortcuts)
        #expect(parts.map { $0.partName } == ["custom.dat", "3001d01s.dat"])
        #expect(parts.map { $0.count } == [2, 1])
        #expect(parts.allSatisfy { $0.rebrickablePartNumber == nil })
    }

    @Test("A part only in a model nothing places is listed, but counts no copies")
    func unplacedModelParts() {
        let file = file(["custom.dat"])
        let spare = LDrawMPDModel.model() as! LDrawMPDModel
        spare.setModelName("spare.ldr")
        let step = spare.addStep()
        step.add(part("custom.dat") as LDrawDirective)
        step.add(part("other.dat") as LDrawDirective)
        file.addSubmodel(spare)

        let parts = LDrawUnmatchedParts.parts(in: [file], identity: identity(), shortcuts: nil)
        #expect(parts.map { $0.partName } == ["custom.dat", "other.dat"])
        #expect(parts.map { $0.count } == [1, 0])
    }

    @Test("An inventory's parts with no LDraw part are listed, counts and spares added up")
    func inventoryParts() {
        let library: Set<String> = ["3001.dat", "3069b.dat", "76382p0l.dat"]
        let items = [item("3001", 5), item("3069bpr0101", 2, spares: 1), item("3069bpr0101", 1),
                     item("3069bpr0020", 4), item("973c04h01pr3045", 1)]

        let strict = LDrawUnmatchedParts.parts(in: items, limit: LDrawPartLimit.inventory("set"),
                                               identity: identity(), libraryHasPart: { library.contains($0) })
        #expect(strict.map { $0.rebrickablePartNumber } == ["3069bpr0020", "3069bpr0101"])
        #expect(strict.map { $0.count } == [4, 4])

        // With any print, a print whose plain part the library has is matched.
        let anyPrint = LDrawPartLimit.inventory("set").mutableCopy() as! LDrawMutablePartLimit
        anyPrint.matchesAnyPrint = true
        let lenient = LDrawUnmatchedParts.parts(in: items, limit: anyPrint.copy() as! LDrawPartLimit,
                                                identity: identity(), libraryHasPart: { library.contains($0) })
        #expect(lenient.map { $0.rebrickablePartNumber } == ["3069bpr0101"])
    }

    @Test("A hand match is keyed as the identity map keys LDraw names, and an empty number removes it")
    func handMatches() {
        let added = LDrawUnmatchedParts.overrides(["3001": "3001"], matching: "S\\3069BP0K.DAT", to: " 3069bpr0020 ")
        #expect(added == ["3001": "3001", "s/3069bp0k": "3069bpr0020"])
        #expect(LDrawUnmatchedParts.overrides(added, matching: "s/3069bp0k.dat", to: "") == ["3001": "3001"])
        #expect(LDrawUnmatchedParts.overrides(nil, matching: "3001.dat", to: nil) == [:])

        // The identity map follows the match.
        let identity = LDrawPartIdentity(catalogRecords: nil, rebrickableData: nil, overrides: added)
        #expect(identity.rebrickablePartNumber(forPartName: "s\\3069bp0k.dat") == "3069bpr0020")
    }
}
