//
//  LDrawUtilitiesFieldTests.swift
//  LDrawCoreTests
//
//  Tests for +[LDrawUtilities readNextField:remainder:], which splits the
//  first field off an LDraw line.
//
//  Created by Sergey Slobodenyuk on 2026-11-27.
//

import Testing
import Foundation
import LDrawCore

@Suite("Reading the next field of a line")
struct LDrawUtilitiesFieldTests {

    private func split(_ line: String) -> (field: String, rest: String?) {
        var rest: NSString?
        let field = LDrawUtilities.readNextField(line, remainder: &rest)

        return (field, rest as String?)
    }

    @Test("The field ends at the first space, which the rest keeps", arguments: [
        ("1 8 -150 3710.DAT", "1", " 8 -150 3710.DAT"),
        ("\t2\t24 0", "2", "\t24 0"),
        ("a\r\nb", "a", "\r\nb"),
        ("é ü", "é", " ü"),
    ])
    func splitsAtSpace(line: String, field: String, rest: String) {
        #expect(split(line) == (field, rest))
    }

    @Test("Spaces around the line are left out", arguments: [
        ("  0 STEP  ", "0", " STEP"),
        ("\n 4 16 \r\n", "4", " 16"),
    ])
    func trimsLine(line: String, field: String, rest: String) {
        #expect(split(line) == (field, rest))
    }

    @Test("A line of one field leaves nothing", arguments: [
        ("3710.DAT", "3710.DAT"),
        ("  3710.DAT \t", "3710.DAT"),
        ("", ""),
        ("  \t ", ""),
    ])
    func lastField(line: String, field: String) {
        #expect(split(line) == (field, ""))
    }

    @Test("Spaces outside ASCII count as spaces too", arguments: [
        ("x\u{00A0}y", "x", "\u{00A0}y"),
        ("\u{3000}x\u{2003}y\u{3000}", "x", "\u{2003}y"),
    ])
    func otherSpaces(line: String, field: String, rest: String) {
        #expect(split(line) == (field, rest))
    }

    @Test("Reading field after field walks the whole line")
    func walksLine() {
        var line = "1 16 0 0 0 1 0 0 0 1 0 0 0 1 3001.dat"
        var fields: [String] = []

        while !line.isEmpty {
            let (field, rest) = split(line)

            fields.append(field)
            line = rest ?? ""
        }
        #expect(fields == ["1", "16", "0", "0", "0", "1", "0", "0", "0", "1", "0", "0", "0", "1", "3001.dat"])
    }

    @Test("Without a place for the rest, only the field comes back")
    func noRemainder() {
        #expect(LDrawUtilities.readNextField(" 0 FILE main.ldr", remainder: nil) == "0")
    }
}
