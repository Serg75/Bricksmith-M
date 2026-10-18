//
//  LPubCalloutStyleMetaTests.swift
//  LDrawCoreTests
//
//  Grammar tests for the LPub CALLOUT metas that say how a callout's box
//  looks: BORDER, BACKGROUND, SUBMODEL_BACKGROUND_COLOR, MARGINS, SEPARATOR,
//  and the FONT and FONT_COLOR of its text. Also the colors those lines name,
//  and the same lines under PLI for a parts list.
//
//  A line we do not understand stays a generic LPubCommand. Every line is
//  written back as it was typed.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//

import Testing
import Foundation
import LDrawCore

@Suite("LPub CALLOUT style metas")
struct LPubCalloutStyleMetaTests {

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

    private func color(_ text: String) -> LPubColorComponents? {
        var components = LPubColorComponents()
        return LPubColorComponentsFromString(text, &components) ? components : nil
    }

    private func expectColor(_ color: LPubColorComponents?,
                             _ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1.0,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        guard let color else {
            Issue.record("the color should be readable", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(color.red - red) < 0.001, sourceLocation: sourceLocation)
        #expect(abs(color.green - green) < 0.001, sourceLocation: sourceLocation)
        #expect(abs(color.blue - blue) < 0.001, sourceLocation: sourceLocation)
        #expect(abs(color.alpha - alpha) < 0.001, sourceLocation: sourceLocation)
    }

    // MARK: - Colors

    @Test("A color is hex digits after a #, with alpha first when there are eight")
    func hexColors() {
        expectColor(color("#daf3ff"), 218.0 / 255.0, 243.0 / 255.0, 1.0)
        expectColor(color("#FFFECC"), 1.0, 254.0 / 255.0, 204.0 / 255.0)
        expectColor(color("#80ff0000"), 1.0, 0.0, 0.0, 128.0 / 255.0)
        expectColor(color("#f00"), 1.0, 0.0, 0.0)
    }

    @Test("A color is also a name, in any case")
    func namedColors() {
        expectColor(color("Black"), 0.0, 0.0, 0.0)
        expectColor(color("white"), 1.0, 1.0, 1.0)
        expectColor(color("LightGray"), 211.0 / 255.0, 211.0 / 255.0, 211.0 / 255.0)
        expectColor(color("transparent"), 0.0, 0.0, 0.0, 0.0)
    }

    @Test("Anything else is no color")
    func unreadableColors() {
        #expect(color("#12345") == nil)
        #expect(color("#gggggg") == nil)
        #expect(color("notacolor") == nil)
        #expect(color("") == nil)
    }

    // MARK: - BORDER

    @Test("A round border gives a color, a thickness, a radius and margins")
    func roundBorder() throws {
        let line = "0 !LPUB CALLOUT BORDER GLOBAL ROUND #fffecc 0.0196841 10 MARGINS 0.11811 0.11811"
        let border = try #require(parse(line) as? LPubCalloutBorder)

        #expect(border.scope == .global)
        #expect(border.shape == .round)
        #expect(border.lineStyle == .solid)
        expectColor(border.color, 1.0, 254.0 / 255.0, 204.0 / 255.0)
        #expect(abs(border.thickness - 0.0196841) < 1e-9)
        #expect(border.radius == 10.0)
        #expect(border.hasMargins)
        #expect(abs(border.margins.width - 0.11811) < 1e-9)
        #expect(abs(border.margins.height - 0.11811) < 1e-9)
        #expect(border.write() == line)
    }

    @Test("A number after the shape is the line style")
    func borderLineStyle() throws {
        let square = try #require(parse("0 !LPUB CALLOUT BORDER LOCAL SQUARE 2 Black 0.031") as? LPubCalloutBorder)

        #expect(square.scope == .local)
        #expect(square.shape == .square)
        #expect(square.lineStyle == .dash)
        #expect(square.hidesArrowTips == false)
        #expect(square.hasMargins == false)
        expectColor(square.color, 0.0, 0.0, 0.0)

        let round = try #require(parse("0 !LPUB CALLOUT BORDER ROUND 3 \"Black\" 0.031 15.000 MARGINS 0.050 0.050")
                                 as? LPubCalloutBorder)

        #expect(round.lineStyle == .dot)
        #expect(round.radius == 15.0)
        #expect(round.hasMargins)
    }

    @Test("NONE draws no border, and HIDDEN is a square one with no arrow heads")
    func borderNoneAndHidden() throws {
        let none = try #require(parse("0 !LPUB CALLOUT BORDER GLOBAL NONE 0 MARGINS 0.05 0.05") as? LPubCalloutBorder)

        #expect(none.shape == .none)
        #expect(none.lineStyle == .none)
        #expect(none.hasMargins)

        let bare = try #require(parse("0 !LPUB CALLOUT BORDER NONE") as? LPubCalloutBorder)

        #expect(bare.shape == .none)
        #expect(bare.hasMargins == false)

        let hidden = try #require(parse("0 !LPUB CALLOUT BORDER HIDDEN #000000 0.02") as? LPubCalloutBorder)

        #expect(hidden.shape == .square)
        #expect(hidden.hidesArrowTips)
    }

    @Test("A border with a number missing, or with words left over, stays generic")
    func malformedBorders() throws {
        try expectGenericAndVerbatim("0 !LPUB CALLOUT BORDER")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT BORDER OVAL Black 0.03")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT BORDER SQUARE Black")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT BORDER ROUND Black 0.03")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT BORDER SQUARE Black thick")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT BORDER SQUARE 9 Black 0.03")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT BORDER SQUARE Black 0.03 MARGINS 0.05")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT BORDER SQUARE Black 0.03 PADDING 0.05 0.05")
    }

    @Test("Editing a border's text changes what it says")
    func editingABorder() throws {
        let border = try #require(parse("0 !LPUB CALLOUT BORDER SQUARE Black 0.03") as? LPubCalloutBorder)

        border.lPubCommandString = "CALLOUT BORDER LOCAL ROUND #ff0000 0.05 20"

        #expect(border.shape == .round)
        #expect(border.scope == .local)
        #expect(border.radius == 20.0)
        expectColor(border.color, 1.0, 0.0, 0.0)
    }

    // MARK: - BACKGROUND

    @Test("A background is a color, the submodel's color, or nothing")
    func backgrounds() throws {
        let line = "0 !LPUB CALLOUT BACKGROUND LOCAL COLOR \"#daf3ff\""
        let filled = try #require(parse(line) as? LPubCalloutBackground)

        #expect(filled.scope == .local)
        #expect(filled.kind == .color)
        expectColor(filled.color, 218.0 / 255.0, 243.0 / 255.0, 1.0)
        #expect(filled.write() == line)

        let submodel = try #require(parse("0 !LPUB CALLOUT BACKGROUND GLOBAL SUBMODEL_BACKGROUND_COLOR")
                                    as? LPubCalloutBackground)

        #expect(submodel.kind == .submodelColor)
        #expect(submodel.scope == .global)

        let clear = try #require(parse("0 !LPUB CALLOUT BACKGROUND TRANSPARENT") as? LPubCalloutBackground)

        #expect(clear.kind == .transparent)
        #expect(try #require(parse("0 !LPUB CALLOUT BACKGROUND TRANS") as? LPubCalloutBackground).kind == .transparent)
    }

    @Test("A picture or a gradient is read as what it is")
    func backgroundsThatAreNotAColor() throws {
        let picture = try #require(parse("0 !LPUB CALLOUT BACKGROUND PICTURE \"paper.png\" STRETCH")
                                   as? LPubCalloutBackground)

        #expect(picture.kind == .picture)
        #expect(try #require(parse("0 !LPUB CALLOUT BACKGROUND paper.png") as? LPubCalloutBackground).kind == .picture)

        let line = "0 !LPUB CALLOUT BACKGROUND GRADIENT 0 0 0 800 600 0 \"0,0|800,600\" \"0,ffffffff|1,ff000000\""
        let gradient = try #require(parse(line) as? LPubCalloutBackground)

        #expect(gradient.kind == .gradient)
        #expect(gradient.write() == line)
    }

    @Test("A background with words left over stays generic")
    func malformedBackgrounds() throws {
        try expectGenericAndVerbatim("0 !LPUB CALLOUT BACKGROUND")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT BACKGROUND COLOR")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT BACKGROUND COLOR red blue green")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT BACKGROUND PICTURE paper.png TILE")
    }

    // MARK: - SUBMODEL_BACKGROUND_COLOR

    @Test("The submodel colors are a list, and a level past its end takes the last")
    func submodelColors() throws {
        let line = "0 !LPUB CALLOUT SUBMODEL_BACKGROUND_COLOR GLOBAL #ffffff #ffeecc #ccddff"
        let colors = try #require(parse(line) as? LPubCalloutSubmodelColor)

        #expect(colors.scope == .global)
        #expect(colors.colorCount == 3)
        expectColor(colors.color(atLevel: 1), 1.0, 238.0 / 255.0, 204.0 / 255.0)
        expectColor(colors.color(atLevel: 7), 204.0 / 255.0, 221.0 / 255.0, 1.0)
        #expect(colors.write() == line)

        try expectGenericAndVerbatim("0 !LPUB CALLOUT SUBMODEL_BACKGROUND_COLOR GLOBAL")
    }

    @Test("With no line, a callout in the top model is cream")
    func defaultSubmodelColors() {
        expectColor(LPubCalloutSubmodelColor.defaultColor(atLevel: 0), 1.0, 1.0, 1.0)
        expectColor(LPubCalloutSubmodelColor.defaultColor(atLevel: 1), 1.0, 1.0, 0.8)
        expectColor(LPubCalloutSubmodelColor.defaultColor(atLevel: 9), 0.8, 0.8, 1.0)
    }

    // MARK: - MARGINS

    @Test("MARGINS are for the box, or for something in it")
    func margins() throws {
        let box = try #require(parse("0 !LPUB CALLOUT MARGINS GLOBAL 0.1181 0.1181") as? LPubCalloutMargins)

        #expect(box.part == .box)
        #expect(box.scope == .global)
        #expect(abs(box.margins.width - 0.1181) < 1e-9)

        let assembly = try #require(parse("0 !LPUB CALLOUT ASSEM MARGINS GLOBAL 0.1575 0.2") as? LPubCalloutMargins)

        #expect(assembly.part == .assembly)
        #expect(abs(assembly.margins.height - 0.2) < 1e-9)

        #expect(try #require(parse("0 !LPUB CALLOUT PLI MARGINS 0.1 0.1") as? LPubCalloutMargins).part == .partsList)
        #expect(try #require(parse("0 !LPUB CALLOUT STEP_NUMBER MARGINS LOCAL 0 0") as? LPubCalloutMargins).part
                == .stepNumber)
        #expect(try #require(parse("0 !LPUB CALLOUT INSTANCE_COUNT MARGINS 0.05 0.05") as? LPubCalloutMargins).part
                == .instanceCount)
    }

    @Test("MARGINS for anything else, or without two numbers, stay generic")
    func malformedMargins() throws {
        try expectGenericAndVerbatim("0 !LPUB CALLOUT MARGINS GLOBAL 0.1181")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT MARGINS 0.1 0.1 0.1")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT MARGINS wide narrow")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT ROTATE_ICON MARGINS 0.1 0.1")
        try expectGenericAndVerbatim("0 !LPUB PLI PART MARGINS GLOBAL 0.1 0.1")
        try expectGenericAndVerbatim("0 !LPUB PLI PLI MARGINS 0.1 0.1")
        try expectGenericAndVerbatim("0 !LPUB PLI STEP_NUMBER MARGINS 0.1 0.1")
    }

    // MARK: - SEPARATOR

    @Test("A separator is a thickness, a color and two margins")
    func separator() throws {
        let line = "0 !LPUB CALLOUT SEPARATOR GLOBAL 0.015 #4c4c4c 0.118109 0.11811"
        let separator = try #require(parse(line) as? LPubCalloutSeparator)

        #expect(separator.scope == .global)
        #expect(abs(separator.thickness - 0.015) < 1e-9)
        expectColor(separator.color, 76.0 / 255.0, 76.0 / 255.0, 76.0 / 255.0)
        #expect(abs(separator.margins.width - 0.118109) < 1e-9)
        #expect(abs(separator.margins.height - 0.11811) < 1e-9)
        #expect(separator.write() == line)
    }

    @Test("The longer separator forms name the length, the thickness and the margins")
    func longSeparators() throws {
        let lines = [
            "0 !LPUB CALLOUT SEPARATOR PAGE 0.02 Black 0.05 0.06",
            "0 !LPUB CALLOUT SEPARATOR PAGE_LENGTH THICKNESS 0.02 Black MARGINS 0.05 0.06",
            "0 !LPUB CALLOUT SEPARATOR CUSTOM 3.5 0.02 Black 0.05 0.06",
            "0 !LPUB CALLOUT SEPARATOR THICKNESS 0.02 Black MARGINS 0.05 0.06",
            "0 !LPUB CALLOUT SEPARATOR LOCAL CUSTOM_LENGTH 3.5 THICKNESS 0.02 Black MARGINS 0.05 0.06",
        ]

        for line in lines {
            let separator = try #require(parse(line) as? LPubCalloutSeparator, "\(line)")

            #expect(abs(separator.thickness - 0.02) < 1e-9, "\(line)")
            #expect(abs(separator.margins.width - 0.05) < 1e-9, "\(line)")
            #expect(abs(separator.margins.height - 0.06) < 1e-9, "\(line)")
            #expect(separator.write() == line)
        }
    }

    @Test("A separator with a number missing stays generic")
    func malformedSeparators() throws {
        try expectGenericAndVerbatim("0 !LPUB CALLOUT SEPARATOR GLOBAL 0.015 #4c4c4c 0.118109")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT SEPARATOR thick #4c4c4c 0.1 0.1")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT SEPARATOR CUSTOM 0.02 Black 0.05 0.06")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT SEPARATOR 0.015 #4c4c4c 0.1 0.1 0.1")
    }

    // MARK: - FONT

    @Test("A font is a family, a size, a weight and a slant")
    func fonts() throws {
        let line = "0 !LPUB CALLOUT INSTANCE_COUNT FONT GLOBAL \"Arial,48,-1,5,50,0,0,0,0,0\""
        let plain = try #require(parse(line) as? LPubCalloutFont)

        #expect(plain.part == .instanceCount)
        #expect(plain.scope == .global)
        #expect(plain.isColor == false)
        #expect(plain.family == "Arial")
        #expect(plain.size == 48.0)
        #expect(plain.isBold == false)
        #expect(plain.isItalic == false)
        #expect(plain.write() == line)

        let bold = try #require(parse("0 !LPUB CALLOUT STEP_NUMBER FONT \"Helvetica Neue,36,-1,255,75,1,0,0,0,0\"")
                                as? LPubCalloutFont)

        #expect(bold.part == .stepNumber)
        #expect(bold.family == "Helvetica Neue")
        #expect(bold.isBold)
        #expect(bold.isItalic)
    }

    @Test("A font from Qt 6 weighs bold from 600, and a size of -1 points is in pixels")
    func newerFonts() throws {
        let heavy = "0 !LPUB CALLOUT STEP_NUMBER FONT \"Arial,24,-1,5,700,0,0,0,0,0,0,0,0,0,0,1\""
        let light = "0 !LPUB CALLOUT STEP_NUMBER FONT \"Arial,24,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\""
        let pixels = "0 !LPUB CALLOUT STEP_NUMBER FONT \"Arial,-1,30,5,50,0,0,0,0,0\""

        #expect(try #require(parse(heavy) as? LPubCalloutFont).isBold)
        #expect(try #require(parse(light) as? LPubCalloutFont).isBold == false)
        #expect(try #require(parse(pixels) as? LPubCalloutFont).size == 30.0)
    }

    @Test("FONT_COLOR is the color of the same text")
    func fontColors() throws {
        let line = "0 !LPUB CALLOUT STEP_NUMBER FONT_COLOR LOCAL #336699"
        let color = try #require(parse(line) as? LPubCalloutFont)

        #expect(color.isColor)
        #expect(color.part == .stepNumber)
        #expect(color.scope == .local)
        expectColor(color.color, 0.2, 0.4, 0.6)
        #expect(color.write() == line)
    }

    @Test("A font for anything else, or with no size, stays generic")
    func malformedFonts() throws {
        try expectGenericAndVerbatim("0 !LPUB CALLOUT STEP_NUMBER FONT")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT STEP_NUMBER FONT \"Arial\"")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT STEP_NUMBER FONT \",36,-1,5,50,0,0,0,0,0\"")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT STEP_NUMBER FONT \"Arial,big,-1,5,50,0,0,0,0,0\"")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT ASSEM FONT \"Arial,36,-1,5,50,0,0,0,0,0\"")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT SUBMODEL_FONT \"Arial,36,-1,5,50,0,0,0,0,0\"")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT ANNOTATE FONT \"Arial,36,-1,5,50,0,0,0,0,0\"")
        try expectGenericAndVerbatim("0 !LPUB PLI STEP_NUMBER FONT \"Arial,36,-1,5,50,0,0,0,0,0\"")
    }

    // MARK: - The parts list's lines

    @Test("BORDER, BACKGROUND, MARGINS and the FONT of counts and annotations read the same under PLI")
    func partsListBranch() throws {
        let borderLine = "0 !LPUB PLI BORDER GLOBAL ROUND 2 #ff0000 0.0417 20 MARGINS 0.1 0.08"
        let border = try #require(parse(borderLine) as? LPubCalloutBorder)

        #expect(border.branch == .partsList)
        #expect(border.shape == .round)
        #expect(border.lineStyle == .dash)
        expectColor(border.color, 1, 0, 0)
        #expect(abs(border.thickness - 0.0417) < 1e-9)
        #expect(abs(border.radius - 20) < 1e-9)
        #expect(border.hasMargins)
        #expect(abs(border.margins.height - 0.08) < 1e-9)
        #expect(border.write() == borderLine)

        let background = try #require(parse("0 !LPUB PLI BACKGROUND LOCAL COLOR #ccccff") as? LPubCalloutBackground)

        #expect(background.branch == .partsList)
        #expect(background.scope == .local)
        #expect(background.kind == .color)
        expectColor(background.color, 0.8, 0.8, 1)

        let margins = try #require(parse("0 !LPUB PLI MARGINS GLOBAL 0.2 0.1") as? LPubCalloutMargins)

        #expect(margins.branch == .partsList)
        #expect(margins.part == .box)
        #expect(abs(margins.margins.width - 0.2) < 1e-9)

        let countMargins = try #require(parse("0 !LPUB PLI INSTANCE_COUNT MARGINS 0 0") as? LPubCalloutMargins)

        #expect(countMargins.part == .instanceCount)

        let fontLine = "0 !LPUB PLI INSTANCE_COUNT FONT GLOBAL \"Helvetica,48,-1,5,75,0,0,0,0,0\""
        let font = try #require(parse(fontLine) as? LPubCalloutFont)

        #expect(font.branch == .partsList)
        #expect(font.part == .instanceCount)
        #expect(font.family == "Helvetica")
        #expect(font.size == 48)
        #expect(font.isBold)
        #expect(font.write() == fontLine)

        let color = try #require(parse("0 !LPUB PLI INSTANCE_COUNT FONT_COLOR #0000ff") as? LPubCalloutFont)

        #expect(color.isColor)
        expectColor(color.color, 0, 0, 1)

        let annotateLine = "0 !LPUB PLI ANNOTATE FONT GLOBAL \"Arial,30,-1,5,50,1,0,0,0,0\""
        let annotate = try #require(parse(annotateLine) as? LPubCalloutFont)

        #expect(annotate.branch == .partsList)
        #expect(annotate.part == .annotation)
        #expect(annotate.size == 30)
        #expect(annotate.isBold == false)
        #expect(annotate.isItalic)
        #expect(annotate.write() == annotateLine)

        let annotateColor = try #require(parse("0 !LPUB PLI ANNOTATE FONT_COLOR GLOBAL \"#0080ff\"") as? LPubCalloutFont)

        #expect(annotateColor.part == .annotation)
        #expect(annotateColor.isColor)
        expectColor(annotateColor.color, 0, 128.0 / 255.0, 1)

        // Only the annotation's font is read, not the room around it.
        try expectGenericAndVerbatim("0 !LPUB PLI ANNOTATE MARGINS 0.1 0.1")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT ANNOTATE MARGINS 0.1 0.1")
    }

    @Test("The page's MARGINS, BORDER and BACKGROUND read the same under PAGE")
    func pageBranch() throws {
        let margins = try #require(parse("0 !LPUB PAGE MARGINS GLOBAL 0.3500 0.1500") as? LPubCalloutMargins)

        #expect(margins.branch == .page)
        #expect(margins.part == .box)
        #expect(abs(margins.margins.width - 0.35) < 1e-9)
        #expect(margins.write() == "0 !LPUB PAGE MARGINS GLOBAL 0.3500 0.1500")

        let border = try #require(parse("0 !LPUB PAGE BORDER GLOBAL NONE MARGINS 0.0499998 0.0499998")
                                  as? LPubCalloutBorder)
        #expect(border.branch == .page)
        #expect(border.shape == .none)

        let background = try #require(parse("0 !LPUB PAGE BACKGROUND GLOBAL COLOR \"#66ccff\"")
                                      as? LPubCalloutBackground)
        #expect(background.branch == .page)

        // The page's text and its number are other kinds of line.
        try expectGenericAndVerbatim("0 !LPUB PAGE NUMBER MARGINS GLOBAL 0.12 0.12")
        try expectGenericAndVerbatim("0 !LPUB PAGE INSTANCE_COUNT MARGINS 0.1 0.1")
        try expectGenericAndVerbatim("0 !LPUB PAGE INSTANCE_COUNT FONT \"Arial,36,-1,5,50,0,0,0,0,0\"")
    }

    @Test("A CALLOUT line keeps the callout branch")
    func calloutBranch() throws {
        let border = try #require(parse("0 !LPUB CALLOUT BORDER SQUARE Black 0.03") as? LPubCalloutBorder)

        #expect(border.branch == .callout)
        #expect(try #require(parse("0 !LPUB CALLOUT PLI MARGINS 0.1 0.1") as? LPubCalloutMargins).branch == .callout)
    }
}
