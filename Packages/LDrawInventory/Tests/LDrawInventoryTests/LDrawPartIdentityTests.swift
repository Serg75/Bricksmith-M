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
                                                     colorLinks: nil, relations: nil, knownPartNumbers: nil)
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

    @Test("A part Rebrickable does not have has no number")
    func knownParts() {
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: ["3001p11.dat": "3001pr0001"],
                                                     colorLinks: nil, relations: nil,
                                                     knownPartNumbers: ["3001", "3001pr0001"])
        let identity = LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)
        #expect(identity.rebrickablePartNumber(forPartName: "3001.dat") == "3001")
        #expect(identity.rebrickablePartNumber(forPartName: "3001p11.dat") == "3001pr0001")
        #expect(identity.rebrickablePartNumber(forPartName: "u9999.dat") == nil)
    }

    @Test("When several LDraw parts link to one number, the same number wins")
    func reverseLink() {
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: ["3062a.dat": "3062b", "3062b.dat": "3062b"],
                                                     colorLinks: nil, relations: nil, knownPartNumbers: nil)
        let identity = LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)
        #expect(identity.partName(forRebrickablePartNumber: "3062b") == "3062b.dat")
    }

    // MARK: - Colors

    @Test("Colors match only through links, never by the same number")
    func colors() {
        // Rebrickable 326 is Olive Green, which LDraw calls 330; LDraw 326 is Yellowish Green, Rebrickable 158.
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil,
                                                     colorLinks: [4: 4, 326: 330, 158: 326, 47: 47, 1047: 47],
                                                     relations: nil, knownPartNumbers: nil)
        let identity = LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)

        #expect(identity.colorCode(forRebrickableColorID: 326).rawValue == 330)
        #expect(identity.rebrickableColorIDs(forColorCode: color(326)) == [158])
        #expect(identity.rebrickableColorIDs(forColorCode: color(47)) == [47, 1047])
        #expect(identity.rebrickableColorIDs(forColorCode: color(16)) == [])
        #expect(identity.colorCode(forRebrickableColorID: 9).rawValue == -1)
    }

    // MARK: - Pools

    @Test("Molds and alternates share a pool; prints join theirs only on request")
    func pools() {
        let relations = [["M", "3062a", "3062b"], ["A", "3062c", "3062a"],
                         ["P", "3062bpr0001", "3062b"], ["T", "3062bpat01", "3062b"],
                         ["B", "2429c01", "2429"]]
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil, colorLinks: nil,
                                                     relations: relations, knownPartNumbers: nil)
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
}
