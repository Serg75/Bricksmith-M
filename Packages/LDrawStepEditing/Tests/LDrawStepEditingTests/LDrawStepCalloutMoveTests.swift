//
//  LDrawStepCalloutMoveTests.swift
//  LDrawStepEditingTests
//
//  What a dragged callout box writes to its step.
//
//  The fixtures build the directives in memory. Their parts name no file, so
//  nothing is loaded from a part library.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawStepEditing
import LDrawTestSupport

@Suite("Moving a callout's box", .usesStepSettings)
struct LDrawStepCalloutMoveTests {

    // MARK: - Fixtures

    private let page = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: 1000, height: 800))
    private let assembly = Box2(origin: Point2(x: 400, y: 300), size: Size2(width: 200, height: 100))
    private let nothing = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: 0, height: 0))

    private func part(_ name: String) -> LDrawPart {
        let color = LDrawColor()
        color.setColorCode(LDrawColorT(rawValue: 4)!)

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

    /// A callout of a one-step submodel on a page, with the lines given inside
    /// it, and the step it is in. Off the page the boxes are stacked.
    private func draggable(_ lines: [LDrawDirective] = [],
                           onPage: Bool = true) throws -> (box: LDrawStepCalloutBox, step: LDrawStep, file: LDrawFile) {
        let file = LDrawFile()
        let main = LDrawMPDModel.model() as! LDrawMPDModel
        main.setModelName("main.ldr")
        file.addSubmodel(main)

        let sub = LDrawMPDModel.model() as! LDrawMPDModel
        sub.setModelName("sub.ldr")
        file.addSubmodel(sub)
        sub.addStep().add(part("3003.dat") as LDrawDirective)

        let handedOver: LPubCalloutPliPerStep = lpub("CALLOUT PLI PER_STEP FALSE")
        let begin: LPubCallout = lpub("CALLOUT BEGIN")
        let end: LPubCallout = lpub("CALLOUT END")
        let step = main.addStep()

        for directive in [handedOver, begin, part("sub.ldr")] + lines + [end] {
            step.add(directive)
        }

        let metrics = LDrawStepPartListLayout.defaultMetrics()
        let options = LDrawStepCalloutBoxOptions(metrics: metrics,
                                                 assemblyScale: metrics.baseScale,
                                                 hostRect: page,
                                                 listFrame: nothing,
                                                 assemblyRect: assembly,
                                                 pointsPerPageInch: onPage ? 100 : 0,
                                                 listViewTransform: IdentityMatrix4,
                                                 showsLists: true)
        let box = try #require(LDrawStepCalloutBox.boxes(forCallouts: LDrawStepCallout.callouts(forStep: step),
                                                         inModel: main,
                                                         options: options).first)

        return (box, step, file)
    }

    @Test("Dragging a box rewrites the offset of its PLACEMENT line")
    func movingABoxUpdatesItsPlacement() throws {
        let placement: LPubPlacement = lpub("CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE")
        let dragged = try draggable([placement])
        let origin = dragged.box.frameRect.origin

        let edit = LDrawStepCalloutEdit.edit(movingBox: dragged.box,
                                        toOrigin: Point2(x: origin.x + 20, y: origin.y - 10),
                                        inStep: dragged.step)

        #expect(edit.kind == .update)
        #expect(edit.existingDirective === placement)
        #expect(edit.commandString == "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.1000 -0.1000")
        #expect(edit.undoActionKey == "UndoStepCalloutMove")
    }

    @Test("A box left where it was changes nothing")
    func unmovedBoxIsNoEdit() throws {
        let placement: LPubPlacement = lpub("CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.1000 -0.1000")
        let dragged = try draggable([placement])

        let edit = LDrawStepCalloutEdit.edit(movingBox: dragged.box,
                                             toOrigin: dragged.box.frameRect.origin,
                                             inStep: dragged.step)

        #expect(edit.kind == .none)
    }

    @Test("A box with no PLACEMENT line gets one, just before the callout's END")
    func movingABoxInsertsAPlacement() throws {
        let dragged = try draggable()
        let origin = dragged.box.frameRect.origin
        let directives = try #require(dragged.step.subdirectives() as? [LDrawDirective])
        let endIndex = try #require(directives.firstIndex { ($0 as? LPubCallout)?.line == .end })

        let edit = LDrawStepCalloutEdit.edit(movingBox: dragged.box,
                                        toOrigin: Point2(x: origin.x - 40, y: origin.y + 50),
                                        inStep: dragged.step)
        let line = try #require(edit.directiveToInsert as? LPubPlacement)

        #expect(edit.kind == .insert)
        #expect(edit.insertIndex == UInt(endIndex))
        #expect(line.lPubCommandString == "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE -0.2000 0.5000")
        #expect(line.position == .right)
    }

    @Test("Off the page a box cannot be moved")
    func stackedBoxesAreNotMoved() throws {
        let dragged = try draggable(onPage: false)

        let edit = LDrawStepCalloutEdit.edit(movingBox: dragged.box,
                                             toOrigin: Point2(x: 300, y: 300),
                                             inStep: dragged.step)

        #expect(dragged.box.isPlacedByFile == false)
        #expect(edit.kind == .none)
    }

    /// An offset is a share of the size of what the line names, and the
    /// assembly that stands in for it here is another size.
    @Test("A box placed against something that is not drawn cannot be moved")
    func standInBoxesAreNotMoved() throws {
        let placement: LPubPlacement = lpub("CALLOUT PLACEMENT RIGHT CENTER MULTI_STEP OUTSIDE")
        let dragged = try draggable([placement])
        let origin = dragged.box.frameRect.origin

        let edit = LDrawStepCalloutEdit.edit(movingBox: dragged.box,
                                             toOrigin: Point2(x: origin.x + 20, y: origin.y - 10),
                                             inStep: dragged.step)

        #expect(dragged.box.isPlacedByFile == false)
        #expect(edit.kind == .none)
    }
}
