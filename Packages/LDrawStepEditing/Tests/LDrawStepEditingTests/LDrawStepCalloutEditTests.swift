//
//  LDrawStepCalloutEditTests.swift
//  LDrawStepEditingTests
//
//  What adding and removing a callout writes to a step: which lines go in,
//  which come out, and where.
//
//  The fixtures build the directives in memory. Their parts name no file, so
//  nothing is loaded from a part library, and an arrow's tip is the middle.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawStepEditing

@Suite("Adding and removing a callout")
struct LDrawStepCalloutEditTests {

    // MARK: - Fixtures

    private func color(_ code: Int32) -> LDrawColor {
        let color = LDrawColor()
        color.setColorCode(LDrawColorT(rawValue: code)!)
        return color
    }

    private func part(_ name: String, color code: Int32 = 4) -> LDrawPart {
        let part = LDrawPart()
        part.setDisplayName(name, parse: false, in: nil)
        part.setLDrawColor(color(code))
        return part
    }

    /// Parses the text, so the line gets the class the file would give it.
    private func lpub(_ text: String) -> LDrawDirective {
        let lines = ["0 !LPUB " + text, "0 STEP"]
        let step = LDrawStep(lines: lines, in: NSRange(location: 0, length: lines.count), parentGroup: nil)

        return (step!.subdirectives() as! [LDrawDirective])[0]
    }

    /// A file whose main model has one step with these directives on display,
    /// and a submodel sub.ldr with a step of its own. The caller keeps the
    /// file.
    private func fixture(_ directives: [LDrawDirective]) -> (file: LDrawFile, model: LDrawModel, step: LDrawStep) {
        let file = LDrawFile()
        let main = LDrawMPDModel.model() as! LDrawMPDModel
        main.setModelName("main.ldr")
        file.addSubmodel(main)

        let sub = LDrawMPDModel.model() as! LDrawMPDModel
        sub.setModelName("sub.ldr")
        file.addSubmodel(sub)
        let built = sub.addStep()
        built.add(part("3003.dat") as LDrawDirective)

        let step = main.addStep()
        for directive in directives {
            step.add(directive)
        }
        main.setStepDisplay(true)
        main.setMaximumStepIndexForStepDisplay(UInt(main.steps().count - 1))

        return (file, main, step)
    }

    /// The row a step's list has for sub.ldr placed in this color.
    private func row(_ name: String = "sub.ldr",
                     color code: Int32 = 4,
                     isSubmodel: Bool = true) -> LDrawStepPartListEntry {
        LDrawStepPartListEntry(partName: name,
                               displayTitle: name,
                               color: color(code),
                               quantity: 1,
                               modelBounds: InvalidBox,
                               isMissing: false,
                               isSubmodel: isSubmodel)
    }

    /// Does what the document does with an edit: takes lines out, then puts
    /// lines in.
    private func apply(_ edit: LDrawStepCalloutEdit, to step: LDrawStep) {
        for directive in edit.directivesToRemove {
            step.remove(directive)
        }
        for (directive, index) in zip(edit.directivesToInsert, edit.insertIndexes) {
            step.insert(directive, at: index.intValue)
        }
    }

    /// The step's lines, short enough to read: a part by its name, an LPub
    /// line by its text.
    private func lines(of step: LDrawStep) -> [String] {
        (step.subdirectives() as! [LDrawDirective]).map { directive in
            if let part = directive as? LDrawPart {
                return part.referenceName()
            }
            if let command = directive as? LPubCommand {
                return command.lPubCommandString
            }
            return String(describing: type(of: directive))
        }
    }

    private let arrow = "CALLOUT POINTER LEFT 0.500 0.500 0.500 0"

    // MARK: - Adding

    @Test("Calling a submodel out puts its placement between BEGIN and END, with an arrow")
    func callingOutWrapsThePlacement() throws {
        let fixture = fixture([part("3001.dat"), part("sub.ldr"), part("3002.dat")])

        let edit = LDrawStepCalloutEdit.edit(callingOut: row(), inModel: fixture.model)

        #expect(edit.kind == .rewrite)
        #expect(edit.directivesToRemove.isEmpty)
        #expect(edit.insertIndexes == [1, 3, 4])
        #expect(edit.undoActionKey == "UndoStepCalloutAdd")

        apply(edit, to: fixture.step)

        #expect(lines(of: fixture.step) == ["3001.dat", "CALLOUT BEGIN", "sub.ldr", arrow, "CALLOUT END", "3002.dat"])

        let callout = try #require(LDrawStepCallout.callouts(forStep: fixture.step).first)
        #expect(callout.mode == .unassembled)
        #expect(callout.placements.count == 1)
        #expect(callout.pointers.count == 1)
    }

    @Test("A submodel placed twice gets one callout with two arrows")
    func twoPlacementsShareACallout() throws {
        let fixture = fixture([part("sub.ldr"), part("sub.ldr"), part("3002.dat")])

        let edit = LDrawStepCalloutEdit.edit(callingOut: row(), inModel: fixture.model)

        #expect(edit.directivesToRemove.isEmpty)

        apply(edit, to: fixture.step)

        #expect(lines(of: fixture.step)
                == ["CALLOUT BEGIN", "sub.ldr", "sub.ldr", arrow, arrow, "CALLOUT END", "3002.dat"])

        let callouts = LDrawStepCallout.callouts(forStep: fixture.step)
        #expect(callouts.count == 1)
        #expect(callouts.first?.placements.count == 2)
        #expect(callouts.first?.entries.first?.quantity == 2)
    }

    @Test("Placements with other lines between them are brought together")
    func separatedPlacementsAreGathered() throws {
        let second = part("sub.ldr")
        let fixture = fixture([part("3001.dat"), part("sub.ldr"), part("3002.dat"), second, part("3003.dat")])

        let edit = LDrawStepCalloutEdit.edit(callingOut: row(), inModel: fixture.model)

        #expect(edit.directivesToRemove.count == 1)
        #expect(edit.directivesToRemove.first === second)

        apply(edit, to: fixture.step)

        #expect(lines(of: fixture.step) == ["3001.dat", "CALLOUT BEGIN", "sub.ldr", "sub.ldr", arrow, arrow,
                                            "CALLOUT END", "3002.dat", "3003.dat"])
    }

    @Test("A placement already in a callout, or left out of the list, is not called out again")
    func onlyTheRowsOwnPlacementsCount() throws {
        let fixture = fixture([lpub("CALLOUT BEGIN"), part("sub.ldr"), lpub("CALLOUT END"),
                               lpub("PLI BEGIN IGN"), part("sub.ldr"), lpub("PLI END"),
                               lpub("PART BEGIN IGN"), part("sub.ldr"), lpub("PART END"),
                               part("sub.ldr")])

        let edit = LDrawStepCalloutEdit.edit(callingOut: row(), inModel: fixture.model)

        apply(edit, to: fixture.step)

        #expect(Array(lines(of: fixture.step).suffix(4)) == ["CALLOUT BEGIN", "sub.ldr", arrow, "CALLOUT END"])
        #expect(LDrawStepCallout.callouts(forStep: fixture.step).count == 2)
    }

    @Test("A row is called out in its own color only")
    func otherColorsAreOtherRows() throws {
        let fixture = fixture([part("sub.ldr", color: 4), part("sub.ldr", color: 1)])

        let edit = LDrawStepCalloutEdit.edit(callingOut: row(color: 1), inModel: fixture.model)

        apply(edit, to: fixture.step)

        #expect(lines(of: fixture.step) == ["sub.ldr", "CALLOUT BEGIN", "sub.ldr", arrow, "CALLOUT END"])
    }

    @Test("A row with nothing to call out changes nothing")
    func nothingToCallOut() {
        let parts = fixture([part("3001.dat"), part("sub.ldr")])

        #expect(LDrawStepCalloutEdit.edit(callingOut: row("3001.dat", isSubmodel: false), inModel: parts.model).kind
                == .none)
        #expect(LDrawStepCalloutEdit.edit(callingOut: row("other.ldr"), inModel: parts.model).kind == .none)
        #expect(LDrawStepCalloutEdit.edit(callingOut: row(), inModel: nil).kind == .none)

        let taken = fixture([lpub("CALLOUT BEGIN"), part("sub.ldr"), lpub("CALLOUT END")])

        #expect(LDrawStepCalloutEdit.edit(callingOut: row(), inModel: taken.model).kind == .none)
    }

    // MARK: - Arrow tips

    @Test("An arrow's tip is a share of the box around the assembly, from its top left")
    func tipIsAShareOfTheOutline() {
        var corners = [Point3(x: 0, y: 0, z: 0), Point3(x: 200, y: 100, z: 50)]
        let outline = Data(bytes: &corners, count: corners.count * MemoryLayout<Point3>.stride)

        let inside = LDrawStepCalloutEdit.tip(forModelPoint: Point3(x: 50, y: 75, z: 10),
                                              inOutline: outline, view: IdentityMatrix4)
        #expect(abs(inside.x - 0.25) < 0.0001)
        #expect(abs(inside.y - 0.75) < 0.0001)

        // A point past the box points at its edge.
        let outside = LDrawStepCalloutEdit.tip(forModelPoint: Point3(x: 500, y: -20, z: 0),
                                               inOutline: outline, view: IdentityMatrix4)
        #expect(outside.x == 1)
        #expect(outside.y == 0)

        // With nothing to measure, the middle.
        let unmeasured = LDrawStepCalloutEdit.tip(forModelPoint: Point3(x: 50, y: 75, z: 10),
                                                  inOutline: nil, view: IdentityMatrix4)
        #expect(unmeasured.x == 0.5 && unmeasured.y == 0.5)
    }

    @Test("The tip is measured as the step's angle shows the assembly")
    func tipFollowsTheView() {
        var corners = [Point3(x: 0, y: 0, z: 0), Point3(x: 200, y: 100, z: 50)]
        let outline = Data(bytes: &corners, count: corners.count * MemoryLayout<Point3>.stride)
        let fromTheSide = LDrawStepPartListLayout.viewTransform(forAngle: Tuple3(x: 0, y: 90, z: 0))

        let straight = LDrawStepCalloutEdit.tip(forModelPoint: Point3(x: 50, y: 75, z: 40),
                                                inOutline: outline, view: IdentityMatrix4)
        let turned = LDrawStepCalloutEdit.tip(forModelPoint: Point3(x: 50, y: 75, z: 40),
                                              inOutline: outline, view: fromTheSide)

        // Seen from the side, the box is as wide as it was deep, and the
        // point sits where its depth puts it.
        #expect(abs(straight.x - 0.25) < 0.0001)
        #expect(abs(turned.y - 0.75) < 0.0001)
        #expect(abs(turned.x - 0.8) < 0.0001 || abs(turned.x - 0.2) < 0.0001)
    }

    // MARK: - Removing

    @Test("Removing a callout takes out its two lines, its arrows and its place, and leaves the parts")
    func removingTakesTheCalloutsOwnLines() throws {
        let fixture = fixture([part("3001.dat"),
                               lpub("CALLOUT BEGIN"),
                               part("sub.ldr"),
                               lpub("CALLOUT POINTER LEFT 0.500 0.250 0.750 0"),
                               lpub("CALLOUT POINTER_ATTRIBUTE LINE 1 Black 0.03 0 1"),
                               lpub("CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.1 0.2"),
                               lpub("CALLOUT END"),
                               part("3002.dat")])
        let callout = try #require(LDrawStepCallout.callouts(forStep: fixture.step).first)

        let edit = LDrawStepCalloutEdit.edit(removing: callout)

        #expect(edit.kind == .rewrite)
        #expect(edit.directivesToRemove.count == 5)
        #expect(edit.directivesToInsert.isEmpty)
        #expect(edit.undoActionKey == "UndoStepCalloutRemove")

        apply(edit, to: fixture.step)

        #expect(lines(of: fixture.step) == ["3001.dat", "sub.ldr", "3002.dat"])
        #expect(LDrawStepCallout.callouts(forStep: fixture.step).isEmpty)
    }

    @Test("A LOCAL styling line goes with its callout, and one that carries to later callouts stays")
    func removingKeepsWhatLaterCalloutsGoBy() throws {
        let fixture = fixture([lpub("CALLOUT BEGIN"),
                               part("sub.ldr"),
                               lpub("CALLOUT BACKGROUND LOCAL COLOR \"#daf3ff\""),
                               lpub("CALLOUT BORDER LOCAL ROUND #daf3ff 0.02 10"),
                               lpub("CALLOUT ALLOC HORIZONTAL"),
                               lpub("CALLOUT MARGINS GLOBAL 0.1 0.1"),
                               lpub("PLI CONSTRAIN LOCAL WIDTH 2.0000"),
                               lpub("CALLOUT END")])
        let callout = try #require(LDrawStepCallout.callouts(forStep: fixture.step).first)

        apply(LDrawStepCalloutEdit.edit(removing: callout), to: fixture.step)

        #expect(lines(of: fixture.step) == ["sub.ldr", "CALLOUT ALLOC HORIZONTAL", "CALLOUT MARGINS GLOBAL 0.1 0.1",
                                            "PLI CONSTRAIN LOCAL WIDTH 2.0000"])
    }

    @Test("A callout that never closes is removed up to its last line")
    func removingAnUnclosedCallout() throws {
        let fixture = fixture([part("3001.dat"), lpub("CALLOUT BEGIN"), part("sub.ldr"),
                               lpub("CALLOUT POINTER LEFT 0.500 0.250 0.750 0")])
        let callout = try #require(LDrawStepCallout.callouts(forStep: fixture.step).first)

        apply(LDrawStepCalloutEdit.edit(removing: callout), to: fixture.step)

        #expect(lines(of: fixture.step) == ["3001.dat", "sub.ldr"])
    }

    @Test("Removing the callout that was just added gives the step back")
    func addingThenRemovingIsNoChange() throws {
        let fixture = fixture([part("3001.dat"), part("sub.ldr"), part("sub.ldr"), part("3002.dat")])
        let before = lines(of: fixture.step)

        apply(LDrawStepCalloutEdit.edit(callingOut: row(), inModel: fixture.model), to: fixture.step)

        let callout = try #require(LDrawStepCallout.callouts(forStep: fixture.step).first)

        apply(LDrawStepCalloutEdit.edit(removing: callout), to: fixture.step)

        #expect(lines(of: fixture.step) == before)
    }

    // MARK: - The way the steps run

    /// A file whose main model has one step for each list, and a submodel
    /// sub.ldr with a step of its own. The caller keeps the file.
    private func steps(_ lists: [[LDrawDirective]]) -> (file: LDrawFile, steps: [LDrawStep]) {
        let file = LDrawFile()
        let main = LDrawMPDModel.model() as! LDrawMPDModel
        main.setModelName("main.ldr")
        file.addSubmodel(main)

        let sub = LDrawMPDModel.model() as! LDrawMPDModel
        sub.setModelName("sub.ldr")
        file.addSubmodel(sub)
        let built = sub.addStep()
        built.add(part("3003.dat") as LDrawDirective)

        let added: [LDrawStep] = lists.map { directives in
            let step = main.addStep()
            for directive in directives {
                step.add(directive)
            }
            return step
        }

        return (file, added)
    }

    /// A step's one callout, with any text between the submodel and END.
    private func called(_ inside: String...) -> [LDrawDirective] {
        [lpub("CALLOUT BEGIN"), part("sub.ldr")] + inside.map { lpub($0) } + [lpub("CALLOUT END")]
    }

    /// Does what the document does with an edit of any kind.
    private func applyAny(_ edit: LDrawStepCalloutEdit, to step: LDrawStep) {
        switch edit.kind {
        case .insert:
            if let line = edit.directiveToInsert {
                step.insert(line, at: Int(edit.insertIndex))
            }
        case .update:
            if let text = edit.commandString {
                edit.existingDirective?.lPubCommandString = text
            }
        case .rewrite:
            apply(edit, to: step)
        default:
            break
        }
    }

    private func isVertical(_ step: LDrawStep) throws -> Bool {
        try #require(LDrawStepCallout.callouts(forStep: step).first).isVertical
    }

    @Test("A callout with no ALLOC line of its own gets a LOCAL one, just before END")
    func turningWritesALocalLine() throws {
        let model = steps([called(arrow)])
        let step = model.steps[0]
        let callout = try #require(LDrawStepCallout.callouts(forStep: step).first)

        #expect(callout.isVertical, "LPub3D's way for a file that says nothing")

        let edit = LDrawStepCalloutEdit.edit(arrangingStepsOf: callout, vertically: false)

        #expect(edit.kind == .insert)
        #expect(edit.insertIndex == 3)
        #expect(edit.directiveToInsert is LPubCalloutAlloc)
        #expect(edit.directiveToInsert?.lPubCommandString == "CALLOUT ALLOC LOCAL HORIZONTAL")
        #expect(edit.undoActionKey == "UndoStepCalloutAlloc")

        applyAny(edit, to: step)

        #expect(lines(of: step) == ["CALLOUT BEGIN", "sub.ldr", arrow, "CALLOUT ALLOC LOCAL HORIZONTAL", "CALLOUT END"])
        #expect(try isVertical(step) == false)
    }

    @Test("Turning the steps back takes the line out again")
    func turningBackIsNoChange() throws {
        let model = steps([called(arrow)])
        let step = model.steps[0]
        let before = lines(of: step)

        let callout = try #require(LDrawStepCallout.callouts(forStep: step).first)

        applyAny(LDrawStepCalloutEdit.edit(arrangingStepsOf: callout, vertically: false), to: step)

        let turned = try #require(LDrawStepCallout.callouts(forStep: step).first)
        let back = LDrawStepCalloutEdit.edit(arrangingStepsOf: turned, vertically: true)

        #expect(back.kind == .rewrite)
        #expect(back.directivesToRemove.count == 1)
        #expect(back.directivesToInsert.isEmpty)

        applyAny(back, to: step)

        #expect(lines(of: step) == before)
        #expect(try isVertical(step))
    }

    @Test("A callout that runs that way already is left alone")
    func turningToWhatItIs() throws {
        let model = steps([called(), called("CALLOUT ALLOC LOCAL HORIZONTAL")])
        let down = try #require(LDrawStepCallout.callouts(forStep: model.steps[0]).first)
        let across = try #require(LDrawStepCallout.callouts(forStep: model.steps[1]).first)

        #expect(LDrawStepCalloutEdit.edit(arrangingStepsOf: down, vertically: true).kind == .none)
        #expect(LDrawStepCalloutEdit.edit(arrangingStepsOf: across, vertically: false).kind == .none)
    }

    /// LPub3D writes the line with no LOCAL, and the callouts of every later
    /// step go by it.
    @Test("A line with no LOCAL stays, and a LOCAL line goes after it")
    func aCarriedLineStays() throws {
        let model = steps([called("CALLOUT ALLOC HORIZONTAL"), called()])
        let first = model.steps[0]
        let callout = try #require(LDrawStepCallout.callouts(forStep: first).first)

        #expect(try isVertical(model.steps[1]) == false, "the later step goes by the first one's line")

        let edit = LDrawStepCalloutEdit.edit(arrangingStepsOf: callout, vertically: true)

        #expect(edit.kind == .insert)

        applyAny(edit, to: first)

        #expect(lines(of: first) == ["CALLOUT BEGIN", "sub.ldr", "CALLOUT ALLOC HORIZONTAL",
                                     "CALLOUT ALLOC LOCAL VERTICAL", "CALLOUT END"])
        #expect(try isVertical(first))
        #expect(try isVertical(model.steps[1]) == false, "and still does")
    }

    @Test("A callout that goes by an earlier step's line is turned alone")
    func turningOneOfSeveral() throws {
        let model = steps([called("CALLOUT ALLOC HORIZONTAL"), called(), called()])
        let middle = model.steps[1]
        let callout = try #require(LDrawStepCallout.callouts(forStep: middle).first)

        applyAny(LDrawStepCalloutEdit.edit(arrangingStepsOf: callout, vertically: true), to: middle)

        #expect(try isVertical(model.steps[0]) == false)
        #expect(try isVertical(middle))
        #expect(try isVertical(model.steps[2]) == false, "a LOCAL line ends with its step")
        #expect(lines(of: model.steps[2]) == ["CALLOUT BEGIN", "sub.ldr", "CALLOUT END"])
    }

    @Test("A LOCAL line that says what the callout would do without it is changed")
    func aLocalLineIsChanged() throws {
        let model = steps([called("CALLOUT ALLOC LOCAL VERTICAL")])
        let step = model.steps[0]
        let callout = try #require(LDrawStepCallout.callouts(forStep: step).first)
        let edit = LDrawStepCalloutEdit.edit(arrangingStepsOf: callout, vertically: false)

        #expect(edit.kind == .update)
        #expect(edit.existingDirective?.lPubCommandString == "CALLOUT ALLOC LOCAL VERTICAL")
        #expect(edit.commandString == "CALLOUT ALLOC LOCAL HORIZONTAL")

        applyAny(edit, to: step)

        #expect(lines(of: step) == ["CALLOUT BEGIN", "sub.ldr", "CALLOUT ALLOC LOCAL HORIZONTAL", "CALLOUT END"])
        #expect(try isVertical(step) == false)
    }

    @Test("Of two lines of its own, the callout goes by the last, and that one is the one changed")
    func theLastLineCounts() throws {
        let model = steps([called("CALLOUT ALLOC LOCAL HORIZONTAL", "CALLOUT ALLOC HORIZONTAL")])
        let step = model.steps[0]
        let callout = try #require(LDrawStepCallout.callouts(forStep: step).first)

        // The last line has no LOCAL, so it stays and a LOCAL line follows it.
        applyAny(LDrawStepCalloutEdit.edit(arrangingStepsOf: callout, vertically: true), to: step)

        #expect(lines(of: step) == ["CALLOUT BEGIN", "sub.ldr", "CALLOUT ALLOC LOCAL HORIZONTAL",
                                    "CALLOUT ALLOC HORIZONTAL", "CALLOUT ALLOC LOCAL VERTICAL", "CALLOUT END"])
        #expect(try isVertical(step))
    }

    /// A LOCAL line would end the second callout's line with the step, and
    /// the later step goes by that line.
    @Test("Where a later line of the step carries on, the line written has no LOCAL")
    func aLaterCarriedLineKeepsCarrying() throws {
        let model = steps([called() + called("CALLOUT ALLOC HORIZONTAL"), called()])
        let first = model.steps[0]
        let callout = try #require(LDrawStepCallout.callouts(forStep: first).first)

        #expect(callout.isVertical)
        #expect(try isVertical(model.steps[1]) == false, "the later step goes by the second callout's line")

        let edit = LDrawStepCalloutEdit.edit(arrangingStepsOf: callout, vertically: false)

        #expect(edit.kind == .insert)
        #expect(edit.directiveToInsert?.lPubCommandString == "CALLOUT ALLOC HORIZONTAL")

        applyAny(edit, to: first)

        #expect(try isVertical(first) == false)
        #expect(try isVertical(model.steps[1]) == false, "and still does")
    }

    @Test("Turning such a callout back takes its line out again")
    func turningBackBeforeACarriedLine() throws {
        let model = steps([called() + called("CALLOUT ALLOC HORIZONTAL"), called()])
        let first = model.steps[0]
        let before = lines(of: first)
        let callout = try #require(LDrawStepCallout.callouts(forStep: first).first)

        applyAny(LDrawStepCalloutEdit.edit(arrangingStepsOf: callout, vertically: false), to: first)

        let turned = try #require(LDrawStepCallout.callouts(forStep: first).first)
        let back = LDrawStepCalloutEdit.edit(arrangingStepsOf: turned, vertically: true)

        #expect(back.kind == .rewrite)

        applyAny(back, to: first)

        #expect(lines(of: first) == before)
        #expect(try isVertical(model.steps[1]) == false)
    }

    /// The second callout's line ends with the step, because a LOCAL line
    /// comes before it. With that LOCAL line gone it would carry on.
    @Test("A LOCAL line with another line after it in the step is changed, not taken out")
    func aLocalLineBeforeAnotherStays() throws {
        let model = steps([called("CALLOUT ALLOC LOCAL HORIZONTAL") + called("CALLOUT ALLOC HORIZONTAL"), called()])
        let first = model.steps[0]
        let callout = try #require(LDrawStepCallout.callouts(forStep: first).first)

        #expect(try isVertical(model.steps[1]), "the second callout's line ends with its step")

        let edit = LDrawStepCalloutEdit.edit(arrangingStepsOf: callout, vertically: true)

        #expect(edit.kind == .update)
        #expect(edit.commandString == "CALLOUT ALLOC LOCAL VERTICAL")

        applyAny(edit, to: first)

        #expect(try isVertical(first))
        #expect(try isVertical(model.steps[1]), "and still does")
    }
}
