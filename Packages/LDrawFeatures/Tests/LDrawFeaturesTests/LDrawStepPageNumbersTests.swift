//
//  LDrawStepPageNumbersTests.swift
//  LDrawFeaturesTests
//
//  Which pages of the instruction book show a step: a submodel's pages come
//  before the step that places it, and a called-out submodel is on the page of
//  the step that places it.
//
//  The fixtures build the directives in memory. Their parts name no file, so
//  nothing is loaded from a part library.
//
//  Created by Sergey Slobodenyuk on 2026-10-18.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures

@Suite("The book's page numbers")
struct LDrawStepPageNumbersTests {

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

    private func brick() -> LDrawPart {
        placing("3001.dat")
    }

    /// A callout that shows the steps of `name`.
    private func callout(_ name: String) -> [LDrawDirective] {
        [lpub("CALLOUT BEGIN"), placing(name), lpub("CALLOUT END")]
    }

    /// Adds a model with these steps to the file. The first model added is the
    /// one the book is made from.
    @discardableResult
    private func model(_ name: String, in file: LDrawFile, _ steps: [[LDrawDirective]]) -> [LDrawStep] {
        let model = LDrawMPDModel.model() as! LDrawMPDModel
        model.setModelName(name)
        file.addSubmodel(model)

        return steps.map { directives in
            let step = model.addStep()
            for directive in directives {
                step.add(directive)
            }
            return step
        }
    }

    private func pages(_ step: LDrawStep) -> [LDrawStepPageNumber] {
        LDrawStepPageNumbers(file: step.enclosingFile()).pages(showing: step)
    }

    private func text(_ step: LDrawStep) -> String {
        LDrawStepPageNumbers.text(for: pages(step))
    }

    // MARK: - Tests

    @Test("A submodel's pages come before the step that places it")
    func submodelPagesComeFirst() {
        let file = LDrawFile()
        let main = model("main.ldr", in: file, [[brick()], [brick(), placing("sub.ldr")], [brick()]])
        let sub = model("sub.ldr", in: file, [[brick()], [brick()]])

        #expect(text(main[0]) == "1")
        #expect(text(sub[0]) == "2")
        #expect(text(sub[1]) == "3")
        #expect(text(main[1]) == "4")
    }

    @Test("A step that places nothing has no page, and the finished model is the last step's")
    func emptyStepsAndTheFinishedModel() {
        let file = LDrawFile()
        let main = model("main.ldr", in: file, [[brick()], [lpub("PLI SHOW FALSE")], [brick()], []])

        #expect(text(main[1]) == "")
        #expect(text(main[2]) == "2")
        #expect(text(main[3]) == "3")

        let pages = self.pages(main[3])

        #expect(pages.count == 1)
        #expect(pages.first?.isInCallout == false)
    }

    @Test("The last step's own page comes before the finished model's")
    func lastStepThatPlacesSomething() {
        let file = LDrawFile()
        let main = model("main.ldr", in: file, [[brick()], [brick()]])

        #expect(text(main[1]) == "2/3")
    }

    @Test("A called-out submodel is in the box on the page of the step that places it")
    func calledOutSubmodel() {
        let file = LDrawFile()
        let main = model("main.ldr", in: file, [[brick()], [brick()] + callout("door.ldr")])
        let door = model("door.ldr", in: file, [[brick()], [], [brick()]])
        let pages = self.pages(door[0])

        #expect(pages.count == 1)
        #expect(pages.first?.number == 2)
        #expect(pages.first?.isInCallout == true)
        #expect(text(door[0]) == "➟2")
        #expect(text(door[1]) == "")
        #expect(text(door[2]) == "➟2")
        #expect(text(main[1]) == "2/3")
    }

    @Test("An ASSEMBLED callout gives its submodel pages of its own")
    func assembledCallout() {
        let file = LDrawFile()
        let main = model("main.ldr", in: file, [
            [brick()],
            [lpub("CALLOUT BEGIN ASSEMBLED"), placing("wheel.ldr"), lpub("CALLOUT END")],
        ])
        let wheel = model("wheel.ldr", in: file, [[brick()]])

        #expect(text(wheel[0]) == "2")
        #expect(text(main[1]) == "3/4")
    }

    @Test("A submodel placed in several steps shows every page that has it")
    func placedInSeveralSteps() {
        let file = LDrawFile()

        model("main.ldr", in: file, [
            [brick()] + callout("seat.ldr"),
            [brick()] + callout("seat.ldr"),
            [brick(), placing("seat.ldr")],
            [brick(), placing("seat.ldr")],
        ])
        let seat = model("seat.ldr", in: file, [[brick()]])

        // The callouts show it twice, then it gets its own page once.
        #expect(text(seat[0]) == "➟1/➟2/3")
    }

    @Test("A submodel placed, then called out, shows the callout's page too")
    func placedThenCalledOut() {
        let file = LDrawFile()
        let main = model("main.ldr", in: file, [[placing("sub.ldr")], [brick()] + callout("sub.ldr")])
        let sub = model("sub.ldr", in: file, [[brick()]])

        #expect(text(sub[0]) == "1/➟3")
        #expect(text(main[0]) == "2")
        #expect(text(main[1]) == "3/4")
    }

    @Test("A part or a placement inside a texture counts, as a hose does")
    func texturesAndHoses() {
        let file = LDrawFile()
        let texture = LDrawTexture()
        let placingTexture = LDrawTexture()

        texture.add(brick() as LDrawDirective)
        placingTexture.add(placing("sub.ldr") as LDrawDirective)

        let main = model("main.ldr", in: file, [[texture], [LDrawLSynth()], [placingTexture]])
        let sub = model("sub.ldr", in: file, [[brick()], [LDrawLSynth()]])

        #expect(text(main[0]) == "1")
        #expect(text(main[1]) == "2")
        #expect(text(sub[0]) == "3")
        #expect(text(sub[1]) == "4")
        #expect(text(main[2]) == "5/6")
    }

    @Test("A hose step of a called-out submodel is in the box")
    func calledOutHose() {
        let file = LDrawFile()

        model("main.ldr", in: file, [[brick()] + callout("hose.ldr")])
        let hose = model("hose.ldr", in: file, [[brick()], [LDrawLSynth()]])

        #expect(text(hose[0]) == "➟1")
        #expect(text(hose[1]) == "➟1")
    }

    @Test("A callout that places a submodel twice shows its steps once")
    func twiceInOneCallout() {
        let file = LDrawFile()

        model("main.ldr", in: file, [
            [brick(), lpub("CALLOUT BEGIN"), placing("leg.ldr"), placing("leg.ldr"), lpub("CALLOUT END")],
        ])
        let leg = model("leg.ldr", in: file, [[brick()]])

        #expect(text(leg[0]) == "➟1")
    }

    @Test("A model the first model never places is on no page")
    func unplacedModel() {
        let file = LDrawFile()

        model("main.ldr", in: file, [[brick()]])
        let spare = model("spare.ldr", in: file, [[brick()]])

        #expect(pages(spare[0]).isEmpty)
        #expect(LDrawStepPageNumbers(file: nil).pages(showing: spare[0]).isEmpty)
    }
}
