//
//  LDrawStepCalloutDividerTests.swift
//  LDrawStepEditingTests
//
//  Which lines put a divider before a step of a called-out submodel, and what
//  adding and removing one writes.
//
//  The fixtures build the directives in memory. Their parts name no file, so
//  nothing is loaded from a part library.
//
//  Created by Sergey Slobodenyuk on 2026-10-04.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawStepEditing

@Suite("Dividers in a called-out submodel")
struct LDrawStepCalloutDividerTests {

    // MARK: - Fixtures

    private func part(_ name: String = "3003.dat") -> LDrawPart {
        let color = LDrawColor()
        color.setColorCode(LDrawColorT(rawValue: 4)!)

        let part = LDrawPart()
        part.setDisplayName(name, parse: false, in: nil)
        part.setLDrawColor(color)
        return part
    }

    /// Parses the text, so the line gets the class the file would give it.
    private func lpub(_ text: String) -> LDrawDirective {
        let lines = ["0 !LPUB " + text, "0 STEP"]
        let step = LDrawStep(lines: lines, in: NSRange(location: 0, length: lines.count), parentGroup: nil)

        return (step!.subdirectives() as! [LDrawDirective])[0]
    }

    private func divider() -> LDrawDirective {
        lpub("CALLOUT DIVIDER")
    }

    /// A submodel with these steps, in a file. The caller keeps the file.
    private func submodel(_ steps: [[LDrawDirective]]) -> (file: LDrawFile, steps: [LDrawStep]) {
        let file = LDrawFile()
        let model = LDrawMPDModel.model() as! LDrawMPDModel
        model.setModelName("sub.ldr")
        file.addSubmodel(model)

        let added: [LDrawStep] = steps.map { directives in
            let step = model.addStep()
            for directive in directives {
                step.add(directive)
            }
            return step
        }

        return (file, added)
    }

    /// Does what the document does with an edit, without the undo.
    private func apply(_ edit: LDrawStepCalloutEdit) {
        for directive in edit.directivesToRemove {
            directive.enclosingDirective()?.remove(directive)
        }
        for (directive, index) in zip(edit.directivesToInsert, edit.insertIndexes) {
            edit.targetStep?.insert(directive, at: index.intValue)
        }
    }

    private func texts(_ step: LDrawStep) -> [String] {
        (step.subdirectives() as! [LDrawDirective]).map { directive in
            (directive as? LPubCommand)?.lPubCommandString ?? "part"
        }
    }

    // MARK: - Which lines divide

    @Test("The step shown before a step is the nearest earlier one that builds something")
    func stepShownBefore() {
        let model = submodel([[part()], [lpub("PLI BEGIN IGN")], [part()], [part()]])

        #expect(LDrawStepCallout.stepShown(before: model.steps[0]) == nil)
        // Past the step that builds nothing.
        #expect(LDrawStepCallout.stepShown(before: model.steps[2]) === model.steps[0])
        #expect(LDrawStepCallout.stepShown(before: model.steps[3]) === model.steps[2])
    }

    @Test("A step whose parts are all dropped by REMOVE GROUP builds nothing")
    func removedPartsBuildNothing() {
        let removed = part()
        let line = divider()
        let model = submodel([[part()], [removed], [line, part()]])

        removed.groupVisibility = .hidden

        #expect(LDrawStepCallout.stepBuildsSomething(model.steps[1]) == false)
        #expect(LDrawStepCallout.stepShown(before: model.steps[2]) === model.steps[0])
        #expect(LDrawStepCalloutEdit.edit(addingDividerBefore: model.steps[1]).kind == .none)
        #expect(LDrawStepCallout.dividerLines(before: model.steps[2]).first === line)
    }

    @Test("A DIVIDER at the top of a step puts a divider before it")
    func dividerAtTheTop() {
        let line = divider()
        let model = submodel([[part()], [line, part()], [part()]])

        #expect(LDrawStepCallout.dividerLines(before: model.steps[1]).count == 1)
        #expect(LDrawStepCallout.dividerLines(before: model.steps[1]).first === line)
        #expect(LDrawStepCallout.dividerLines(before: model.steps[2]).isEmpty, "the step after is not divided")
    }

    @Test("A DIVIDER after something built in the step before counts too")
    func dividerAfterTheParts() {
        let atEnd = divider()
        let between = divider()
        let ended = submodel([[part(), atEnd], [part()]])
        let split = submodel([[part(), between, part()], [part()]])

        #expect(LDrawStepCallout.dividerLines(before: ended.steps[1]).first === atEnd)
        #expect(LDrawStepCallout.dividerLines(before: split.steps[1]).first === between)
    }

    @Test("A DIVIDER in a step that builds nothing counts for the step after it")
    func dividerInAnEmptyStep() {
        let line = divider()
        let model = submodel([[part()], [line], [part()]])

        #expect(LDrawStepCallout.dividerLines(before: model.steps[2]).first === line)
    }

    @Test("A DIVIDER before anything is built in the step before belongs to that step")
    func dividerOfTheStepBefore() {
        let model = submodel([[part()], [divider(), part()], [part()]])

        #expect(LDrawStepCallout.dividerLines(before: model.steps[2]).isEmpty)
    }

    @Test("A DIVIDER after the first thing a step builds does not divide that step")
    func dividerBelowTheFirstPart() {
        let model = submodel([[part()], [part(), divider()]])

        #expect(LDrawStepCallout.dividerLines(before: model.steps[1]).isEmpty)
    }

    @Test("The first step shown has no divider, whatever comes before it")
    func firstStepHasNoDivider() {
        let model = submodel([[divider()], [divider(), part()]])

        #expect(LDrawStepCallout.dividerLines(before: model.steps[1]).isEmpty)
    }

    @Test("The divider's arrows come with it")
    func dividerArrowsComeWithIt() {
        let line = divider()
        let arrow = lpub("CALLOUT DIVIDER_POINTER TOP 0.5 0.4 0.6 0")
        let look = lpub("CALLOUT DIVIDER_POINTER_ATTRIBUTE LINE 1 Black 0.03")
        let model = submodel([[part()], [line, arrow, look, part()]])
        let lines = LDrawStepCallout.dividerLines(before: model.steps[1])

        #expect(lines.count == 3)
        #expect(lines[0] === line && lines[1] === arrow && lines[2] === look, "in file order")
    }

    @Test("Arrows with no DIVIDER line make no divider, and neither does DIVIDER STEPS")
    func whatIsNoDivider() {
        let arrows = submodel([[part()], [lpub("CALLOUT DIVIDER_POINTER TOP 0.5 0.4 0.6 0"), part()]])
        let betweenSteps = submodel([[part()], [lpub("CALLOUT DIVIDER STEPS"), part()]])

        #expect(LDrawStepCallout.dividerLines(before: arrows.steps[1]).isEmpty)
        #expect(LDrawStepCallout.dividerLines(before: betweenSteps.steps[1]).isEmpty)
    }

    // MARK: - Adding

    @Test("Adding writes one DIVIDER line at the top of the step")
    func addingWritesOneLine() throws {
        let model = submodel([[part()], [lpub("PLI BEGIN IGN"), part()]])
        let edit = LDrawStepCalloutEdit.edit(addingDividerBefore: model.steps[1])

        #expect(edit.kind == .rewrite)
        #expect(edit.directivesToRemove.isEmpty)
        #expect(edit.insertIndexes == [0])
        #expect(edit.targetStep === model.steps[1], "the line goes into the submodel's step")
        #expect(edit.undoActionKey == "UndoStepCalloutDividerAdd")

        let line = try #require(edit.directivesToInsert.first as? LPubCallout)
        #expect(edit.directivesToInsert.count == 1)
        #expect(line.line == .divider)
        #expect(line.lPubCommandString == "CALLOUT DIVIDER")

        apply(edit)

        #expect(texts(model.steps[1]) == ["CALLOUT DIVIDER", "PLI BEGIN IGN", "part"])
        #expect(LDrawStepCallout.dividerLines(before: model.steps[1]).first === line)
    }

    @Test("Adding does nothing for the first step shown, a step that builds nothing, and a step with a divider")
    func addingWhereItCannot() {
        let model = submodel([[lpub("PLI BEGIN IGN")], [part()], [divider(), part()], [lpub("PLI END")]])

        #expect(LDrawStepCalloutEdit.edit(addingDividerBefore: model.steps[1]).kind == .none, "the first shown")
        #expect(LDrawStepCalloutEdit.edit(addingDividerBefore: model.steps[2]).kind == .none, "has one")
        #expect(LDrawStepCalloutEdit.edit(addingDividerBefore: model.steps[3]).kind == .none, "builds nothing")
    }

    // MARK: - Removing

    @Test("Removing takes out every line of the divider, wherever it is")
    func removingTakesEveryLine() {
        let atEnd = divider()
        let alone = divider()
        let atTop = divider()
        let arrow = lpub("CALLOUT DIVIDER_POINTER TOP 0.5 0.4 0.6 0")
        let model = submodel([[part(), atEnd], [alone], [atTop, arrow, part()]])
        let edit = LDrawStepCalloutEdit.edit(removingDividerBefore: model.steps[2])

        #expect(edit.kind == .rewrite)
        #expect(edit.directivesToInsert.isEmpty)
        #expect(edit.directivesToRemove.count == 4)
        #expect(edit.undoActionKey == "UndoStepCalloutDividerRemove")

        apply(edit)

        #expect(texts(model.steps[0]) == ["part"])
        #expect(texts(model.steps[1]).isEmpty)
        #expect(texts(model.steps[2]) == ["part"])
        #expect(LDrawStepCallout.dividerLines(before: model.steps[2]).isEmpty)
    }

    @Test("Removing leaves the lines that are no part of the divider")
    func removingLeavesTheRest() {
        let model = submodel([[part()],
                              [lpub("CALLOUT DIVIDER STEPS"), divider(), lpub("PLI BEGIN IGN"), part(), divider()],
                              [part()]])

        apply(LDrawStepCalloutEdit.edit(removingDividerBefore: model.steps[1]))

        // The last line divides the next step, not this one.
        #expect(texts(model.steps[1]) == ["CALLOUT DIVIDER STEPS", "PLI BEGIN IGN", "part", "CALLOUT DIVIDER"])
        #expect(LDrawStepCallout.dividerLines(before: model.steps[2]).count == 1)
    }

    @Test("Removing does nothing for a step with no divider")
    func removingWithNoDivider() {
        let model = submodel([[part()], [part()]])

        #expect(LDrawStepCalloutEdit.edit(removingDividerBefore: model.steps[0]).kind == .none)
        #expect(LDrawStepCalloutEdit.edit(removingDividerBefore: model.steps[1]).kind == .none)
    }

    @Test("A divider that is added and taken out again leaves the step as it was")
    func addThenRemove() {
        let model = submodel([[part()], [lpub("PLI BEGIN IGN"), part()]])
        let before = texts(model.steps[1])

        apply(LDrawStepCalloutEdit.edit(addingDividerBefore: model.steps[1]))
        #expect(LDrawStepCalloutEdit.edit(addingDividerBefore: model.steps[1]).kind == .none)

        apply(LDrawStepCalloutEdit.edit(removingDividerBefore: model.steps[1]))
        #expect(texts(model.steps[1]) == before)
    }
}
