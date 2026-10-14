//
//  LDrawStepOverlayPageTests.swift
//  LDrawStepRenderingTests
//
//  How the presenter keeps LPub3D's page in place against a camera.
//
//  The parts list's settings are process-wide, so the suite puts them back when
//  it is done.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//

import Testing
import Foundation
import CoreGraphics
import LDrawCore
import LDrawFeatures
import LDrawStepRendering

/// A camera that draws the model flat: a model point lands at its x and y
/// times the zoom, from where the origin is drawn. `turn(toDegrees:)` turns the
/// model about its y axis, which moves its points sideways.
private final class FlatCamera: NSObject, LDrawStepOverlayCamera {

    var zoom: CGFloat = 100
    var origin = CGPoint(x: 500, y: 400)
    var angle = Tuple3(x: 0, y: 0, z: 0)
    var scrollCount = 0

    /// The box it gives for the assembly, around where the origin is drawn.
    /// The fixtures' models place nothing a camera could measure.
    var assemblySize = CGSize.zero

    /// How much bigger than the zoom it draws the model, as perspective draws
    /// a model that is nearer the camera.
    var nearness = 1.0

    private var turn = 0.0

    private var scale: CGFloat { zoom / 100 }

    func turn(toDegrees degrees: Double) {
        turn = degrees * .pi / 180
        angle = Tuple3(x: 0, y: degrees, z: 0)
    }

    func zoomPercentage() -> CGFloat { zoom }

    func setZoomPercentage(_ newPercentage: CGFloat) { zoom = newPercentage }

    func pointsPerLDU(atModelPoint modelPoint: Point3) -> Double { Double(scale) * nearness }

    func scrollCenter(toModelPoint modelPoint: Point3) {
        scrollModelPoint(modelPoint, toViewPoint: CGPoint(x: 500, y: 400))
    }

    func viewingAngle() -> Tuple3 { angle }

    /// How far to the right of the origin a model point is drawn, in LDU.
    private func across(_ point: Point3) -> Double {
        point.x * cos(turn) + point.z * sin(turn)
    }

    func viewPoint(forModelPoint modelPoint: Point3) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(across(modelPoint)) * scale, y: origin.y + CGFloat(modelPoint.y) * scale)
    }

    func modelPoint(forViewPoint viewPoint: CGPoint, depthReferencePoint depthPoint: Point3) -> Point3 {
        let across = Double((viewPoint.x - origin.x) / scale)
        let depth = depthPoint.z * cos(turn) - depthPoint.x * sin(turn)

        return Point3(x: across * cos(turn) - depth * sin(turn),
                      y: Double((viewPoint.y - origin.y) / scale),
                      z: across * sin(turn) + depth * cos(turn))
    }

    func viewRect(forModelPoints points: Data) -> CGRect {
        guard assemblySize != .zero else { return .zero }

        return CGRect(x: origin.x - assemblySize.width / 2, y: origin.y - assemblySize.height / 2,
                      width: assemblySize.width, height: assemblySize.height)
    }

    func viewPoints(forModelPoints points: Data) -> Data {
        Data()
    }

    func scrollModelPoint(_ modelPoint: Point3, toViewPoint viewPoint: CGPoint) {
        origin = CGPoint(x: viewPoint.x - CGFloat(across(modelPoint)) * scale,
                         y: viewPoint.y - CGFloat(modelPoint.y) * scale)
        scrollCount += 1
    }
}

extension StepOverlayTests {

    @Suite("The page against a camera", .serialized)
    final class LDrawStepOverlayPageTests {

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

        /// A model showing its one step, a camera on it, and a presenter that
        /// has laid the step out once. The step has a page of its own size.
        /// With `callsOut` it also calls sub.ldr out. Without, it places
        /// nothing. Either way nothing is asked of a part library.
        ///
        /// `assembly` is the size the camera gives the step's assembly, which
        /// has the callout placed against it. `submodelAt` is where the step
        /// places sub.ldr.
        private func shown(callsOut: Bool = false, assembly: CGSize = .zero, submodelAt: Point3? = nil)
            -> (fixture: CalloutFixture, camera: FlatCamera, presenter: LDrawStepOverlayPresenter) {
            let fixture = CalloutFixture()
            let pageSize = LPubPageSize()
            pageSize.lPubCommandString = "PAGE SIZE 8.5 11"

            if callsOut {
                hollowOut(fixture)
            }
            else {
                for directive in fixture.step.subdirectives() as! [LDrawDirective] {
                    fixture.step.remove(directive)
                }
            }

            if let position = submodelAt {
                var components = IdentityComponents
                components.translate = position

                for case let part as LDrawPart in fixture.step.subdirectives() {
                    part.setTransformComponents(components)
                }
            }

            fixture.step.insert(pageSize, at: 0)
            fixture.main.setStepDisplay(true)
            fixture.main.setMaximumStepIndexForStepDisplay(UInt(fixture.main.steps().count - 1))

            let camera = FlatCamera()
            camera.assemblySize = assembly

            let presenter = LDrawStepOverlayPresenter()
            presenter.model = fixture.main
            presenter.camera = camera
            presenter.viewSize = Size2(width: 1000, height: 800)
            presenter.reload()

            return (fixture, camera, presenter)
        }

        /// Makes sub.ldr build an empty model of the file in place of each
        /// catalog part. Measuring the page's anchor then stays in the file.
        private func hollowOut(_ fixture: CalloutFixture) {
            let inner = LDrawMPDModel.model() as! LDrawMPDModel
            inner.setModelName("inner.ldr")
            fixture.file.addSubmodel(inner)

            for step in fixture.sub.steps() as! [LDrawStep] {
                for directive in step.subdirectives() as! [LDrawDirective] where directive is LDrawPart {
                    step.remove(directive)
                    step.add(CalloutFixture.part("inner.ldr") as LDrawDirective)
                }
            }
        }

        /// Gives the callout a PLACEMENT line with an offset, as a dropped box
        /// does.
        private func writeOffset(in fixture: CalloutFixture, _ offset: Point2 = Point2(x: 0.2, y: 0.1)) {
            let placement = LPubPlacement()
            placement.lPubCommandString = String(format: "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE %.4f %.4f",
                                                 offset.x, offset.y)
            fixture.step.insert(placement, at: fixture.step.subdirectives().count - 1)
        }

        /// A step whose callout is placed against an assembly 200 by 100
        /// points, with its submodel 60 LDU to the right of the middle. It has
        /// been laid out twice, so where the page is drawn is noted.
        private func shownWithPlacedCallout()
            -> (fixture: CalloutFixture, camera: FlatCamera, presenter: LDrawStepOverlayPresenter) {
            let shown = shown(callsOut: true,
                              assembly: CGSize(width: 200, height: 100),
                              submodelAt: Point3(x: 60, y: 0, z: 0))

            shown.presenter.reload()

            return shown
        }

        private func boxOrigin(_ presenter: LDrawStepOverlayPresenter) throws -> Point2 {
            try #require(presenter.presentation?.calloutBoxes.first).frameRect.origin
        }

        private func lpub<Line: LPubCommand>(_ line: Line, _ text: String) -> Line {
            line.lPubCommandString = text
            return line
        }

        /// A step with two callouts, each with an arrow: one for a submodel
        /// 60 LDU left of the middle, and one for a submodel 60 LDU right of
        /// it. The file puts them on these sides of the assembly. Laid out
        /// twice.
        private func shownWithTwoArrows(sides: [String] = ["LEFT", "RIGHT"])
            -> (fixture: CalloutFixture, camera: FlatCamera, presenter: LDrawStepOverlayPresenter) {
            let fixture = CalloutFixture()
            let pageSize = LPubPageSize()
            pageSize.lPubCommandString = "PAGE SIZE 8.5 11"

            hollowOut(fixture)

            for directive in fixture.step.subdirectives() as! [LDrawDirective] {
                fixture.step.remove(directive)
            }

            for (x, side) in zip([-60.0, 60.0], sides) {
                var components = IdentityComponents
                components.translate = Point3(x: x, y: 0, z: 0)

                let part = CalloutFixture.part("sub.ldr")
                part.setTransformComponents(components)

                fixture.step.add(lpub(LPubCallout(), "CALLOUT BEGIN"))
                fixture.step.add(part as LDrawDirective)
                fixture.step.add(lpub(LPubCalloutPointer(), "CALLOUT POINTER TOP_LEFT 0.5 0.5 0"))
                fixture.step.add(lpub(LPubPlacement(), "CALLOUT PLACEMENT \(side) CENTER ASSEM OUTSIDE"))
                fixture.step.add(lpub(LPubCallout(), "CALLOUT END"))
            }

            fixture.step.insert(pageSize, at: 0)
            fixture.main.setStepDisplay(true)
            fixture.main.setMaximumStepIndexForStepDisplay(UInt(fixture.main.steps().count - 1))

            let camera = FlatCamera()
            camera.assemblySize = CGSize(width: 200, height: 100)

            let presenter = LDrawStepOverlayPresenter()
            presenter.model = fixture.main
            presenter.camera = camera
            presenter.viewSize = Size2(width: 1000, height: 800)
            presenter.reload()
            presenter.reload()

            return (fixture, camera, presenter)
        }

        private func middle(_ box: Box2) -> Point2 {
            Point2(x: box.origin.x + box.size.width / 2, y: box.origin.y + box.size.height / 2)
        }

        private func isClose(_ a: Point2, _ b: Point2) -> Bool {
            abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.01
        }

        // MARK: - Tests

        @Test("The page is drawn around the model point the anchor keeps for it")
        func pageIsPinnedToTheModel() throws {
            let shown = shown()
            let presentation = try #require(shown.presenter.presentation)
            let center = shown.presenter.pageAnchor.pageCenter(forModel: shown.fixture.main)
            let drawn = shown.camera.viewPoint(forModelPoint: center)

            #expect(presentation.isOnPage)
            #expect(presentation.pageRect.size.width > 0)
            #expect(shown.presenter.pageAnchor.hasPageCenter(forModel: shown.fixture.main))
            #expect(isClose(middle(presentation.pageRect), Point2(x: Double(drawn.x), y: Double(drawn.y))))
        }

        @Test("Laying the same step out again leaves the camera alone")
        func secondLayoutMovesNothing() throws {
            let shown = shown()
            let first = try #require(shown.presenter.presentation).pageRect
            let scrolls = shown.camera.scrollCount

            shown.presenter.reload()

            #expect(shown.camera.scrollCount == scrolls)
            #expect(isClose(middle(try #require(shown.presenter.presentation).pageRect), middle(first)))
        }

        @Test("A pan moves the page with the model")
        func panMovesThePage() throws {
            let shown = shown()
            let before = middle(try #require(shown.presenter.presentation).pageRect)

            shown.camera.origin.x += 50
            #expect(shown.presenter.changeForCameraMove() == .layout)
            shown.presenter.reload()

            let after = middle(try #require(shown.presenter.presentation).pageRect)
            #expect(isClose(after, Point2(x: before.x + 50, y: before.y)))
        }

        /// Perspective draws the model nearer or further as it turns. The page
        /// is sized from how it is drawn at the angle of the layout.
        @Test("The page is sized at the angle of the layout, and keeps that size through a turn")
        func turnKeepsThePageSize() throws {
            let shown = shown()
            let before = try #require(shown.presenter.presentation).pointsPerPageInch

            // Turned so the model comes nearer: the page keeps its size.
            shown.camera.nearness = 1.1
            shown.camera.turn(toDegrees: 30)
            shown.presenter.reload()
            #expect(abs(try #require(shown.presenter.presentation).pointsPerPageInch - before) < 0.0001)

            // Laid out again at this angle, the step is measured afresh.
            shown.presenter.centerPageOnStep()
            shown.presenter.reload()
            #expect(abs(try #require(shown.presenter.presentation).pointsPerPageInch - before * 1.1) < 0.0001)
        }

        @Test("A turn leaves the page where it was drawn, and the model turns on it")
        func turnKeepsThePage() throws {

            let shown = shown()

            // A second layout notes where the page is drawn.
            shown.presenter.reload()
            let before = middle(try #require(shown.presenter.presentation).pageRect)

            // The turn moves every model point on screen.
            shown.camera.angle = Tuple3(x: 0, y: 30, z: 0)
            shown.camera.origin.x += 50
            shown.presenter.reload()

            let after = middle(try #require(shown.presenter.presentation).pageRect)
            #expect(isClose(after, before))
        }

        @Test("A turn moves a callout's box as far as its submodel moves on the page")
        func turnMovesTheCallout() throws {
            let shown = shownWithPlacedCallout()
            let page = try #require(shown.presenter.presentation).pageRect
            let placed = try boxOrigin(shown.presenter)

            // The submodel is drawn 60 points right of the middle, then 30.
            shown.camera.turn(toDegrees: 60)
            #expect(shown.presenter.changeForCameraMove() == .layout)
            shown.presenter.reload()

            let turned = try boxOrigin(shown.presenter)
            #expect(isClose(middle(try #require(shown.presenter.presentation).pageRect), middle(page)))
            #expect(isClose(turned, Point2(x: placed.x - 30, y: placed.y)))

            // Laying the step out again at that angle moves nothing more.
            shown.presenter.reload()
            #expect(isClose(try boxOrigin(shown.presenter), turned))
        }

        @Test("Back at the angle of the layout the box is where the file puts it")
        func turningBackPutsTheCalloutBack() throws {
            let shown = shownWithPlacedCallout()
            let placed = try boxOrigin(shown.presenter)

            for degrees in [20.0, 75.0, 140.0, 0.0] {
                shown.camera.turn(toDegrees: degrees)
                shown.presenter.reload()
            }

            #expect(isClose(try boxOrigin(shown.presenter), placed))
        }

        @Test("A pan while turned moves the box with the page")
        func panKeepsTheFollowedCallout() throws {
            let shown = shownWithPlacedCallout()

            shown.camera.turn(toDegrees: 60)
            shown.presenter.reload()

            let turned = try boxOrigin(shown.presenter)
            let page = try #require(shown.presenter.presentation).pageRect

            shown.camera.origin.x += 50
            shown.camera.origin.y -= 20
            shown.presenter.reload()

            let panned = try #require(shown.presenter.presentation).pageRect
            #expect(isClose(panned.origin, Point2(x: page.origin.x + 50, y: page.origin.y - 20)))
            #expect(isClose(try boxOrigin(shown.presenter), Point2(x: turned.x + 50, y: turned.y - 20)))
        }

        @Test("A box dropped while the camera is turned stays where it is dropped")
        func dropWhileTurned() throws {
            let shown = shownWithPlacedCallout()

            shown.camera.turn(toDegrees: 60)
            shown.presenter.reload()

            let box = try #require(shown.presenter.presentation?.calloutBoxes.first)
            let page = try #require(shown.presenter.presentation).pageRect
            let drop = Point2(x: box.frameRect.origin.x + 25, y: box.frameRect.origin.y - 40)
            var offset = Point2(x: 0, y: 0)

            try #require(box.getPlacementOffset(&offset, forOrigin: drop))
            writeOffset(in: shown.fixture, offset)
            shown.presenter.reload()

            // The offset is written to four decimals of a box 200 by 100 points.
            let dropped = try boxOrigin(shown.presenter)
            #expect(isClose(middle(try #require(shown.presenter.presentation).pageRect), middle(page)))
            #expect(abs(dropped.x - drop.x) < 0.02)
            #expect(abs(dropped.y - drop.y) < 0.02)

            // At the angle of the layout it is that far from where it was.
            shown.camera.turn(toDegrees: 0)
            shown.presenter.reload()

            let back = try boxOrigin(shown.presenter)
            #expect(abs(back.x - (drop.x + 30)) < 0.02)
            #expect(abs(back.y - drop.y) < 0.02)
        }

        @Test("When two submodels change sides in a turn, their boxes change places, over a short time")
        func turnHasBoxesChangePlaces() throws {
            let shown = shownWithTwoArrows()
            let boxes = try #require(shown.presenter.presentation).calloutBoxes
            var now = 100.0

            func frames() throws -> [Box2] {
                try #require(shown.presenter.presentation).calloutBoxes.map { $0.frameRect }
            }
            func right(_ box: Box2) -> Double { box.origin.x + box.size.width }

            shown.presenter.clock = { now }

            try #require(boxes.count == 2)
            try #require(boxes[0].tipCount == 1 && boxes[1].tipCount == 1)

            let placed = boxes.map { $0.frameRect }
            try #require(right(placed[0]) < placed[1].origin.x)
            #expect(shown.presenter.isMovingCallouts == false)

            shown.camera.turn(toDegrees: 180)
            shown.presenter.reload()

            let firstTip = Double(shown.camera.viewPoint(forModelPoint: Point3(x: -60, y: 0, z: 0)).x)
            let secondTip = Double(shown.camera.viewPoint(forModelPoint: Point3(x: 60, y: 0, z: 0)).x)
            try #require(firstTip > secondTip)

            // At first the boxes are drawn where the file's order has them:
            // each short of where the other's arrow goes, by the margin and
            // half an arrow's head, 0.05 and 1/16 inch at 64 points to the inch.
            let room = (0.05 + 1.0 / 16.0) * 64
            let started = try frames()
            #expect(shown.presenter.isMovingCallouts)
            #expect(abs(right(started[0]) - (secondTip - room)) < 0.01)
            #expect(abs(started[1].origin.x - (firstTip + room)) < 0.01)

            // Half way through the move they are on their way.
            now += 0.15
            shown.presenter.reload()

            let halfWay = try frames()
            #expect(shown.presenter.isMovingCallouts)
            #expect(halfWay[0].origin.x > started[0].origin.x + 1)
            #expect(halfWay[1].origin.x < started[1].origin.x - 1)

            // Then each is beside its own submodel, and the first is to the
            // right of the second, the margin away.
            now += 1
            shown.presenter.reload()

            let changed = try frames()
            #expect(shown.presenter.isMovingCallouts == false)
            #expect(abs(changed[0].origin.x - right(changed[1]) - 0.05 * 64) < 0.01)
            #expect(right(changed[0]) < firstTip)
            #expect(changed[1].origin.x > secondTip)
            #expect(firstTip - right(changed[0]) < (firstTip - right(started[0])) / 2)
            #expect(isClose(Point2(x: 0, y: changed[0].origin.y), Point2(x: 0, y: placed[0].origin.y)))

            // Laid out again, they stay.
            now += 1
            shown.presenter.reload()
            #expect(isClose(try frames()[0].origin, changed[0].origin))
            #expect(shown.presenter.isMovingCallouts == false)

            // Back at the angle of the layout they move to where the file
            // puts them.
            shown.camera.turn(toDegrees: 0)
            shown.presenter.reload()
            #expect(shown.presenter.isMovingCallouts)
            #expect(isClose(try frames()[0].origin, changed[0].origin))

            now += 1
            shown.presenter.reload()
            #expect(shown.presenter.isMovingCallouts == false)
            #expect(isClose(try frames()[0].origin, placed[0].origin))
            #expect(isClose(try frames()[1].origin, placed[1].origin))
        }

        @Test("Placed automatically, each box is beside the assembly on its submodel's side, whatever its line says")
        func automaticPlacement() throws {
            LDrawStepPartList.setPlacesCalloutsAutomatically(true)
            defer { LDrawStepPartList.setPlacesCalloutsAutomatically(false) }

            // The file has each box on the far side from its submodel.
            let shown = shownWithTwoArrows(sides: ["RIGHT", "LEFT"])
            var now = 100.0

            func frames() throws -> [Box2] {
                try #require(shown.presenter.presentation).calloutBoxes.map { $0.frameRect }
            }
            func right(_ box: Box2) -> Double { box.origin.x + box.size.width }

            shown.presenter.clock = { now }
            now += 1
            shown.presenter.reload()

            // The assembly is 200 points wide about where the origin is drawn.
            let middle = Double(shown.camera.viewPoint(forModelPoint: Point3(x: 0, y: 0, z: 0)).x)
            let placed = try frames()
            #expect(right(placed[0]) < middle - 100)
            #expect(placed[1].origin.x > middle + 100)
            #expect(try #require(shown.presenter.presentation).calloutBoxes.allSatisfy { $0.isPlacedByFile == false })
            #expect(shown.presenter.isMovingCallouts == false)

            // Turned half way round the submodels have changed sides, and the
            // boxes go with them, over a short time.
            shown.camera.turn(toDegrees: 180)
            shown.presenter.reload()
            #expect(shown.presenter.isMovingCallouts)

            now += 1
            shown.presenter.reload()

            let turned = try frames()
            #expect(shown.presenter.isMovingCallouts == false)
            #expect(turned[0].origin.x > middle + 100)
            #expect(right(turned[1]) < middle - 100)
        }

        @Test("With the automatic placing turned off in a turned view, the boxes are where they would have followed to")
        func automaticPlacementTurnedOff() throws {
            var now = 100.0

            /// Where the boxes are from the page's corner.
            func places(_ presenter: LDrawStepOverlayPresenter) throws -> [Point2] {
                let presentation = try #require(presenter.presentation)
                let corner = presentation.pageRect.origin

                return presentation.calloutBoxes.map {
                    Point2(x: $0.frameRect.origin.x - corner.x, y: $0.frameRect.origin.y - corner.y)
                }
            }

            // Placed by the file all along, and turned half way round.
            let plain = shownWithTwoArrows()
            plain.presenter.clock = { now }

            let home = try places(plain.presenter)

            plain.camera.turn(toDegrees: 180)
            plain.presenter.reload()
            now += 1
            plain.presenter.reload()

            let followed = try places(plain.presenter)
            try #require(isClose(followed[0], home[0]) == false)

            // Laid out and turned while the boxes were placed automatically.
            LDrawStepPartList.setPlacesCalloutsAutomatically(true)
            defer { LDrawStepPartList.setPlacesCalloutsAutomatically(false) }

            let shown = shownWithTwoArrows()
            shown.presenter.clock = { now }
            shown.camera.turn(toDegrees: 180)
            shown.presenter.reload()
            now += 1
            shown.presenter.reload()

            LDrawStepPartList.setPlacesCalloutsAutomatically(false)
            shown.presenter.reload()

            let switched = try places(shown.presenter)
            #expect(shown.presenter.isMovingCallouts == false)
            #expect(isClose(switched[0], followed[0]))
            #expect(isClose(switched[1], followed[1]))
        }

        @Test("A move is not said to go on once the page is gone")
        func noMoveOffThePage() throws {
            let shown = shownWithTwoArrows()

            shown.presenter.clock = { 100 }
            shown.camera.turn(toDegrees: 180)
            shown.presenter.reload()
            try #require(shown.presenter.isMovingCallouts)

            LDrawStepPartList.setUsesLPubScale(false)
            shown.presenter.reload()
            #expect(shown.presenter.isMovingCallouts == false)

            LDrawStepPartList.setUsesLPubScale(true)
        }

        @Test("Centering the page on its step again does not move the camera")
        func centeringLeavesTheCamera() throws {
            let shown = shown()
            let scrolls = shown.camera.scrollCount

            shown.presenter.centerPageOnStep()

            #expect(shown.camera.scrollCount == scrolls)
            #expect(shown.presenter.pageAnchor.hasPageCenter(forModel: shown.fixture.main))
        }

        @Test("A PLACEMENT line that changes centers the step again, with the page held where it is")
        func changedPlacementCentersAgain() throws {
            let shown = shown(callsOut: true)
            let scrolls = shown.camera.scrollCount
            let page = try #require(shown.presenter.presentation).pageRect

            writeOffset(in: shown.fixture)
            shown.presenter.reload()

            #expect(shown.camera.scrollCount == scrolls + 1)
            #expect(isClose(middle(try #require(shown.presenter.presentation).pageRect), middle(page)))

            shown.presenter.reload()
            #expect(shown.camera.scrollCount == scrolls + 1)
        }

        @Test("So does the line a dropped box writes")
        func dropCentersAgain() throws {
            let shown = shown(callsOut: true)
            let scrolls = shown.camera.scrollCount

            shown.presenter.hasCalloutPreview = true
            shown.presenter.calloutPreviewBox = 0
            shown.presenter.calloutPreviewPoint = Point2(x: 700, y: 300)
            shown.presenter.reload()

            #expect(shown.camera.scrollCount == scrolls)

            writeOffset(in: shown.fixture)
            shown.presenter.hasCalloutPreview = false
            shown.presenter.reload()

            #expect(shown.camera.scrollCount == scrolls + 1)
        }

        @Test("Off the page only the arrows follow the camera")
        func offThePage() throws {
            LDrawStepPartList.setUsesLPubScale(false)

            let shown = shown(callsOut: true)
            let presentation = try #require(shown.presenter.presentation)

            #expect(presentation.isOnPage == false)
            #expect(presentation.calloutBoxes.count == 1)
            #expect(shown.presenter.calloutArrows.count == 1)
            #expect(shown.presenter.changeForCameraMove() == .arrows)

            LDrawStepPartList.setUsesLPubScale(true)
        }
    }
}
