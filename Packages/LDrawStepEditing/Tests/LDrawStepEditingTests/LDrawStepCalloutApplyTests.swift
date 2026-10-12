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

@Suite("Making a callout's edit through a host")
struct LDrawStepCalloutApplyTests {

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
