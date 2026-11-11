//
//  LDrawEditorStringsTests.swift
//  LDrawEditingTests
//
//  Tests for cutting long names short for menu items.
//
//  Created by Sergey Slobodenyuk on 2026-11-11.
//

import Testing
import Foundation
import LDrawEditing

@Suite("Shortening a name")
struct LDrawEditorStringsTests {

    @Test("A name within the limit stays whole", arguments: ["Left Wing", "1234567890"])
    func shortNameStays(name: String) {
        #expect(LDrawEditorStrings.shortenedName(name, maximumLength: 10) == name)
    }

    @Test("A long name loses its middle, and the start keeps the odd place",
          arguments: [(11, "abcde…56789"), (10, "abcde…6789")])
    func longNameLosesMiddle(maximumLength: Int, expected: String) {
        let name = "abcdefghijklmnopqrstuvwxyz0123456789"
        #expect(LDrawEditorStrings.shortenedName(name, maximumLength: UInt(maximumLength)) == expected)
    }

    @Test("A cut never splits a character", arguments: [("ab👍cdefgh", "ab…gh"), ("abcdefg👍h", "abc…h")])
    func cutKeepsCharactersWhole(name: String, expected: String) {
        #expect(LDrawEditorStrings.shortenedName(name, maximumLength: 6) == expected)
    }
}
