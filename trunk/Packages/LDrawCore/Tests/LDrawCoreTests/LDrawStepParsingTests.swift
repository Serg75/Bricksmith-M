//
//  LDrawStepParsingTests.swift
//  UnitTests
//
//  Guards LDrawStep's parse loop against lines it cannot turn into a directive.
//
//  These are memory-safety tests, so a regression here does not fail politely:
//  before the guards existed, a single line whose type code was outside 0-5 made
//  +classForDirectiveBeginningWithLine: return Nil, the Nil class hand back a
//  zeroed NSRange, and the loop cursor rewind to 0 -- spinning while insertIndex
//  walked off the end of a calloc'd buffer of __strong slots. That crashed in
//  objc_release, so if these tests ever break they will take the whole runner
//  down with them rather than report a failure.
//
//  Every fixture below uses type-2 lines only. Type-1 lines would reach
//  +[LDrawPartLibrary sharedPartLibrary], which asserts unless a renderer has
//  registered itself -- and the UnitTests target is deliberately renderer-free.
//
//  Created by Sergey Slobodenyuk on 2026-09-02.
//

import Testing
import Foundation
import LDrawCore

@Suite("Step parsing survives lines it cannot use")
struct LDrawStepParsingTests {

    private static let unrecognizedLine = "7 0 0 0"

    private func step(from lines: [String]) throws -> LDrawStep {
        try #require(LDrawStep(lines: lines,
                               in: NSRange(location: 0, length: lines.count),
                               parentGroup: nil))
    }

    // MARK: - The precondition

    /// The trigger is not exotic: any type code the parser does not know about
    /// yields no class at all, and nothing upstream filters such lines out
    /// before a step sees them.
    @Test("Unrecognized line types map to no directive class")
    func unrecognizedLineTypesHaveNoClass() {
        #expect(LDrawUtilities.classForDirectiveBeginning(withLine: Self.unrecognizedLine) == nil)
        #expect(LDrawUtilities.classForDirectiveBeginning(withLine: "6 1 2 3") == nil)
        #expect(LDrawUtilities.classForDirectiveBeginning(withLine: "99 x") == nil)

        // Control: the codes the parser does know still resolve.
        #expect(LDrawUtilities.classForDirectiveBeginning(withLine: "2 24 0 0 0 1 1 1") != nil)
        #expect(LDrawUtilities.classForDirectiveBeginning(withLine: "0 STEP") != nil)
    }

    // MARK: - Step level

    @Test("An unrecognized line is skipped and its neighbours still parse")
    func unrecognizedLineIsSkipped() throws {
        let parsed = try step(from: ["2 24 0 0 0 1 1 1",
                                     Self.unrecognizedLine,
                                     "0 STEP"])

        #expect(parsed.subdirectives().count == 1)
    }

    /// The unrecognized line used to rewind the cursor to 0, so a valid line
    /// ahead of it got parsed repeatedly. Placing valid lines on both sides
    /// checks the cursor now moves past the bad line exactly once.
    @Test("A step keeps every good line around an unrecognized one, once each")
    func goodLinesAroundBadLineParseOnce() throws {
        let parsed = try step(from: ["2 24 0 0 0 1 1 1",
                                     Self.unrecognizedLine,
                                     "2 24 1 1 1 2 2 2",
                                     "0 STEP"])

        #expect(parsed.subdirectives().count == 2)
    }

    @Test("Back-to-back unrecognized lines are all skipped")
    func consecutiveUnrecognizedLinesAreSkipped() throws {
        let parsed = try step(from: ["2 24 0 0 0 1 1 1",
                                     Self.unrecognizedLine,
                                     "6 1 2 3",
                                     "42 nonsense",
                                     "0 STEP"])

        #expect(parsed.subdirectives().count == 1)
    }

    @Test("A step of nothing but unrecognized lines is empty, not fatal")
    func onlyUnrecognizedLines() throws {
        let parsed = try step(from: [Self.unrecognizedLine, "6 1 2 3", "0 STEP"])

        #expect(parsed.subdirectives().count == 0)
    }

    @Test("Control: a step of recognized lines keeps all of them")
    func recognizedLinesAllSurvive() throws {
        let parsed = try step(from: ["2 24 0 0 0 1 1 1",
                                     "2 24 1 1 1 2 2 2",
                                     "0 STEP"])

        #expect(parsed.subdirectives().count == 2)
    }

    // MARK: - File level

    /// The path a document open actually takes. This is what crashed the app:
    /// the bad line is three frames below +parseFromFileContents:, inside the
    /// step that LDrawModel builds for it.
    @Test("A file containing an unrecognized line type still opens")
    func fileWithUnrecognizedLineParses() throws {
        let contents = """
            0 Fixture Model
            0 Name: fixture.ldr
            2 24 0 0 0 1 1 1
            \(Self.unrecognizedLine)
            2 24 1 1 1 2 2 2
            0 STEP

            """

        let file = try #require(LDrawFile.parse(fromFileContents: contents))

        #expect(file.submodels().count == 1)
    }
}
