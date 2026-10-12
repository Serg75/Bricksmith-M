//
//  LPubCalloutMetaTests.swift
//  LDrawCoreTests
//
//  Grammar tests for the LPub CALLOUT metas that get their own directive
//  class: BEGIN, DIVIDER and END, POINTER, PLACEMENT, ALLOC and PLI PER_STEP,
//  and for ASSEM SHOW_STEP_NUMBER, which a callout's box reads.
//
//  A line we do not understand stays a generic LPubCommand. Every line is
//  written back as it was typed.
//
//  The fixtures use no type-1 lines. Parsing one loads the referenced file
//  through LDrawPartLibrary, which needs a renderer the tests do not have.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//

import Testing
import Foundation
import LDrawCore

@Suite("LPub CALLOUT metas")
struct LPubCalloutMetaTests {

    // MARK: - Helpers

    /// Parses one line the way opening a document does and returns the
    /// directive it made.
    private func parse(_ line: String) throws -> LDrawDirective {
        let lines = [line, "0 STEP"]
        let step = try #require(LDrawStep(lines: lines,
                                          in: NSRange(location: 0, length: lines.count),
                                          parentGroup: nil))
        let directives = try #require(step.subdirectives() as? [LDrawDirective])
        return try #require(directives.first)
    }

    private func expectGenericAndVerbatim(_ line: String,
                                          sourceLocation: SourceLocation = #_sourceLocation) throws {
        let directive = try parse(line)

        #expect(directive.isMember(of: LPubCommand.self),
                "\(line) should stay a generic LPub command",
                sourceLocation: sourceLocation)
        #expect(directive.write() == line, sourceLocation: sourceLocation)
    }

    // MARK: - BEGIN, DIVIDER, END

    @Test("BEGIN, DIVIDER and END are the lines of one class")
    func bracketLines() throws {
        let begin = try #require(parse("0 !LPUB CALLOUT BEGIN") as? LPubCallout)
        #expect(begin.line == .begin)
        #expect(begin.mode == .unassembled)

        let divider = try #require(parse("0 !LPUB CALLOUT DIVIDER") as? LPubCallout)
        #expect(divider.line == .divider)

        let end = try #require(parse("0 !LPUB CALLOUT END") as? LPubCallout)
        #expect(end.line == .end)
    }

    @Test("BEGIN takes ASSEMBLED or ROTATED")
    func beginModes() throws {
        let assembled = try #require(parse("0 !LPUB CALLOUT BEGIN ASSEMBLED") as? LPubCallout)
        #expect(assembled.line == .begin)
        #expect(assembled.mode == .assembled)

        let rotated = try #require(parse("0 !LPUB CALLOUT BEGIN ROTATED") as? LPubCallout)
        #expect(rotated.mode == .rotated)
    }

    @Test("A bracket with a word it does not take stays generic")
    func malformedBrackets() throws {
        try expectGenericAndVerbatim("0 !LPUB CALLOUT BEGIN WHOLE")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT BEGIN ASSEMBLED ROTATED")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT DIVIDER LEFT")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT END NOW")
    }

    /// LPub3D writes DIVIDER with a space after it.
    @Test("Brackets are written back as typed")
    func bracketsRoundTrip() throws {
        for line in ["0 !LPUB CALLOUT BEGIN",
                     "0 !LPUB CALLOUT BEGIN ROTATED",
                     "0 !LPUB CALLOUT DIVIDER ",
                     "0 !LPUB CALLOUT END"] {
            let directive = try parse(line)
            #expect(directive is LPubCallout, "\(line)")
            #expect(directive.write() == line)
        }
    }

    @Test("Editing a BEGIN's text changes its mode")
    func editingTextRederivesTheMode() throws {
        let begin = try #require(parse("0 !LPUB CALLOUT BEGIN") as? LPubCallout)

        begin.lPubCommandString = "CALLOUT BEGIN ROTATED"

        #expect(begin.mode == .rotated)
        #expect(begin.write() == "0 !LPUB CALLOUT BEGIN ROTATED")
    }

    // MARK: - POINTER

    @Test("A corner pointer is a tip and an optional base")
    func cornerPointer() throws {
        let pointer = try #require(parse("0 !LPUB CALLOUT POINTER TOP_LEFT 0.367 0.656 0") as? LPubCalloutPointer)
        #expect(pointer.position == .topLeft)
        #expect(pointer.location == 0)
        #expect(pointer.tip.x == 0.367)
        #expect(pointer.tip.y == 0.656)
        #expect(pointer.segmentCount == 1)

        let noBase = try #require(parse("0 !LPUB CALLOUT POINTER BOTTOM_RIGHT 0.1 0.2") as? LPubCalloutPointer)
        #expect(noBase.position == .bottomRight)
        #expect(noBase.tip.y == 0.2)
    }

    @Test("A side pointer starts with where along the side it leaves")
    func sidePointer() throws {
        let pointer = try #require(parse("0 !LPUB CALLOUT POINTER TOP 0.392 0.521 0.399 0") as? LPubCalloutPointer)
        #expect(pointer.position == .top)
        #expect(pointer.location == 0.392)
        #expect(pointer.tip.x == 0.521)
        #expect(pointer.tip.y == 0.399)

        let center = try #require(parse("0 !LPUB CALLOUT POINTER CENTER 0.5 0.25 0.75") as? LPubCalloutPointer)
        #expect(center.position == .center)
        #expect(center.location == 0.5)
        #expect(center.tip.x == 0.25)
    }

    /// LPub3D writes a base of 0 and reads it as its default, an eighth of an
    /// inch.
    @Test("A base of zero, or none, is the default width")
    func pointerBaseDefault() throws {
        let zero = try #require(parse("0 !LPUB CALLOUT POINTER LEFT 0.5 0.1 0.2 0") as? LPubCalloutPointer)
        #expect(zero.baseWidth == 0.125)

        let none = try #require(parse("0 !LPUB CALLOUT POINTER LEFT 0.5 0.1 0.2") as? LPubCalloutPointer)
        #expect(none.baseWidth == 0.125)

        let given = try #require(parse("0 !LPUB CALLOUT POINTER LEFT 0.5 0.1 0.2 0.25") as? LPubCalloutPointer)
        #expect(given.baseWidth == 0.25)
    }

    @Test("The long form carries three more points and a segment count")
    func bentPointer() throws {
        let corner = try #require(
            parse("0 !LPUB CALLOUT POINTER TOP_LEFT 10 20 30 40 50 60 70 80 0.2 3") as? LPubCalloutPointer)
        #expect(corner.tip.x == 10)
        #expect(corner.baseWidth == 0.2)
        #expect(corner.segmentCount == 3)

        let cornerNoBase = try #require(
            parse("0 !LPUB CALLOUT POINTER TOP_LEFT 10 20 30 40 50 60 70 80 2") as? LPubCalloutPointer)
        #expect(cornerNoBase.segmentCount == 2)
        #expect(cornerNoBase.baseWidth == 0.125)

        let side = try #require(
            parse("0 !LPUB CALLOUT POINTER RIGHT 0.4 10 20 30 40 50 60 70 80 0.2 3") as? LPubCalloutPointer)
        #expect(side.location == 0.4)
        #expect(side.tip.y == 20)
        #expect(side.segmentCount == 3)

        let sideNoBase = try #require(
            parse("0 !LPUB CALLOUT POINTER RIGHT 0.4 10 20 30 40 50 60 70 80 2") as? LPubCalloutPointer)
        #expect(sideNoBase.segmentCount == 2)
    }

    @Test("A new arrow's text is a side with where it leaves, or a corner, then the tip and no base")
    func newPointerText() throws {
        let side = LPubCalloutPointer.commandString(position: .left, location: 0.5, tip: Point2(x: 0.25, y: 0.7512))
        let corner = LPubCalloutPointer.commandString(position: .topRight, location: 0.5, tip: Point2(x: 1, y: 0))

        #expect(side == "CALLOUT POINTER LEFT 0.500 0.250 0.751 0")
        #expect(corner == "CALLOUT POINTER TOP_RIGHT 1.000 0.000 0")

        let read = try #require(parse("0 !LPUB " + side) as? LPubCalloutPointer)

        #expect(read.position == .left)
        #expect(abs(read.location - 0.5) < 0.0001)
        #expect(abs(read.tip.x - 0.25) < 0.0001)
        #expect(abs(read.tip.y - 0.751) < 0.0001)
        #expect(try #require(parse("0 !LPUB " + corner) as? LPubCalloutPointer).position == .topRight)
    }

    @Test("A pointer with the wrong count of numbers, or a word among them, stays generic")
    func malformedPointers() throws {
        try expectGenericAndVerbatim("0 !LPUB CALLOUT POINTER TOP_LEFT 0.5")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT POINTER TOP 0.5 0.5")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT POINTER TOP 0.5 0.5 0.5 0 0")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT POINTER MIDDLE 0.5 0.5 0")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT POINTER TOP_LEFT 0.5 half 0")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT POINTER TOP_LEFT 10 20 30 40 50 60 70 80 0.2 2.5")
    }

    // MARK: - PLACEMENT

    @Test("Outside, a side says where along it the box sits")
    func placementOutsideASide() throws {
        let placement = try #require(
            parse("0 !LPUB CALLOUT PLACEMENT BOTTOM CENTER ASSEM OUTSIDE -0.00452592 0.032123")
                as? LPubPlacement)
        #expect(placement.scope == .unspecified)
        #expect(placement.position == .bottom)
        #expect(placement.justification == .center)
        #expect(placement.relativeTo == "ASSEM")
        #expect(placement.isInside == false)
        #expect(placement.offset.x == -0.00452592)
        #expect(placement.offset.y == 0.032123)

        let right = try #require(
            parse("0 !LPUB CALLOUT PLACEMENT RIGHT BOTTOM ASSEM OUTSIDE 0.1 0.2") as? LPubPlacement)
        #expect(right.position == .right)
        #expect(right.justification == .bottom)
    }

    @Test("A corner, and any position inside, takes no justification")
    func placementCornersAndInside() throws {
        let corner = try #require(
            parse("0 !LPUB CALLOUT PLACEMENT TOP_RIGHT ASSEM OUTSIDE 0.1 0.2") as? LPubPlacement)
        #expect(corner.position == .topRight)
        #expect(corner.justification == .center)

        let inside = try #require(parse("0 !LPUB CALLOUT PLACEMENT BOTTOM ASSEM INSIDE") as? LPubPlacement)
        #expect(inside.position == .bottom)
        #expect(inside.isInside == true)
        #expect(inside.offset.x == 0)
        #expect(inside.offset.y == 0)

        let middle = try #require(parse("0 !LPUB CALLOUT PLACEMENT CENTER PAGE INSIDE") as? LPubPlacement)
        #expect(middle.position == .center)
        #expect(middle.relativeTo == "PAGE")
    }

    @Test("The scope keyword and the OFFSET word are both optional")
    func placementScopeAndOffsetWord() throws {
        let local = try #require(
            parse("0 !LPUB CALLOUT PLACEMENT LOCAL RIGHT CENTER MULTI_STEP OUTSIDE") as? LPubPlacement)
        #expect(local.scope == .local)
        #expect(local.relativeTo == "MULTI_STEP")

        let worded = try #require(
            parse("0 !LPUB CALLOUT PLACEMENT GLOBAL TOP LEFT ASSEM OUTSIDE OFFSET 0.25 -0.5")
                as? LPubPlacement)
        #expect(worded.scope == .global)
        #expect(worded.justification == .left)
        #expect(worded.offset.x == 0.25)
        #expect(worded.offset.y == -0.5)
    }

    /// LPub3D drops a CENTER justification inside, and takes no other there.
    @Test("Inside, CENTER after a side means nothing")
    func placementInsideCenter() throws {
        let placement = try #require(
            parse("0 !LPUB CALLOUT PLACEMENT TOP CENTER ASSEM INSIDE") as? LPubPlacement)
        #expect(placement.position == .top)
        #expect(placement.justification == .center)
        #expect(placement.isInside == true)
    }

    @Test("A placement LPub3D has no place for stays generic")
    func malformedPlacements() throws {
        // A side outside needs a justification, and the middle cannot be outside.
        try expectGenericAndVerbatim("0 !LPUB CALLOUT PLACEMENT TOP ASSEM OUTSIDE")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT PLACEMENT CENTER ASSEM OUTSIDE")
        // Inside takes no justification but CENTER.
        try expectGenericAndVerbatim("0 !LPUB CALLOUT PLACEMENT TOP LEFT ASSEM INSIDE")
        // TOP runs left to right, so TOP and BOTTOM cannot justify it.
        try expectGenericAndVerbatim("0 !LPUB CALLOUT PLACEMENT TOP BOTTOM ASSEM OUTSIDE")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT PLACEMENT TOP_LEFT NOWHERE OUTSIDE")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT PLACEMENT TOP_LEFT ASSEM")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT PLACEMENT TOP_LEFT ASSEM BESIDE")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT PLACEMENT TOP_LEFT ASSEM OUTSIDE 0.5")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT PLACEMENT TOP_LEFT ASSEM OUTSIDE OFFSET")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT PLACEMENT TOP_LEFT ASSEM OUTSIDE 0.5 0.5 0.5")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT PLACEMENT OFFSET 0.5 0.5")
    }

    // MARK: - ALLOC

    @Test("ALLOC says which way the steps run")
    func alloc() throws {
        let horizontal = try #require(parse("0 !LPUB CALLOUT ALLOC HORIZONTAL") as? LPubCalloutAlloc)
        #expect(horizontal.isVertical == false)
        #expect(horizontal.scope == .unspecified)

        let vertical = try #require(parse("0 !LPUB CALLOUT ALLOC LOCAL VERTICAL") as? LPubCalloutAlloc)
        #expect(vertical.isVertical == true)
        #expect(vertical.scope == .local)

        try expectGenericAndVerbatim("0 !LPUB CALLOUT ALLOC DIAGONAL")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT ALLOC")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT ALLOC VERTICAL TRUE")
    }

    // MARK: - PLI PER_STEP

    @Test("PLI PER_STEP is a boolean with a scope")
    func pliPerStep() throws {
        let off = try #require(parse("0 !LPUB CALLOUT PLI PER_STEP GLOBAL FALSE") as? LPubCalloutPliPerStep)
        #expect(off.isPerStep == false)
        #expect(off.scope == .global)

        let on = try #require(parse("0 !LPUB CALLOUT PLI PER_STEP TRUE") as? LPubCalloutPliPerStep)
        #expect(on.isPerStep == true)
        #expect(on.scope == .unspecified)

        try expectGenericAndVerbatim("0 !LPUB CALLOUT PLI PER_STEP MAYBE")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT PLI PER_STEP")
    }

    // MARK: - Everything else

    // MARK: - Editing

    @Test("A placement's text takes a new offset and keeps the rest as typed")
    func placementTextWithANewOffset() throws {
        let typed = "0 !LPUB CALLOUT PLACEMENT BOTTOM CENTER ASSEM OUTSIDE -0.00452592 0.032123"
        let plain = try #require(parse(typed) as? LPubPlacement)
        #expect(plain.commandString(withOffset: Point2(x: 0.1, y: -0.25))
                == "CALLOUT PLACEMENT BOTTOM CENTER ASSEM OUTSIDE 0.1000 -0.2500")

        let bare = try #require(parse("0 !LPUB CALLOUT PLACEMENT LOCAL TOP_LEFT PAGE INSIDE") as? LPubPlacement)
        #expect(bare.commandString(withOffset: Point2(x: 0.05, y: 0))
                == "CALLOUT PLACEMENT LOCAL TOP_LEFT PAGE INSIDE 0.0500 0.0000")

        let worded = try #require(
            parse("0 !LPUB CALLOUT PLACEMENT RIGHT TOP ASSEM OUTSIDE OFFSET 0.1 0.2") as? LPubPlacement)
        #expect(worded.commandString(withOffset: Point2(x: -1, y: 2))
                == "CALLOUT PLACEMENT RIGHT TOP ASSEM OUTSIDE OFFSET -1.0000 2.0000")
    }

    @Test("An assembly's PLACEMENT is the same line with another subject")
    func assemblyPlacement() throws {
        let typed = "0 !LPUB ASSEM PLACEMENT LOCAL CENTER PAGE INSIDE -0.0119972 0.0963294"
        let placement = try #require(parse(typed) as? LPubPlacement)

        #expect(placement.branch == .assembly)
        #expect(placement.scope == .local)
        #expect(placement.position == .center)
        #expect(placement.relativeTo == "PAGE")
        #expect(placement.isInside)
        #expect(abs(placement.offset.y - 0.0963294) < 1e-9)
        #expect(placement.write() == typed)

        let callout = try #require(parse("0 !LPUB CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE") as? LPubPlacement)
        #expect(callout.branch == .callout)

        // Another subject's placement is not read.
        try expectGenericAndVerbatim("0 !LPUB PLI PLACEMENT TOP_LEFT PAGE INSIDE")
    }

    @Test("The new text reads back as the same placement at the new offset")
    func placementTextReadsBack() throws {
        let placement = try #require(
            parse("0 !LPUB CALLOUT PLACEMENT BOTTOM LEFT ASSEM OUTSIDE 0.5 0.5") as? LPubPlacement)

        placement.lPubCommandString = placement.commandString(withOffset: Point2(x: 0.125, y: -0.5))

        #expect(placement.position == .bottom)
        #expect(placement.justification == .left)
        #expect(placement.relativeTo == "ASSEM")
        #expect(placement.isInside == false)
        #expect(placement.offset.x == 0.125)
        #expect(placement.offset.y == -0.5)
    }

    @Test("The default placement's text is the one LPub3D assumes, with an offset")
    func defaultPlacementText() throws {
        let text = LPubPlacement.defaultCalloutCommandString(withOffset: Point2(x: 0.1, y: 0.2))
        let placement = try #require(parse("0 !LPUB " + text) as? LPubPlacement)

        #expect(text == "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.1000 0.2000")
        #expect(placement.position == .right)
        #expect(placement.justification == .center)
        #expect(placement.offset.x == 0.1)
    }

    @Test("ASSEM SHOW_STEP_NUMBER is a boolean with a scope")
    func showStepNumber() throws {
        let hidden = try #require(parse("0 !LPUB ASSEM SHOW_STEP_NUMBER GLOBAL FALSE") as? LPubAssemShowStepNumber)
        #expect(hidden.isShown == false)
        #expect(hidden.scope == .global)
        #expect(hidden.write() == "0 !LPUB ASSEM SHOW_STEP_NUMBER GLOBAL FALSE")

        let shown = try #require(parse("0 !LPUB ASSEM SHOW_STEP_NUMBER TRUE") as? LPubAssemShowStepNumber)
        #expect(shown.isShown)
        #expect(shown.scope == .unspecified)

        #expect(LPubAssemShowStepNumber().isShown)

        try expectGenericAndVerbatim("0 !LPUB ASSEM SHOW_STEP_NUMBER MAYBE")
        try expectGenericAndVerbatim("0 !LPUB ASSEM SHOW_STEP_NUMBER TRUE FALSE")
        try expectGenericAndVerbatim("0 !LPUB ASSEM SHOW_STEP_NUMBER")
    }

    /// The shapes LPub3D writes, taken from a real file, with type-2 lines in
    /// place of the parts.
    @Test("A file's callout lines come back out exactly as they went in")
    func calloutLinesRoundTrip() throws {
        let fixture = """
            0 Callout Fixture
            0 Name: main.ldr
            0 Author: Bricksmith
            0 !LPUB CALLOUT PLI PER_STEP GLOBAL FALSE
            0 !LPUB CALLOUT SEPARATOR GLOBAL 0.015 #4c4c4c 0.118109 0.11811
            0 !LPUB CALLOUT BEGIN
            2 24 0 0 0 20 0 0
            0 !LPUB CALLOUT POINTER TOP_LEFT 0.367 0.656 0
            0 !LPUB CALLOUT POINTER TOP 0.392 0.521 0.399 0
            0 !LPUB CALLOUT ALLOC HORIZONTAL
            0 !LPUB CALLOUT PLACEMENT BOTTOM CENTER ASSEM OUTSIDE -0.00452592 0.032123
            0 !LPUB CALLOUT END
            0 STEP
            0 !LPUB CALLOUT BEGIN
            2 24 0 0 0 0 20 0
            0 !LPUB CALLOUT BACKGROUND LOCAL COLOR "#daf3ff"
            0 !LPUB CALLOUT PLACEMENT TOP_RIGHT ASSEM INSIDE
            0 !LPUB CALLOUT END
            0 STEP
            """
        let file = try #require(LDrawFile.parse(fromFileContents: fixture))
        let lines: (String) -> [String] = { $0.split(whereSeparator: \.isNewline).map(String.init) }

        #expect(lines(file.write()) == lines(fixture))
    }
}
