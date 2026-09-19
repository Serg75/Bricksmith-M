//
//  LDrawInlinePartTests.swift
//  UnitTests
//
//  Tests for the check that a model header declares the model a part.
//  The fixtures have no type-1 lines, so the part library is never loaded.
//
//  Created by Sergey Slobodenyuk on 2026-09-14.
//

import Testing
import Foundation
import LDrawCore

@Suite("A model that declares itself a part")
struct LDrawInlinePartTests {

    private func model(typeLine: String?, afterHeader: Bool = false) throws -> LDrawModel {
        var lines = ["0 88704 orig",
                     "0 Name: 88704 orig.ldr",
                     "0 Author: Sergey S."]
        if let typeLine, !afterHeader { lines.append(typeLine) }
        lines.append("2 24 0 0 0 20 0 0")
        if let typeLine, afterHeader { lines.append(typeLine) }

        return try #require(LDrawModel(lines: lines,
                                       in: NSRange(location: 0, length: lines.count),
                                       parentGroup: nil))
    }

    @Test("Every spelling LPub3D reads as a part is one",
          arguments: ["0 !LDRAW_ORG Unofficial_Part",
                      "0 !LDRAW_ORG Unofficial_Part Alias",
                      "0 !LDRAW_ORG Unofficial_Subpart",
                      "0 !LDRAW_ORG Unofficial_Primitive",
                      "0 !LDRAW_ORG Unofficial_48_Primitive",
                      "0 !LDRAW_ORG Unofficial_Shortcut",
                      "0 !ldraw_org unofficial_part",
                      "0 Unofficial Part",
                      "0 UNOFFICIAL PART",
                      "0 !LDCAD GENERATED 2024"])
    func headerSpellings(line: String) throws {
        #expect(try model(typeLine: line).isInlinePart())
    }

    @Test("A plain model is not a part")
    func plainModelIsNotAPart() throws {
        #expect(try model(typeLine: nil).isInlinePart() == false)
    }

    /// Only the header is read, and an official part says "Part", not
    /// "Unofficial_Part", so it counts as a submodel here.
    @Test("An official type line, or one below the header, does not make a part")
    func otherLinesDoNot() throws {
        #expect(try model(typeLine: "0 !LDRAW_ORG Part UPDATE 2018-02").isInlinePart() == false)
        #expect(try model(typeLine: "0 !LDRAW_ORG Unofficial_Part", afterHeader: true).isInlinePart() == false)
        #expect(try model(typeLine: "0 Unofficial Model").isInlinePart() == false)
    }
}
