//
//  LDrawStepCalloutFollowTests.swift
//  LDrawFeaturesTests
//
//  How the boxes of a page move with their submodels, and what stops them.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures

extension StepPartListStaticSettings {

    @Suite("Callouts that follow their submodels", .serialized)
    final class LDrawStepCalloutFollowTests {

        init() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
        }

        deinit {
            LDrawStepPartList.setEnabled(false)
            LDrawStepPartList.setUsesLPubScale(false)
            LDrawStepPartList.setPlacesCalloutsAutomatically(false)
        }

        // MARK: - Fixtures

        private func lpub(_ text: String) -> LDrawDirective {
            let lines = ["0 !LPUB " + text, "0 STEP"]
            let step = LDrawStep(lines: lines, in: NSRange(location: 0, length: lines.count), parentGroup: nil)
            return (step!.subdirectives() as! [LDrawDirective])[0]
        }

        private func part(_ name: String, at position: Point3 = Point3(x: 0, y: 0, z: 0)) -> LDrawPart {
            var components = IdentityComponents
            components.translate = position

            let part = LDrawPart()
            part.setDisplayName(name, parse: false, in: nil)
            part.setTransformComponents(components)
            return part
        }

        /// A file whose main model shows one step on a page. The step calls
        /// sub.ldr out once for each PLACEMENT line, and places a part of its
        /// own, so it has a parts list. The caller keeps the file.
        private func pageModel(_ placements: [String]) -> (file: LDrawFile, model: LDrawModel) {
            let file = LDrawFile()
            let main = LDrawMPDModel.model() as! LDrawMPDModel
            main.setModelName("main.ldr")
            file.addSubmodel(main)
            let sub = LDrawMPDModel.model() as! LDrawMPDModel
            sub.setModelName("sub.ldr")
            file.addSubmodel(sub)
            sub.addStep().add(part("3001.dat") as LDrawDirective)

            let step = main.addStep()
            step.add(lpub("PAGE SIZE 8.5 11"))

            for placement in placements {
                step.add(lpub("CALLOUT BEGIN"))
                step.add(part("sub.ldr") as LDrawDirective)
                step.add(lpub(placement))
                step.add(lpub("CALLOUT END"))
            }

            step.add(part("3001.dat") as LDrawDirective)
            main.setStepDisplay(true)
            main.setMaximumStepIndexForStepDisplay(UInt(main.steps().count - 1))

            return (file, main)
        }

        /// A view with the page's middle and the assembly's box in its middle.
        private func host() -> LDrawStepPartListHostState {
            var host = LDrawStepPartListHostState()
            host.viewSize = Size2(width: 1000, height: 800)
            host.assemblyScale = 2
            host.pageCenterInView = Point2(x: 500, y: 400)
            host.assemblyRect = Box2(origin: Point2(x: 470, y: 380), size: Size2(width: 60, height: 40))
            return host
        }

        private func data<Value>(_ values: [Value]) -> Data {
            values.withUnsafeBufferPointer { Data(buffer: $0) }
        }

        /// Where what a box places is drawn: its middle, then where its arrows
        /// go.
        private func places(middle: Point2, arrows: [Box2] = []) -> Data {
            data([rect(middle.x, middle.y, 0, 0)] + arrows)
        }

        /// Moves the boxes by these shifts, on the file's sides. `targets` has
        /// where each box's arrows go now, and `laidOut` where they went when
        /// the step was laid out.
        private func move(_ presentation: LDrawStepPartListPresentation,
                          by shifts: [Point2],
                          targets: [[Box2]] = [],
                          laidOut: [[Box2]] = []) {
            let now = shifts.indices.map { places(middle: shifts[$0], arrows: $0 < targets.count ? targets[$0] : []) }
            let then = shifts.indices.map {
                places(middle: Point2(x: 0, y: 0), arrows: $0 < laidOut.count ? laidOut[$0] : [])
            }

            presentation.moveCalloutBoxes(from: then, to: now, arrangement: nil)
        }

        /// Lays the boxes out at the step's own angle, as a step is before the
        /// camera is turned. A box that has not been drawn has nowhere to move
        /// from.
        private func layOut(_ presentation: LDrawStepPartListPresentation,
                            _ arrangement: LDrawStepCalloutArrangement) {
            arrangement.time = 9
            presentation.restCalloutBoxes(arrangement: arrangement)
        }

        /// No shift for either of two boxes.
        private let still = [Point2(x: 0, y: 0), Point2(x: 0, y: 0)]

        private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Box2 {
            Box2(origin: Point2(x: x, y: y), size: Size2(width: width, height: height))
        }

        private func same(_ a: Point2, _ b: Point2) -> Bool { a.x == b.x && a.y == b.y }

        private func maxX(_ box: Box2) -> Double { box.origin.x + box.size.width }
        private func maxY(_ box: Box2) -> Double { box.origin.y + box.size.height }

        private func overlap(_ a: Box2, _ b: Box2) -> Bool {
            a.origin.x < maxX(b) - 0.001 && b.origin.x < maxX(a) - 0.001
                && a.origin.y < maxY(b) - 0.001 && b.origin.y < maxY(a) - 0.001
        }

        private func holds(_ outer: Box2, _ inner: Box2) -> Bool {
            inner.origin.x >= outer.origin.x - 0.001 && inner.origin.y >= outer.origin.y - 0.001
                && maxX(inner) <= maxX(outer) + 0.001 && maxY(inner) <= maxY(outer) + 0.001
        }

        /// The room the list's frame keeps to the page's edge, which a box
        /// keeps too.
        private func spacing(_ presentation: LDrawStepPartListPresentation) -> Double {
            presentation.frameRect.origin.x - presentation.pageRect.origin.x
        }

        // MARK: - Tests

        @Test("With nothing moved the boxes stay where the file puts them")
        func nothingMovedNothingMoves() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let placed = try #require(presentation.calloutBoxes.first).frameRect

            move(presentation, by: [Point2(x: 0, y: 0)])
            #expect(same(try #require(presentation.calloutBoxes.first).frameRect.origin, placed.origin))

            presentation.moveCalloutBoxes(from: [], to: [], arrangement: nil)
            #expect(same(try #require(presentation.calloutBoxes.first).frameRect.origin, placed.origin))
        }

        @Test("A box goes as far as its submodel where there is room, and everything in it goes along")
        func boxFollows() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let box = try #require(presentation.calloutBoxes.first)
            let placed = box.frameRect
            let picture = try #require(box.pictures.first).rect

            move(presentation, by: [Point2(x: 40, y: -30)])

            #expect(abs(box.frameRect.origin.x - (placed.origin.x + 40)) < 0.001)
            #expect(abs(box.frameRect.origin.y - (placed.origin.y - 30)) < 0.001)
            #expect(abs(try #require(box.pictures.first).rect.origin.x - (picture.origin.x + 40)) < 0.001)

            // A shift is measured from where the file puts the box, not from
            // where the last one left it.
            move(presentation, by: [Point2(x: 10, y: 0)])
            #expect(abs(box.frameRect.origin.x - (placed.origin.x + 10)) < 0.001)
            #expect(abs(box.frameRect.origin.y - placed.origin.y) < 0.001)
        }

        @Test("A box stops short of the page's edge")
        func boxStaysOnThePage() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let box = try #require(presentation.calloutBoxes.first)
            let page = presentation.pageRect
            let room = spacing(presentation)

            move(presentation, by: [Point2(x: 5000, y: 5000)])

            #expect(room > 0)
            #expect(abs(maxX(box.frameRect) - (maxX(page) - room)) < 0.001)
            #expect(abs(maxY(box.frameRect) - (maxY(page) - room)) < 0.001)
        }

        @Test("A box the file puts off the page stays there")
        func boxOffThePageStays() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 20.0000 0.0000"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let box = try #require(presentation.calloutBoxes.first)
            let placed = box.frameRect

            try #require(maxX(placed) > maxX(presentation.pageRect))

            move(presentation, by: [Point2(x: -100, y: 50)])

            #expect(same(box.frameRect.origin, placed.origin))
        }

        @Test("A box that reaches a little over the page's edge still moves, and may go back there")
        func boxJustOverTheEdgeMoves() throws {
            let plain = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let measured = LDrawStepPartListPresentation(model: plain.model, host: host())
            let page = measured.pageRect
            let frame = try #require(measured.calloutBoxes.first).frameRect

            // Six points over the right edge, with a tenth of an inch at 12.8.
            let offset = (maxX(page) + 6 - maxX(frame)) / 60
            let line = String(format: "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE %.4f 0.0000", offset)
            let fixture = pageModel([line])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let box = try #require(presentation.calloutBoxes.first)
            let placed = box.frameRect

            try #require(abs(maxX(placed) - (maxX(page) + 6)) < 0.01)

            move(presentation, by: [Point2(x: -100, y: 30)])
            #expect(abs(box.frameRect.origin.x - (placed.origin.x - 100)) < 0.001)
            #expect(abs(box.frameRect.origin.y - (placed.origin.y + 30)) < 0.001)

            move(presentation, by: [Point2(x: 100, y: 0)])
            #expect(abs(box.frameRect.origin.x - placed.origin.x) < 0.001)
        }

        @Test("A box stays clear of the parts list")
        func boxKeepsClearOfTheList() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let box = try #require(presentation.calloutBoxes.first)
            let list = presentation.frameRect

            try #require(list.size.width > 0)

            move(presentation, by: [Point2(x: -5000, y: -5000)])

            #expect(overlap(box.frameRect, list) == false)
            #expect(holds(presentation.pageRect, box.frameRect))
        }

        @Test("Two boxes that meet stop each other, and keep their order")
        func boxesKeepClearOfEachOther() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE",
                                     "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let left = presentation.calloutBoxes[0]
            let right = presentation.calloutBoxes[1]
            let gap = right.frameRect.origin.x - maxX(left.frameRect)
            let kept = min(gap, spacing(presentation))
            let middle = (maxX(left.frameRect) + right.frameRect.origin.x) / 2

            try #require(gap > 0)

            move(presentation, by: [Point2(x: 300, y: 0), Point2(x: -300, y: 0)])

            // Each was stopped as far from where it started as the other.
            #expect(abs(right.frameRect.origin.x - maxX(left.frameRect) - kept) < 0.01)
            #expect(abs((maxX(left.frameRect) + right.frameRect.origin.x) / 2 - middle) < 0.01)

            // One that moves away is not held back.
            move(presentation, by: [Point2(x: -50, y: 0), Point2(x: 80, y: 20)])
            #expect(abs(right.frameRect.origin.x - maxX(left.frameRect) - (gap + 130)) < 0.001)
        }

        @Test("A box that is off the page is in the way of one that moves")
        func boxOffThePageIsInTheWay() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE",
                                     "CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE -8.3000 0.0000"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let moving = presentation.calloutBoxes[0]
            let staying = presentation.calloutBoxes[1]
            let placed = staying.frameRect
            let page = presentation.pageRect

            // Half over the page's left edge.
            try #require(placed.origin.x < page.origin.x && maxX(placed) > page.origin.x)

            move(presentation, by: [Point2(x: -5000, y: 0), Point2(x: 100, y: 0)])

            #expect(same(staying.frameRect.origin, placed.origin))
            #expect(moving.frameRect.origin.x >= maxX(placed))
        }

        // MARK: - Margins

        @Test("A box keeps its own MARGINS to the page's edge, where they are more than the page's")
        func boxKeepsItsMarginsToThePage() throws {
            let fixture = pageModel(["CALLOUT MARGINS LOCAL 0.25 0.1"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let box = try #require(presentation.calloutBoxes.first)
            let page = presentation.pageRect
            let inch = presentation.pointsPerPageInch

            move(presentation, by: [Point2(x: 5000, y: 5000)])

            #expect(abs(maxX(box.frameRect) - (maxX(page) - 0.25 * inch)) < 0.001)
            #expect(abs(maxY(box.frameRect) - (maxY(page) - 0.1 * inch)) < 0.001)

            // The page's own margin is the least a box keeps.
            let thin = pageModel(["CALLOUT MARGINS LOCAL 0.01 0.01"])
            let tight = LDrawStepPartListPresentation(model: thin.model, host: host())

            move(tight, by: [Point2(x: 5000, y: 5000)])
            #expect(abs(maxX(try #require(tight.calloutBoxes.first).frameRect) - (maxX(page) - 0.05 * inch)) < 0.001)
        }

        @Test("Two boxes keep the larger of their margins between them")
        func boxesKeepTheLargerMargin() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE",
                                     "CALLOUT MARGINS LOCAL 0.3 0.3"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let left = presentation.calloutBoxes[0]
            let right = presentation.calloutBoxes[1]

            try #require(right.frameRect.origin.x - maxX(left.frameRect) > 0.3 * presentation.pointsPerPageInch)

            move(presentation, by: [Point2(x: 300, y: 0), Point2(x: -300, y: 0)])

            #expect(abs(right.frameRect.origin.x - maxX(left.frameRect) - 0.3 * presentation.pointsPerPageInch) < 0.01)
        }

        // MARK: - Arrows

        @Test("A box moves out of the way of where another box's arrow goes")
        func boxKeepsOffAnotherArrow() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE",
                                     "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let left = presentation.calloutBoxes[0]
            let right = presentation.calloutBoxes[1]
            let placed = left.frameRect
            let rightPlaced = right.frameRect
            let inch = presentation.pointsPerPageInch

            // The right box's arrow went into the assembly, and now goes to a
            // placement that has moved under the left box.
            let then = rect(490, 390, 20, 20)
            let now = rect(placed.origin.x + 10, 390, 20, 20)

            move(presentation, by: still, targets: [[], [now]], laidOut: [[], [then]])

            // The margin, and half the width of an arrow's head.
            let room = (0.05 + 1.0 / 16.0) * inch
            #expect(abs(maxX(left.frameRect) - (now.origin.x - room)) < 0.001)
            #expect(abs(left.frameRect.origin.y - placed.origin.y) < 0.001)
            #expect(same(right.frameRect.origin, rightPlaced.origin))

            // With the placement back where it was, so is the box.
            move(presentation, by: still, targets: [[], [then]], laidOut: [[], [then]])
            #expect(abs(left.frameRect.origin.x - placed.origin.x) < 0.001)
        }

        @Test("A box keeps room for its own arrow")
        func boxKeepsRoomForItsArrow() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 1.0000 0.0000"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let box = try #require(presentation.calloutBoxes.first)
            let placed = box.frameRect
            let inch = presentation.pointsPerPageInch

            // The placement its arrow goes to was a good way to the left, and
            // has come up to the box's edge.
            let then = rect(490, 390, 20, 20)
            let now = rect(placed.origin.x - 25, 390, 20, 20)

            try #require(placed.origin.x - maxX(then) > 0.5 * inch)

            move(presentation, by: [Point2(x: 0, y: 0)], targets: [[now]], laidOut: [[then]])

            #expect(abs(box.frameRect.origin.x - (maxX(now) + 0.5 * inch)) < 0.001)
        }

        @Test("Where the file leaves an arrow less room, the box keeps that")
        func boxKeepsTheRoomTheFileLeaves() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let box = try #require(presentation.calloutBoxes.first)
            let placed = box.frameRect

            // Ten points from the box, and then twenty further right.
            let then = rect(placed.origin.x - 30, 390, 20, 20)
            let now = rect(placed.origin.x - 10, 390, 20, 20)

            move(presentation, by: [Point2(x: 0, y: 0)], targets: [[now]], laidOut: [[then]])
            #expect(abs(box.frameRect.origin.x - (placed.origin.x + 20)) < 0.001)

            // An arrow that goes where it went moves nothing.
            move(presentation, by: [Point2(x: 0, y: 0)], targets: [[then]], laidOut: [[then]])
            #expect(same(box.frameRect.origin, placed.origin))
        }

        @Test("The page's edge counts for more than an arrow")
        func thePageCountsForMoreThanAnArrow() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let box = try #require(presentation.calloutBoxes.first)
            let page = presentation.pageRect
            let then = rect(490, 390, 20, 20)
            let now = rect(maxX(page) - 30, 390, 20, 20)

            move(presentation, by: [Point2(x: 0, y: 0)], targets: [[now]], laidOut: [[then]])

            #expect(abs(maxX(box.frameRect) - (maxX(page) - spacing(presentation))) < 0.001)
        }

        @Test("So does another box")
        func anotherBoxCountsForMoreThanAnArrow() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE",
                                     "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let left = presentation.calloutBoxes[0]
            let right = presentation.calloutBoxes[1]
            let page = presentation.pageRect
            let room = spacing(presentation)

            // The left box's arrow goes to its left. The placement comes so
            // far right that the box cannot be past it and beside the other.
            let then = rect(left.frameRect.origin.x - 60, 390, 20, 20)
            let now = rect(maxX(page) - 100, 390, 20, 20)

            move(presentation, by: still, targets: [[now], []], laidOut: [[then], []])

            #expect(abs(maxX(right.frameRect) - (maxX(page) - room)) < 0.01)
            #expect(abs(right.frameRect.origin.x - maxX(left.frameRect) - room) < 0.01)
            #expect(left.frameRect.origin.x < maxX(now))
        }

        @Test("With arrows in the way the boxes still move without a jump")
        func boxesMoveSmoothlyRoundArrows() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE",
                                     "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE",
                                     "CALLOUT PLACEMENT BOTTOM CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let boxes = presentation.calloutBoxes
            let list = presentation.frameRect
            let homes = [Point2(x: 480, y: 395), Point2(x: 520, y: 395), Point2(x: 500, y: 410)]
            let stepCount = 720
            let placed = boxes.map { $0.frameRect.origin }
            var last = placed
            var furthest = 0.0

            // Each placement goes round the middle of the page, as in a turn.
            func place(_ index: Int, at step: Int) -> Point2 {
                let angle = Double(step) / Double(stepCount) * 2 * Double.pi * (index == 1 ? -1 : 1)
                let radius = 300.0 + 80.0 * Double(index)
                let start = homes[index]

                return Point2(x: start.x + radius * sin(angle), y: start.y + radius * 0.6 * (1 - cos(angle)))
            }

            for step in 0...stepCount {
                let places = (0..<3).map { place($0, at: step) }
                let shifts = (0..<3).map { Point2(x: places[$0].x - homes[$0].x, y: places[$0].y - homes[$0].y) }
                let targets = places.map { [rect($0.x - 10, $0.y - 10, 20, 20)] }
                let laidOut = homes.map { [rect($0.x - 10, $0.y - 10, 20, 20)] }

                move(presentation, by: shifts, targets: targets, laidOut: laidOut)

                for (index, box) in boxes.enumerated() {
                    let origin = box.frameRect.origin

                    furthest = max(furthest, hypot(origin.x - last[index].x, origin.y - last[index].y))
                    last[index] = origin

                    #expect(holds(presentation.pageRect, box.frameRect))
                    #expect(overlap(box.frameRect, list) == false)
                }

                #expect(overlap(boxes[0].frameRect, boxes[1].frameRect) == false)
                #expect(overlap(boxes[0].frameRect, boxes[2].frameRect) == false)
                #expect(overlap(boxes[1].frameRect, boxes[2].frameRect) == false)
            }

            // A placement goes under 4 points a step, and three of them move a box.
            #expect(furthest < 12)
            #expect(furthest > 1)

            // The placements are back where they started, and so are the boxes.
            for (index, box) in boxes.enumerated() {
                #expect(abs(box.frameRect.origin.x - placed[index].x) < 0.001)
                #expect(abs(box.frameRect.origin.y - placed[index].y) < 0.001)
            }
        }

        // MARK: - Changing places

        /// Where what a box places is drawn, with one arrow to it: a box 10
        /// points square about the middle.
        private func arrowPlaces(_ middle: Point2) -> Data {
            places(middle: middle, arrows: [rect(middle.x - 5, middle.y - 5, 10, 10)])
        }

        @Test("Boxes whose submodels change sides change places, over a short time")
        func boxesChangePlaces() throws {
            let lines = ["CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE", "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"]
            let fixture = pageModel(lines)
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let plain = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let arrangement = LDrawStepCalloutArrangement()
            let boxes = presentation.calloutBoxes
            let placed = boxes.map { $0.frameRect }

            // Each submodel was on its box's side of the middle, and is now
            // far on the other.
            let then = [arrowPlaces(Point2(x: 485, y: 400)), arrowPlaces(Point2(x: 515, y: 400))]
            let now = [arrowPlaces(Point2(x: 700, y: 400)), arrowPlaces(Point2(x: 300, y: 400))]

            // At first they are drawn where the file's order has them.
            layOut(presentation, arrangement)
            arrangement.time = 10
            presentation.moveCalloutBoxes(from: then, to: now, arrangement: arrangement)
            plain.moveCalloutBoxes(from: then, to: now, arrangement: nil)

            let started = boxes.map { $0.frameRect }
            #expect(arrangement.isMoving)
            #expect(same(started[0].origin, plain.calloutBoxes[0].frameRect.origin))
            #expect(same(started[1].origin, plain.calloutBoxes[1].frameRect.origin))
            #expect(maxX(started[0]) < started[1].origin.x)

            // On their way.
            arrangement.time = 10.15
            presentation.moveCalloutBoxes(from: then, to: now, arrangement: arrangement)
            #expect(arrangement.isMoving)
            #expect(boxes[0].frameRect.origin.x > started[0].origin.x + 1)
            #expect(boxes[1].frameRect.origin.x < started[1].origin.x - 1)

            // There: the first box is now to the right of the second, each
            // beside its own submodel, and nothing lies over anything.
            arrangement.time = 11
            presentation.moveCalloutBoxes(from: then, to: now, arrangement: arrangement)

            let changed = boxes.map { $0.frameRect }
            #expect(arrangement.isMoving == false)
            #expect(maxX(changed[1]) < changed[0].origin.x)
            #expect(overlap(changed[0], changed[1]) == false)
            #expect(holds(presentation.pageRect, changed[0]) && holds(presentation.pageRect, changed[1]))
            #expect(maxX(changed[0]) < 695 && maxX(changed[0]) > 695 - presentation.pointsPerPageInch)
            #expect(changed[1].origin.x > 305 && changed[1].origin.x < 305 + presentation.pointsPerPageInch)

            // The same again changes nothing.
            arrangement.time = 12
            presentation.moveCalloutBoxes(from: then, to: now, arrangement: arrangement)
            #expect(arrangement.isMoving == false)
            #expect(same(boxes[0].frameRect.origin, changed[0].origin))

            // At the angle of the layout they move back to the file's places.
            presentation.restCalloutBoxes(arrangement: arrangement)
            #expect(arrangement.isMoving)
            #expect(abs(boxes[0].frameRect.origin.x - changed[0].origin.x) < 0.001)

            arrangement.time = 13
            presentation.restCalloutBoxes(arrangement: arrangement)
            #expect(arrangement.isMoving == false)
            #expect(same(boxes[0].frameRect.origin, placed[0].origin))
            #expect(same(boxes[1].frameRect.origin, placed[1].origin))
        }

        @Test("At the angle of the layout a box that is on its way sets out from where it is drawn")
        func restingMidMoveDoesNotJump() throws {
            let lines = ["CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE", "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"]
            let fixture = pageModel(lines)
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let arrangement = LDrawStepCalloutArrangement()
            let boxes = presentation.calloutBoxes
            let placed = boxes.map { $0.frameRect.origin }
            let then = [arrowPlaces(Point2(x: 485, y: 400)), arrowPlaces(Point2(x: 515, y: 400))]
            let swapped = [arrowPlaces(Point2(x: 700, y: 400)), arrowPlaces(Point2(x: 300, y: 400))]
            let near = [arrowPlaces(Point2(x: 525, y: 400)), arrowPlaces(Point2(x: 555, y: 400))]

            // The boxes change places, and are then sent back to the file's.
            arrangement.time = 10
            presentation.moveCalloutBoxes(from: then, to: swapped, arrangement: arrangement)
            arrangement.time = 11
            presentation.moveCalloutBoxes(from: then, to: swapped, arrangement: arrangement)
            presentation.restCalloutBoxes(arrangement: arrangement)

            // On their way the camera is turned a little: they are on the
            // file's sides, 40 points along, with the rest of their move.
            arrangement.time = 11.1
            presentation.moveCalloutBoxes(from: then, to: near, arrangement: arrangement)

            let onTheWay = boxes.map { $0.frameRect.origin }
            try #require(arrangement.isMoving)
            try #require(abs(onTheWay[0].x - (placed[0].x + 40)) > 20)

            // Back at the angle of the layout they are drawn where they were.
            arrangement.time = 11.15
            presentation.restCalloutBoxes(arrangement: arrangement)
            #expect(abs(boxes[0].frameRect.origin.x - onTheWay[0].x) < 0.001)
            #expect(abs(boxes[1].frameRect.origin.x - onTheWay[1].x) < 0.001)

            // Laid out there again, they go on, and arrive.
            arrangement.time = 11.3
            presentation.restCalloutBoxes(arrangement: arrangement)
            #expect(abs(boxes[0].frameRect.origin.x - placed[0].x) < abs(onTheWay[0].x - placed[0].x) - 1)

            arrangement.time = 12
            presentation.restCalloutBoxes(arrangement: arrangement)
            #expect(arrangement.isMoving == false)
            #expect(same(boxes[0].frameRect.origin, placed[0]))
            #expect(same(boxes[1].frameRect.origin, placed[1]))
        }

        // MARK: - Drops while the boxes are arranged

        /// One box to the right of the assembly, with a line that has an
        /// offset, and where its submodel is drawn: in the middle when the
        /// step was laid out, and at the page's right edge now. On the file's
        /// side the box has no room there, so it goes to the far side.
        /// The caller keeps the file.
        private func boxAtTheEdge() throws
            -> (file: LDrawFile, model: LDrawModel, line: LPubPlacement, then: [Data], now: [Data]) {
            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.2000 0.1000"])
            let step = try #require((fixture.model.steps() as? [LDrawStep])?.last)
            let lines = try #require(step.subdirectives() as? [LDrawDirective])
            let line = try #require(lines.compactMap { $0 as? LPubPlacement }.first)
            let page = LDrawStepPartListPresentation(model: fixture.model, host: host()).pageRect

            return (fixture.file, fixture.model, line, [arrowPlaces(Point2(x: 500, y: 400))],
                    [arrowPlaces(Point2(x: maxX(page) - 20, y: 400))])
        }

        /// Where the box ends up once its move is over.
        private func placeOfBox(_ model: LDrawModel, from then: [Data], to now: [Data]) throws -> Point2 {
            let presentation = LDrawStepPartListPresentation(model: model, host: host())
            let arrangement = LDrawStepCalloutArrangement()

            arrangement.time = 10
            presentation.moveCalloutBoxes(from: then, to: now, arrangement: arrangement)
            arrangement.time = 11
            presentation.moveCalloutBoxes(from: then, to: now, arrangement: arrangement)

            return try #require(presentation.calloutBoxes.first).frameRect.origin
        }

        @Test("A drop of a box that is on its way is measured as if it had arrived")
        func dropLeavesOutTheMove() throws {
            // Two boxes whose submodels change sides: they change places, and
            // each stays on the file's side of its own submodel.
            let fixture = pageModel(["CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE -0.2000 0.1000",
                                     "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.2000 0.1000"])
            let then = [arrowPlaces(Point2(x: 485, y: 400)), arrowPlaces(Point2(x: 515, y: 400))]
            let now = [arrowPlaces(Point2(x: 700, y: 400)), arrowPlaces(Point2(x: 300, y: 400))]

            func laidOut(at times: [Double]) throws -> LDrawStepCalloutBox {
                let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
                let arrangement = LDrawStepCalloutArrangement()

                layOut(presentation, arrangement)

                for time in times {
                    arrangement.time = time
                    presentation.moveCalloutBoxes(from: then, to: now, arrangement: arrangement)
                }

                #expect(arrangement.isMoving == (times.last == 10.1))
                return try #require(presentation.calloutBoxes.first)
            }

            let arrived = try laidOut(at: [10, 11])
            let onItsWay = try laidOut(at: [10, 10.1])
            let place = arrived.frameRect.origin
            let drop = Point2(x: place.x + 6, y: place.y - 4)
            var offset = Point2(x: 0, y: 0)
            var same = Point2(x: 0, y: 0)

            try #require(hypot(onItsWay.frameRect.origin.x - place.x, onItsWay.frameRect.origin.y - place.y) > 20)
            try #require(arrived.getPlacementOffset(&same, forOrigin: drop))
            try #require(onItsWay.getPlacementOffset(&offset, forOrigin: drop))

            #expect(abs(offset.x - same.x) < 0.0001)
            #expect(abs(offset.y - same.y) < 0.0001)
            withExtendedLifetime(fixture.file) {}
        }

        @Test("A box that is picked up has no move under way, and sets out again when it is let go")
        func heldBoxDoesNotMoveOn() throws {
            let edge = try boxAtTheEdge()
            let place = try placeOfBox(edge.model, from: edge.then, to: edge.now)
            let arrangement = LDrawStepCalloutArrangement()
            var held = host()
            held.hasCalloutPreview = true
            held.calloutPreviewBox = 0
            held.calloutPreviewPoint = Point2(x: 300, y: 200)

            // The box has gone to the far side, and is on its way there.
            let moving = LDrawStepPartListPresentation(model: edge.model, host: host())
            layOut(moving, arrangement)
            arrangement.time = 10
            moving.moveCalloutBoxes(from: edge.then, to: edge.now, arrangement: arrangement)
            try #require(arrangement.isMoving)

            // Picked up on the way.
            let holding = LDrawStepPartListPresentation(model: edge.model, host: held)
            arrangement.time = 10.1
            holding.moveCalloutBoxes(from: edge.then, to: edge.now, arrangement: arrangement)

            #expect(same(try #require(holding.calloutBoxes.first).frameRect.origin, Point2(x: 300, y: 200)))
            #expect(arrangement.isMoving == false)

            // Let go with nothing written, it goes to the far side again.
            let free = LDrawStepPartListPresentation(model: edge.model, host: host())
            arrangement.time = 10.2
            free.moveCalloutBoxes(from: edge.then, to: edge.now, arrangement: arrangement)
            #expect(arrangement.isMoving)

            arrangement.time = 11.2
            free.moveCalloutBoxes(from: edge.then, to: edge.now, arrangement: arrangement)

            let letGo = try #require(free.calloutBoxes.first).frameRect.origin
            #expect(arrangement.isMoving == false)
            #expect(abs(letGo.x - place.x) < 0.001)
            #expect(abs(letGo.y - place.y) < 0.001)
            withExtendedLifetime(edge.file) {}
        }

        @Test("While a box is held the other boxes stay where they are, until it is let go")
        func otherBoxesWaitForTheDrop() throws {
            // Two boxes that have changed places, so they are not where the
            // file's sides would have them.
            let fixture = pageModel(["CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE -0.2000 0.1000",
                                     "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.2000 0.1000"])
            let step = try #require((fixture.model.steps() as? [LDrawStep])?.last)
            let lines = try #require(step.subdirectives() as? [LDrawDirective])
            let line = try #require(lines.compactMap { $0 as? LPubPlacement }.first)
            let then = [arrowPlaces(Point2(x: 485, y: 400)), arrowPlaces(Point2(x: 515, y: 400))]
            let now = [arrowPlaces(Point2(x: 700, y: 400)), arrowPlaces(Point2(x: 300, y: 400))]
            let arrangement = LDrawStepCalloutArrangement()
            var offset = Point2(x: 0, y: 0)

            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let plain = LDrawStepPartListPresentation(model: fixture.model, host: host())
            for time in [10.0, 11.0] {
                arrangement.time = time
                presentation.moveCalloutBoxes(from: then, to: now, arrangement: arrangement)
            }
            plain.moveCalloutBoxes(from: then, to: now, arrangement: nil)

            let before = presentation.calloutBoxes.map { $0.frameRect.origin }
            let onFileSides = plain.calloutBoxes[1].frameRect.origin
            try #require(hypot(before[1].x - onFileSides.x, before[1].y - onFileSides.y) > 20)

            // The first box is picked up, and held for a while: further from
            // its submodel, which is to its right, so its arrow keeps its room.
            let drop = Point2(x: before[0].x - 50, y: before[0].y + 40)
            var held = host()
            held.hasCalloutPreview = true
            held.calloutPreviewBox = 0
            held.calloutPreviewPoint = drop

            let holding = LDrawStepPartListPresentation(model: fixture.model, host: held)
            for time in [12.0, 12.1, 13.0] {
                arrangement.time = time
                holding.moveCalloutBoxes(from: then, to: now, arrangement: arrangement)

                let other = holding.calloutBoxes[1].frameRect.origin
                #expect(same(holding.calloutBoxes[0].frameRect.origin, drop))
                #expect(abs(other.x - before[1].x) < 0.001)
                #expect(abs(other.y - before[1].y) < 0.001)
                #expect(arrangement.isMoving == false)
            }

            // Let go: it is where it was dropped, and the other one is found
            // a place again, clear of it.
            try #require(holding.calloutBoxes[0].getPlacementOffset(&offset, forOrigin: drop))
            line.lPubCommandString = String(format: "CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE %.4f %.4f",
                                            offset.x, offset.y)

            let after = LDrawStepPartListPresentation(model: fixture.model, host: host())
            for time in [13.0, 14.0] {
                arrangement.time = time
                after.moveCalloutBoxes(from: then, to: now, arrangement: arrangement)

                let dropped = after.calloutBoxes[0].frameRect.origin
                #expect(abs(dropped.x - drop.x) < 0.01)
                #expect(abs(dropped.y - drop.y) < 0.01)
            }

            #expect(arrangement.isMoving == false)
            #expect(overlap(after.calloutBoxes[0].frameRect, after.calloutBoxes[1].frameRect) == false)
            withExtendedLifetime(fixture.file) {}
        }

        @Test("A box picked up on the far side of its submodel stays where it is dropped")
        func dropFromTheFarSide() throws {
            let edge = try boxAtTheEdge()
            let place = try placeOfBox(edge.model, from: edge.then, to: edge.now)
            let arrangement = LDrawStepCalloutArrangement()
            let page = LDrawStepPartListPresentation(model: edge.model, host: host()).pageRect
            var offset = Point2(x: 0, y: 0)

            let presentation = LDrawStepPartListPresentation(model: edge.model, host: host())
            for time in [10.0, 11.0] {
                arrangement.time = time
                presentation.moveCalloutBoxes(from: edge.then, to: edge.now, arrangement: arrangement)
            }

            // It is to the left of its submodel, where the file has it to
            // the right.
            let before = try #require(presentation.calloutBoxes.first).frameRect
            try #require(same(before.origin, place))
            try #require(maxX(before) < maxX(page) - 20)

            // Picked up, and held 30 points left of and 20 below its place.
            let drop = Point2(x: place.x - 30, y: place.y + 20)
            var held = host()
            held.hasCalloutPreview = true
            held.calloutPreviewBox = 0
            held.calloutPreviewPoint = drop

            let holding = LDrawStepPartListPresentation(model: edge.model, host: held)
            arrangement.time = 12
            holding.moveCalloutBoxes(from: edge.then, to: edge.now, arrangement: arrangement)

            let box = try #require(holding.calloutBoxes.first)
            try #require(same(box.frameRect.origin, drop))
            try #require(box.getPlacementOffset(&offset, forOrigin: drop))

            edge.line.lPubCommandString = String(format: "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE %.4f %.4f",
                                                 offset.x, offset.y)

            // Let go: it is where it was dropped, at once and afterwards.
            let after = LDrawStepPartListPresentation(model: edge.model, host: host())
            for time in [12.0, 13.0] {
                arrangement.time = time
                after.moveCalloutBoxes(from: edge.then, to: edge.now, arrangement: arrangement)

                // The offset is written to four decimals of a box 60 by 40.
                let dropped = try #require(after.calloutBoxes.first).frameRect.origin
                #expect(arrangement.isMoving == false)
                #expect(abs(dropped.x - drop.x) < 0.01)
                #expect(abs(dropped.y - drop.y) < 0.01)
            }

            // The file has the box as far from there as its submodel has
            // moved: on the page, to the left of the assembly now.
            after.restCalloutBoxes(arrangement: arrangement)
            let home = try #require(after.calloutBoxes.first).frameRect
            #expect(abs(home.origin.x - (drop.x - (maxX(page) - 20 - 500))) < 0.01)
            #expect(holds(page, home))
            withExtendedLifetime(edge.file) {}
        }

        @Test("A first drop from the far side stays where it is let go, though the assembly moves to the middle")
        func firstDropFromTheFarSide() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let step = try #require((fixture.model.steps() as? [LDrawStep])?.last)
            let lines = try #require(step.subdirectives() as? [LDrawDirective])
            let line = try #require(lines.compactMap { $0 as? LPubPlacement }.first)

            // What a host does: it has the step centered, and keeps the page
            // where it is, so the assembly moves.
            func centered(_ host: LDrawStepPartListHostState) -> LDrawStepPartListHostState {
                let measured = LDrawStepPartListPresentation(model: fixture.model, host: host)
                var moved = host
                moved.assemblyRect.origin.x += host.pageCenterInView.x - measured.stepCenterInView.x
                moved.assemblyRect.origin.y += host.pageCenterInView.y - measured.stepCenterInView.y
                return moved
            }
            func middle(_ host: LDrawStepPartListHostState) -> Point2 {
                Point2(x: host.assemblyRect.origin.x + host.assemblyRect.size.width / 2,
                       y: host.assemblyRect.origin.y + host.assemblyRect.size.height / 2)
            }

            // The assembly and its box are centered together. The submodel
            // was in the middle of the assembly, and is now at the page's
            // edge.
            let shown = centered(host())
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: shown)
            let arrangement = LDrawStepCalloutArrangement()
            let reach = maxX(presentation.pageRect) - 20 - middle(shown).x
            var offset = Point2(x: 0, y: 0)

            func places(_ host: LDrawStepPartListHostState) -> (then: [Data], now: [Data]) {
                ([arrowPlaces(middle(host))], [arrowPlaces(Point2(x: middle(host).x + reach, y: middle(host).y))])
            }

            for time in [10.0, 11.0] {
                arrangement.time = time
                presentation.moveCalloutBoxes(from: places(shown).then, to: places(shown).now, arrangement: arrangement)
            }

            // The box is to the left of its submodel now.
            let place = try #require(presentation.calloutBoxes.first).frameRect
            try #require(maxX(place) < middle(shown).x + reach)

            let drop = Point2(x: place.origin.x - 30, y: place.origin.y + 20)
            var held = shown
            held.hasCalloutPreview = true
            held.calloutPreviewBox = 0
            held.calloutPreviewPoint = drop

            let holding = LDrawStepPartListPresentation(model: fixture.model, host: held)
            arrangement.time = 12
            holding.moveCalloutBoxes(from: places(shown).then, to: places(shown).now, arrangement: arrangement)
            try #require(try #require(holding.calloutBoxes.first).getPlacementOffset(&offset, forOrigin: drop))

            line.lPubCommandString = String(format: "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE %.4f %.4f",
                                            offset.x, offset.y)

            // The box is centered with the assembly no more, so the assembly
            // goes to the middle, and the submodel with it.
            let settled = centered(shown)
            try #require(abs(settled.assemblyRect.origin.x - shown.assemblyRect.origin.x) > 1)

            let after = LDrawStepPartListPresentation(model: fixture.model, host: settled)
            arrangement.time = 13
            after.moveCalloutBoxes(from: places(settled).then, to: places(settled).now, arrangement: arrangement)

            // The offset is written to four decimals of a box 60 by 40 points.
            let dropped = try #require(after.calloutBoxes.first).frameRect.origin
            #expect(arrangement.isMoving == false)
            #expect(abs(dropped.x - drop.x) < 0.02)
            #expect(abs(dropped.y - drop.y) < 0.02)
            withExtendedLifetime(fixture.file) {}
        }

        @Test("A drop that the file could only keep off the page keeps the box on the page")
        func dropStaysOnThePageForTheFile() throws {
            let edge = try boxAtTheEdge()
            let page = LDrawStepPartListPresentation(model: edge.model, host: host()).pageRect
            let far = [arrowPlaces(Point2(x: page.origin.x + 60, y: 400))]
            var offset = Point2(x: 0, y: 0)

            // The submodel has gone 484 points to the left, and the box with
            // it. Dropped 300 points from the page's right edge, the file
            // would have to put it past that edge.
            let presentation = LDrawStepPartListPresentation(model: edge.model, host: host())
            presentation.moveCalloutBoxes(from: edge.then, to: far, arrangement: nil)

            let box = try #require(presentation.calloutBoxes.first)
            let drop = Point2(x: maxX(page) - 300, y: box.frameRect.origin.y)
            try #require(box.getPlacementOffset(&offset, forOrigin: drop))

            edge.line.lPubCommandString = String(format: "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE %.4f %.4f",
                                                 offset.x, offset.y)

            // The file has it at the page's edge, and it still follows.
            let after = LDrawStepPartListPresentation(model: edge.model, host: host())
            let home = try #require(after.calloutBoxes.first).frameRect
            #expect(abs(maxX(home) - maxX(page)) < 0.01)

            after.moveCalloutBoxes(from: edge.then, to: far, arrangement: nil)
            let followed = try #require(after.calloutBoxes.first).frameRect
            #expect(abs(followed.origin.x - (home.origin.x - 484)) < 0.01)
            #expect(followed.origin.x < drop.x)
            withExtendedLifetime(edge.file) {}
        }

        @Test("A drop in a turned view finds the file a place clear of the parts list")
        func dropKeepsClearOfTheListForTheFile() throws {
            let edge = try boxAtTheEdge()
            let measured = LDrawStepPartListPresentation(model: edge.model, host: host())
            let list = measured.frameRect
            let page = measured.pageRect
            var offset = Point2(x: 0, y: 0)

            try #require(list.size.width > 0)

            // The submodel has gone 300 points right and 250 down, and the box
            // with it.
            let now = [arrowPlaces(Point2(x: 800, y: 650))]
            let presentation = LDrawStepPartListPresentation(model: edge.model, host: host())
            presentation.moveCalloutBoxes(from: edge.then, to: now, arrangement: nil)

            // Dropped where the file would have it over the list's corner.
            let box = try #require(presentation.calloutBoxes.first)
            let drop = Point2(x: list.origin.x + 10 + 300, y: list.origin.y + 10 + 250)
            try #require(holds(page, Box2(origin: drop, size: box.frameRect.size)))
            try #require(box.getPlacementOffset(&offset, forOrigin: drop))

            edge.line.lPubCommandString = String(format: "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE %.4f %.4f",
                                                 offset.x, offset.y)

            // The file has it beside the list, the margin away, and on the
            // page.
            let home = try #require(LDrawStepPartListPresentation(model: edge.model, host: host())
                .calloutBoxes.first).frameRect
            let gap = max(home.origin.x - maxX(list), home.origin.y - maxY(list))

            #expect(overlap(home, list) == false)
            #expect(holds(page, home))
            #expect(abs(gap - 0.05 * measured.pointsPerPageInch) < 0.02)
            withExtendedLifetime(edge.file) {}
        }

        @Test("And clear of another box")
        func dropKeepsClearOfABoxForTheFile() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE -0.2000 0.1000",
                                     "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.2000 0.1000"])
            let step = try #require((fixture.model.steps() as? [LDrawStep])?.last)
            let lines = try #require(step.subdirectives() as? [LDrawDirective])
            let line = try #require(lines.compactMap { $0 as? LPubPlacement }.first)
            let then = [arrowPlaces(Point2(x: 485, y: 400)), arrowPlaces(Point2(x: 515, y: 400))]
            let now = [arrowPlaces(Point2(x: 585, y: 480)), arrowPlaces(Point2(x: 615, y: 480))]
            var offset = Point2(x: 0, y: 0)

            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let other = presentation.calloutBoxes[1].frameRect

            // Both submodels have gone 100 points right and 80 down. The first
            // box is dropped where the file would have it over the second.
            presentation.moveCalloutBoxes(from: then, to: now, arrangement: nil)

            let drop = Point2(x: other.origin.x + 5 + 100, y: other.origin.y + 5 + 80)
            try #require(presentation.calloutBoxes[0].getPlacementOffset(&offset, forOrigin: drop))

            line.lPubCommandString = String(format: "CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE %.4f %.4f",
                                            offset.x, offset.y)

            let after = LDrawStepPartListPresentation(model: fixture.model, host: host()).calloutBoxes
            #expect(same(after[1].frameRect.origin, other.origin))
            #expect(overlap(after[0].frameRect, after[1].frameRect) == false)
            withExtendedLifetime(fixture.file) {}
        }

        @Test("At the angle of the layout a box goes where it is dropped, over the list too")
        func dropAtTheLayoutAngleIsFree() throws {
            let edge = try boxAtTheEdge()
            let presentation = LDrawStepPartListPresentation(model: edge.model, host: host())
            let list = presentation.frameRect
            let box = try #require(presentation.calloutBoxes.first)
            let drop = Point2(x: list.origin.x + 10, y: list.origin.y + 10)
            var offset = Point2(x: 0, y: 0)

            try #require(box.getPlacementOffset(&offset, forOrigin: drop))

            edge.line.lPubCommandString = String(format: "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE %.4f %.4f",
                                                 offset.x, offset.y)

            let home = try #require(LDrawStepPartListPresentation(model: edge.model, host: host())
                .calloutBoxes.first).frameRect
            #expect(abs(home.origin.x - drop.x) < 0.01)
            #expect(abs(home.origin.y - drop.y) < 0.01)
            withExtendedLifetime(edge.file) {}
        }

        @Test("Boxes that are well where they are keep the file's sides, and nothing moves over time")
        func settledBoxesAreLetBe() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let plain = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let arrangement = LDrawStepCalloutArrangement()
            let then = [arrowPlaces(Point2(x: 500, y: 400))]
            let now = [arrowPlaces(Point2(x: 540, y: 370))]

            arrangement.time = 10
            presentation.moveCalloutBoxes(from: then, to: now, arrangement: arrangement)
            plain.moveCalloutBoxes(from: then, to: now, arrangement: nil)

            let box = try #require(presentation.calloutBoxes.first)
            #expect(arrangement.isMoving == false)
            #expect(same(box.frameRect.origin, try #require(plain.calloutBoxes.first).frameRect.origin))
        }

        @Test("A box whose submodel goes to the page's edge goes to the other side of it")
        func boxGoesToTheOtherSide() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let arrangement = LDrawStepCalloutArrangement()
            let box = try #require(presentation.calloutBoxes.first)
            let page = presentation.pageRect
            let middle = Point2(x: maxX(page) - 20, y: 400)
            let then = [arrowPlaces(Point2(x: 500, y: 400))]
            let now = [arrowPlaces(middle)]

            // On the file's side the box is held at the edge, over the
            // placement its arrow goes to.
            layOut(presentation, arrangement)
            arrangement.time = 10
            presentation.moveCalloutBoxes(from: then, to: now, arrangement: arrangement)
            #expect(arrangement.isMoving)
            #expect(box.frameRect.origin.x < middle.x && maxX(box.frameRect) > middle.x)

            arrangement.time = 11
            presentation.moveCalloutBoxes(from: then, to: now, arrangement: arrangement)
            #expect(arrangement.isMoving == false)
            #expect(maxX(box.frameRect) < middle.x - 5)
            #expect(holds(page, box.frameRect))

            // With its submodel back in the middle it goes back to the right.
            let back = [arrowPlaces(Point2(x: 520, y: 400))]

            arrangement.time = 12
            presentation.moveCalloutBoxes(from: then, to: back, arrangement: arrangement)
            arrangement.time = 13
            presentation.moveCalloutBoxes(from: then, to: back, arrangement: arrangement)
            #expect(arrangement.isMoving == false)
            #expect(box.frameRect.origin.x > 520)
        }

        @Test("A box that is first drawn in a turned view is on its side at once")
        func newBoxDoesNotMove() throws {
            let edge = try boxAtTheEdge()
            let presentation = LDrawStepPartListPresentation(model: edge.model, host: host())
            let arrangement = LDrawStepCalloutArrangement()
            let box = try #require(presentation.calloutBoxes.first)
            let middle = maxX(presentation.pageRect) - 20

            arrangement.time = 10
            presentation.moveCalloutBoxes(from: edge.then, to: edge.now, arrangement: arrangement)

            let first = box.frameRect

            #expect(arrangement.isMoving == false)
            #expect(maxX(first) < middle - 5)

            arrangement.time = 11
            presentation.moveCalloutBoxes(from: edge.then, to: edge.now, arrangement: arrangement)
            #expect(same(box.frameRect.origin, first.origin))
            withExtendedLifetime(edge.file) {}
        }

        @Test("However the boxes are arranged, they stay on the page and off each other and the list")
        func arrangedBoxesKeepClear() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE",
                                     "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE",
                                     "CALLOUT PLACEMENT BOTTOM CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let arrangement = LDrawStepCalloutArrangement()
            let boxes = presentation.calloutBoxes
            let list = presentation.frameRect
            let homes = [Point2(x: 480, y: 395), Point2(x: 520, y: 395), Point2(x: 500, y: 410)]
            let then = homes.map { arrowPlaces($0) }
            let stepCount = 360
            var changes = 0
            var last = boxes.map { $0.frameRect.origin }

            for step in 0...stepCount {
                let now: [Data] = (0..<3).map { index in
                    let angle = Double(step) / Double(stepCount) * 2 * Double.pi * (index == 1 ? -1 : 1)
                    let radius = 300.0 + 80.0 * Double(index)

                    return arrowPlaces(Point2(x: homes[index].x + radius * sin(angle),
                                              y: homes[index].y + radius * 0.6 * (1 - cos(angle))))
                }

                // Long after the last layout, so every move has ended.
                arrangement.time = Double(step) * 10
                presentation.moveCalloutBoxes(from: then, to: now, arrangement: arrangement)

                for (index, box) in boxes.enumerated() {
                    #expect(holds(presentation.pageRect, box.frameRect))
                    #expect(overlap(box.frameRect, list) == false)

                    if hypot(box.frameRect.origin.x - last[index].x, box.frameRect.origin.y - last[index].y) > 40 {
                        changes += 1
                    }
                    last[index] = box.frameRect.origin
                }

                #expect(overlap(boxes[0].frameRect, boxes[1].frameRect) == false)
                #expect(overlap(boxes[0].frameRect, boxes[2].frameRect) == false)
                #expect(overlap(boxes[1].frameRect, boxes[2].frameRect) == false)
            }

            // Boxes did change places on the way, and not at every step.
            #expect(changes > 0)
            #expect(changes < 60)
        }

        // MARK: - Callouts placed automatically

        /// An assembly a few inches across, in the middle of the page.
        private let bigAssembly = Box2(origin: Point2(x: 300, y: 250), size: Size2(width: 400, height: 300))

        @Test("Placed automatically, a box's PLACEMENT line is not read, and the box cannot be dragged")
        func automaticBoxesDoNotReadTheirLines() throws {
            LDrawStepPartList.setPlacesCalloutsAutomatically(true)
            defer { LDrawStepPartList.setPlacesCalloutsAutomatically(false) }

            let placed = pageModel(["CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE -2.0000 1.0000"])
            let plain = pageModel(["CALLOUT MARGINS LOCAL 0.05 0.05"])
            let presentation = LDrawStepPartListPresentation(model: placed.model, host: host())
            let box = try #require(presentation.calloutBoxes.first)
            let other = try #require(LDrawStepPartListPresentation(model: plain.model, host: host()).calloutBoxes.first)
            var offset = Point2(x: 0, y: 0)

            // Both start where a box with no line goes.
            #expect(same(box.frameRect.origin, other.frameRect.origin))
            #expect(box.isPlacedByFile == false)
            #expect(box.getPlacementOffset(&offset, forOrigin: box.frameRect.origin) == false)
            #expect(presentation.placementKey.contains("PLACEMENT") == false)

            // With the option off the line is read again.
            LDrawStepPartList.setPlacesCalloutsAutomatically(false)
            let read = try #require(LDrawStepPartListPresentation(model: placed.model, host: host()).calloutBoxes.first)
            #expect(read.isPlacedByFile)
            #expect(read.frameRect.origin.x < other.frameRect.origin.x)
            withExtendedLifetime((placed.file, plain.file)) {}
        }

        @Test("A box goes beside the assembly, past the side nearest what it calls out, and level with that")
        func automaticBoxGoesToTheNearestSide() throws {
            LDrawStepPartList.setPlacesCalloutsAutomatically(true)
            defer { LDrawStepPartList.setPlacesCalloutsAutomatically(false) }

            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let box = try #require(presentation.calloutBoxes.first)
            let assembly = bigAssembly
            let margin = 0.05 * presentation.pointsPerPageInch

            func placed(at aim: Point2) -> Box2 {
                presentation.placeCalloutBoxes(aroundAssembly: assembly, places: [arrowPlaces(aim)], arrangement: nil)
                return box.frameRect
            }
            func middle(_ frame: Box2) -> Point2 {
                Point2(x: frame.origin.x + frame.size.width / 2, y: frame.origin.y + frame.size.height / 2)
            }

            // Near the left edge, the right edge, the top and the bottom.
            let left = placed(at: Point2(x: 320, y: 400))
            #expect(maxX(left) <= assembly.origin.x - margin + 0.001)
            #expect(abs(middle(left).y - 400) < 0.001)

            let right = placed(at: Point2(x: 680, y: 430))
            #expect(right.origin.x >= maxX(assembly) + margin - 0.001)
            #expect(abs(middle(right).y - 430) < 0.001)

            let above = placed(at: Point2(x: 480, y: 270))
            #expect(maxY(above) <= assembly.origin.y - margin + 0.001)
            #expect(abs(middle(above).x - 480) < 0.001)

            let below = placed(at: Point2(x: 520, y: 530))
            #expect(below.origin.y >= maxY(assembly) + margin - 0.001)
            #expect(abs(middle(below).x - 520) < 0.001)

            // Each has room for its arrow: half an inch to where it goes, a
            // box 10 points square about that place.
            #expect(abs((315 - maxX(left)) - 0.5 * presentation.pointsPerPageInch) < 0.001)
            withExtendedLifetime(fixture.file) {}
        }

        @Test("Boxes placed automatically keep clear of each other and of the list, on the page")
        func automaticBoxesKeepClear() throws {
            LDrawStepPartList.setPlacesCalloutsAutomatically(true)
            defer { LDrawStepPartList.setPlacesCalloutsAutomatically(false) }

            let fixture = pageModel(["CALLOUT MARGINS LOCAL 0.05 0.05", "CALLOUT MARGINS LOCAL 0.05 0.05",
                                     "CALLOUT MARGINS LOCAL 0.05 0.05"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let boxes = presentation.calloutBoxes
            let list = presentation.frameRect

            // All three call out something at the same place by the left edge.
            let places = (0..<3).map { _ in arrowPlaces(Point2(x: 320, y: 400)) }
            presentation.placeCalloutBoxes(aroundAssembly: bigAssembly, places: places, arrangement: nil)

            for (index, box) in boxes.enumerated() {
                #expect(holds(presentation.pageRect, box.frameRect))
                #expect(overlap(box.frameRect, list) == false)

                for other in boxes[(index + 1)...] {
                    #expect(overlap(box.frameRect, other.frameRect) == false)
                }
            }

            withExtendedLifetime(fixture.file) {}
        }

        @Test("On a page with no room beside the assembly, a box goes beside what it calls out")
        func automaticBoxWithNoRoomOutside() throws {
            LDrawStepPartList.setPlacesCalloutsAutomatically(true)
            defer { LDrawStepPartList.setPlacesCalloutsAutomatically(false) }

            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let box = try #require(presentation.calloutBoxes.first)
            let page = presentation.pageRect
            let full = Box2(origin: Point2(x: page.origin.x + 5, y: page.origin.y + 5),
                            size: Size2(width: page.size.width - 10, height: page.size.height - 10))
            let aim = Point2(x: 500, y: 600)
            let target = rect(aim.x - 5, aim.y - 5, 10, 10)

            presentation.placeCalloutBoxes(aroundAssembly: full, places: [arrowPlaces(aim)], arrangement: nil)

            // On the page, off what it calls out, and half an inch from it:
            // room for its arrow.
            let frame = box.frameRect
            let across = max(target.origin.x - maxX(frame), frame.origin.x - maxX(target))
            let down = max(target.origin.y - maxY(frame), frame.origin.y - maxY(target))

            #expect(holds(page, frame))
            #expect(overlap(frame, target) == false)
            #expect(abs(max(across, down) - 0.5 * presentation.pointsPerPageInch) < 0.001)
            withExtendedLifetime(fixture.file) {}
        }

        @Test("A box placed automatically changes sides over a short time when what it calls out does")
        func automaticBoxChangesSides() throws {
            LDrawStepPartList.setPlacesCalloutsAutomatically(true)
            defer { LDrawStepPartList.setPlacesCalloutsAutomatically(false) }

            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let arrangement = LDrawStepCalloutArrangement()
            let box = try #require(presentation.calloutBoxes.first)
            let assembly = bigAssembly

            func place(_ aim: Point2, at time: Double) {
                arrangement.time = time
                presentation.placeCalloutBoxes(aroundAssembly: assembly, places: [arrowPlaces(aim)],
                                               arrangement: arrangement)
            }

            // It is in its place at once the first time.
            place(Point2(x: 320, y: 400), at: 10)
            let left = box.frameRect
            #expect(arrangement.isMoving == false)
            #expect(maxX(left) < assembly.origin.x)

            // What it calls out moves a little: it stays on its side, level
            // with it.
            place(Point2(x: 340, y: 420), at: 11)
            #expect(arrangement.isMoving == false)
            #expect(maxX(box.frameRect) < assembly.origin.x)
            #expect(abs(box.frameRect.origin.y - (left.origin.y + 20)) < 0.001)

            // It goes to the other edge: the box sets out from its own side.
            place(Point2(x: 680, y: 420), at: 12)
            #expect(arrangement.isMoving)
            #expect(maxX(box.frameRect) < assembly.origin.x)

            place(Point2(x: 680, y: 420), at: 12.15)
            #expect(arrangement.isMoving)
            #expect(maxX(box.frameRect) > assembly.origin.x)
            #expect(box.frameRect.origin.x < maxX(assembly))

            place(Point2(x: 680, y: 420), at: 13)
            #expect(arrangement.isMoving == false)
            #expect(box.frameRect.origin.x > maxX(assembly))
            withExtendedLifetime(fixture.file) {}
        }

        @Test("Sides taken while the boxes were placed automatically are forgotten when the file places them")
        func automaticSidesAreForgotten() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let arrangement = LDrawStepCalloutArrangement()
            let then = [arrowPlaces(Point2(x: 500, y: 400))]
            let now = [arrowPlaces(Point2(x: 540, y: 370))]
            let page = LDrawStepPartListPresentation(model: fixture.model, host: host()).pageRect
            let atTheEdge = [arrowPlaces(Point2(x: maxX(page) - 20, y: 400))]

            // Placed automatically, the box takes a place to the left.
            LDrawStepPartList.setPlacesCalloutsAutomatically(true)
            defer { LDrawStepPartList.setPlacesCalloutsAutomatically(false) }

            let automatic = LDrawStepPartListPresentation(model: fixture.model, host: host())
            arrangement.time = 10
            automatic.placeCalloutBoxes(aroundAssembly: bigAssembly, places: [arrowPlaces(Point2(x: 320, y: 400))],
                                        arrangement: arrangement)
            try #require(maxX(try #require(automatic.calloutBoxes.first).frameRect) < bigAssembly.origin.x)

            // Placed by the file again, it goes with its submodel from where
            // the file puts it, as if it had never been anywhere else.
            LDrawStepPartList.setPlacesCalloutsAutomatically(false)

            let placed = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let plain = LDrawStepPartListPresentation(model: fixture.model, host: host())
            arrangement.time = 11
            placed.moveCalloutBoxes(from: then, to: now, arrangement: arrangement)
            plain.moveCalloutBoxes(from: then, to: now, arrangement: nil)

            #expect(arrangement.isMoving == false)
            #expect(same(try #require(placed.calloutBoxes.first).frameRect.origin,
                         try #require(plain.calloutBoxes.first).frameRect.origin))

            // Where it has to take a side of its own, it is there at once.
            let aside = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let fresh = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let untouched = LDrawStepCalloutArrangement()
            untouched.time = 10
            fresh.moveCalloutBoxes(from: then, to: atTheEdge, arrangement: untouched)

            LDrawStepPartList.setPlacesCalloutsAutomatically(true)
            arrangement.time = 11.5
            automatic.placeCalloutBoxes(aroundAssembly: bigAssembly, places: [arrowPlaces(Point2(x: 320, y: 400))],
                                        arrangement: arrangement)
            LDrawStepPartList.setPlacesCalloutsAutomatically(false)

            arrangement.time = 11.6
            aside.moveCalloutBoxes(from: then, to: atTheEdge, arrangement: arrangement)

            #expect(arrangement.isMoving == false)
            #expect(same(try #require(aside.calloutBoxes.first).frameRect.origin,
                         try #require(fresh.calloutBoxes.first).frameRect.origin))

            // And the other way round: its place is found afresh.
            LDrawStepPartList.setPlacesCalloutsAutomatically(true)

            let again = LDrawStepPartListPresentation(model: fixture.model, host: host())
            arrangement.time = 12
            again.placeCalloutBoxes(aroundAssembly: bigAssembly, places: [arrowPlaces(Point2(x: 680, y: 400))],
                                    arrangement: arrangement)

            #expect(arrangement.isMoving == false)
            #expect(try #require(again.calloutBoxes.first).frameRect.origin.x > maxX(bigAssembly))
            withExtendedLifetime(fixture.file) {}
        }

        @Test("A followed box that is dropped where it is drawn keeps its line")
        func dropAllowsForTheShift() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.2000 0.1000"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let box = try #require(presentation.calloutBoxes.first)
            var offset = Point2(x: 0, y: 0)

            move(presentation, by: [Point2(x: 40, y: -30)])

            try #require(box.getPlacementOffset(&offset, forOrigin: box.frameRect.origin))
            #expect(abs(offset.x - 0.2) < 0.0001)
            #expect(abs(offset.y - 0.1) < 0.0001)

            // Dropped 6 points to the right, a tenth of the assembly's width.
            let drop = Point2(x: box.frameRect.origin.x + 6, y: box.frameRect.origin.y)
            try #require(box.getPlacementOffset(&offset, forOrigin: drop))
            #expect(abs(offset.x - 0.3) < 0.0001)
        }

        @Test("A box held by a drag stays under the pointer")
        func heldBoxDoesNotFollow() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            var held = host()
            held.hasCalloutPreview = true
            held.calloutPreviewBox = 0
            held.calloutPreviewPoint = Point2(x: 300, y: 200)

            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: held)
            let box = try #require(presentation.calloutBoxes.first)

            move(presentation, by: [Point2(x: 40, y: -30)])

            #expect(same(box.frameRect.origin, Point2(x: 300, y: 200)))
        }

        @Test("Boxes move without a jump, whatever is in their way")
        func boxesMoveSmoothly() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT LEFT CENTER ASSEM OUTSIDE",
                                     "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE",
                                     "CALLOUT PLACEMENT BOTTOM CENTER ASSEM OUTSIDE"])
            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let boxes = presentation.calloutBoxes
            let list = presentation.frameRect
            let ends = [Point2(x: 900, y: -1200), Point2(x: -1100, y: -900), Point2(x: -300, y: -1500)]
            let stepCount = 400
            var last = boxes.map { $0.frameRect.origin }
            var furthest = 0.0

            try #require(boxes.count == 3)

            for step in 0...stepCount {
                let share = Double(step) / Double(stepCount)

                move(presentation, by: ends.map { Point2(x: $0.x * share, y: $0.y * share) })

                for (index, box) in boxes.enumerated() {
                    let origin = box.frameRect.origin

                    furthest = max(furthest, hypot(origin.x - last[index].x, origin.y - last[index].y))
                    last[index] = origin

                    #expect(holds(presentation.pageRect, box.frameRect))
                    #expect(overlap(box.frameRect, list) == false)
                }

                #expect(overlap(boxes[0].frameRect, boxes[1].frameRect) == false)
                #expect(overlap(boxes[0].frameRect, boxes[2].frameRect) == false)
                #expect(overlap(boxes[1].frameRect, boxes[2].frameRect) == false)
            }

            // The three shifts together change by under 8 points a step.
            #expect(furthest < 8)
            #expect(furthest > 1)
        }

        @Test("A box follows the middle of what its callout places")
        func placementsMiddle() throws {
            let fixture = pageModel(["CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE"])
            let step = try #require((fixture.model.steps() as? [LDrawStep])?.last)
            let directives = try #require(step.subdirectives() as? [LDrawDirective])
            let placed = try #require(directives.firstIndex { $0 is LDrawPart })

            // A second placement, beside the one at the origin.
            step.insert(part("sub.ldr", at: Point3(x: 100, y: 40, z: -20)), at: placed + 1)

            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host())
            let middle = try #require(presentation.calloutBoxes.first).placementsMiddle

            #expect(abs(middle.x - 50) < 0.001)
            #expect(abs(middle.y - 20) < 0.001)
            #expect(abs(middle.z + 10) < 0.001)
        }
    }
}
