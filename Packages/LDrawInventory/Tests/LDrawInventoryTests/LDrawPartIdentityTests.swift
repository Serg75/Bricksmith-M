//
//  LDrawPartIdentityTests.swift
//  LDrawInventoryTests
//
//  Tests for matching LDraw parts and colors to Rebrickable's.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawCore
import LDrawInventory

@Suite("Part identity")
struct LDrawPartIdentityTests {

    /// A catalog record as the part library keeps it.
    private func record(_ name: String, _ description: String = "Part", keywords: [String] = []) -> [String: Any] {
        [PART_NUMBER_KEY: name, PART_NAME_KEY: description, PART_KEYWORDS_KEY: keywords]
    }

    private func color(_ code: Int32) -> LDrawColorT {
        LDrawColorT(rawValue: code)!
    }

    // MARK: - Names

    @Test("An LDraw name loses case, its .dat and backslashes", arguments: [
        ("3001.dat", "3001"),
        ("3001.DAT", "3001"),
        ("  3626bp01.dat ", "3626bp01"),
        ("s\\3001s01.dat", "s/3001s01"),
        ("custom.ldr", "custom.ldr"),
    ])
    func normalizedName(name: String, expected: String) {
        #expect(LDrawPartIdentity.normalizedPartName(name) == expected)
    }

    // MARK: - Parts

    @Test("With nothing known, a part keeps its own number")
    func sameNumber() {
        let identity = LDrawPartIdentity.empty()
        #expect(identity.rebrickablePartNumber(forPartName: "3001.dat") == "3001")
        #expect(identity.partName(forRebrickablePartNumber: "3001") == "3001.dat")
    }

    @Test("The library's Rebrickable keyword links a print, in any case")
    func keywordLink() {
        let records = [
            record("2431px7.dat", keywords: ["BrickLink 2431px7", "Rebrickable 2431pr0014", "Set 6521"]),
            record("3001.dat", keywords: ["brick"]),
            record("973p01.dat", keywords: ["REBRICKABLE 973pr0001 "]),
        ]
        let links = LDrawPartIdentity.keywordLinks(fromCatalogRecords: records)
        #expect(links == ["2431px7": "2431pr0014", "973p01": "973pr0001"])

        let identity = LDrawPartIdentity(catalogRecords: records, rebrickableData: nil, overrides: nil)
        #expect(identity.rebrickablePartNumber(forPartName: "2431PX7.DAT") == "2431pr0014")
        #expect(identity.partName(forRebrickablePartNumber: "2431pr0014") == "2431px7.dat")
    }

    @Test("Hand matches beat keywords, which beat Rebrickable's links")
    func precedence() {
        let records = [record("2431px7.dat", keywords: ["Rebrickable 2431pr0014"]),
                       record("3002.dat", keywords: ["Rebrickable 3002b"])]
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: ["2431px7.dat": "2431pr9999",
                                                                     "3003.dat": "3003a"],
                                                     colorLinks: nil, relations: nil, knownPartNumbers: nil,
                                                     rubberPartNumbers: nil)
        let identity = LDrawPartIdentity(catalogRecords: records, rebrickableData: data,
                                         overrides: ["3002.DAT": "3002x"])

        #expect(identity.rebrickablePartNumber(forPartName: "2431px7.dat") == "2431pr0014")
        #expect(identity.rebrickablePartNumber(forPartName: "3002.dat") == "3002x")
        #expect(identity.rebrickablePartNumber(forPartName: "3003.dat") == "3003a")
    }

    @Test("A moved part is followed to its target, and a loop does not hang")
    func movedParts() {
        let records = [
            record("3001old.dat", "~Moved to 3001"),
            record("a.dat", "~Moved to b"),
            record("b.dat", "~Moved to a"),
        ]
        let identity = LDrawPartIdentity(catalogRecords: records, rebrickableData: nil, overrides: nil)
        #expect(identity.rebrickablePartNumber(forPartName: "3001old.dat") == "3001")
        #expect(identity.rebrickablePartNumber(forPartName: "a.dat") != nil)
    }

    @Test("A hand match on a moved part's old name wins over the move")
    func handMatchOnMovedPart() {
        let records = [record("x.dat", "~Moved to y"), record("y.dat")]
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: nil, relations: nil,
                                                     knownPartNumbers: ["1234"], rubberPartNumbers: nil)
        let identity = LDrawPartIdentity(catalogRecords: records, rebrickableData: data,
                                         overrides: ["x.dat": "1234"])
        #expect(identity.rebrickablePartNumber(forPartName: "x.dat") == "1234")
        #expect(identity.rebrickablePartNumber(forPartName: "y.dat") == nil)
    }

    @Test("A renamed part keeps its old number while Rebrickable has only that")
    func renamedParts() {
        let records = [
            record("32532.dat", "~Moved to 32532a"),
            record("3062a.dat", "~Moved to 3062b"),
            record("2654.dat", "~Moved to 2654a"),
            record("2654a.dat", keywords: ["Rebrickable 2654b"]),
        ]
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: nil, relations: nil,
                                                     knownPartNumbers: ["32532", "3062a", "3062b", "2654", "2654b"],
                                                     rubberPartNumbers: nil)
        let identity = LDrawPartIdentity(catalogRecords: records, rebrickableData: data, overrides: nil)
        #expect(identity.rebrickablePartNumber(forPartName: "32532a.dat") == "32532")
        #expect(identity.partNames(forRebrickablePartNumber: "32532").first == "32532a.dat")
        #expect(identity.rebrickablePartNumber(forPartName: "3062b.dat") == "3062b")
        #expect(identity.rebrickablePartNumber(forPartName: "2654a.dat") == "2654b")
    }

    @Test("A part renamed twice keeps the oldest number, whatever the names' order")
    func renamedTwice() {
        let records = [record("a2.dat", "~Moved to a1"), record("a1.dat", "~Moved to a0"), record("a0.dat")]
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: nil, relations: nil,
                                                     knownPartNumbers: ["a2"], rubberPartNumbers: nil)
        let identity = LDrawPartIdentity(catalogRecords: records, rebrickableData: data, overrides: nil)
        #expect(identity.rebrickablePartNumber(forPartName: "a0.dat") == "a2")
        #expect(identity.rebrickablePartNumber(forPartName: "a2.dat") == "a2")
    }

    @Test("A part Rebrickable does not have has no number")
    func knownParts() {
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: ["3001p11.dat": "3001pr0001"],
                                                     colorLinks: nil, relations: nil,
                                                     knownPartNumbers: ["3001", "3001pr0001"], rubberPartNumbers: nil)
        let identity = LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)
        #expect(identity.rebrickablePartNumber(forPartName: "3001.dat") == "3001")
        #expect(identity.rebrickablePartNumber(forPartName: "3001p11.dat") == "3001pr0001")
        #expect(identity.rebrickablePartNumber(forPartName: "u9999.dat") == nil)
    }

    @Test("When several LDraw parts link to one number, the same number wins")
    func reverseLink() {
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: ["3062a.dat": "3062b", "3062b.dat": "3062b"],
                                                     colorLinks: nil, relations: nil, knownPartNumbers: nil,
                                                     rubberPartNumbers: nil)
        let identity = LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)
        #expect(identity.partName(forRebrickablePartNumber: "3062b") == "3062b.dat")
    }

    // MARK: - Colors

    @Test("Colors match only through links, never by the same number")
    func colors() {
        // Rebrickable 326 is Olive Green, which LDraw calls 330; LDraw 326 is Yellowish Green, Rebrickable 158.
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil,
                                                     colorLinks: [4: 4, 326: 330, 158: 326, 47: 47, 1047: 47],
                                                     relations: nil, knownPartNumbers: nil, rubberPartNumbers: nil)
        let identity = LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)

        #expect(identity.colorCode(forRebrickableColorID: 326).rawValue == 330)
        #expect(identity.rebrickableColorIDs(forColorCode: color(326)) == [158])
        #expect(identity.rebrickableColorIDs(forColorCode: color(47)) == [47, 1047])
        #expect(identity.rebrickableColorIDs(forColorCode: color(16)) == [])
        #expect(identity.colorCode(forRebrickableColorID: 9).rawValue == -1)
    }

    @Test("A rubber color suits a rubber part, or any part while materials are not known")
    func rubberColors() {
        let links: [NSNumber: Any] = [0: [0, 256], 179: [179, 315, 504]]
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: links, relations: nil,
                                                     knownPartNumbers: nil, rubberPartNumbers: ["3483"])
        let identity = LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil,
                                         rubberColorCodes: [256, 504])

        #expect(identity.colorCodes(forRebrickableColorID: 0, ofPartNumber: "3483") == [0, 256])
        #expect(identity.colorCodes(forRebrickableColorID: 0, ofPartNumber: "32062") == [0])
        #expect(identity.colorCodes(forRebrickableColorID: 179, ofPartNumber: "56145") == [179, 315])
        #expect(identity.colorCodes(forRebrickableColorID: 0, ofPartNumber: nil) == [0])
        #expect(identity.rebrickableColorIDs(forColorCode: color(256)) == [0])
        #expect(identity.colorCode(color(256), suitsPartNamed: "3483.dat"))
        #expect(identity.colorCode(color(256), suitsPartNamed: "32062.dat") == false)
        #expect(identity.colorCode(color(0), suitsPartNamed: "32062.dat"))

        let updated = LDrawPartIdentity.rebrickableData(byUpdating: data, partLinks: nil, colorLinks: nil,
                                                        relations: nil, knownPartNumbers: nil,
                                                        rubberPartNumbers: nil)
        #expect(LDrawPartIdentity.rubberPartNumbers(inRebrickableData: updated) == ["3483"])

        let unknown = LDrawPartIdentity(catalogRecords: nil,
                                        rebrickableData: LDrawPartIdentity.rebrickableData(
                                            withPartLinks: nil, colorLinks: links, relations: nil,
                                            knownPartNumbers: nil, rubberPartNumbers: nil),
                                        overrides: nil, rubberColorCodes: [256, 504])
        #expect(unknown.colorCodes(forRebrickableColorID: 0, ofPartNumber: "32062") == [0, 256])
        #expect(unknown.colorCode(color(256), suitsPartNamed: "32062.dat"))
    }

    // MARK: - Pools

    @Test("Molds and alternates share a pool; prints join theirs only on request")
    func pools() {
        let relations = [["M", "3062a", "3062b"], ["A", "3062c", "3062a"],
                         ["P", "3062bpr0001", "3062b"], ["T", "3062bpat01", "3062b"],
                         ["B", "2429c01", "2429"]]
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: nil,
                                                     relations: relations, knownPartNumbers: nil,
                                                     rubberPartNumbers: nil)
        let identity = LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)

        func pool(_ part: String, molds: Bool, prints: Bool) -> String {
            identity.poolKey(forRebrickablePartNumber: part, matchesMoldVariants: molds, matchesAnyPrint: prints)
        }

        #expect(pool("3062a", molds: true, prints: false) == "3062a")
        #expect(pool("3062b", molds: true, prints: false) == "3062a")
        #expect(pool("3062c", molds: true, prints: false) == "3062a")
        #expect(pool("3062b", molds: false, prints: false) == "3062b")
        #expect(pool("3062bpr0001", molds: true, prints: false) == "3062bpr0001")
        #expect(pool("3062bpr0001", molds: true, prints: true) == "3062a")
        #expect(pool("3062bpat01", molds: false, prints: true) == "3062b")
        #expect(pool("2429c01", molds: true, prints: true) == "2429c01")
    }

    @Test("A part's molds, and its plain part and prints past a print of a print, in counting order")
    func relatedParts() {
        let relations = [["M", "12825", "2555"], ["M", "15712", "2555"], ["A", "93794", "15712"],
                         ["P", "3069bpr0002", "3069b"], ["P", "3069bpr0010", "3069b"],
                         ["P", "3069bpr0010a", "3069bpr0010"], ["B", "2429c01", "2429"],
                         ["P", "loop1", "loop2"], ["P", "loop2", "loop1"]]
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: nil,
                                                     relations: relations, knownPartNumbers: nil,
                                                     rubberPartNumbers: nil)
        let identity = LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)

        #expect(identity.moldVariants(ofPartNumber: "2555") == ["12825", "15712", "93794"])
        #expect(identity.moldVariants(ofPartNumber: "93794") == ["2555", "12825", "15712"])
        #expect(identity.moldVariants(ofPartNumber: "3001").isEmpty)

        #expect(identity.plainPartNumber(ofPartNumber: "3069bpr0010a") == "3069b")
        #expect(identity.plainPartNumber(ofPartNumber: "3069bpr0002") == "3069b")
        #expect(identity.plainPartNumber(ofPartNumber: "3069b") == nil)
        #expect(identity.plainPartNumber(ofPartNumber: "2429c01") == nil)

        #expect(identity.printPartNumbers(ofPartNumber: "3069b") == ["3069bpr0002", "3069bpr0010", "3069bpr0010a"])
        #expect(identity.printPartNumbers(ofPartNumber: "3069bpr0010") == ["3069bpr0010a"])
        #expect(identity.printPartNumbers(ofPartNumber: "3001").isEmpty)
        #expect(identity.printPartNumbers(ofPartNumber: "loop1") == ["loop2"])
    }
}
