//
//  LDrawRegexTests.swift
//  LDrawCoreTests
//
//  The NSString regex helpers, which keep each compiled pattern for later calls.
//
//  Created by Sergey Slobodenyuk on 2026-11-10.
//

import Testing
import Foundation
import LDrawCore

@Suite("Regex helpers")
struct LDrawRegexTests {

    private static let groupPattern = "0\\s+MLCAD\\s+BTG\\s+(\\S+)"

    @Test("One pattern gives each string its own answer")
    func samePatternManyStrings() {
        let pattern = Self.groupPattern

        #expect(("0 MLCAD BTG wheel" as NSString).isMatched(byRegex: pattern))
        #expect(!("1 16 0 0 0 1 0 0 0 1 0 0 0 1 3001.dat" as NSString).isMatched(byRegex: pattern))
        #expect(("0 MLCAD BTG door" as NSString).captureComponentsMatched(byRegex: pattern) == ["0 MLCAD BTG door", "door"])
    }

    @Test("A group that does not take part gives an empty string")
    func missingGroup() {
        let components = ("0 SYNTH SHOW" as NSString).captureComponentsMatched(byRegex: "0\\s+SYNTH\\s+(SHOW)|(HIDE)")

        #expect(components == ["0 SYNTH SHOW", "SHOW", ""])
    }

    @Test("Every match of a pattern is returned")
    func allMatches() {
        let all = ("a1 b2 c3" as NSString).arrayOfCaptureComponentsMatched(byRegex: "([a-z])([0-9])")

        #expect(all == [["a1", "a", "1"], ["b2", "b", "2"], ["c3", "c", "3"]])
    }

    @Test("An empty or bad pattern matches nothing, also when asked again")
    func badPatterns() {
        for _ in 0..<2 {
            #expect(!("anything" as NSString).isMatched(byRegex: ""))
            #expect(!("anything" as NSString).isMatched(byRegex: "(unclosed"))
            #expect(("anything" as NSString).captureComponentsMatched(byRegex: "(unclosed").isEmpty)
            #expect(("anything" as NSString).arrayOfCaptureComponentsMatched(byRegex: "(unclosed").isEmpty)
        }
    }

    @Test("Many threads can use the same pattern at once")
    func concurrentUse() {
        let pattern = Self.groupPattern
        let count = 2000
        let results = UnsafeMutableBufferPointer<Bool>.allocate(capacity: count)
        defer { results.deallocate() }

        DispatchQueue.concurrentPerform(iterations: count) { index in
            let line = (index % 2 == 0) ? "0 MLCAD BTG g\(index)" : "0 STEP"
            results[index] = (line as NSString).isMatched(byRegex: pattern)
        }

        for index in 0..<count {
            #expect(results[index] == (index % 2 == 0))
        }
    }
}
