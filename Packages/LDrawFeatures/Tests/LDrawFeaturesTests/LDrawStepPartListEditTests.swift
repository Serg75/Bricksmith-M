//
//  LDrawStepPartListEditTests.swift
//  UnitTests
//
//  Tests for what committing a frame resize does to the document.
//
//  Created by Sergey Slobodenyuk on 2026-09-10.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures

@Suite("Committing a parts list resize")
struct LDrawStepPartListEditTests {

    // MARK: - Fixtures

    private static let inheritedWidth = 2.5

    private func constrain(_ mode: LPubPliConstrainMode,
                           _ inches: Double = 0,
                           scope: LPubMetaScope = .local,
                           columns: Int = 0) -> LPubPliConstrain {
        let directive = LPubPliConstrain()
        directive.scope = scope
        directive.mode = mode
        directive.inches = inches
        directive.columns = columns
        return directive
    }

    private func step(_ directives: [LDrawDirective] = []) -> LDrawStep {
        let step = LDrawStep.empty() as! LDrawStep
        for directive in directives {
            step.add(directive)
        }
        return step
    }

    private func setWidth(_ inches: Double,
                          in step: LDrawStep?) -> LDrawStepPartListEdit {
        LDrawStepPartListEdit.edit(settingAxis: .width,
                                   toInches: inches,
                                   inStep: step,
                                   inheritedInches: Self.inheritedWidth)
    }

    // MARK: - Insert

    @Test("A step with no constraint gets one")
    func firstResizeInserts() throws {
        let edit = setWidth(3.0, in: step())

        #expect(edit.kind == .insert)

        let directive = try #require(edit.directiveToInsert)
        #expect(directive.mode == .width)
        #expect(directive.scope == .local)
        #expect(directive.inches == 3.0)
        #expect(directive.write() == "0 !LPUB PLI CONSTRAIN LOCAL WIDTH 3.0000")
    }

    @Test("A nil step is handled without crashing")
    func nilStepIsSafe() {
        #expect(setWidth(3.0, in: nil).kind == .insert)
        #expect(LDrawStepPartListEdit.edit(clearingAxis: .width, inStep: nil).kind == .none)
    }

    /// The retyped line is no longer a CONSTRAIN, so the text stays as typed.
    @Test("A line retyped out of CONSTRAIN is not overwritten by a resize")
    func retypedLineIsNotOverwritten() throws {
        let retyped = try #require(constrain(.width, 2).replacement(forText: "PLI CONSTRAIN LOCAL WIDTH"))
        let edit = setWidth(3.0, in: step([retyped]))

        #expect(edit.kind == .insert)
        #expect(edit.existingDirective == nil)
    }

    private func part() -> LDrawPart {
        let part = LDrawPart()
        part.setDisplayName("3001.dat", parse: false, in: nil)
        return part
    }

    @Test("A new LOCAL goes after the step's last CONSTRAIN")
    func insertGoesAfterTheLastConstrain() {
        #expect(setWidth(4.0, in: step([constrain(.width, 3.0, scope: .global), part()])).insertIndex == 1)
        #expect(setWidth(4.0, in: step([constrain(.width, 2.0, scope: .unspecified), part(),
                                        constrain(.height, 1.0, scope: .global), part()])).insertIndex == 3)
        #expect(setWidth(4.0, in: step()).insertIndex == 0)
    }

    /// Put first, the new line would be overridden by the step's later
    /// HEIGHT, and that HEIGHT would stop carrying on.
    @Test("An inserted LOCAL holds for its step, and the next step keeps what carries on")
    func insertedLocalHoldsForItsStepOnly() throws {
        let document = LDrawModel.model() as! LDrawModel
        let header = try #require(document.steps().first as? LDrawStep)
        let own = document.addStep()

        document.addStep()
        header.add(constrain(.width, 2.0, scope: .unspecified))

        for directive: LDrawDirective in [part(), constrain(.height, 1.0, scope: .global), part()] {
            own.add(directive)
        }
        document.setStepDisplay(true)
        document.setMaximumStepIndexForStepDisplay(1)

        let edit = LDrawStepPartListEdit.edit(settingAxis: .width,
                                              toInches: 3.0,
                                              inStep: own,
                                              inheritedInches: LDrawStepPartListPolicy.inheritedInches(forAxis: .width,
                                                                                                       inModel: document))
        #expect(edit.kind == .insert)
        #expect(edit.insertIndex == 2)

        own.insert(try #require(edit.directiveToInsert), at: Int(edit.insertIndex))

        let here = LDrawStepPartListPolicy.constraint(forVisibleStepOfModel: document)
        #expect(here.mode == .width)
        #expect(here.inches == 3.0)

        document.setMaximumStepIndexForStepDisplay(2)

        let next = LDrawStepPartListPolicy.constraint(forVisibleStepOfModel: document)
        #expect(next.mode == .height)
        #expect(next.inches == 1.0)
    }

    /// The unscoped line sets later steps too, so it is left alone.
    @Test("A resize leaves a line that carries on alone")
    func resizeLeavesACarriedLineAlone() throws {
        let edit = setWidth(3.0, in: step([constrain(.width, 2.0, scope: .unspecified)]))

        #expect(edit.kind == .insert)
        #expect(edit.insertIndex == 1)
        #expect(edit.existingDirective == nil)
        #expect(try #require(edit.directiveToInsert).scope == .local)
    }

    // MARK: - Update

    @Test("A step that already has a constraint has it changed, not duplicated")
    func secondResizeUpdates() throws {
        let existing = constrain(.width, 3.0)
        let edit = setWidth(4.0, in: step([existing]))

        #expect(edit.kind == .update)
        #expect(edit.existingDirective === existing)
        #expect(edit.directiveToInsert == nil, "a second line would be wrong")
    }

    // MARK: - Remove

    /// With no line of its own, the frame follows the document again.
    @Test("Asking for the inherited size removes the local line")
    func returningToInheritedRemoves() throws {
        let existing = constrain(.width, 3.0)
        let edit = setWidth(Self.inheritedWidth, in: step([existing]))

        #expect(edit.kind == .remove)
        #expect(edit.existingDirective === existing)
    }

    /// The inherited line pins this axis, so once the step's line is gone the
    /// width asked for applies, whatever that line pinned.
    @Test("Asking for the inherited width removes a line pinning another mode")
    func returningToInheritedRemovesAnotherMode() throws {
        for mode in [LPubPliConstrainMode.height, .columns, .area, .square] {
            let existing = constrain(mode, 1.5)
            let edit = setWidth(Self.inheritedWidth, in: step([existing]))

            #expect(edit.kind == .remove, "\(mode)")
            #expect(edit.existingDirective === existing, "\(mode)")
            #expect(edit.resetsAxis, "\(mode)")
        }
    }

    @Test("Asking for the inherited size with nothing to remove does nothing")
    func returningToInheritedWithNoLineDoesNothing() {
        #expect(setWidth(Self.inheritedWidth, in: step()).kind == .none)
    }

    /// A host shows the pins from this while the drag is still going.
    @Test("A reset is flagged and a resize is not")
    func resetIsFlagged() throws {
        let existing = constrain(.width, 3.0)

        // The step's own earlier WIDTH is what it inherits without its last
        // line, and it still pins the axis once that line is gone.
        let document = LDrawModel.model() as! LDrawModel
        let own = try #require(document.steps().first as? LDrawStep)
        let last = constrain(.height, 2.0)

        own.add(constrain(.width, 3.0))
        own.add(last)

        let inherited = LDrawStepPartListPolicy.inheritedInches(forAxis: .width, inModel: document)
        let kept = LDrawStepPartListEdit.edit(settingAxis: .width, toInches: inherited, inStep: own, inheritedInches: inherited)

        #expect(inherited == 3.0)
        #expect(kept.kind == .remove)
        #expect(kept.existingDirective === last)
        #expect(kept.resetsAxis == false)
        #expect(kept.undoActionKey == setWidth(4.0, in: step()).undoActionKey)

        #expect(setWidth(Self.inheritedWidth, in: step([existing])).resetsAxis)
        #expect(setWidth(Self.inheritedWidth, in: step()).resetsAxis)
        #expect(LDrawStepPartListEdit.edit(clearingAxis: .width, inStep: step([existing])).resetsAxis)

        #expect(setWidth(4.0, in: step()).resetsAxis == false)
        #expect(setWidth(4.0, in: step([existing])).resetsAxis == false)
        #expect(setWidth(3.0, in: step([existing])).resetsAxis == false)
    }

    @Test("Clearing an axis removes the line that pins it, and no other")
    func clearingIsPerAxis() {
        let width = constrain(.width, 3.0)
        let height = constrain(.height, 1.2)

        let clearing = LDrawStepPartListEdit.edit(clearingAxis: .width, inStep: step([width]))
        #expect(clearing.kind == .remove)
        #expect(clearing.existingDirective === width)

        #expect(LDrawStepPartListEdit.edit(clearingAxis: .width, inStep: step([height])).kind == .none)
        #expect(LDrawStepPartListEdit.edit(clearingAxis: .height, inStep: step([height])).kind == .remove)
    }

    // MARK: - Nothing

    /// A gesture that changes nothing must not land in the undo menu.
    @Test("Re-committing the same value does nothing")
    func idempotentCommitDoesNothing() {
        let existing = constrain(.width, 3.0)

        #expect(setWidth(3.0, in: step([existing])).kind == .none)
    }

    /// The meta is written to four decimals, so a smaller change would never
    /// be recorded.
    @Test("A difference too small to write down counts as no change")
    func subPrecisionDifferenceIsNoChange() {
        let existing = constrain(.width, 3.0)

        #expect(setWidth(3.00001, in: step([existing])).kind == .none)
        #expect(setWidth(3.01, in: step([existing])).kind == .update)
    }

    // MARK: - Undo naming

    /// The Edit menu must name the right action, so that a reset does not read
    /// as a resize.
    @Test("Setting and resetting get different undo names")
    func setAndResetAreNamedDifferently() {
        let existing = constrain(.width, 3.0)

        let resize = setWidth(4.0, in: step([existing]))
        let reset = LDrawStepPartListEdit.edit(clearingAxis: .width, inStep: step([existing]))
        let backToInherited = setWidth(Self.inheritedWidth, in: step([existing]))

        #expect(resize.undoActionKey != reset.undoActionKey)
        #expect(backToInherited.undoActionKey == reset.undoActionKey,
                "dragging back to the inherited size is a reset, whatever gesture got there")
    }

    // MARK: - Other constraint modes

    /// A step has one CONSTRAIN line, so a drag changes it instead of adding a
    /// second one, whatever it held before.
    @Test("Dragging an edge takes over a constraint of another mode")
    func draggingConvertsAnUnpinnedConstraint() {
        for mode in [LPubPliConstrainMode.height, .area, .square, .columns] {
            let existing = constrain(mode, 1.2, columns: 3)
            let edit = setWidth(3.0, in: step([existing]))

            #expect(edit.kind == .update, "\(mode)")
            #expect(edit.existingDirective === existing, "\(mode)")
        }
    }

    /// Later lines win, as they do elsewhere in LDraw.
    @Test("The last constraint in a step is the one edited")
    func theLastConstraintWins() {
        let first = constrain(.width, 3.0)
        let last = constrain(.width, 4.0)

        #expect(setWidth(5.0, in: step([first, last])).existingDirective === last)
    }
}
