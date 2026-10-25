//
//  LDrawStepCalloutApplyTests.swift
//  LDrawStepEditingTests
//
//  How an edit is made through a host: which of the host's three changes it
//  asks for, in which order, and on which step.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawStepEditing
import LDrawTestSupport

private final class ConversionUndoHost: NSObject, LDrawStepCalloutEditHost {
    let undo = UndoManager()

    override init() {
        super.init()
        undo.groupsByEvent = false
    }

    func add(_ directive: LDrawDirective, toParent parent: LDrawContainer, at index: Int) {
        undo.registerUndo(withTarget: self) { host in host.delete(directive) }
        parent.insert(directive, at: index)
    }

    func delete(_ directive: LDrawDirective) {
        guard let parent = directive.enclosingDirective() else { return }
        let index = parent.subdirectives().index(of: directive)
        undo.registerUndo(withTarget: self) { host in
            host.add(directive, toParent: parent, at: index)
        }
        parent.remove(directive)
    }

    func preserveDirectiveState(_ directive: LDrawDirective) {}
}

/// Does what a document does, without the undo, and notes what it was asked.
private final class RecordingHost: NSObject, LDrawStepCalloutEditHost {

    var log: [String] = []

    func add(_ newDirective: LDrawDirective, toParent parent: LDrawContainer, at index: Int) {
        parent.insert(newDirective, at: index)
        log.append("add \(text(newDirective)) at \(index)")
    }

    func delete(_ doomedDirective: LDrawDirective) {
        doomedDirective.enclosingDirective()?.remove(doomedDirective)
        log.append("delete \(text(doomedDirective))")
    }

    func preserveDirectiveState(_ directive: LDrawDirective) {
        log.append("preserve \(text(directive))")
    }

    private func text(_ directive: LDrawDirective) -> String {
        (directive as? LPubCommand)?.lPubCommandString ?? (directive as? LDrawPart)?.referenceName() ?? "?"
    }
}

@Suite("Making a callout's edit through a host", .usesStepSettings)
struct LDrawStepCalloutApplyTests {

    // Parsing and copying type-1 lines ask the library to preload their files.
    // These fixtures use nonexistent names; the core library needs no renderer.
    private static let library: LDrawPartLibrary = {
        if let registered = LDrawPartLibrary.sharedPartLibraryIfRegistered() {
            return registered
        }
        let library = LDrawPartLibrary()
        LDrawPartLibrary.registerSharedPartLibrary(library)
        return library
    }()

    init() {
        _ = Self.library
    }

    @Test("Selected parts survive conversion, saving, reopening and expansion")
    func conversionRoundTrip() throws {
        let file = LDrawFile()
        let main = try #require(LDrawMPDModel.model() as? LDrawMPDModel)
        main.setModelName("main.ldr")
        file.addSubmodel(main)
        let step = main.addStep()
        let first = CalloutFixture.part("first.dat")
        let second = CalloutFixture.part("second.dat")
        var a = Matrix4Translate(IdentityMatrix4, Point3(x: 30, y: -20, z: 10))
        var b = Matrix4Translate(IdentityMatrix4, Point3(x: 50, y: 40, z: -10))
        first.setTransformationMatrix(&a)
        second.setTransformationMatrix(&b)
        step.add(first as LDrawDirective)
        step.add(second as LDrawDirective)
        let originals = [first.write(), second.write()]
        let host = RecordingHost()
        let edit = LDrawStepCalloutEdit.edit(convertingSelection: [second, first])
        #expect(edit.kind == .rewrite)
        #expect(file.submodels().count == 1) // Planning must not mutate.
        #expect(edit.apply(to: step, host: host))
        #expect(file.submodels().count == 2)
        #expect(LDrawStepCallout.callouts(forStep: step).count == 1)
        let reopened = try #require(LDrawFile.parse(fromFileContents: file.write()))
        let parent = reopened.firstModel()
        let savedStep = try #require(parent.steps().last as? LDrawStep)
        let callout = try #require(LDrawStepCallout.callouts(forStep: savedStep).first)
        let expand = LDrawStepCalloutEdit.edit(expanding: callout)
        #expect(expand.apply(to: savedStep, host: host))
        #expect(expand.resultParts.map { $0.write() } == originals)
        #expect(LDrawStepCallout.callouts(forStep: savedStep).isEmpty)
        #expect(reopened.submodels().count == 1)
    }

    @Test("Expanding one instance preserves its shared definition and other placements")
    func expansionPreservesSharedModelsAndColor() throws {
        let fixture = CalloutFixture()
        let callout = try fixture.callout
        let placement = try #require(callout.placements.first)
        let childStep = try #require(fixture.sub.steps().last as? LDrawStep)
        let child = try #require(childStep.subdirectives().firstObject as? LDrawPart)
        let current = LDrawColor()
        current.setColorCode(LDrawColorT.currentColor)
        child.setLDrawColor(current)
        let other = CalloutFixture.part("sub.ldr")
        fixture.step.add(other as LDrawDirective)
        let before = (fixture.sub as LDrawDirective).write()
        var transform = Matrix4Rotate(IdentityMatrix4, Point3(x: 0, y: 90, z: 0))
        transform = Matrix4Translate(transform, Point3(x: 30, y: 20, z: 10))
        placement.setTransformationMatrix(&transform)
        let edit = LDrawStepCalloutEdit.edit(expanding: callout)
        #expect(edit.apply(to: fixture.step, host: RecordingHost()))
        let expanded = try #require(edit.resultParts.first)
        #expect(expanded.lDrawColor().colorCode() == placement.lDrawColor().colorCode())
        #expect(expanded.position().x == 30)
        #expect((fixture.sub as LDrawDirective).write() == before)
        #expect(other.enclosingDirective() === fixture.step)
        #expect(child.lDrawColor().colorCode() == LDrawColorT.currentColor)
    }

    @Test("Repeated mirrored placements preserve transforms and nested references")
    func mirroredNestedPlacements() throws {
        let fixture = CalloutFixture()
        let nested = try #require(LDrawMPDModel.model() as? LDrawMPDModel)
        nested.setModelName("nested.ldr")
        fixture.file.addSubmodel(nested)
        nested.addStep().add(CalloutFixture.part("leaf.dat") as LDrawDirective)
        let contents = try #require(fixture.sub.steps().last as? LDrawStep)
        let child = try #require(contents.subdirectives().firstObject as? LDrawPart)
        child.setDisplayName("nested.ldr", parse: false, in: nil)
        var local = Matrix4Translate(IdentityMatrix4, Point3(x: 10, y: 20, z: 30))
        child.setTransformationMatrix(&local)
        let mirrored = CalloutFixture.part("sub.ldr")
        var transform = Matrix4Scale(IdentityMatrix4, Point3(x: -1, y: 1, z: 1))
        transform = Matrix4Rotate(transform, Point3(x: 0, y: 90, z: 0))
        transform = Matrix4Translate(transform, Point3(x: 100, y: -40, z: 60))
        mirrored.setTransformationMatrix(&transform)
        fixture.step.insert(mirrored, at: fixture.step.subdirectives().count - 1)
        let callout = try fixture.callout
        #expect(callout.placements.count == 2)
        let expected = CalloutFixture.part("nested.ldr")
        var combined = Matrix4Multiply(local, transform)
        expected.setTransformationMatrix(&combined)
        let edit = LDrawStepCalloutEdit.edit(expanding: callout)
        #expect(edit.apply(to: fixture.step, host: RecordingHost()))
        #expect(edit.resultParts.count == 2)
        #expect(edit.resultParts.last?.write() == expected.write())
        #expect(edit.resultParts.allSatisfy { $0.referenceName() == "nested.ldr" })
        #expect(fixture.file.submodels().count == 2)
        #expect(nested.enclosingDirective() === fixture.file)
        #expect(fixture.sub.enclosingDirective() == nil)
    }

    @Test("A one-step ROTSTEP callout expands without changing geometry or the parent view")
    func rotatedSingleStepCallout() throws {
        let text = """
        0 FILE main.ldr
        0 Main
        0 Name: main.ldr
        0 !LPUB CALLOUT BEGIN
        1 71 0 0 0 1 0 0 0 1 0 0 0 1 inner block.ldr
        0 !LPUB CALLOUT POINTER BOTTOM 0.269 0.352 0.100 0
        0 !LPUB CALLOUT END
        0 ROTSTEP 0 45 0 REL
        0 NOFILE
        0 FILE inner block.ldr
        0 inner block
        0 Name: inner block.ldr
        1 72 0 -40 -130 1 0 0 0 1 0 0 0 1 3666.dat
        1 71 0 -64 -130 1 0 0 0 1 0 0 0 1 3701.dat
        1 71 0 -72 -130 -1 0 0 0 1 0 0 0 -1 60479.dat
        1 71 -20.000017 -54.499989 -120.000008 1 0 0 0 0 -1 0 1 0 3062b.dat
        0 ROTSTEP 0 90 0 REL
        0 NOFILE
        """
        let file = try #require(LDrawFile.parse(fromFileContents: text))
        let main = file.firstModel()
        let step = try #require(main.steps().first as? LDrawStep)
        let callout = try #require(LDrawStepCallout.callouts(forStep: step).first)
        let submodel = try #require(callout.submodels.first)
        let contents = try #require(submodel.steps().first as? LDrawStep)
        let parts = try #require(contents.subdirectives() as? [LDrawPart])
        let expected = parts.map { $0.write() }
        let submodelBefore = (submodel as LDrawDirective).write()
        let before = file.write()
        let parentRotation = step.stepRotationType()
        let parentAngle = step.rotationAngle()
        let edit = LDrawStepCalloutEdit.edit(expanding: callout)
        #expect(edit.kind == .rewrite)
        let host = ConversionUndoHost()
        host.undo.beginUndoGrouping()
        #expect(edit.apply(to: step, host: host))
        host.undo.endUndoGrouping()
        #expect(edit.resultParts.map { $0.write() } == expected)
        #expect(step.stepRotationType() == parentRotation)
        #expect(step.rotationAngle().y == parentAngle.y)
        #expect((submodel as LDrawDirective).write() == submodelBefore)
        #expect(LDrawStepCallout.callouts(forStep: step).isEmpty)
        let after = file.write()
        host.undo.undo()
        #expect(file.write() == before)
        host.undo.redo()
        #expect(file.write() == after)
    }

    @Test("Unrelated parent group removals allow repeated callout expansion", arguments: [false, true])
    func unrelatedGroupRemovals(usesUnrelatedGroup: Bool) throws {
        let fixture = CalloutFixture()
        let contents = try #require(fixture.sub.steps().last as? LDrawStep)
        let child = try #require(contents.subdirectives().firstObject as? LDrawPart)
        if usesUnrelatedGroup {
            child.group = "seat"
        }
        let second = CalloutFixture.part("sub.ldr")
        fixture.step.insert(second, at: fixture.step.subdirectives().count - 1)
        let later = fixture.main.addStep()
        let removal = LPubRemoveGroup()
        removal.groupName = "doors"
        later.add(removal)
        let before = fixture.file.write()
        let callout = try fixture.callout
        #expect(callout.placements.count == 2)
        let edit = LDrawStepCalloutEdit.edit(expanding: callout)
        #expect(edit.kind == .rewrite)
        let host = ConversionUndoHost()
        host.undo.beginUndoGrouping()
        #expect(edit.apply(to: fixture.step, host: host))
        host.undo.endUndoGrouping()
        #expect(edit.resultParts.count == 2)
        #expect(edit.resultParts.allSatisfy { $0.group == child.group })
        #expect(removal.enclosingDirective() === later)
        #expect(removal.groupName == "doors")
        #expect(fixture.sub.enclosingDirective() == nil)
        let after = fixture.file.write()
        host.undo.undo()
        #expect(fixture.file.write() == before)
        host.undo.redo()
        #expect(fixture.file.write() == after)
    }

    @Test("A parent removal matching an expanded part's group still blocks expansion")
    func conflictingGroupRemoval() throws {
        let fixture = CalloutFixture()
        let contents = try #require(fixture.sub.steps().last as? LDrawStep)
        let child = try #require(contents.subdirectives().firstObject as? LDrawPart)
        child.group = "doors"
        let removal = LPubRemoveGroup()
        removal.groupName = "doors"
        fixture.main.addStep().add(removal)
        let before = fixture.file.write()
        let edit = LDrawStepCalloutEdit.edit(expanding: try fixture.callout)
        #expect(edit.kind == .none)
        #expect(!edit.apply(to: fixture.step, host: RecordingHost()))
        #expect(fixture.file.write() == before)
    }

    @Test("Parking brake steps flatten into the parent, with undo and optional shared use",
          arguments: [false, true])
    func flattenParkingBrake(shared: Bool) throws {
        let text = """
        0 FILE main.ldr
        0 Main
        0 Name: main.ldr
        0 !LPUB CALLOUT BEGIN
        1 0 0 -16 100 1 0 0 0 1 0 0 0 1 parking brake.ldr
        0 !LPUB CALLOUT POINTER BOTTOM 0.675 0.682 0.413 0
        0 !LPUB CALLOUT END
        0 ROTSTEP 0 45 0 REL
        0 NOFILE
        0 FILE parking brake.ldr
        0 parking brake
        0 Name: parking brake.ldr
        1 0 0 0 0 1 0 0 0 1 0 0 0 1 3022.dat
        1 71 0 -8 -10 1 0 0 0 1 0 0 0 1 48336.dat
        0 ROTSTEP -156.139 46.439 179.079 ABS
        1 0 0 -16 -10 1 0 0 0 1 0 0 0 1 3023b.dat
        0 STEP
        1 0 0 -8 10 -1 0 0 0 1 0 0 0 -1 28802.dat
        0 STEP
        1 0 0 -7.653821 -35.76757 0 0 1 -0.961262 -0.275637 0 0.275637 -0.961262 0 15712.dat
        0 ROTSTEP 21.863 48.065 1.267 ABS
        0 !LPUB CALLOUT BEGIN
        0 !LPUB CALLOUT POINTER CENTER 0 0.246429 0.63
        0 !LPUB CALLOUT END
        1 71 0 -9.858917 -43.457668 0 0 1 0.275637 -0.961262 0 0.961262 0.275637 0 61184.dat
        0 STEP
        0 NOFILE
        """
        let file = try #require(LDrawFile.parse(fromFileContents: text))
        let main = file.firstModel()
        let step = try #require(main.steps().first as? LDrawStep)
        let callout = try #require(LDrawStepCallout.callouts(forStep: step).first)
        let sub = try #require(callout.submodels.first)
        let placement = try #require(callout.placements.first)
        if shared {
            main.addStep().add(CalloutFixture.part("parking brake.ldr") as LDrawDirective)
        }
        let originals = (sub.steps() as! [LDrawStep]).flatMap {
            ($0.subdirectives() as! [LDrawDirective]).compactMap { $0 as? LDrawPart }
        }
        let expected = originals.map { part -> String in
            let copy = CalloutFixture.part(part.referenceName())
            copy.setLDrawColor(part.lDrawColor())
            var matrix = Matrix4Multiply(part.transformationMatrix(), placement.transformationMatrix())
            copy.setTransformationMatrix(&matrix)
            return copy.write()
        }
        let before = file.write()
        let definition = (sub as LDrawDirective).write()
        let stepCount = main.steps().count
        let parentAngle = step.rotationAngle()
        let parentRotation = step.stepRotationType()
        let host = ConversionUndoHost()
        let edit = LDrawStepCalloutEdit.edit(expanding: callout)
        #expect(edit.kind == .rewrite)
        host.undo.beginUndoGrouping()
        #expect(edit.apply(to: step, host: host))
        host.undo.endUndoGrouping()
        #expect(edit.resultParts.count == 6)
        #expect(edit.resultParts.map { $0.write() } == expected)
        #expect(step.subdirectives().count == 6)
        #expect(main.steps().count == stepCount)
        #expect(step.rotationAngle().x == parentAngle.x)
        #expect(step.rotationAngle().y == parentAngle.y)
        #expect(step.rotationAngle().z == parentAngle.z)
        #expect(step.stepRotationType() == parentRotation)
        #expect((sub.enclosingDirective() != nil) == shared)
        #expect((sub as LDrawDirective).write() == definition)
        let after = file.write()
        host.undo.undo()
        #expect(file.write() == before)
        host.undo.redo()
        #expect(file.write() == after)
    }

    @Test("Flattening refuses geometry-affecting metadata in any source step")
    func flattenRejectsIgnoredParts() throws {
        let fixture = CalloutFixture(stepCount: 3)
        let last = try #require(fixture.sub.steps().last as? LDrawStep)
        last.insert(CalloutFixture.parsed("PART BEGIN IGN"), at: 0)
        last.add(CalloutFixture.parsed("PART END"))
        let before = fixture.file.write()
        let edit = LDrawStepCalloutEdit.edit(expanding: try fixture.callout)
        #expect(edit.kind == .none)
        #expect(!edit.apply(to: fixture.step, host: RecordingHost()))
        #expect(fixture.file.write() == before)
    }

    @Test("Conversion refuses mixed steps and scoped directives without mutation")
    func invalidConversionsDoNothing() throws {
        let fixture = CalloutFixture()
        let a = CalloutFixture.part("a.dat")
        let b = CalloutFixture.part("b.dat")
        let second = fixture.main.addStep()
        second.add(a as LDrawDirective)
        fixture.step.add(b as LDrawDirective)
        #expect(!LDrawStepCalloutEdit.canConvert(selection: [a, b])) // Existing callout metadata blocks this step.
        #expect(!LDrawStepCalloutEdit.canConvert(selection: []))
        second.insert(CalloutFixture.parsed("PLI BEGIN IGN"), at: 0)
        let before = fixture.file.write()
        let edit = LDrawStepCalloutEdit.edit(convertingSelection: [a])
        #expect(!edit.apply(to: second, host: RecordingHost()))
        #expect(fixture.file.write() == before)
        let multiple = CalloutFixture(stepCount: 2)
        #expect(LDrawStepCalloutEdit.edit(expanding: try multiple.callout).kind == .rewrite)
    }

    @Test("Porsche layout metadata and unrelated group removals permit extraction")
    func extractionWithPageLayout() throws {
        let fixture = CalloutFixture()
        let step = fixture.main.addStep()
        let metadata = ["MULTI_STEP END", "MULTI_STEP BEGIN", "PLI CONSTRAIN HEIGHT 2.1706"]
            .map { CalloutFixture.parsed($0) }
        for line in metadata { step.add(line) }
        let a = CalloutFixture.part("a.dat")
        let b = CalloutFixture.part("b.dat")
        let remaining = CalloutFixture.part("c.dat")
        step.add(a as LDrawDirective)
        step.add(b as LDrawDirective)
        step.add(remaining as LDrawDirective)
        let removal = LPubRemoveGroup()
        removal.groupName = "doors"
        fixture.main.addStep().add(removal)
        let original = fixture.file.write()
        let host = ConversionUndoHost()
        #expect(LDrawStepCalloutEdit.canConvert(selection: [a, b]))
        let edit = LDrawStepCalloutEdit.edit(convertingSelection: [a, b])
        host.undo.beginUndoGrouping()
        #expect(edit.apply(to: step, host: host))
        host.undo.endUndoGrouping()
        for (index, line) in metadata.enumerated() {
            #expect(step.subdirectives().object(at: index) as? LDrawDirective === line)
        }
        #expect(remaining.enclosingDirective() === step)
        #expect(LDrawStepCallout.callouts(forStep: step).count == 1)
        let converted = fixture.file.write()
        host.undo.undo()
        #expect(fixture.file.write() == original)
        host.undo.redo()
        #expect(fixture.file.write() == converted)
    }

    @Test("Extraction rejects affected groups and selections spanning layout changes")
    func extractionPreservesScopes() {
        let fixture = CalloutFixture()
        let step = fixture.main.addStep()
        let a = CalloutFixture.part("a.dat")
        let b = CalloutFixture.part("b.dat")
        step.add(a as LDrawDirective)
        step.add(CalloutFixture.parsed("MULTI_STEP DIVIDER"))
        step.add(b as LDrawDirective)
        #expect(!LDrawStepCalloutEdit.canConvert(selection: [a, b]))
        #expect(LDrawStepCalloutEdit.canConvert(selection: [a]))
        let removal = LPubRemoveGroup()
        removal.groupName = "doors"
        fixture.main.addStep().add(removal)
        a.group = "doors"
        let before = fixture.file.write()
        let edit = LDrawStepCalloutEdit.edit(convertingSelection: [a])
        #expect(!edit.apply(to: step, host: RecordingHost()))
        #expect(fixture.file.write() == before)
        #expect(LDrawStepCalloutEdit.canConvert(selection: [b]))
    }

    @Test("Selection across steps uses document order and undoes every source step")
    func extractionAcrossSteps() throws {
        let fixture = CalloutFixture()
        let first = fixture.main.addStep()
        let second = fixture.main.addStep()
        let a = CalloutFixture.part("a.dat")
        let b = CalloutFixture.part("b.dat")
        let remaining = CalloutFixture.part("c.dat")
        first.add(a as LDrawDirective)
        first.add(remaining as LDrawDirective)
        second.add(b as LDrawDirective)
        let metadata = CalloutFixture.parsed("PLI CONSTRAIN HEIGHT 2.1706")
        second.insert(metadata, at: 0)
        let original = fixture.file.write()
        let stepCount = fixture.main.steps().count
        #expect(LDrawStepCalloutEdit.canConvert(selection: [b, a]))
        #expect(!LDrawStepCalloutEdit.canConvert(selection: [a, a]))
        let foreign = CalloutFixture.part("foreign.dat")
        let otherFixture = CalloutFixture()
        otherFixture.sub.addStep().add(foreign as LDrawDirective)
        #expect(!LDrawStepCalloutEdit.canConvert(selection: [a, foreign]))
        let host = ConversionUndoHost()
        let edit = LDrawStepCalloutEdit.edit(convertingSelection: [b, a])
        #expect(edit.targetStep === first)
        host.undo.beginUndoGrouping()
        #expect(edit.apply(to: second, host: host))
        host.undo.endUndoGrouping()
        #expect(fixture.main.steps().count == stepCount)
        #expect(remaining.enclosingDirective() === first)
        #expect(second.subdirectives().count == 1)
        #expect(metadata.enclosingDirective() === second)
        let submodel = try #require(edit.resultParts.first?.referencedMPDSubmodel())
        let contents = try #require(submodel.steps().first as? LDrawStep)
        let parts = contents.subdirectives().compactMap { $0 as? LDrawPart }
        #expect(parts.map { $0.referenceName() } == ["a.dat", "b.dat"])
        let converted = fixture.file.write()
        host.undo.undo()
        #expect(fixture.file.write() == original)
        host.undo.redo()
        #expect(fixture.file.write() == converted)
    }

    @Test("Extraction avoids name collisions and reuses a selected embedded model")
    func uniqueNamesAndReuse() throws {
        let fixture = CalloutFixture()
        fixture.sub.setModelName("callout.ldr")
        let step = fixture.main.addStep()
        let part = CalloutFixture.part("a.dat")
        step.add(part as LDrawDirective)
        let edit = LDrawStepCalloutEdit.edit(convertingSelection: [part])
        #expect(edit.apply(to: step, host: RecordingHost()))
        #expect(edit.resultParts.first?.referenceName() == "callout-2.ldr")
        let otherStep = fixture.main.addStep()
        let reference = CalloutFixture.part("callout.ldr")
        otherStep.add(reference as LDrawDirective)
        let count = fixture.file.submodels().count
        let reuse = LDrawStepCalloutEdit.edit(convertingSelection: [reference])
        #expect(reuse.apply(to: otherStep, host: RecordingHost()))
        #expect(fixture.file.submodels().count == count)
        #expect(reuse.resultParts.first === reference)
    }

    @Test("A reference in another submodel preserves the expanded definition")
    func expansionKeepsReferencesElsewhere() throws {
        let fixture = CalloutFixture()
        let other = try #require(LDrawMPDModel.model() as? LDrawMPDModel)
        other.setModelName("other.ldr")
        fixture.file.addSubmodel(other)
        let reference = CalloutFixture.part("SUB.LDR")
        other.addStep().add(reference as LDrawDirective)
        let edit = LDrawStepCalloutEdit.edit(expanding: try fixture.callout)
        #expect(edit.apply(to: fixture.step, host: RecordingHost()))
        #expect(fixture.sub.enclosingDirective() === fixture.file)
        #expect(reference.referencedMPDSubmodel() === fixture.sub)
        #expect(fixture.file.submodels().count == 3)
    }

    @Test("Conversion and expansion each undo and redo as one transaction")
    func conversionUndoRedo() throws {
        let fixture = CalloutFixture()
        let step = fixture.main.addStep()
        let a = CalloutFixture.part("a.dat")
        let b = CalloutFixture.part("b.dat")
        a.group = "selected group"
        step.add(a as LDrawDirective)
        step.add(b as LDrawDirective)
        let host = ConversionUndoHost()
        let original = fixture.file.write()
        let edit = LDrawStepCalloutEdit.edit(convertingSelection: [a, b])
        host.undo.beginUndoGrouping()
        #expect(edit.apply(to: step, host: host))
        host.undo.endUndoGrouping()
        let converted = fixture.file.write()
        host.undo.undo()
        #expect(fixture.file.write() == original)
        #expect(!host.undo.canUndo)
        host.undo.redo()
        #expect(fixture.file.write() == converted)
        let callout = try #require(LDrawStepCallout.callouts(forStep: step).first)
        let expand = LDrawStepCalloutEdit.edit(expanding: callout)
        host.undo.beginUndoGrouping()
        #expect(expand.apply(to: step, host: host))
        host.undo.endUndoGrouping()
        #expect(expand.resultParts.first?.group == "selected group")
        let expanded = fixture.file.write()
        host.undo.undo()
        #expect(fixture.file.write() == converted)
        host.undo.redo()
        #expect(fixture.file.write() == expanded)
    }

    @Test("A second callout leaves the first intact and cannot extract its placements")
    func secondCalloutInSameStep() throws {
        let fixture = CalloutFixture()
        let step = fixture.main.addStep()
        let a = CalloutFixture.part("a.dat")
        let b = CalloutFixture.part("b.dat")
        step.add(a as LDrawDirective)
        step.add(b as LDrawDirective)
        let host = RecordingHost()
        let first = LDrawStepCalloutEdit.edit(convertingSelection: [a])
        #expect(first.apply(to: step, host: host))
        #expect(!LDrawStepCalloutEdit.canConvert(selection: first.resultParts))
        let second = LDrawStepCalloutEdit.edit(convertingSelection: [b])
        #expect(second.apply(to: step, host: host))
        #expect(LDrawStepCallout.callouts(forStep: step).count == 2)
        let callout = try #require(LDrawStepCalloutEdit.callout(inSelection: second.resultParts))
        #expect(LDrawStepCalloutEdit.edit(expanding: callout).apply(to: step, host: host))
        #expect(LDrawStepCallout.callouts(forStep: step).count == 1)
        #expect(first.resultParts.first?.enclosingDirective() === step)
    }

    @Test("A source step left with nothing goes, unless it sets a rotation")
    func emptiedSourceSteps() throws {
        let fixture = CalloutFixture()
        let first = fixture.main.addStep()
        let emptied = fixture.main.addStep()
        let rotated = fixture.main.addStep()
        let a = CalloutFixture.part("a.dat")
        let b = CalloutFixture.part("b.dat")
        let c = CalloutFixture.part("c.dat")
        first.add(a as LDrawDirective)
        emptied.add(b as LDrawDirective)
        rotated.add(c as LDrawDirective)
        rotated.setStepRotationType(.relative)
        let original = fixture.file.write()
        let host = ConversionUndoHost()
        let edit = LDrawStepCalloutEdit.edit(convertingSelection: [c, b, a])
        host.undo.beginUndoGrouping()
        #expect(edit.apply(to: first, host: host))
        host.undo.endUndoGrouping()
        #expect(emptied.enclosingDirective() == nil)
        #expect(rotated.enclosingDirective() === fixture.main)
        #expect(rotated.subdirectives().count == 0)
        #expect(edit.resultParts.first?.lDrawColor().colorCode() == LDrawColorT.currentColor)
        host.undo.undo()
        #expect(fixture.file.write() == original)
    }

    @Test("Meta lines Bricksmith does not read are passed over, but INVERTNEXT stays with its part")
    func plainMetaLines() throws {
        let fixture = CalloutFixture()
        let contents = try #require(fixture.sub.steps().last as? LDrawStep)
        contents.insert(Self.meta("BFC CERTIFY CCW"), at: 0)
        #expect(LDrawStepCalloutEdit.canExpand(try fixture.callout))
        contents.insert(Self.meta("BFC INVERTNEXT"), at: 1)
        #expect(!LDrawStepCalloutEdit.canExpand(try fixture.callout))
        #expect(LDrawStepCalloutEdit.edit(expanding: try fixture.callout).kind == .none)

        let step = fixture.main.addStep()
        let a = CalloutFixture.part("a.dat")
        let b = CalloutFixture.part("b.dat")
        step.add(Self.meta("BFC CERTIFY CCW"))
        step.add(a as LDrawDirective)
        step.add(Self.meta("BFC INVERTNEXT"))
        step.add(b as LDrawDirective)
        #expect(LDrawStepCalloutEdit.canConvert(selection: [a]))
        #expect(!LDrawStepCalloutEdit.canConvert(selection: [a, b]))
    }

    private static func meta(_ text: String) -> LDrawMetaCommand {
        let line = LDrawMetaCommand()
        line.commandString = text
        return line
    }

    @Test("A moved box has its PLACEMENT line kept for undo, then changed")
    func updateKeepsTheOldLineFirst() throws {
        let placement: LPubPlacement = CalloutFixture.lpub("CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE")
        let fixture = CalloutFixture(lines: [placement])
        let box = try fixture.box()
        let origin = box.frameRect.origin
        let host = RecordingHost()

        let edit = LDrawStepCalloutEdit.edit(movingBox: box,
                                             toOrigin: Point2(x: origin.x + 20, y: origin.y - 10),
                                             inStep: fixture.step)

        #expect(edit.apply(to: fixture.step, host: host))
        #expect(host.log == ["preserve CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
        #expect(placement.lPubCommandString == "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.1000 -0.1000")
    }

    @Test("A box with no PLACEMENT line gets one put into its step")
    func insertGoesIntoTheCalloutsStep() throws {
        let fixture = CalloutFixture()
        let box = try fixture.box()
        let origin = box.frameRect.origin
        let host = RecordingHost()

        let edit = LDrawStepCalloutEdit.edit(movingBox: box,
                                             toOrigin: Point2(x: origin.x - 40, y: origin.y + 50),
                                             inStep: fixture.step)

        #expect(edit.kind == .insert)
        #expect(edit.apply(to: fixture.step, host: host))
        #expect(host.log.count == 1)

        let lines = CalloutFixture.lines(of: fixture.step)
        #expect(lines.count == 5)
        #expect(lines[3].hasPrefix("CALLOUT PLACEMENT"))
        #expect(lines[4] == "CALLOUT END")
    }

    @Test("A divider goes into the step of the submodel, not the step on display")
    func dividerGoesIntoItsOwnStep() throws {
        let fixture = CalloutFixture(stepCount: 3)
        let second = try #require(try fixture.box().steps.dropFirst().first).step
        let host = RecordingHost()

        let edit = LDrawStepCalloutEdit.edit(addingDividerBefore: second)

        #expect(edit.apply(to: fixture.step, host: host))
        #expect(CalloutFixture.lines(of: second).first == "CALLOUT DIVIDER")
        #expect(CalloutFixture.lines(of: fixture.step).contains("CALLOUT DIVIDER") == false)
    }

    @Test("Removing a callout takes its lines out and leaves the placement")
    func removalDeletesBeforeItInserts() throws {
        let fixture = CalloutFixture()
        let host = RecordingHost()

        let edit = LDrawStepCalloutEdit.edit(removing: try fixture.callout)

        #expect(edit.apply(to: fixture.step, host: host))
        #expect(host.log.allSatisfy { $0.hasPrefix("delete ") })
        #expect(CalloutFixture.lines(of: fixture.step).contains("sub.ldr"))
        #expect(CalloutFixture.lines(of: fixture.step).contains("CALLOUT BEGIN") == false)
        #expect(CalloutFixture.lines(of: fixture.step).contains("CALLOUT END") == false)
    }

    @Test("An edit that changes nothing asks the host for nothing")
    func nothingToDoTouchesNothing() throws {
        let text = "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.1000 -0.1000"
        let placement: LPubPlacement = CalloutFixture.lpub(text)
        let fixture = CalloutFixture(lines: [placement])
        let box = try fixture.box()
        let host = RecordingHost()

        let edit = LDrawStepCalloutEdit.edit(movingBox: box, toOrigin: box.frameRect.origin, inStep: fixture.step)

        #expect(edit.kind == .none)
        #expect(edit.apply(to: fixture.step, host: host) == false)
        #expect(host.log.isEmpty)
    }

    @Test("With no step to put a line into, nothing is done")
    func noStepNoInsert() throws {
        let fixture = CalloutFixture()
        let box = try fixture.box()
        let origin = box.frameRect.origin
        let host = RecordingHost()

        let edit = LDrawStepCalloutEdit.edit(movingBox: box,
                                             toOrigin: Point2(x: origin.x - 40, y: origin.y + 50),
                                             inStep: fixture.step)

        #expect(edit.apply(to: nil, host: host) == false)
        #expect(host.log.isEmpty)
    }
}
