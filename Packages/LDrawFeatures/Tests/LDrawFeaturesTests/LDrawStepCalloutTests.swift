//
//  LDrawStepCalloutTests.swift
//  LDrawFeaturesTests
//
//  Tests for what a step's callouts hold.
//
//  The fixtures are built, not parsed, and run with no part catalog, so a
//  submodel's row has no bounds.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures

@Suite("A step's callouts")
struct LDrawStepCalloutTests {

    // MARK: - Fixtures

    private static let blue: Int32 = 1
    private static let red: Int32 = 4

    private func part(_ name: String, _ code: Int32 = LDrawStepCalloutTests.red) -> LDrawPart {
        let color = LDrawColor()
        color.setColorCode(LDrawColorT(rawValue: code)!)

        let part = LDrawPart()
        part.setDisplayName(name, parse: false, in: nil)
        part.setLDrawColor(color)
        return part
    }

    private func lpub<Command: LPubCommand>(_ text: String) -> Command {
        let command = Command()
        command.lPubCommandString = text
        return command
    }

    private func begin(_ mode: String? = nil) -> LPubCallout {
        lpub("CALLOUT BEGIN" + (mode.map { " \($0)" } ?? ""))
    }

    private func end() -> LPubCallout {
        lpub("CALLOUT END")
    }

    @discardableResult
    private func addStep(to model: LDrawModel, _ directives: [LDrawDirective]) -> LDrawStep {
        let step = model.addStep()
        for directive in directives {
            step.add(directive)
        }
        return step
    }

    /// The caller keeps the file: a directive's link to its parent is weak.
    @discardableResult
    private func submodel(_ name: String, in file: LDrawFile) -> LDrawMPDModel {
        let model = LDrawMPDModel.model() as! LDrawMPDModel
        model.setModelName(name)
        file.addSubmodel(model)
        return model
    }

    /// Builds main.ldr and sub.ldr. The main model's only step holds the given
    /// directives, and sub.ldr builds something in two of its steps.
    private func fixture(_ directives: [LDrawDirective]) -> (file: LDrawFile, step: LDrawStep) {
        let file = LDrawFile()
        let main = submodel("main.ldr", in: file)
        let sub = submodel("sub.ldr", in: file)

        addStep(to: sub, [part("3003.dat")])
        addStep(to: sub, [part("3004.dat")])

        return (file, addStep(to: main, directives))
    }

    // MARK: - What is collected

    @Test("A callout holds the submodels placed between its BEGIN and END")
    func calloutHoldsItsSubmodels() throws {
        let fixture = fixture([part("3001.dat"), begin(), part("sub.ldr"), end()])

        let callouts = LDrawStepCallout.callouts(forStep: fixture.step)
        let callout = try #require(callouts.first)

        #expect(callouts.count == 1)
        #expect(callout.mode == .unassembled)
        #expect(callout.entries.map(\.partName) == ["sub.ldr"])
        #expect(callout.entries.first?.isSubmodel == true)
        #expect((callout.submodels.first as? LDrawMPDModel)?.modelName() == "sub.ldr")
        #expect(callout.placements.count == 1)
        #expect(callout.endDirective != nil)
    }

    @Test("Two placements of one submodel are one row counted twice, and two arrows")
    func instancesShareARow() throws {
        let fixture = fixture([begin(), part("sub.ldr"), part("sub.ldr"), end()])

        let callout = try #require(LDrawStepCallout.callouts(forStep: fixture.step).first)

        #expect(callout.entries.count == 1)
        #expect(callout.entries.first?.quantity == 2)
        #expect(callout.placements.count == 2)
    }

    @Test("The same submodel in two colors is two rows")
    func colorsAreSeparateRows() throws {
        let fixture = fixture([begin(), part("sub.ldr", Self.red), part("sub.ldr", Self.blue), end()])

        let callout = try #require(LDrawStepCallout.callouts(forStep: fixture.step).first)

        #expect(callout.entries.count == 2)
        #expect(callout.submodels.count == 2)
    }

    /// LPub3D treats such a part as an ordinary part of the step.
    @Test("A part that places no submodel is not called out")
    func ordinaryPartsAreNotCalledOut() {
        let onlyAPart = fixture([begin(), part("3001.dat"), end()])
        #expect(LDrawStepCallout.callouts(forStep: onlyAPart.step).isEmpty)

        let mixed = fixture([begin(), part("3001.dat"), part("sub.ldr"), end()])
        #expect(LDrawStepCallout.callouts(forStep: mixed.step).first?.placements.count == 1)
    }

    @Test("A submodel outside any callout is not called out")
    func submodelsOutsideAreLeftAlone() {
        let fixture = fixture([part("sub.ldr"), begin(), end(), part("sub.ldr")])

        #expect(LDrawStepCallout.callouts(forStep: fixture.step).isEmpty)
    }

    @Test("Each BEGIN and END pair is its own callout, in file order")
    func severalCallouts() {
        let file = LDrawFile()
        let main = submodel("main.ldr", in: file)
        let first = submodel("first.ldr", in: file)
        let second = submodel("second.ldr", in: file)
        addStep(to: first, [part("3003.dat")])
        addStep(to: second, [part("3004.dat")])

        let step = addStep(to: main, [begin(), part("first.ldr"), end(),
                                      begin("ROTATED"), part("second.ldr"), end()])
        let callouts = LDrawStepCallout.callouts(forStep: step)

        #expect(callouts.map { $0.entries.first?.partName } == ["first.ldr", "second.ldr"])
        #expect(callouts.map(\.mode) == [.unassembled, .rotated])
    }

    @Test("The pointer and placement lines inside belong to the callout")
    func linesInsideBelongToTheCallout() throws {
        let pointer: LPubCalloutPointer = lpub("CALLOUT POINTER TOP_LEFT 0.367 0.656 0")
        let second: LPubCalloutPointer = lpub("CALLOUT POINTER TOP 0.392 0.521 0.399 0")
        let placement: LPubPlacement = lpub("CALLOUT PLACEMENT BOTTOM CENTER ASSEM OUTSIDE 0.1 0.2")
        let outside: LPubCalloutPointer = lpub("CALLOUT POINTER LEFT 0.5 0.5 0.5 0")

        let fixture = fixture([outside, begin(), part("sub.ldr"), pointer, second, placement, end()])
        let callout = try #require(LDrawStepCallout.callouts(forStep: fixture.step).first)

        #expect(callout.pointers.count == 2)
        #expect(callout.pointers.first === pointer)
        #expect(callout.placement === placement)
    }

    @Test("A callout that never closes still holds what follows its BEGIN")
    func unterminatedCallout() throws {
        let fixture = fixture([begin(), part("sub.ldr")])

        let callout = try #require(LDrawStepCallout.callouts(forStep: fixture.step).first)

        #expect(callout.placements.count == 1)
        #expect(callout.endDirective == nil)
    }

    @Test("A nil step has no callouts, and an END with nothing open is ignored")
    func edgeCases() {
        #expect(LDrawStepCallout.callouts(forStep: nil).isEmpty)
        #expect(LDrawStepCallout.callouts(forVisibleStepOf: nil).isEmpty)

        let fixture = fixture([end(), part("sub.ldr")])
        #expect(LDrawStepCallout.callouts(forStep: fixture.step).isEmpty)
    }

    // MARK: - What the box is told

    @Test("The steps run down unless an ALLOC line says across")
    func allocDecidesTheDirection() throws {
        let plain = fixture([begin(), part("sub.ldr"), end()])
        #expect(try #require(LDrawStepCallout.callouts(forStep: plain.step).first).isVertical)

        let across: LPubCalloutAlloc = lpub("CALLOUT ALLOC HORIZONTAL")
        let inside = fixture([begin(), part("sub.ldr"), across, end()])
        #expect(try #require(LDrawStepCallout.callouts(forStep: inside.step).first).isVertical == false)

        // A line before the callout holds for it too.
        let carried: LPubCalloutAlloc = lpub("CALLOUT ALLOC GLOBAL HORIZONTAL")
        let before = fixture([carried, begin(), part("sub.ldr"), end()])
        #expect(try #require(LDrawStepCallout.callouts(forStep: before.step).first).isVertical == false)

        // The callout's own line wins.
        let carriedAcross: LPubCalloutAlloc = lpub("CALLOUT ALLOC GLOBAL HORIZONTAL")
        let down: LPubCalloutAlloc = lpub("CALLOUT ALLOC VERTICAL")
        let both = fixture([carriedAcross, begin(), part("sub.ldr"), down, end()])
        #expect(try #require(LDrawStepCallout.callouts(forStep: both.step).first).isVertical)
    }

    @Test("Steps are numbered unless the file turns step numbers off")
    func stepNumbersFollowTheFile() throws {
        let plain = fixture([begin(), part("sub.ldr"), end()])
        #expect(try #require(LDrawStepCallout.callouts(forStep: plain.step).first).showsStepNumbers)

        let off: LPubAssemShowStepNumber = lpub("ASSEM SHOW_STEP_NUMBER GLOBAL FALSE")
        let hidden = fixture([off, begin(), part("sub.ldr"), end()])
        #expect(try #require(LDrawStepCallout.callouts(forStep: hidden.step).first).showsStepNumbers == false)
    }

    /// LPub3D gives each step in the box its own parts list unless the file
    /// says PER_STEP FALSE, which hands them to the step that holds the callout.
    @Test("A box lists its submodels' parts unless the step's list has them")
    func boxListsItsOwnParts() throws {
        let kept = fixture([begin(), part("sub.ldr"), part("sub.ldr"), end()])
        let callout = try #require(LDrawStepCallout.callouts(forStep: kept.step).first)
        let quantities = Dictionary(uniqueKeysWithValues: callout.partEntries.map { ($0.partName, $0.quantity) })

        #expect(callout.listsOwnParts)
        #expect(quantities == ["3003.dat": 2, "3004.dat": 2])

        let perStep: LPubCalloutPliPerStep = lpub("CALLOUT PLI PER_STEP FALSE")
        let handedOver = fixture([perStep, begin(), part("sub.ldr"), end()])
        let emptied = try #require(LDrawStepCallout.callouts(forStep: handedOver.step).first)

        #expect(emptied.listsOwnParts == false)
        #expect(emptied.partEntries.isEmpty)
    }

    @Test("A callout that shows its submodel finished lists no parts")
    func finishedCalloutsListNoParts() throws {
        for mode in ["ASSEMBLED", "ROTATED"] {
            let fixture = fixture([begin(mode), part("sub.ldr"), end()])
            let callout = try #require(LDrawStepCallout.callouts(forStep: fixture.step).first)

            #expect(callout.listsOwnParts == false, "\(mode)")
            #expect(callout.partEntries.isEmpty, "\(mode)")
        }
    }

    // MARK: - Steps

    /// A new model starts with a blank step, and a file ends with one after
    /// its last STEP line.
    @Test("Only the steps that build something are counted")
    func stepCountLeavesOutBlankSteps() throws {
        let fixture = fixture([begin(), part("sub.ldr"), end()])

        let callout = try #require(LDrawStepCallout.callouts(forStep: fixture.step).first)

        #expect(callout.stepCount == 2)
    }

    @Test("A submodel that is really a part is not called out")
    func partLikeSubmodelIsNotCalledOut() {
        let file = LDrawFile()
        let main = submodel("main.ldr", in: file)
        let custom = submodel("custom.ldr", in: file)
        addStep(to: custom, [LDrawLine()])

        let step = addStep(to: main, [begin(), part("custom.ldr"), end()])

        #expect(LDrawStepCallout.callouts(forStep: step).isEmpty)
    }
}
