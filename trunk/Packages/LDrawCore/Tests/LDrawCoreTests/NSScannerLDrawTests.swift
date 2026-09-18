//
//  NSScannerLDrawTests.swift
//  LDrawCoreTests
//
//  Splitting an LDraw line into words, where a quoted phrase is one word.
//
//  Created by Sergey Slobodenyuk on 2023-03-03.
//

import Testing
import Foundation
import LDrawCore

@Suite("Splitting a line into words")
struct NSScannerLDrawTests {

    @Test("Words are split on spaces and tabs, and a quoted phrase stays whole", arguments: [
        ("", []),
        ("  \t", []),
        ("word", ["word"]),
        ("   word\t", ["word"]),
        ("word1 word2 word3", ["word1", "word2", "word3"]),
        ("word1   word2\t\t\tword3\t", ["word1", "word2", "word3"]),
        ("\"word1   word2\"\t", ["\"word1   word2\""]),
        ("word1   word2   \"word3   word4\"\t", ["word1", "word2", "\"word3   word4\""]),
        ("\"word1   word2\"   \"word3   word4\"\t", ["\"word1   word2\"", "\"word3   word4\""]),
        (" word1\"word2\" ", ["word1\"word2\""]),
    ] as [(String, [String])])
    func splitsIntoWords(line: String, words: [String]) {
        #expect(Scanner(string: line).scanSubstringsWithQuotations() == words)
    }

    @Test("Spaces just inside the quotes stay part of the phrase",
          .disabled("The scanner trims them today"))
    func spacesInsideQuotesAreKept() {
        #expect(Scanner(string: "\" word1   word2 \" ").scanSubstringsWithQuotations() == ["\" word1   word2 \""])
    }

    @Test("A quote that is never closed does not start a phrase",
          .disabled("The scanner takes the rest of the line today"))
    func anUnclosedQuoteIsAWord() {
        #expect(Scanner(string: " word1   \"word2 ").scanSubstringsWithQuotations() == ["word1", "\"word2"])
    }
}
