//
//  LDrawStepCalloutStyleTests.swift
//  LDrawFeaturesTests
//
//  How a callout's box looks on LPub3D's page: which of the file's lines are
//  in force for one callout, and what LPub3D draws when the file says nothing.
//
//  The fixtures build the directives in memory. Their parts name no file, so
//  nothing is loaded from a part library.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawTestSupport

@Suite("A callout's style", .usesStepSettings)
struct LDrawStepCalloutStyleTests {

    // MARK: - Fixtures

    /// Parses the text, so the line gets the class the file would give it.
    private func lpub(_ text: String) -> LDrawDirective {
        let lines = ["0 !LPUB " + text, "0 STEP"]
        let step = LDrawStep(lines: lines, in: NSRange(location: 0, length: lines.count), parentGroup: nil)

        return (step!.subdirectives() as! [LDrawDirective])[0]
    }

    private func placing(_ name: String) -> LDrawPart {
        let part = LDrawPart()
        part.setDisplayName(name, parse: false, in: nil)
        return part
    }

    @discardableResult
    private func addStep(to model: LDrawModel, _ directives: [LDrawDirective]) -> LDrawStep {
        let step = model.addStep()
        for directive in directives {
            step.add(directive)
        }
        return step
    }

    private func submodel(_ name: String, in file: LDrawFile) -> LDrawMPDModel {
        let model = LDrawMPDModel.model() as! LDrawMPDModel
        model.setModelName(name)
        file.addSubmodel(model)
        return model
    }

    /// A callout of `name`, with these lines between its two lines.
    private func callout(_ name: String, _ lines: [String] = []) -> [LDrawDirective] {
        [lpub("CALLOUT BEGIN"), placing(name)] + lines.map(lpub) + [lpub("CALLOUT END")]
    }

    /// A file whose main model has the steps given, each a list of directives,
    /// and two small submodels to call out. The caller keeps the file.
    private func file(steps: [[LDrawDirective]]) -> (file: LDrawFile, main: LDrawMPDModel, steps: [LDrawStep]) {
        let file = LDrawFile()
        let main = submodel("main.ldr", in: file)

        for name in ["a.ldr", "b.ldr"] {
            addStep(to: submodel(name, in: file), [placing("3003.dat")])
        }

        return (file, main, steps.map { addStep(to: main, $0) })
    }

    private func styles(ofStep step: LDrawStep) -> [LDrawStepCalloutStyle] {
        LDrawStepCallout.callouts(forStep: step).map { LDrawStepCalloutStyle(callout: $0) }
    }

    private func expectColor(_ color: LPubColorComponents,
                             _ red: Double, _ green: Double, _ blue: Double,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(color.red - red) < 0.001, sourceLocation: sourceLocation)
        #expect(abs(color.green - green) < 0.001, sourceLocation: sourceLocation)
        #expect(abs(color.blue - blue) < 0.001, sourceLocation: sourceLocation)
    }

    // MARK: - LPub3D's own style

    @Test("With no lines a box is LPub3D's: a thin black square, cream inside, bold Arial")
    func defaults() throws {
        let fixture = file(steps: [callout("a.ldr")])
        let style = try #require(styles(ofStep: fixture.steps[0]).first)

        #expect(style.borderShape == .square)
        #expect(style.borderLineStyle == .solid)
        expectColor(style.borderColor, 0, 0, 0)
        #expect(abs(style.borderThickness - 1.0 / 32.0) < 1e-9)
        #expect(style.cornerRadius == 0)
        #expect(abs(style.borderMargins.width - 0.05) < 1e-9)
        #expect(style.hasFill)
        expectColor(style.fillColor, 1.0, 1.0, 0.8)
        #expect(abs(style.margins.width - 0.05) < 1e-9)
        #expect(abs(style.assemblyMargins.height - 0.05) < 1e-9)
        #expect(abs(style.separatorThickness - 1.0 / 32.0) < 1e-9)
        #expect(style.stepNumberText.fontFamily == "Arial")
        #expect(abs(style.stepNumberText.fontSize - 36.0 / 150.0) < 1e-9)
        #expect(style.stepNumberText.isBold)
        #expect(abs(style.countText.fontSize - 24.0 / 150.0) < 1e-9)
    }

    // MARK: - The file's lines

    @Test("The header's lines style every callout")
    func headerLinesApply() throws {
        let header = ["CALLOUT BORDER GLOBAL ROUND #fffecc 0.02 15 MARGINS 0.1 0.2",
                      "CALLOUT MARGINS GLOBAL 0.3 0.4",
                      "CALLOUT ASSEM MARGINS GLOBAL 0.15 0.16",
                      "CALLOUT PLI MARGINS GLOBAL 0.11 0.12",
                      "CALLOUT SEPARATOR GLOBAL 0.015 #4c4c4c 0.2 0.1",
                      "CALLOUT STEP_NUMBER FONT GLOBAL \"Arial,45,-1,5,50,0,0,0,0,0\"",
                      "CALLOUT STEP_NUMBER FONT_COLOR GLOBAL #336699",
                      "RESOLUTION GLOBAL 300 DPI"].map(lpub)
        let fixture = file(steps: [header, callout("a.ldr")])
        let style = try #require(styles(ofStep: fixture.steps[1]).first)

        #expect(style.borderShape == .round)
        expectColor(style.borderColor, 1.0, 254.0 / 255.0, 0.8)
        #expect(abs(style.borderThickness - 0.02) < 1e-9)
        #expect(abs(style.cornerRadius - 15.0 / 300.0) < 1e-9)
        #expect(abs(style.borderMargins.width - 0.1) < 1e-9)
        #expect(abs(style.borderMargins.height - 0.2) < 1e-9)
        #expect(abs(style.margins.height - 0.4) < 1e-9)
        #expect(abs(style.assemblyMargins.width - 0.15) < 1e-9)
        #expect(abs(style.partsListMargins.height - 0.12) < 1e-9)
        #expect(abs(style.separatorThickness - 0.015) < 1e-9)
        expectColor(style.separatorColor, 76.0 / 255.0, 76.0 / 255.0, 76.0 / 255.0)
        #expect(abs(style.separatorMargins.width - 0.2) < 1e-9)
        #expect(abs(style.stepNumberText.fontSize - 45.0 / 300.0) < 1e-9)
        #expect(style.stepNumberText.isBold == false)
        expectColor(style.stepNumberText.color, 0.2, 0.4, 0.6)
    }

    @Test("A line between a callout's two lines is for that callout alone")
    func ownLinesWin() throws {
        let header = [lpub("CALLOUT BORDER GLOBAL ROUND #fffecc 0.02 10 MARGINS 0.1 0.1")]
        let blue = ["CALLOUT BORDER LOCAL ROUND #daf3ff 0.02 10 MARGINS 0.1 0.1",
                    "CALLOUT BACKGROUND LOCAL COLOR \"#daf3ff\""]
        let fixture = file(steps: [header, callout("a.ldr") + callout("b.ldr", blue)])
        let both = styles(ofStep: fixture.steps[1])

        try #require(both.count == 2)
        expectColor(both[0].borderColor, 1.0, 254.0 / 255.0, 0.8)
        expectColor(both[0].fillColor, 1.0, 1.0, 0.8)
        expectColor(both[1].borderColor, 218.0 / 255.0, 243.0 / 255.0, 1.0)
        expectColor(both[1].fillColor, 218.0 / 255.0, 243.0 / 255.0, 1.0)
    }

    @Test("A line before a callout in its step counts, and one after it does not")
    func stepLinesAheadOfTheCallout() throws {
        let before = lpub("CALLOUT BACKGROUND LOCAL COLOR \"#ff0000\"")
        let after = lpub("CALLOUT BACKGROUND LOCAL COLOR \"#00ff00\"")
        let fixture = file(steps: [[before] + callout("a.ldr") + [after] + callout("b.ldr")])
        let both = styles(ofStep: fixture.steps[0])

        try #require(both.count == 2)
        expectColor(both[0].fillColor, 1.0, 0.0, 0.0)
        expectColor(both[1].fillColor, 0.0, 1.0, 0.0)
    }

    @Test("A line with no LOCAL inside a callout carries to later steps")
    func bracketLinesCarry() throws {
        let fixture = file(steps: [callout("a.ldr", ["CALLOUT BACKGROUND COLOR \"#0000ff\""]),
                                   callout("b.ldr"),
                                   callout("a.ldr", ["CALLOUT BACKGROUND LOCAL COLOR \"#ff0000\""]),
                                   callout("b.ldr")])

        expectColor(try #require(styles(ofStep: fixture.steps[1]).first).fillColor, 0.0, 0.0, 1.0)
        expectColor(try #require(styles(ofStep: fixture.steps[2]).first).fillColor, 1.0, 0.0, 0.0)

        // A LOCAL line ends with its step.
        expectColor(try #require(styles(ofStep: fixture.steps[3]).first).fillColor, 0.0, 0.0, 1.0)
    }

    @Test("A border line with no MARGINS keeps the margins of the line before it")
    func bordersKeepTheirMargins() throws {
        let header = [lpub("CALLOUT BORDER GLOBAL SQUARE Black 0.02 MARGINS 0.3 0.4")]
        let fixture = file(steps: [header, callout("a.ldr", ["CALLOUT BORDER LOCAL ROUND #ff0000 0.05 10"])])
        let style = try #require(styles(ofStep: fixture.steps[1]).first)

        #expect(style.borderShape == .round)
        #expect(abs(style.borderThickness - 0.05) < 1e-9)
        #expect(abs(style.borderMargins.width - 0.3) < 1e-9)
        #expect(abs(style.borderMargins.height - 0.4) < 1e-9)
    }

    // MARK: - The fill

    @Test("A box is see-through when the file says so")
    func transparentBackground() throws {
        let fixture = file(steps: [callout("a.ldr", ["CALLOUT BACKGROUND TRANSPARENT"])])

        #expect(try #require(styles(ofStep: fixture.steps[0]).first).hasFill == false)
    }

    @Test("A callout takes the color one level deeper than the model it is in")
    func fillFollowsTheDepth() throws {
        let fixture = file(steps: [[placing("a.ldr")]])
        let inner = try #require(fixture.file.submodels().first { ($0 as? LDrawMPDModel)?.modelName() == "a.ldr" }
                                 as? LDrawMPDModel)
        let step = addStep(to: inner, callout("b.ldr"))

        #expect(LDrawStepPartListPolicy.submodelDepth(of: fixture.main) == 0)
        #expect(LDrawStepPartListPolicy.submodelDepth(of: inner) == 1)
        expectColor(try #require(styles(ofStep: step).first).fillColor, 1.0, 0.8, 0.8)
    }

    @Test("SUBMODEL_BACKGROUND_COLOR gives the colors for each depth")
    func submodelColorsFromTheFile() throws {
        let header = [lpub("CALLOUT SUBMODEL_BACKGROUND_COLOR GLOBAL #ffffff #00ff00 #0000ff")]
        let fixture = file(steps: [header, callout("a.ldr")])

        expectColor(try #require(styles(ofStep: fixture.steps[1]).first).fillColor, 0.0, 1.0, 0.0)
    }

    // MARK: - Units

    @Test("A file measured in centimeters gives its lengths in them")
    func centimeterFiles() throws {
        let header = ["RESOLUTION GLOBAL 60 DPCM",
                      "CALLOUT BORDER GLOBAL ROUND Black 0.254 30 MARGINS 2.54 5.08"].map(lpub)
        let fixture = file(steps: [header, callout("a.ldr")])
        let style = try #require(styles(ofStep: fixture.steps[1]).first)

        #expect(abs(style.borderThickness - 0.1) < 1e-9)
        #expect(abs(style.borderMargins.width - 1.0) < 1e-9)
        #expect(abs(style.borderMargins.height - 2.0) < 1e-9)

        // 30 dots at 60 to the centimeter is half a centimeter.
        #expect(abs(style.cornerRadius - 0.5 / 2.54) < 1e-9)
    }

    @Test("In a file measured in centimeters LPub3D's own sizes are still inches")
    func centimeterFilesKeepTheDefaults() throws {
        let fixture = file(steps: [[lpub("RESOLUTION GLOBAL 60 DPCM")], callout("a.ldr")])
        let style = try #require(styles(ofStep: fixture.steps[1]).first)

        #expect(abs(style.borderThickness - 1.0 / 32.0) < 1e-9)
        #expect(abs(style.borderMargins.width - 0.05) < 1e-9)
        #expect(abs(style.separatorThickness - 1.0 / 32.0) < 1e-9)
        #expect(abs(style.separatorMargins.width - 0.05) < 1e-9)
    }
}
