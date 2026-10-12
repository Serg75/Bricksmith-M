//
//  LDrawStepCalloutTrackerTests.swift
//  LDrawStepEditingTests
//
//  What a press on a callout's box, or on the button that leads back, means.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawStepEditing

@Suite("A press on a callout's box")
struct LDrawStepCalloutTrackerTests {

    // MARK: - Fixtures

    private let viewSize = Size2(width: 1000, height: 800)
    private let button = Box2(origin: Point2(x: 12, y: 760), size: Size2(width: 120, height: 28))
    private let noButton = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: 0, height: 0))
    private let nowhere = Point2(x: 990, y: 10)

    private func tracker(_ box: LDrawStepCalloutBox,
                         onPage: Bool = true,
                         button: Box2? = nil) -> LDrawStepCalloutTracker {
        let tracker = LDrawStepCalloutTracker()
        tracker.show([box], onPage: onPage, viewSize: viewSize, returnButtonRect: button ?? noButton)
        return tracker
    }

    private func moved(_ point: Point2, _ dx: Double, _ dy: Double) -> Point2 {
        Point2(x: point.x + dx, y: point.y + dy)
    }

    // MARK: - Clicks

    @Test("A click on a box chooses its callout")
    func clickChoosesTheCallout() throws {
        let fixture = CalloutFixture()
        let box = try fixture.box()
        let tracker = tracker(box)
        let point = middle(of: box.frameRect)

        #expect(tracker.isLink(at: point))
        #expect(tracker.begin(at: point))
        #expect(tracker.end(at: point, inStep: fixture.step) == .choseCallout)
        #expect(tracker.chosenCallout === box.callout)
        #expect(tracker.chosenSubmodel === fixture.sub)
    }

    @Test("A click on a callout of two submodels says which of them was clicked")
    func clickSaysWhichSubmodel() throws {
        let fixture = CalloutFixture()
        let other = LDrawMPDModel.model() as! LDrawMPDModel
        other.setModelName("other.ldr")
        fixture.file.addSubmodel(other)
        other.addStep().add(CalloutFixture.part("3004.dat") as LDrawDirective)
        fixture.step.insert(CalloutFixture.part("other.ldr"), at: 3)

        let box = try fixture.box()
        let tracker = tracker(box)

        try #require(box.steps.count == 2)

        for (step, submodel) in zip(box.steps, [fixture.sub, other]) {
            let point = middle(of: step.rect)

            #expect(tracker.begin(at: point))
            #expect(tracker.end(at: point, inStep: fixture.step) == .choseCallout)
            #expect(tracker.chosenSubmodel === submodel)
        }
    }

    @Test("The callout is found again after the step was laid out anew")
    func clickSurvivesANewLayout() throws {
        let fixture = CalloutFixture()
        let first = try fixture.box()
        let tracker = tracker(first)
        let point = middle(of: first.frameRect)

        #expect(tracker.begin(at: point))

        let second = try fixture.box()
        tracker.show([second], onPage: true, viewSize: viewSize, returnButtonRect: noButton)

        #expect(tracker.end(at: point, inStep: fixture.step) == .choseCallout)
        #expect(tracker.chosenCallout === second.callout)
    }

    @Test("A press let go somewhere else follows nothing, and is still used")
    func releaseElsewhereFollowsNothing() throws {
        let fixture = CalloutFixture()
        let box = try fixture.box(onPage: false)
        let tracker = tracker(box, onPage: false)

        #expect(tracker.begin(at: middle(of: box.frameRect)))
        #expect(tracker.end(at: nowhere, inStep: fixture.step) == .used)
    }

    @Test("A press on nothing is not the tracker's")
    func pressOnNothing() throws {
        let fixture = CalloutFixture()
        let tracker = tracker(try fixture.box())

        #expect(tracker.isLink(at: nowhere) == false)
        #expect(tracker.begin(at: nowhere) == false)
        #expect(tracker.drag(to: moved(nowhere, 30, 0)) == .none)
        #expect(tracker.end(at: nowhere, inStep: fixture.step) == .none)
    }

    @Test("A click on the button that leads back chooses the way back")
    func clickOnTheButton() throws {
        let fixture = CalloutFixture()
        let tracker = tracker(try fixture.box(), button: button)
        let point = middle(of: button)

        #expect(tracker.isLink(at: point))
        #expect(tracker.begin(at: point))
        #expect(tracker.drag(to: moved(point, 40, 0)) == .used)
        #expect(tracker.isDragging == false)
        #expect(tracker.end(at: point, inStep: fixture.step) == .choseReturn)
    }

    @Test("A point outside the view hits nothing, even over a box")
    func outsideTheView() throws {
        let fixture = CalloutFixture()
        let box = try fixture.box()
        let tracker = LDrawStepCalloutTracker()
        tracker.show([box], onPage: true, viewSize: Size2(width: 50, height: 50), returnButtonRect: noButton)

        #expect(tracker.begin(at: middle(of: box.frameRect)) == false)
    }

    // MARK: - Drags

    @Test("A small move is still a click")
    func smallMoveIsAClick() throws {
        let fixture = CalloutFixture()
        let box = try fixture.box()
        let tracker = tracker(box)
        let point = middle(of: box.frameRect)

        #expect(tracker.begin(at: point))
        #expect(tracker.drag(to: moved(point, 2, 0)) == .used)
        #expect(tracker.isDragging == false)
        #expect(tracker.end(at: moved(point, 2, 0), inStep: fixture.step) == .choseCallout)
    }

    @Test("Past that, the box's corner follows the pointer")
    func dragMovesTheCorner() throws {
        let fixture = CalloutFixture()
        let box = try fixture.box()
        let tracker = tracker(box)
        let point = middle(of: box.frameRect)
        let origin = box.frameRect.origin

        #expect(tracker.begin(at: point))
        #expect(tracker.drag(to: moved(point, 20, 5)) == .moved)
        #expect(tracker.isDragging)
        #expect(tracker.draggedBoxIndex == 0)
        #expect(abs(tracker.dragOrigin.x - (origin.x + 20)) < 0.0001)
        #expect(abs(tracker.dragOrigin.y - (origin.y + 5)) < 0.0001)
    }

    @Test("Letting go of a drag ends it with an edit, and follows no callout")
    func dropGivesAnEdit() throws {
        let fixture = CalloutFixture()
        let box = try fixture.box()
        let tracker = tracker(box)
        let point = middle(of: box.frameRect)

        #expect(tracker.begin(at: point))
        #expect(tracker.drag(to: moved(point, 20, 5)) == .moved)
        #expect(tracker.end(at: point, inStep: fixture.step) == .dropped)
        #expect(tracker.isDragging == false)
        #expect(tracker.edit?.undoActionKey == "UndoStepCalloutMove")
    }

    @Test("An abandoned drag writes nothing, and the rest of the gesture is still used")
    func abandonedDrag() throws {
        let fixture = CalloutFixture()
        let box = try fixture.box()
        let tracker = tracker(box)
        let point = middle(of: box.frameRect)

        #expect(tracker.abandonDrag() == false)
        #expect(tracker.begin(at: point))
        #expect(tracker.drag(to: moved(point, 20, 5)) == .moved)
        #expect(tracker.abandonDrag())
        #expect(tracker.isDragging == false)
        #expect(tracker.drag(to: moved(point, 60, 5)) == .used)
        #expect(tracker.end(at: point, inStep: fixture.step) == .dropped)
        #expect(tracker.edit == nil)
    }

    @Test("Off the page a box cannot be dragged")
    func noDragOffThePage() throws {
        let fixture = CalloutFixture()
        let box = try fixture.box(onPage: false)
        let tracker = tracker(box, onPage: false)
        let point = middle(of: box.frameRect)

        #expect(tracker.begin(at: point))
        #expect(tracker.drag(to: moved(point, 40, 0)) == .used)
        #expect(tracker.isDragging == false)
        #expect(tracker.end(at: point, inStep: fixture.step) == .choseCallout)
    }

    @Test("Forgetting the gesture leaves nothing to end")
    func resetForgets() throws {
        let fixture = CalloutFixture()
        let box = try fixture.box()
        let tracker = tracker(box)
        let point = middle(of: box.frameRect)

        #expect(tracker.begin(at: point))
        #expect(tracker.drag(to: moved(point, 20, 5)) == .moved)

        tracker.reset()

        #expect(tracker.isDragging == false)
        #expect(tracker.end(at: point, inStep: fixture.step) == .none)
    }
}
