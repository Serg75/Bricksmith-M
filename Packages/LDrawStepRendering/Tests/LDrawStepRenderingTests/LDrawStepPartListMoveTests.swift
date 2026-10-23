//
//  LDrawStepPartListMoveTests.swift
//  LDrawStepRenderingTests
//
//  Dragging the parts list on LPub3D's page, and the PLI PLACEMENT line the
//  drop writes, read back by the layout.
//
//  Created by Sergey Slobodenyuk on 2026-10-21.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawStepEditing
import LDrawStepRendering

extension StepOverlayTests {

    @Suite("Moving the parts list on the page")
    final class LDrawStepPartListMoveTests {

        init() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
        }

        deinit {
            LDrawStepPartList.setEnabled(false)
            LDrawStepPartList.setUsesLPubScale(false)
        }

        /// An LPub line, parsed as the file would be.
        private func lpub(_ text: String) -> LDrawDirective {
            let lines = ["0 !LPUB " + text, "0 STEP"]
            let step = LDrawStep(lines: lines, in: NSRange(location: 0, length: lines.count), parentGroup: nil)

            return (step!.subdirectives() as! [LDrawDirective])[0]
        }

        /// A one-step model on an 8.5 by 11 page, 64 points to the inch, with
        /// one part in its list.
        private func model(_ lines: [String] = []) -> LDrawModel {
            let model = LDrawModel()
            let step = model.addStep()

            for line in ["PAGE SIZE 8.5 11"] + lines {
                step.add(lpub(line))
            }
            step.add(CalloutFixture.part("3001.dat") as LDrawDirective)

            model.setStepDisplay(true)
            model.setMaximumStepIndexForStepDisplay(0)
            return model
        }

        private func presentation(of model: LDrawModel, preview: Point2? = nil) -> LDrawStepPartListPresentation {
            var host = LDrawStepPartListHostState()
            host.viewSize = Size2(width: 1000, height: 800)
            host.assemblyScale = 1
            host.pageCenterInView = Point2(x: 500, y: 400)

            if let origin = preview {
                host.hasListPreview = true
                host.listPreviewOrigin = origin
            }
            return LDrawStepPartListPresentation(model: model, host: host)
        }

        private func lines(of model: LDrawModel) -> [String] {
            ((model.steps().first as! LDrawStep).subdirectives() as! [LDrawDirective]).compactMap {
                ($0 as? LPubCommand)?.lPubCommandString
            }
        }

        private func isClose(_ a: Point2, _ b: Point2) -> Bool {
            abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.01
        }

        /// Drags the list by the pointer from its middle so its corner goes to
        /// `origin`, and drops it.
        private func drop(_ model: LDrawModel, at origin: Point2) throws -> LDrawStepAssemblyEdit? {
            let start = presentation(of: model)
            let frame = start.frameRect
            let tracker = LDrawStepPartListMoveTracker()
            let grab = Point2(x: frame.origin.x + frame.size.width / 2, y: frame.origin.y + frame.size.height / 2)

            try #require(tracker.begin(at: grab, presentation: start))
            tracker.drag(to: Point2(x: grab.x + origin.x - frame.origin.x, y: grab.y + origin.y - frame.origin.y))
            return tracker.editForDrop(inModel: model, scope: .step)
        }

        @Test("Dropped near one of the page's places, the list goes there with no offset")
        func dropOnAPlace() throws {
            let model = model()
            let place = presentation(of: model).listOrigin(atPagePosition: .topRight)

            let edit = try #require(try drop(model, at: Point2(x: place.x - 4, y: place.y + 3)))
            #expect(edit.undoActionKey == "UndoStepPartListMove")
            #expect(edit.apply(host: ApplyingHost()))

            #expect(lines(of: model).contains("PLI PLACEMENT LOCAL TOP_RIGHT PAGE INSIDE"))
            #expect(isClose(presentation(of: model).frameRect.origin, place))
        }

        @Test("Dropped anywhere else, it goes to the nearest place, with the offset from it")
        func dropWithAnOffset() throws {
            let model = model()
            let start = presentation(of: model)
            let place = start.listOrigin(atPagePosition: .topLeft)
            let target = Point2(x: place.x + 40, y: place.y + 60)

            let edit = try #require(try drop(model, at: target))
            #expect(edit.apply(host: ApplyingHost()))

            let page = start.pageRect.size
            let expected = String(format: "PLI PLACEMENT LOCAL TOP_LEFT PAGE INSIDE %.4f %.4f",
                                  40 / page.width, 60 / page.height)

            // The offset is written with four decimals, so it reads back a
            // few hundredths of a point away.
            let placed = presentation(of: model).frameRect.origin

            #expect(lines(of: model).contains(expected))
            #expect(abs(placed.x - target.x) < 0.05 && abs(placed.y - target.y) < 0.05)
        }

        @Test("Where the list snaps, the page's line it meets is a guide")
        func guidesWhereItSnaps() throws {
            let model = model()
            let start = presentation(of: model)
            let frame = start.frameRect
            let page = start.pageRect
            let place = start.listOrigin(atPagePosition: .topRight)
            let tracker = LDrawStepPartListMoveTracker()
            let grab = Point2(x: frame.origin.x + 2, y: frame.origin.y + 2)

            func lines() -> [Box2] {
                tracker.guides.withUnsafeBytes { Array($0.bindMemory(to: Box2.self)) }
            }

            try #require(tracker.begin(at: grab, presentation: start))

            // Near the top right place: its right edge meets the right margin,
            // and its top the top margin.
            tracker.drag(to: Point2(x: grab.x + place.x - frame.origin.x - 3, y: grab.y + place.y - frame.origin.y + 2))

            let snapped = lines()
            #expect(snapped.count == 2)
            #expect(snapped.contains { $0.size.width == 0 && abs($0.origin.x - (place.x + frame.size.width)) < 0.01
                                       && abs($0.size.height - page.size.height) < 0.01 })
            #expect(snapped.contains { $0.size.height == 0 && abs($0.origin.y - place.y) < 0.01 })

            // Away from every place there are none, and none once it ends.
            tracker.drag(to: Point2(x: grab.x + 150, y: grab.y + 200))
            #expect(lines().isEmpty)

            tracker.drag(to: Point2(x: grab.x + place.x - frame.origin.x, y: grab.y + place.y - frame.origin.y))
            tracker.end()
            #expect(lines().isEmpty)
        }

        @Test("Put at a corner point, as the arrow keys put it, the list goes to the nearest place with the offset")
        func placeAtAnOrigin() throws {
            let model = model()
            let start = presentation(of: model)
            let place = start.listOrigin(atPagePosition: .topRight)
            let step = 0.05 * start.pointsPerPageInch
            let nudged = Point2(x: place.x - step, y: place.y)

            let edit = try #require(LDrawStepPartListMoveTracker.edit(placingListAt: nudged, presentation: start,
                                                                      scope: .step, inModel: model))
            #expect(edit.apply(host: ApplyingHost()))

            let expected = String(format: "PLI PLACEMENT LOCAL TOP_RIGHT PAGE INSIDE %.4f %.4f",
                                  -step / start.pageRect.size.width, 0.0)
            #expect(lines(of: model).contains(expected))
            #expect(abs(presentation(of: model).frameRect.origin.x - nudged.x) < 0.05)
        }

        @Test("A press that hardly moves, or one off the list, places nothing")
        func clickIsNoMove() throws {
            let model = model()
            let start = presentation(of: model)
            let frame = start.frameRect
            let tracker = LDrawStepPartListMoveTracker()

            #expect(tracker.begin(at: Point2(x: frame.origin.x - 20, y: frame.origin.y - 20), presentation: start) == false)

            let middle = Point2(x: frame.origin.x + frame.size.width / 2, y: frame.origin.y + frame.size.height / 2)
            #expect(tracker.begin(at: middle, presentation: start))
            tracker.drag(to: Point2(x: middle.x + 1, y: middle.y))
            #expect(tracker.editForDrop(inModel: model, scope: .step) == nil)
        }

        @Test("While the list is dragged, the frame is where the drag holds it")
        func previewHoldsTheFrame() {
            let model = model()
            let held = Point2(x: 300, y: 200)

            #expect(isClose(presentation(of: model, preview: held).frameRect.origin, held))
        }

        @Test("Beside the assembly, and back to what the step inherits")
        func besideAndReset() throws {
            let model = model(["PLI PLACEMENT LOCAL TOP_RIGHT PAGE INSIDE"])

            #expect(LDrawStepAssemblyEdit.edit(placingListBesideAssemblyAt: .right, scope: .step, inModel: model)
                .apply(host: ApplyingHost()))
            #expect(lines(of: model).contains("PLI PLACEMENT LOCAL RIGHT CENTER ASSEM OUTSIDE"))

            #expect(LDrawStepAssemblyEdit.edit(resettingListPlacementIn: model).apply(host: ApplyingHost()))
            #expect(lines(of: model).allSatisfy { $0.hasPrefix("PLI PLACEMENT") == false })
        }

        @Test("The step's own place shows a pin on the corner that stays put, and clicking it clears the line")
        func ownPlacePin() throws {
            let model = model(["PLI PLACEMENT LOCAL TOP_RIGHT PAGE INSIDE"])
            let placed = presentation(of: model)
            let frame = placed.frameRect
            let pin = placed.placementPinRect
            let corner = Point2(x: frame.origin.x + frame.size.width, y: frame.origin.y)

            #expect(placed.placementPinned)
            #expect(isClose(Point2(x: pin.origin.x + pin.size.width / 2, y: pin.origin.y + pin.size.height / 2), corner))
            #expect(placed.control(at: corner) == .placementPin)

            // It is drawn in the pin color, just outside the frame's corner.
            let renderer = LDrawStepOverlayRenderer()
            let size = Size2(width: 1000, height: 800)
            let plain = Canvas(width: 1000, height: 800)
            let pinned = Canvas(width: 1000, height: 800)

            renderer.presentation = placed
            renderer.drawPageAndFrame(in: plain.context, viewSize: size)
            renderer.pinColor = CGColor(srgbRed: 0, green: 0.4, blue: 1, alpha: 1)
            renderer.drawPageAndFrame(in: pinned.context, viewSize: size)

            #expect(plain.isInked(Int(corner.x) + 2, Int(corner.y) - 2) == false)
            #expect(pinned.isInked(Int(corner.x) + 2, Int(corner.y) - 2))

            #expect(LDrawStepAssemblyEdit.edit(resettingListPlacementIn: model).apply(host: ApplyingHost()))
            #expect(lines(of: model).allSatisfy { $0.hasPrefix("PLI PLACEMENT") == false })
            #expect(presentation(of: model).placementPinned == false)
        }

        @Test("A place that carries on to later steps, or a list being dragged, shows no corner pin")
        func noPlacePin() {
            let carried = presentation(of: model(["PLI PLACEMENT TOP_RIGHT PAGE INSIDE"]))
            let frame = carried.frameRect
            let corner = Point2(x: frame.origin.x + frame.size.width, y: frame.origin.y)

            #expect(carried.placementPinned == false)
            #expect(carried.control(at: corner) != .placementPin)

            let dragged = presentation(of: model(["PLI PLACEMENT LOCAL TOP_RIGHT PAGE INSIDE"]),
                                       preview: Point2(x: 300, y: 200))
            #expect(dragged.placementPinned == false)
        }
    }
}
