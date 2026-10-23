//
//  LDrawStepAssemblyEditTests.swift
//  LDrawStepEditingTests
//
//  What a change to the assembly's size, place or angle writes, for the step
//  alone, for later steps and for the whole model.
//
//  Created by Sergey Slobodenyuk on 2026-10-20.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawStepEditing

/// Does what a document does, without the undo.
private final class ApplyingHost: NSObject, LDrawStepCalloutEditHost {

    func add(_ newDirective: LDrawDirective, toParent parent: LDrawContainer, at index: Int) {
        parent.insert(newDirective, at: index)
    }

    func delete(_ doomedDirective: LDrawDirective) {
        doomedDirective.enclosingDirective()?.remove(doomedDirective)
    }

    func preserveDirectiveState(_ directive: LDrawDirective) {
    }
}

/// A file with one model, a step for each list of lines, in Steps mode at
/// `visible`.
private struct AssemblyFixture {

    let file = LDrawFile()
    let model = LDrawMPDModel.model() as! LDrawMPDModel

    init(_ steps: [[String]], visible: Int) {
        model.setModelName("main.ldr")
        file.addSubmodel(model)

        for (index, lines) in steps.enumerated() {
            let step = index == 0 ? (model.steps().first as! LDrawStep) : model.addStep()

            for line in lines {
                step.add(CalloutFixture.parsed(line))
            }
        }

        model.setStepDisplay(true)
        model.setMaximumStepIndexForStepDisplay(UInt(visible))
    }

    func step(_ index: Int) -> LDrawStep {
        model.steps()[index] as! LDrawStep
    }

    func lines(_ index: Int) -> [String] {
        CalloutFixture.lines(of: step(index))
    }

    /// Whether LPub3D sees the step at this viewing angle.
    func sees(step index: Int, at angle: Tuple3) -> Bool {
        let seen = LDrawStepPartListPolicy.assemblyViewingAngle(forStepAt: UInt(index), inModel: model)

        for point in [Point3(x: 40, y: 10, z: 20), Point3(x: -5, y: 30, z: 7)] {
            let a = V3MulPointByProjMatrix(point, Matrix4Rotate(IdentityMatrix4, seen))
            let b = V3MulPointByProjMatrix(point, Matrix4Rotate(IdentityMatrix4, angle))

            if abs(a.x - b.x) > 0.1 || abs(a.y - b.y) > 0.1 || abs(a.z - b.z) > 0.1 {
                return false
            }
        }
        return true
    }
}

@Suite("Writing the assembly's size, place and angle")
struct LDrawStepAssemblyEditTests {

    private func apply(_ edit: LDrawStepAssemblyEdit?) throws {
        _ = try #require(edit).apply(host: ApplyingHost())
    }

    private func isClose(_ a: Tuple3, _ b: Tuple3) -> Bool {
        abs(a.x - b.x) < 0.001 && abs(a.y - b.y) < 0.001 && abs(a.z - b.z) < 0.001
    }

    /// Whether two triples of angles turn alike.
    private func isSameRotation(_ a: Tuple3, _ b: Tuple3) -> Bool {
        Matrix4RotationsWithinTolerance(Matrix4Rotate(IdentityMatrix4, a), Matrix4Rotate(IdentityMatrix4, b), 0.0001)
    }

    /// The viewing angle of a camera at these angles, with no rotation.
    private func camera(_ latitude: Double, _ longitude: Double) -> Tuple3 {
        LDrawStepPartListPolicy.viewingAngle(forView: LDrawStepPartListLayout.viewTransform(latitude: latitude,
                                                                                              longitude: longitude))
    }

    // MARK: - Size

    @Test("A size for the step alone is a LOCAL line after the step's other size lines")
    func scaleForTheStep() throws {
        let fixture = AssemblyFixture([[], ["ASSEM MODEL_SCALE 1.5"]], visible: 1)
        let edit = LDrawStepAssemblyEdit.edit(settingScale: 1.2, scope: .step, inModel: fixture.model)

        #expect(edit.undoActionKey == "UndoStepAssemblyScale")
        try apply(edit)

        #expect(fixture.lines(1) == ["ASSEM MODEL_SCALE 1.5", "ASSEM MODEL_SCALE LOCAL 1.2000"])
        #expect(abs(LDrawStepPartListPolicy.modelScale(forBranch: .assembly, inModel: fixture.model) - 1.2) < 0.0001)
    }

    @Test("The step's own size line is changed, and taken out when the step has that size anyway")
    func scaleChangesOrDropsTheStepsLine() throws {
        let changed = AssemblyFixture([["ASSEM MODEL_SCALE 1.1"], ["ASSEM MODEL_SCALE LOCAL 1.2"]], visible: 1)
        try apply(LDrawStepAssemblyEdit.edit(settingScale: 1.4, scope: .step, inModel: changed.model))
        #expect(changed.lines(1) == ["ASSEM MODEL_SCALE LOCAL 1.4000"])

        let dropped = AssemblyFixture([["ASSEM MODEL_SCALE 1.1"], ["ASSEM MODEL_SCALE LOCAL 1.2"]], visible: 1)
        try apply(LDrawStepAssemblyEdit.edit(settingScale: 1.1, scope: .step, inModel: dropped.model))
        #expect(dropped.lines(1).isEmpty)

        let same = AssemblyFixture([[], []], visible: 1)
        #expect(LDrawStepAssemblyEdit.edit(settingScale: 1.0, scope: .step, inModel: same.model).isEmpty)
        #expect(LDrawStepAssemblyEdit.edit(settingScale: 1.2, scope: .step, inModel: changed.model).isEmpty == false)
    }

    @Test("For later steps the step's own lines go and its carried line changes")
    func scaleForLaterSteps() throws {
        let fixture = AssemblyFixture([["ASSEM MODEL_SCALE 1.1"],
                                       ["ASSEM MODEL_SCALE 1.3", "ASSEM MODEL_SCALE LOCAL 1.2"],
                                       []], visible: 1)
        try apply(LDrawStepAssemblyEdit.edit(settingScale: 1.5, scope: .laterSteps, inModel: fixture.model))
        #expect(fixture.lines(1) == ["ASSEM MODEL_SCALE 1.5000"])

        // What the step carries in anyway: no line is needed.
        let carried = AssemblyFixture([["ASSEM MODEL_SCALE 1.1"],
                                       ["ASSEM MODEL_SCALE 1.3", "ASSEM MODEL_SCALE LOCAL 1.2"]], visible: 1)
        try apply(LDrawStepAssemblyEdit.edit(settingScale: 1.1, scope: .laterSteps, inModel: carried.model))
        #expect(carried.lines(1).isEmpty)

        // No line of its own: one with no scope goes first.
        let plain = AssemblyFixture([[], ["ASSEM PLACEMENT CENTER PAGE INSIDE"]], visible: 1)
        try apply(LDrawStepAssemblyEdit.edit(settingScale: 0.8, scope: .laterSteps, inModel: plain.model))
        #expect(plain.lines(1) == ["ASSEM MODEL_SCALE 0.8000", "ASSEM PLACEMENT CENTER PAGE INSIDE"])
    }

    @Test("For the whole model only the header's GLOBAL line changes, as LPub3D writes it")
    func scaleForTheModel() throws {
        let fixture = AssemblyFixture([["ASSEM MODEL_SCALE GLOBAL 1.1"], ["ASSEM MODEL_SCALE LOCAL 1.2"]], visible: 1)
        try apply(LDrawStepAssemblyEdit.edit(settingScale: 1.3, scope: .model, inModel: fixture.model))
        #expect(fixture.lines(0) == ["ASSEM MODEL_SCALE GLOBAL 1.3000"])
        #expect(fixture.lines(1) == ["ASSEM MODEL_SCALE LOCAL 1.2"])

        let bare = AssemblyFixture([[], []], visible: 1)
        try apply(LDrawStepAssemblyEdit.edit(settingScale: 1.3, scope: .model, inModel: bare.model))
        #expect(bare.lines(0) == ["ASSEM MODEL_SCALE GLOBAL 1.3000"])

        // The header is the step on display: its LOCAL line stays too.
        let header = AssemblyFixture([["ASSEM MODEL_SCALE LOCAL 1.2", "ASSEM MODEL_SCALE GLOBAL 1.4"]], visible: 0)
        try apply(LDrawStepAssemblyEdit.edit(settingScale: 1.3, scope: .model, inModel: header.model))
        #expect(header.lines(0) == ["ASSEM MODEL_SCALE LOCAL 1.2", "ASSEM MODEL_SCALE GLOBAL 1.3000"])
    }

    @Test("For the whole model the lines of other steps stay, and still hold where they did")
    func scaleForTheModelKeepsStepLines() throws {
        let fixture = AssemblyFixture([["ASSEM MODEL_SCALE GLOBAL 1.1", "ASSEM MODEL_SCALE 0.7"],
                                       ["ASSEM MODEL_SCALE 0.8"],
                                       [],
                                       ["ASSEM MODEL_SCALE 0.9"]], visible: 2)
        try apply(LDrawStepAssemblyEdit.edit(settingScale: 1.3, scope: .model, inModel: fixture.model))

        #expect(fixture.lines(0) == ["ASSEM MODEL_SCALE GLOBAL 1.3000", "ASSEM MODEL_SCALE 0.7"])
        #expect(fixture.lines(1) == ["ASSEM MODEL_SCALE 0.8"])
        #expect(fixture.lines(3) == ["ASSEM MODEL_SCALE 0.9"])
        #expect(abs(LDrawStepPartListPolicy.modelScale(forBranch: .assembly, inModel: fixture.model) - 0.8) < 0.0001)
    }

    @Test("For the whole model a value the step shows already writes nothing")
    func scaleForTheModelLeftAlone() throws {
        let fixture = AssemblyFixture([["ASSEM MODEL_SCALE GLOBAL 1.1"], ["ASSEM MODEL_SCALE 0.8"]], visible: 1)

        #expect(LDrawStepAssemblyEdit.edit(settingScale: 0.8, scope: .model, inModel: fixture.model).isEmpty)
    }

    // MARK: - Place

    @Test("A place keeps the words of the placement in force, or centers the step on the page")
    func offsetKeepsThePlacement() throws {
        let bare = AssemblyFixture([[]], visible: 0)
        let edit = LDrawStepAssemblyEdit.edit(settingOffset: Point2(x: 0.02, y: -0.1), scope: .step, inModel: bare.model)

        #expect(edit.undoActionKey == "UndoStepAssemblyMove")
        try apply(edit)
        #expect(bare.lines(0) == ["ASSEM PLACEMENT LOCAL CENTER PAGE INSIDE 0.0200 -0.1000"])

        let placed = AssemblyFixture([["ASSEM PLACEMENT BOTTOM PAGE INSIDE"], []], visible: 1)
        try apply(LDrawStepAssemblyEdit.edit(settingOffset: Point2(x: 0.02, y: -0.1), scope: .step, inModel: placed.model))
        #expect(placed.lines(1) == ["ASSEM PLACEMENT LOCAL BOTTOM PAGE INSIDE 0.0200 -0.1000"])
    }

    @Test("Back to the middle takes a centered line out, and keeps one that is not centered")
    func offsetBackToTheMiddle() throws {
        let centered = AssemblyFixture([[], ["ASSEM PLACEMENT LOCAL CENTER PAGE INSIDE 0.02 -0.1"]], visible: 1)
        try apply(LDrawStepAssemblyEdit.edit(settingOffset: Point2(x: 0, y: 0), scope: .step, inModel: centered.model))
        #expect(centered.lines(1).isEmpty)

        let bottom = AssemblyFixture([[], ["ASSEM PLACEMENT LOCAL BOTTOM PAGE INSIDE 0.02 0"]], visible: 1)
        try apply(LDrawStepAssemblyEdit.edit(settingOffset: Point2(x: 0, y: 0), scope: .step, inModel: bottom.model))
        #expect(bottom.lines(1) == ["ASSEM PLACEMENT LOCAL BOTTOM PAGE INSIDE 0.0000 0.0000"])
    }

    // MARK: - Angle

    @Test("A turn of one step is a REL ROTSTEP, its camera line goes, and the next step gets back what held")
    func turnOfOneStep() throws {
        for target in [camera(30, 60), Tuple3(x: 10, y: 20, z: 30)] {
            let fixture = AssemblyFixture([[], ["ASSEM CAMERA_ANGLES LOCAL 10 10"], []], visible: 1)
            let before = fixture.model.rotationAngleForStep(at: 2)
            let edit = LDrawStepAssemblyEdit.edit(settingViewingAngle: target, scope: .step, inModel: fixture.model)

            #expect(edit?.undoActionKey == "UndoStepAssemblyTurn")
            try apply(edit)

            #expect(fixture.lines(1).isEmpty)
            #expect(fixture.step(1).stepRotationType() == .relative)
            #expect(fixture.step(2).stepRotationType() == .end)
            #expect(fixture.sees(step: 1, at: target))
            #expect(fixture.sees(step: 2, at: before))
        }
    }

    @Test("Under an ABS rotation a turn of one step is a REL ROTSTEP, and the next step gets the ABS back")
    func turnUnderAnAbsoluteRotation() throws {
        let fixture = AssemblyFixture([[], [], []], visible: 1)
        fixture.step(0).setStepRotationType(.absolute)
        fixture.step(0).setRotationAngle(Tuple3(x: 0, y: 90, z: 0))

        let target = camera(30, 60)
        try apply(LDrawStepAssemblyEdit.edit(settingViewingAngle: target, scope: .step, inModel: fixture.model))

        #expect(fixture.lines(1).isEmpty)
        #expect(fixture.step(1).stepRotationType() == .relative)
        #expect(fixture.step(2).stepRotationType() == .absolute)
        #expect(fixture.sees(step: 1, at: target))
        #expect(fixture.sees(step: 2, at: Tuple3(x: 0, y: 90, z: 0)))
    }

    @Test("A turn writes the ROTSTEP numbers typed for it, when they say the turn")
    func turnKeepsTypedNumbers() throws {
        let fixture = AssemblyFixture([[], [], []], visible: 1)
        let typed = Tuple3(x: 180, y: -70, z: 180)
        let angle = LDrawStepAssemblyEdit.viewingAngle(forRotation: typed, inModel: fixture.model)

        try apply(LDrawStepAssemblyEdit.edit(settingViewingAngle: angle, rotation: typed, scope: .laterSteps,
                                             inModel: fixture.model))

        #expect(fixture.step(1).stepRotationType() == .relative)
        #expect(isClose(fixture.step(1).rotationAngle(), typed))
        #expect(fixture.sees(step: 1, at: angle))
    }

    @Test("A turn for later steps is a REL ROTSTEP that the camera still looks through")
    func turnForLaterSteps() throws {
        let fixture = AssemblyFixture([[], ["ASSEM CAMERA_ANGLES LOCAL 10 10"], []], visible: 1)
        let target = Tuple3(x: 10, y: 20, z: 30)

        try apply(LDrawStepAssemblyEdit.edit(settingViewingAngle: target, scope: .laterSteps, inModel: fixture.model))

        #expect(fixture.lines(1).isEmpty)
        #expect(fixture.step(1).stepRotationType() == .relative)
        #expect(fixture.sees(step: 1, at: target))
        #expect(fixture.sees(step: 2, at: target))
    }

    @Test("The whole model takes no turn, and leaves the step's camera line alone")
    func turnForTheModel() throws {
        let fixture = AssemblyFixture([[], ["ASSEM CAMERA_ANGLES LOCAL 10 10"]], visible: 1)
        let current = LDrawStepPartListPolicy.assemblyViewingAngle(forStepAt: 1, inModel: fixture.model)

        #expect(LDrawStepAssemblyEdit.edit(settingViewingAngle: camera(30, 60), scope: .model,
                                           inModel: fixture.model) == nil)

        // Even the angle the step would have without its line is a turn here.
        let inherited = LDrawStepAssemblyEdit.inheritedViewingAngle(in: fixture.model)
        #expect(LDrawStepAssemblyEdit.edit(settingViewingAngle: inherited, scope: .model,
                                           inModel: fixture.model) == nil)

        let edit = try #require(LDrawStepAssemblyEdit.edit(settingViewingAngle: current, scope: .model,
                                                           inModel: fixture.model))
        #expect(edit.isEmpty)
        #expect(fixture.lines(1) == ["ASSEM CAMERA_ANGLES LOCAL 10 10"])
    }

    @Test("Turning back to what the step inherits takes its camera line out")
    func turnBackDropsTheLine() throws {
        let fixture = AssemblyFixture([[], ["ASSEM CAMERA_ANGLES LOCAL 30 60"]], visible: 1)
        let inherited = fixture.model.rotationAngleForStep(at: 1)

        try apply(LDrawStepAssemblyEdit.edit(settingViewingAngle: inherited, scope: .step, inModel: fixture.model))
        #expect(fixture.lines(1).isEmpty)
    }

    // MARK: - Reset Angle

    /// Four steps on display at the third, which turns the parts on from the
    /// second's rotation, as a ROTSTEP REL of its own.
    private func rotatedFixture(_ lines: [String] = []) -> AssemblyFixture {
        let fixture = AssemblyFixture([[], [], lines, []], visible: 2)

        fixture.step(1).setStepRotationType(.relative)
        fixture.step(1).setRotationAngle(Tuple3(x: 180, y: 0, z: 180))
        fixture.step(2).setStepRotationType(.relative)
        fixture.step(2).setRotationAngle(Tuple3(x: 180, y: -70, z: 180))
        return fixture
    }

    @Test("Reset Angle for one step takes its ROTSTEP out, and the next step gets it, so later steps keep theirs")
    func resetAngleOfOneStep() throws {
        let fixture = rotatedFixture(["ASSEM CAMERA_ANGLES LOCAL 30 60"])
        let before = fixture.model.rotationAngleForStep(at: 1)
        let later = fixture.model.rotationAngleForStep(at: 3)
        let reset = LDrawStepAssemblyEdit.resetViewingAngle(scope: .step, in: fixture.model)

        try apply(LDrawStepAssemblyEdit.edit(settingViewingAngle: reset, scope: .step, inModel: fixture.model))

        #expect(fixture.lines(2).isEmpty)
        #expect(fixture.step(2).stepRotationType() == .none)
        #expect(fixture.step(3).stepRotationType() == .relative)
        #expect(fixture.sees(step: 2, at: before))
        #expect(fixture.sees(step: 3, at: later))
    }

    @Test("Reset Angle for later steps takes the ROTSTEP out, and the steps after it turn back too")
    func resetAngleOfLaterSteps() throws {
        let fixture = rotatedFixture()
        let before = fixture.model.rotationAngleForStep(at: 1)
        let reset = LDrawStepAssemblyEdit.resetViewingAngle(scope: .laterSteps, in: fixture.model)

        try apply(LDrawStepAssemblyEdit.edit(settingViewingAngle: reset, scope: .laterSteps, inModel: fixture.model))

        #expect(fixture.step(2).stepRotationType() == .none)
        #expect(fixture.step(3).stepRotationType() == .none)
        #expect(fixture.sees(step: 2, at: before))
        #expect(fixture.sees(step: 3, at: before))
    }

    @Test("Reset Angle for one step leaves the next step's own ROTSTEP alone")
    func resetAngleKeepsTheNextRotation() throws {
        let fixture = rotatedFixture()
        fixture.step(3).setStepRotationType(.absolute)
        fixture.step(3).setRotationAngle(Tuple3(x: 10, y: 20, z: 30))

        let reset = LDrawStepAssemblyEdit.resetViewingAngle(scope: .step, in: fixture.model)
        try apply(LDrawStepAssemblyEdit.edit(settingViewingAngle: reset, scope: .step, inModel: fixture.model))

        #expect(fixture.step(2).stepRotationType() == .none)
        #expect(fixture.step(3).stepRotationType() == .absolute)
        #expect(fixture.sees(step: 3, at: Tuple3(x: 10, y: 20, z: 30)))
    }

    @Test("On the first step, Reset Angle goes back to no rotation")
    func resetAngleOfTheFirstStep() throws {
        let fixture = AssemblyFixture([[], []], visible: 0)
        let unturned = fixture.model.rotationAngleForStep(at: 0)

        fixture.step(0).setStepRotationType(.absolute)
        fixture.step(0).setRotationAngle(Tuple3(x: 10, y: 20, z: 30))

        let reset = LDrawStepAssemblyEdit.resetViewingAngle(scope: .step, in: fixture.model)
        try apply(LDrawStepAssemblyEdit.edit(settingViewingAngle: reset, scope: .step, inModel: fixture.model))

        #expect(fixture.step(0).stepRotationType() == .none)
        #expect(fixture.step(1).stepRotationType() == .absolute)
        #expect(fixture.sees(step: 0, at: unturned))
    }

    @Test("For the whole model Reset Angle is the angle the step has, and writes nothing")
    func resetAngleForTheModel() throws {
        let fixture = rotatedFixture(["ASSEM CAMERA_ANGLES LOCAL 30 60"])
        let reset = LDrawStepAssemblyEdit.resetViewingAngle(scope: .model, in: fixture.model)

        #expect(fixture.sees(step: 2, at: reset))

        let edit = try #require(LDrawStepAssemblyEdit.edit(settingViewingAngle: reset, scope: .model,
                                                           inModel: fixture.model))
        #expect(edit.isEmpty)
        #expect(fixture.lines(2) == ["ASSEM CAMERA_ANGLES LOCAL 30 60"])
        #expect(fixture.step(2).stepRotationType() == .relative)
    }

    // MARK: - What the step inherits

    @Test("What the step inherits leaves out its own lines, and keeps its ROTSTEP")
    func inheritedValues() throws {
        let fixture = AssemblyFixture([["ASSEM MODEL_SCALE 1.1", "ASSEM CAMERA_ANGLES 10 20"],
                                       ["ASSEM MODEL_SCALE LOCAL 1.4", "ASSEM CAMERA_ANGLES LOCAL 30 60"]], visible: 1)
        fixture.step(1).setStepRotationType(.relative)
        fixture.step(1).setRotationAngle(Tuple3(x: 0, y: 90, z: 0))

        #expect(abs(LDrawStepAssemblyEdit.inheritedScale(in: fixture.model) - 1.1) < 0.0001)

        // The view the step has once its camera line is gone: its own ROTSTEP,
        // then the camera it inherits.
        let angle = LDrawStepAssemblyEdit.inheritedViewingAngle(in: fixture.model)
        let dropped = AssemblyFixture([["ASSEM MODEL_SCALE 1.1", "ASSEM CAMERA_ANGLES 10 20"], []], visible: 1)
        dropped.step(1).setStepRotationType(.relative)
        dropped.step(1).setRotationAngle(Tuple3(x: 0, y: 90, z: 0))

        #expect(dropped.sees(step: 1, at: angle))

        let bare = AssemblyFixture([[]], visible: 0)
        #expect(LDrawStepAssemblyEdit.inheritedScale(in: bare.model) == 1)
    }

    @Test("The inherited offset is the inherited line's, when both lines place the step alike")
    func inheritedOffset() throws {
        var offset = Point2(x: 9, y: 9)

        let alike = AssemblyFixture([["ASSEM PLACEMENT CENTER PAGE INSIDE 0.1 0"],
                                     ["ASSEM PLACEMENT LOCAL CENTER PAGE INSIDE 0.3 0.2"]], visible: 1)
        #expect(LDrawStepAssemblyEdit.getInheritedOffset(&offset, in: alike.model))
        #expect(abs(offset.x - 0.1) < 0.0001 && abs(offset.y) < 0.0001)

        let bare = AssemblyFixture([[], ["ASSEM PLACEMENT LOCAL CENTER PAGE INSIDE 0.3 0.2"]], visible: 1)
        #expect(LDrawStepAssemblyEdit.getInheritedOffset(&offset, in: bare.model))
        #expect(offset.x == 0 && offset.y == 0)

        let unlike = AssemblyFixture([[], ["ASSEM PLACEMENT LOCAL BOTTOM PAGE INSIDE 0 0"]], visible: 1)
        #expect(LDrawStepAssemblyEdit.getInheritedOffset(&offset, in: unlike.model) == false)
    }

    @Test("Reset gives what the step has without its own lines, or for the whole model what it has")
    func resetScaleAndOffset() throws {
        let fixture = AssemblyFixture([["ASSEM MODEL_SCALE 1.1", "ASSEM PLACEMENT CENTER PAGE INSIDE 0.1 0"],
                                       ["ASSEM MODEL_SCALE LOCAL 1.4",
                                        "ASSEM PLACEMENT LOCAL CENTER PAGE INSIDE 0.3 0.2"]], visible: 1)
        var offset = Point2(x: 9, y: 9)

        #expect(abs(LDrawStepAssemblyEdit.resetScale(scope: .step, in: fixture.model) - 1.1) < 0.0001)
        #expect(abs(LDrawStepAssemblyEdit.resetScale(scope: .laterSteps, in: fixture.model) - 1.1) < 0.0001)
        #expect(abs(LDrawStepAssemblyEdit.resetScale(scope: .model, in: fixture.model) - 1.4) < 0.0001)

        #expect(LDrawStepAssemblyEdit.getResetOffset(&offset, scope: .step, in: fixture.model))
        #expect(abs(offset.x - 0.1) < 0.0001 && abs(offset.y) < 0.0001)
        #expect(LDrawStepAssemblyEdit.getResetOffset(&offset, scope: .model, in: fixture.model))
        #expect(abs(offset.x - 0.3) < 0.0001 && abs(offset.y - 0.2) < 0.0001)

        // A step placed beside the page has no offset on it.
        let beside = AssemblyFixture([[], ["ASSEM PLACEMENT LOCAL BOTTOM PAGE OUTSIDE 0.3 0.2"]], visible: 1)
        #expect(LDrawStepAssemblyEdit.getResetOffset(&offset, scope: .model, in: beside.model))
        #expect(offset.x == 0 && offset.y == 0)
    }

    @Test("A view reads as LPub3D's angles after the step's rotation, and back")
    func latitudeAndLongitude() throws {
        let fixture = AssemblyFixture([[], []], visible: 1)
        fixture.step(1).setStepRotationType(.relative)
        fixture.step(1).setRotationAngle(Tuple3(x: 0, y: 90, z: 0))

        let angle = LDrawStepPartListPolicy.assemblyViewingAngle(latitude: 30, longitude: 60, inModel: fixture.model)
        var latitude = 0.0
        var longitude = 0.0

        #expect(LDrawStepPartListPolicy.getAssemblyLatitude(&latitude, longitude: &longitude, forViewingAngle: angle,
                                                          inModel: fixture.model))
        #expect(abs(latitude - 30) < 0.01 && abs(longitude - 60) < 0.01)

        // Bricksmith's 3D view is LPub3D's 23, 45.
        let plain = AssemblyFixture([[], []], visible: 1)
        #expect(LDrawStepPartListPolicy.getAssemblyLatitude(&latitude, longitude: &longitude,
                                                          forViewingAngle: plain.model.rotationAngleForStep(at: 1),
                                                          inModel: plain.model))
        #expect(abs(latitude - 23) < 0.05 && abs(longitude - 45) < 0.05)

        // Tilted to one side: no angles say it.
        #expect(LDrawStepPartListPolicy.getAssemblyLatitude(&latitude, longitude: &longitude,
                                                          forViewingAngle: Tuple3(x: 10, y: 20, z: 30),
                                                          inModel: plain.model) == false)
    }

    // MARK: - The step's ROTSTEP

    @Test("A view reads as the step's REL ROTSTEP, with the file's numbers while they say it, and back")
    func rotationOfAView() throws {
        let fixture = AssemblyFixture([[], [], []], visible: 2)
        let given = Tuple3(x: 180, y: -70, z: 180)

        fixture.step(1).setStepRotationType(.relative)
        fixture.step(1).setRotationAngle(given)

        // The step after it has the same ROTSTEP in force.
        let seen = LDrawStepPartListPolicy.assemblyViewingAngle(forStepAt: 2, inModel: fixture.model)
        let rotation = LDrawStepAssemblyEdit.rotation(forViewingAngle: seen, inModel: fixture.model)

        #expect(isClose(rotation, given))
        #expect(fixture.sees(step: 2, at: LDrawStepAssemblyEdit.viewingAngle(forRotation: rotation,
                                                                              inModel: fixture.model)))

        // Another turn reads as other numbers that say it, unless those typed
        // for it are preferred.
        let typed = Tuple3(x: 10, y: -70, z: 180)
        let turned = LDrawStepAssemblyEdit.viewingAngle(forRotation: typed, inModel: fixture.model)
        let read = LDrawStepAssemblyEdit.rotation(forViewingAngle: turned, inModel: fixture.model)

        #expect(isSameRotation(read, typed))
        #expect(isClose(LDrawStepAssemblyEdit.rotation(forViewingAngle: turned, preferring: typed,
                                                       inModel: fixture.model), typed))
        #expect(isSameRotation(LDrawStepAssemblyEdit.rotation(forViewingAngle: turned, preferring: given,
                                                              inModel: fixture.model), typed))

        // Bricksmith's 3D view is no turn at all.
        let plain = AssemblyFixture([[], []], visible: 1)
        let none = LDrawStepAssemblyEdit.rotation(forViewingAngle: plain.model.rotationAngleForStep(at: 1),
                                                  inModel: plain.model)
        #expect(isSameRotation(none, Tuple3(x: 0, y: 0, z: 0)))
    }

    @Test("A named view shows the parts with no rotation")
    func namedViewHasNoRotation() {
        let plain = AssemblyFixture([[]], visible: 0)
        let view = LDrawStepAssemblyEdit.viewingAngle(latitude: 23, longitude: 45)

        #expect(Matrix4RotationsWithinTolerance(Matrix4Rotate(IdentityMatrix4, view),
                                                Matrix4Rotate(IdentityMatrix4, plain.model.rotationAngleForStep(at: 0)),
                                                0.002))
    }

    @Test("A quick turn turns the parts about their own axes, from where they are")
    func quickTurns() {
        let front = LDrawStepAssemblyEdit.viewingAngle(latitude: 0, longitude: 0)
        let left = LDrawStepAssemblyEdit.viewingAngle(latitude: 0, longitude: 90)
        let right = LDrawStepAssemblyEdit.viewingAngle(latitude: 0, longitude: -90)
        let back = LDrawStepAssemblyEdit.viewingAngle(latitude: 0, longitude: 180)

        // Turned left, the side that faced the viewer went left, so the left
        // side shows.
        #expect(isSameRotation(LDrawStepAssemblyEdit.viewingAngle(front, afterTurn: .left), left))
        #expect(isSameRotation(LDrawStepAssemblyEdit.viewingAngle(front, afterTurn: .right), right))
        #expect(isSameRotation(LDrawStepAssemblyEdit.viewingAngle(front, afterTurn: .around), back))

        // Upside down, the front still faces the viewer and the top is below.
        let flipped = Matrix4Rotate(IdentityMatrix4, LDrawStepAssemblyEdit.viewingAngle(front, afterTurn: .upsideDown))
        let seen = Matrix4Rotate(IdentityMatrix4, front)
        let top = Point3(x: 0, y: -100, z: 0)
        let ahead = Point3(x: 0, y: 0, z: -100)

        #expect(abs(V3MulPointByProjMatrix(top, flipped).y + V3MulPointByProjMatrix(top, seen).y) < 0.01)
        #expect(abs(V3MulPointByProjMatrix(ahead, flipped).z - V3MulPointByProjMatrix(ahead, seen).z) < 0.01)

        // From the default view the parts turn on the same turntable.
        let corner = LDrawStepAssemblyEdit.viewingAngle(latitude: 23, longitude: 45)
        #expect(isSameRotation(LDrawStepAssemblyEdit.viewingAngle(corner, afterTurn: .left),
                               LDrawStepAssemblyEdit.viewingAngle(latitude: 23, longitude: 135)))
    }

    // MARK: - Together

    @Test("Edits made together are one, named for what changes")
    func combinedEdits() throws {
        let fixture = AssemblyFixture([[]], visible: 0)
        let scale = LDrawStepAssemblyEdit.edit(settingScale: 1.2, scope: .step, inModel: fixture.model)
        let offset = LDrawStepAssemblyEdit.edit(settingOffset: Point2(x: 0.1, y: 0), scope: .step, inModel: fixture.model)
        let nothing = LDrawStepAssemblyEdit.edit(settingScale: 1.0, scope: .step, inModel: fixture.model)

        #expect(LDrawStepAssemblyEdit.edit(combining: [scale, nothing]).undoActionKey == "UndoStepAssemblyScale")

        let both = LDrawStepAssemblyEdit.edit(combining: [scale, offset])
        #expect(both.undoActionKey == "UndoStepAssemblyArrange")

        try apply(both)
        #expect(Set(fixture.lines(0)) == ["ASSEM MODEL_SCALE LOCAL 1.2000",
                                          "ASSEM PLACEMENT LOCAL CENTER PAGE INSIDE 0.1000 0.0000"])
    }
}
