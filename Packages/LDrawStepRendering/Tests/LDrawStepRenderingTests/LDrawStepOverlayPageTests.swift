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
import LDrawStepEditing
import LDrawStepRendering

/// A camera that draws the model flat: a model point lands at its x and y
/// times the zoom, from where the origin is drawn. `turn(toDegrees:)` turns the
/// model about its y axis, which moves its points sideways.
private final class FlatCamera: NSObject, LDrawStepOverlayCamera {

    var zoom: CGFloat = 100
    var origin = CGPoint(x: 500, y: 400)
    var angle = Tuple3(x: 0, y: 0, z: 0)
    var scrollCount = 0
    var measureCount = 0

    /// The box it gives for the assembly, around where the origin is drawn.
    /// The fixtures' models place nothing a camera could measure.
    var assemblySize = CGSize.zero

    /// How far that box is drawn off the origin, as when a part of it moves.
    var assemblyShift = CGSize.zero

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

    /// Takes the turn about the y axis, the only one this camera draws.
    func setViewingAngle(_ newAngle: Tuple3) {
        angle = newAngle
        turn = newAngle.y * .pi / 180
    }

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
        measureCount += 1

        guard assemblySize != .zero else { return .zero }

        return CGRect(x: origin.x - assemblySize.width / 2 + assemblyShift.width,
                      y: origin.y - assemblySize.height / 2 + assemblyShift.height,
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

        /// Another presenter on the same model and camera, with a layout cache.
        private func presenter(on shown: (fixture: CalloutFixture, camera: FlatCamera,
                                          presenter: LDrawStepOverlayPresenter),
                               sharing cache: LDrawStepLayoutCache) -> LDrawStepOverlayPresenter {
            let presenter = LDrawStepOverlayPresenter()
            presenter.model = shown.fixture.main
            presenter.camera = shown.camera
            presenter.viewSize = shown.presenter.viewSize
            presenter.layoutCache = cache
            return presenter
        }

        private func isSame(_ a: Point3, _ b: Point3) -> Bool {
            abs(a.x - b.x) < 0.001 && abs(a.y - b.y) < 0.001 && abs(a.z - b.z) < 0.001
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

        @Test("A step centered again in the same view takes its place from the layout cache")
        func centeringFromTheCache() throws {
            let shown = shownWithPlacedCallout()
            let cache = LDrawStepLayoutCache()

            shown.presenter.layoutCache = cache
            shown.presenter.centerPageOnStep()
            shown.presenter.reload()

            let other = presenter(on: shown, sharing: cache)
            let measures = shown.camera.measureCount

            other.centerPageOnStep()

            #expect(shown.camera.measureCount == measures)
            #expect(isSame(other.pageAnchor.pageCenter(forModel: shown.fixture.main),
                           shown.presenter.pageAnchor.pageCenter(forModel: shown.fixture.main)))

            let scrolls = shown.camera.scrollCount

            other.reload()

            #expect(shown.camera.scrollCount == scrolls)
            let page = try #require(shown.presenter.presentation).pageRect

            #expect(isClose(middle(try #require(other.presentation).pageRect), middle(page)))
        }

        @Test("In another view the step is measured again")
        func centeringInAnotherView() throws {
            let shown = shownWithPlacedCallout()
            let cache = LDrawStepLayoutCache()

            shown.presenter.layoutCache = cache
            shown.presenter.centerPageOnStep()

            let other = presenter(on: shown, sharing: cache)
            let measures = shown.camera.measureCount

            shown.camera.zoom = 150
            other.centerPageOnStep()

            #expect(shown.camera.measureCount > measures)
        }

        @Test("A change to the file forgets what the cache kept")
        func changeEmptiesTheCache() throws {
            let shown = shownWithPlacedCallout()

            shown.presenter.layoutCache = LDrawStepLayoutCache()
            shown.presenter.centerPageOnStep()
            _ = shown.presenter.change(forChangedObject: nil)

            let measures = shown.camera.measureCount

            shown.presenter.centerPageOnStep()

            #expect(shown.camera.measureCount > measures)
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

        // MARK: - Arranging
        //
        // The fixture's page is 8.5 by 11 inches, its step has no MODEL_SCALE,
        // and the camera draws one LDU at a point, so an inch of the page is
        // 64 points when arranging starts.

        /// A step laid out on its page, with an assembly the camera measures,
        /// being arranged.
        private func arranged() throws
            -> (fixture: CalloutFixture, camera: FlatCamera, presenter: LDrawStepOverlayPresenter) {
            let shown = shown(assembly: CGSize(width: 200, height: 100))

            shown.presenter.reload()
            try #require(shown.presenter.beginArranging())
            shown.presenter.reload()

            return shown
        }

        private func isSameBox(_ a: Box2, _ b: Box2) -> Bool {
            isClose(a.origin, b.origin) && abs(a.size.width - b.size.width) < 0.01
                && abs(a.size.height - b.size.height) < 0.01
        }

        @Test("Arranging holds the page where it is drawn through a pan, a zoom and a turn")
        func arrangingHoldsThePage() throws {
            let shown = try arranged()
            let page = try #require(shown.presenter.presentation).pageRect

            shown.camera.origin.x += 40
            shown.camera.origin.y += 15
            shown.presenter.reload()
            #expect(isSameBox(try #require(shown.presenter.presentation).pageRect, page))

            shown.camera.zoom = 150
            shown.presenter.reload()
            #expect(isSameBox(try #require(shown.presenter.presentation).pageRect, page))

            shown.camera.turn(toDegrees: 30)
            shown.presenter.reload()
            #expect(isSameBox(try #require(shown.presenter.presentation).pageRect, page))
        }

        @Test("A pan moves the step on the page, by that share of the page")
        func arrangingPanGivesAnOffset() throws {
            let shown = try arranged()

            #expect(isClose(shown.presenter.arrangedOffset, Point2(x: 0, y: 0)))
            #expect(abs(shown.presenter.arrangedScale - 1) < 0.000001)

            shown.camera.origin.x += 85
            shown.camera.origin.y -= 22
            shown.presenter.reload()

            #expect(abs(shown.presenter.arrangedOffset.x - 85 / (8.5 * 64)) < 0.00001)
            #expect(abs(shown.presenter.arrangedOffset.y + 22 / (11 * 64)) < 0.00001)
            #expect(abs(shown.presenter.arrangedScale - 1) < 0.000001)
        }

        @Test("A zoom changes the assembly's scale, and the step keeps its offset")
        func arrangingZoomGivesAScale() throws {
            let shown = try arranged()

            shown.camera.origin.x += 85
            shown.presenter.reload()
            let offset = shown.presenter.arrangedOffset

            shown.camera.zoom = 150
            shown.presenter.reload()

            #expect(abs(shown.presenter.arrangedScale - 1.5) < 0.000001)
            #expect(isClose(shown.presenter.arrangedOffset, offset))

            // The page keeps its inch, so the list and the boxes keep their size.
            #expect(abs(try #require(shown.presenter.presentation).pointsPerPageInch - 64) < 0.0001)
        }

        @Test("A turn keeps the scale and the offset, and zooms to keep the model's size beside the anchor")
        func arrangingTurnKeepsScaleAndOffset() throws {
            let shown = try arranged()

            shown.camera.origin.x += 85
            shown.presenter.reload()
            let offset = shown.presenter.arrangedOffset

            // Seen from here the anchor is nearer, so the model is drawn bigger.
            shown.camera.nearness = 1.25
            shown.camera.turn(toDegrees: 30)
            shown.presenter.reload()

            #expect(abs(shown.presenter.arrangedScale - 1) < 0.000001)
            #expect(abs(shown.camera.zoom - 80) < 0.0001)
            #expect(isClose(shown.presenter.arrangedOffset, offset))
            #expect(shown.presenter.arrangedViewingAngle.y == 30)
        }

        @Test("Moving the arranged step by inches moves the model under the page")
        func arrangingMoveByInches() throws {
            let shown = try arranged()
            let origin = shown.camera.origin

            shown.presenter.moveArrangedStep(byInches: Vector2(x: 0.5, y: -0.25))
            shown.presenter.reload()

            #expect(abs(shown.presenter.arrangedOffset.x - 0.5 / 8.5) < 0.00001)
            #expect(abs(shown.presenter.arrangedOffset.y + 0.25 / 11) < 0.00001)
            #expect(abs(shown.camera.origin.x - origin.x - 32) < 0.01)
            #expect(abs(shown.camera.origin.y - origin.y + 16) < 0.01)
        }

        @Test("A scale or an offset set while arranging moves the model to it, under the page")
        func arrangingSetScaleAndOffset() throws {
            let shown = try arranged()
            let page = try #require(shown.presenter.presentation).pageRect

            shown.camera.origin.x += 85
            shown.presenter.reload()
            let offset = shown.presenter.arrangedOffset

            // The model is zoomed to the scale and keeps its place.
            shown.presenter.arrangedScale = 2
            shown.presenter.reload()

            #expect(abs(shown.camera.zoom - 200) < 0.0001)
            #expect(isClose(shown.presenter.arrangedOffset, offset))
            #expect(isSameBox(try #require(shown.presenter.presentation).pageRect, page))

            // Back to the middle of the page.
            let origin = shown.camera.origin
            shown.presenter.arrangedOffset = Point2(x: 0, y: 0)
            shown.presenter.reload()

            #expect(isClose(shown.presenter.arrangedOffset, Point2(x: 0, y: 0)))
            #expect(abs(shown.camera.origin.x - origin.x + 85) < 0.01)
        }

        @Test("A pan snaps the step's middle to the page's middle, with a guide, and a pan on gets past it")
        func arrangingPanSnapsToTheMiddle() throws {
            let shown = try arranged()
            let origin = shown.camera.origin

            // Centered as it starts: both middle lines show.
            #expect(shown.presenter.arrangedGuides.count == 2 * MemoryLayout<Box2>.size)

            shown.camera.origin.x += 40
            shown.presenter.reload()
            #expect(abs(shown.presenter.arrangedOffset.x - 40 / (8.5 * 64)) < 0.00001)
            #expect(shown.presenter.arrangedGuides.count == MemoryLayout<Box2>.size, "Only the line across")

            // Back to 3 points from the middle: it snaps there.
            shown.camera.origin.x -= 37
            shown.presenter.reload()
            #expect(abs(shown.presenter.arrangedOffset.x) < 0.00001)
            #expect(abs(shown.camera.origin.x - origin.x) < 0.01)

            // A few points more stays snapped, and then it gets past.
            shown.camera.origin.x += 2
            shown.presenter.reload()
            #expect(abs(shown.presenter.arrangedOffset.x) < 0.00001)

            shown.camera.origin.x += 5
            shown.presenter.reload()
            #expect(abs(shown.presenter.arrangedOffset.x - 10 / (8.5 * 64)) < 0.00001)
            #expect(abs(shown.camera.origin.x - origin.x - 10) < 0.01)
        }

        @Test("A pan snaps the step's edge to the page's margin")
        func arrangingPanSnapsToTheMargin() throws {
            let shown = try arranged()
            let presentation = try #require(shown.presenter.presentation)
            let margin = presentation.pageRect.origin.x + presentation.pageMargins().width * 64
            let left = presentation.stepRect.origin.x

            // To 4 points right of the margin.
            shown.camera.origin.x -= left - margin - 4
            shown.presenter.reload()

            let snapped = try #require(shown.presenter.presentation).stepRect
            #expect(abs(snapped.origin.x - margin) < 0.01)
        }

        @Test("A zoom snaps to a step of 0.05")
        func arrangingZoomSnaps() throws {
            let shown = try arranged()

            shown.camera.zoom = 100.6
            shown.presenter.reload()
            #expect(abs(shown.presenter.arrangedScale - 1) < 0.000001)
            #expect(abs(shown.camera.zoom - 100) < 0.0001)

            // Zoomed on from there, the scale goes on from where the pinch
            // was, 1.006, and the model jumps there off the snap.
            shown.camera.zoom = 112.0
            shown.presenter.reload()
            #expect(abs(shown.presenter.arrangedScale - 1.006 * 1.12) < 0.000001)
            #expect(abs(shown.camera.zoom - 100.6 * 1.12) < 0.0001)

            shown.camera.zoom = 114.5
            shown.presenter.reload()
            #expect(abs(shown.presenter.arrangedScale - 1.15) < 0.000001)
            #expect(abs(shown.camera.zoom - 115) < 0.0001)
        }

        @Test("With Shift a turn snaps to steps of 15 degrees")
        func arrangingTurnSnapsToSteps() throws {
            let shown = try arranged()

            shown.presenter.snapsTurnsToSteps = true
            shown.camera.turn(toDegrees: 31)
            shown.presenter.reload()

            #expect(abs(abs(shown.camera.angle.y) - 30) < 0.001)

            // Without Shift the turn goes on from where it was, 31, so a
            // further 7 degrees comes to 38.
            shown.presenter.snapsTurnsToSteps = false
            shown.camera.turn(toDegrees: 37)
            shown.presenter.reload()

            #expect(abs(abs(shown.camera.angle.y) - 38) < 0.001)
        }

        @Test("An angle the host sets is kept as it is, with Shift too")
        func arrangingExactTurnDoesNotSnap() throws {
            let shown = try arranged()

            shown.presenter.snapsTurnsToSteps = true
            shown.presenter.turnArrangedStep(toViewingAngle: Tuple3(x: 0, y: 31, z: 0))
            shown.presenter.reload()

            #expect(abs(shown.camera.angle.y - 31) < 0.001)

            // A turn by a gesture after it snaps again.
            shown.camera.turn(toDegrees: 44)
            shown.presenter.reload()

            #expect(abs(abs(shown.camera.angle.y) - 45) < 0.001)
        }

        @Test("Only a pan snaps the step: its box moving without one leaves the model where it is")
        func arrangingSnapsOnlyOnAPan() throws {
            let shown = try arranged()
            let origin = shown.camera.origin

            // 3 points off the page's middle, where a pan would snap back.
            shown.camera.assemblyShift.width = 3
            shown.presenter.reload()

            #expect(abs(shown.camera.origin.x - origin.x) < 0.01)
            #expect(abs(shown.presenter.arrangedOffset.x - 3 / (8.5 * 64)) < 0.00001)

            // A pan from there snaps, from the offset the box was moved to.
            shown.camera.origin.x += 1
            shown.presenter.reload()

            #expect(abs(shown.presenter.arrangedOffset.x) < 0.00001)
            #expect(abs(shown.camera.origin.x - origin.x + 3) < 0.01)
        }

        @Test("Once arranging ends the step goes back where its lines put it, with the page held")
        func arrangingEnds() throws {
            let shown = try arranged()
            let page = try #require(shown.presenter.presentation).pageRect

            shown.camera.origin.x += 85
            shown.presenter.reload()
            shown.presenter.endArranging()
            shown.presenter.reload()

            let presentation = try #require(shown.presenter.presentation)

            #expect(shown.presenter.isArranging == false)
            #expect(isSameBox(presentation.pageRect, page))
            #expect(isClose(presentation.stepCenterInView, middle(presentation.pageRect)))
        }

        @Test("Written and laid out from the file, the arranged step stays where it was arranged")
        func arrangedStepWrittenStaysPut() throws {
            let shown = try arranged()

            shown.camera.origin.x += 85
            shown.camera.origin.y -= 22
            shown.presenter.reload()
            shown.camera.zoom = 150
            shown.presenter.reload()

            let presenter = shown.presenter
            let model = shown.fixture.main
            let page = try #require(presenter.presentation).pageRect
            let origin = shown.camera.origin
            let edit = LDrawStepAssemblyEdit.edit(combining: [
                LDrawStepAssemblyEdit.edit(settingScale: presenter.arrangedScale, scope: .step, inModel: model),
                LDrawStepAssemblyEdit.edit(settingOffset: presenter.arrangedOffset, scope: .step, inModel: model),
            ])

            #expect(edit.apply(host: ApplyingHost()))
            #expect(presenter.change(forChangedObject: shown.fixture.step) != [])

            presenter.endArranging()
            presenter.reload()

            let presentation = try #require(presenter.presentation)

            #expect(isSameBox(presentation.pageRect, page))
            #expect(abs(shown.camera.origin.x - origin.x) < 0.05 && abs(shown.camera.origin.y - origin.y) < 0.05)
        }

        @Test("While arranging, a dashed line is drawn just outside the step, and a line just outside the page")
        func arrangingDrawsTheFrame() throws {
            let shown = try arranged()
            let presentation = try #require(shown.presenter.presentation)
            let step = presentation.stepRect
            let size = Size2(width: 1000, height: 800)

            #expect(abs(step.size.width - 200) < 0.01 && abs(step.size.height - 100) < 0.01)

            let renderer = LDrawStepOverlayRenderer()
            renderer.presentation = presentation

            let plain = Canvas(width: 1000, height: 800)
            renderer.drawCallouts(in: plain.context, viewSize: size)
            #expect(plain.inkBounds == nil, "With no color there is no frame")

            renderer.arrangeFrameColor = CGColor(srgbRed: 0, green: 0.4, blue: 1, alpha: 1)

            let framed = Canvas(width: 1000, height: 800)
            renderer.drawCallouts(in: framed.context, viewSize: size)

            // The frame's top line, 6 points out, has a dash 20 points along,
            // past the corner's handle.
            let left = Int(step.origin.x) - 6
            let top = Int(step.origin.y) - 6

            #expect(framed.isInked(left + 22, top))
            #expect(framed.isInked(left + 22, top - 4) == false, "Nothing just outside the frame")
            #expect(framed.isInked(left + 22, top + 4) == false, "Nothing just inside it")

            // The corner's handle is filled.
            #expect(framed.isInked(left + 2, top + 2))
            #expect(plain.isInked(left + 2, top + 2) == false)

            // The page's edge, all round, and nothing just inside it or along
            // the view's edge.
            let page = presentation.pageRect
            let minX = Int(page.origin.x), maxX = Int(page.origin.x + page.size.width)
            let minY = Int(page.origin.y), maxY = Int(page.origin.y + page.size.height)
            let midX = (minX + maxX) / 2, midY = (minY + maxY) / 2

            try #require(minX > 4 && minY > 4 && maxX < 996 && maxY < 796, "The page is inside the view")
            #expect(framed.isInked(minX - 2, midY) && framed.isInked(maxX + 1, midY))
            #expect(framed.isInked(midX, minY - 2) && framed.isInked(midX, maxY + 1))
            #expect(framed.isInked(minX + 3, midY) == false && framed.isInked(minX - 5, midY) == false)
            #expect(framed.isInked(1, 400) == false && framed.isInked(500, 1) == false)
        }

        @Test("While arranging, the line around the page stays out of the scroll bars")
        func arrangingEdgeStaysUncovered() throws {
            let shown = try arranged()
            let presentation = try #require(shown.presenter.presentation)
            let page = presentation.pageRect
            let renderer = LDrawStepOverlayRenderer()
            let canvas = Canvas(width: 1000, height: 800)
            let midY = Int(page.origin.y + page.size.height / 2)
            let cut = Int(page.origin.x + page.size.width / 2)

            // Scroll bars that cover the view from the page's middle rightward.
            renderer.presentation = presentation
            renderer.arrangeFrameColor = CGColor(srgbRed: 0, green: 0.4, blue: 1, alpha: 1)
            renderer.unobscuredRect = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: Double(cut), height: 800))
            renderer.drawCallouts(in: canvas.context, viewSize: Size2(width: 1000, height: 800))

            #expect(canvas.isInked(cut - 2, midY))
            #expect(canvas.isInked(cut + 1, midY) == false)
            #expect(canvas.isInked(Int(page.origin.x + page.size.width) + 1, midY) == false)
        }

        @Test("While arranging, each corner of the step's frame has a handle, and a drag on one scales the step")
        func arrangingHandlesScale() throws {
            let shown = try arranged()
            let presentation = try #require(shown.presenter.presentation)
            let step = presentation.stepRect
            let frame = presentation.arrangeFrameRect
            let tracker = LDrawStepAssemblyScaleTracker()

            #expect(isSameBox(frame, Box2(origin: Point2(x: step.origin.x - 6, y: step.origin.y - 6),
                                          size: Size2(width: step.size.width + 12, height: step.size.height + 12))))
            #expect([.topLeft, .topRight, .bottomRight, .bottomLeft].allSatisfy {
                presentation.rect(ofArrangeHandle: $0).size.width > 0
            })

            // With no placement line the step grows from its middle.
            let anchor = presentation.stepAnchorInView
            let corner = Point2(x: frame.origin.x + frame.size.width, y: frame.origin.y + frame.size.height)

            #expect(isClose(anchor, middle(step)))
            #expect(presentation.arrangeHandle(at: Point2(x: corner.x + 4, y: corner.y - 4)) == .bottomRight)
            #expect(presentation.arrangeHandle(at: middle(step)) == .none)
            #expect(tracker.begin(at: middle(step), presentation: presentation, scale: 1) == false)

            // Pressed off the corner, the drag keeps that grab.
            let grab = Point2(x: corner.x + 2, y: corner.y - 1)
            try #require(tracker.begin(at: grab, presentation: presentation, scale: 1))
            #expect(tracker.handle == .bottomRight)

            let twice = Point2(x: anchor.x + 2 * (corner.x - anchor.x) + 2, y: anchor.y + 2 * (corner.y - anchor.y) - 1)
            #expect(abs(tracker.scaleForDrag(to: twice) - 2) < 0.000001)
            #expect(abs(tracker.scaleForDrag(to: Point2(x: anchor.x - 50, y: anchor.y - 50)) - 0.05) < 0.000001)

            // Given to the presenter, the scale snaps as a zoom does, and the
            // model is zoomed to it.
            shown.presenter.zoomArrangedStep(toScale: 2.004)
            shown.presenter.reload()
            #expect(abs(shown.presenter.arrangedScale - 2) < 0.000001)
            #expect(abs(shown.camera.zoom - 200) < 0.0001)

            shown.presenter.zoomArrangedStep(toScale: 1.83)
            shown.presenter.reload()
            #expect(abs(shown.presenter.arrangedScale - 1.83) < 0.000001)

            tracker.end()
            #expect(tracker.isScaling == false && tracker.handle == .none)
        }

        @Test("A step placed by its corner grows from that corner, which has no handle")
        func cornerPlacedStepHasNoHandleThere() throws {
            let shown = shown(assembly: CGSize(width: 200, height: 100))
            let step = shown.fixture.step

            step.insert(lpub(LPubPlacement(), "ASSEM PLACEMENT LOCAL TOP_LEFT PAGE INSIDE"),
                        at: step.subdirectives().count - 1)
            shown.presenter.reload()

            let presentation = try #require(shown.presenter.presentation)

            #expect(isClose(presentation.stepAnchorInView, presentation.stepRect.origin))
            #expect(presentation.rect(ofArrangeHandle: .topLeft).size.width == 0)
            #expect(presentation.arrangeHandle(at: presentation.arrangeFrameRect.origin) == .none)
            #expect(presentation.rect(ofArrangeHandle: .bottomRight).size.width > 0)
        }

        @Test("The guides the step lines up with are drawn across the page")
        func arrangingDrawsTheGuides() throws {
            let shown = try arranged()
            let presentation = try #require(shown.presenter.presentation)
            let page = presentation.pageRect
            let renderer = LDrawStepOverlayRenderer()

            renderer.presentation = presentation
            renderer.guides = shown.presenter.arrangedGuides
            renderer.guideColor = CGColor(srgbRed: 0, green: 0.4, blue: 1, alpha: 1)

            let canvas = Canvas(width: 1000, height: 800)
            renderer.drawCallouts(in: canvas.context, viewSize: Size2(width: 1000, height: 800))

            // The page's middle lines, away from the step and its frame.
            let middleX = Int(page.origin.x + page.size.width / 2)
            let middleY = Int(page.origin.y + page.size.height / 2)

            #expect(canvas.isInked(middleX, Int(page.origin.y) + 20))
            #expect(canvas.isInked(Int(page.origin.x) + 20, middleY))
            #expect(canvas.isInked(middleX + 30, Int(page.origin.y) + 20) == false)
        }

        /// A step laid out on its page, then a second step after it, being
        /// arranged. The camera gives both the same assembly. The previous
        /// step is shown unless `showsPrevious` is false.
        private func arrangedAfterAStep(showsPrevious: Bool = true) throws
            -> (fixture: CalloutFixture, camera: FlatCamera, presenter: LDrawStepOverlayPresenter) {
            let shown = shown(assembly: CGSize(width: 200, height: 100))

            let main = shown.fixture.main

            main.addStep()
            shown.presenter.reload()

            main.setMaximumStepIndexForStepDisplay(UInt(main.steps().count - 1))
            shown.presenter.reload()
            shown.presenter.showsPreviousStep = showsPrevious
            try #require(shown.presenter.beginArranging())
            shown.presenter.reload()

            return shown
        }

        @Test("The previous step is hidden to begin with, and the step still lines up with it")
        func previousStepHiddenByDefault() throws {
            #expect(LDrawStepOverlayPresenter().showsPreviousStep == false)

            let shown = try arrangedAfterAStep(showsPrevious: false)
            let presenter = shown.presenter

            #expect(presenter.previousStepOutline.isEmpty)
            #expect(presenter.previousStepPicture == nil)
            #expect(presenter.canAlignArrangedStepWithPreviousStep)

            presenter.showsPreviousStep = true
            presenter.reload()
            #expect(presenter.previousStepOutline.isEmpty == false)
        }

        private func boxAround(_ outline: Data) -> Box2 {
            let points = outline.withUnsafeBytes { Array($0.bindMemory(to: Point2.self)) }
            let xs = points.map(\.x)
            let ys = points.map(\.y)

            return Box2(origin: Point2(x: xs.min() ?? 0, y: ys.min() ?? 0),
                        size: Size2(width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0)))
        }

        @Test("While arranging, the previous step's outline is where it sat on its page, and the step lines up with it")
        func arrangingShowsThePreviousStep() throws {
            let shown = try arrangedAfterAStep()
            let presenter = shown.presenter
            let step = try #require(presenter.presentation).stepRect
            let ghost = boxAround(presenter.previousStepOutline)

            // Both steps are centered alike, so it sat where this one is.
            #expect(presenter.previousStepOutline.count == 4 * MemoryLayout<Point2>.size)
            #expect(isSameBox(ghost, step))

            // Moved on the page, the step leaves the outline where it was.
            shown.camera.origin.x += 85
            shown.camera.origin.y -= 22
            presenter.reload()
            #expect(isSameBox(boxAround(presenter.previousStepOutline), ghost))
            #expect(abs(presenter.arrangedOffset.x - 85 / (8.5 * 64)) < 0.00001)

            // Lined up, its earlier parts are back where the previous step had
            // them.
            #expect(presenter.canAlignArrangedStepWithPreviousStep)
            presenter.alignArrangedStepWithPreviousStep()
            presenter.reload()
            #expect(isClose(presenter.arrangedOffset, Point2(x: 0, y: 0)))
            #expect(isSameBox(try #require(presenter.presentation).stepRect, ghost))

            // Centered, the middle of its box is on the middle of the page.
            shown.camera.origin.x -= 40
            presenter.reload()
            presenter.centerArrangedStepOnPage()
            presenter.reload()

            let centered = try #require(presenter.presentation)
            #expect(isClose(middle(centered.stepRect), middle(centered.pageRect)))
            #expect(isClose(presenter.arrangedOffset, Point2(x: 0, y: 0)))

            presenter.endArranging()
            #expect(presenter.previousStepOutline.isEmpty)
        }

        @Test("A change to the previous step forgets where it sat, and a change to this one or to the file does not")
        func previousStepIsForgottenWhenItChanges() throws {
            let shown = try arrangedAfterAStep()
            let presenter = shown.presenter
            let steps = shown.fixture.main.steps() as! [LDrawStep]

            _ = presenter.change(forChangedObject: steps[steps.count - 1])
            presenter.reload()
            #expect(presenter.previousStepOutline.isEmpty == false)
            #expect(presenter.canAlignArrangedStepWithPreviousStep)

            // A note for the whole file, as a change of step posts, is read
            // as a change to the step on display.
            _ = presenter.change(forChangedObject: shown.fixture.file)
            presenter.reload()
            #expect(presenter.previousStepOutline.isEmpty == false)

            _ = presenter.change(forChangedObject: shown.fixture.step)
            presenter.reload()
            #expect(presenter.previousStepOutline.isEmpty)
            #expect(presenter.canAlignArrangedStepWithPreviousStep == false)
        }

        @Test("With its previous step never laid out, a step has nothing to show or line up with")
        func unseenPreviousStep() throws {
            let shown = try arranged()

            #expect(shown.presenter.previousStepOutline.isEmpty)
            #expect(shown.presenter.canAlignArrangedStepWithPreviousStep == false)
        }

        @Test("The previous step's outline is filled on the paper in its color")
        func previousStepOutlineIsDrawn() throws {
            let shown = try arrangedAfterAStep()
            let presentation = try #require(shown.presenter.presentation)
            let center = middle(boxAround(shown.presenter.previousStepOutline))
            let size = Size2(width: 1000, height: 800)
            let renderer = LDrawStepOverlayRenderer()

            renderer.presentation = presentation
            renderer.ghostOutline = shown.presenter.previousStepOutline

            let plain = Canvas(width: 1000, height: 800)
            renderer.drawPageAndFrame(in: plain.context, viewSize: size)
            #expect(plain.isInked(Int(center.x), Int(center.y)) == false, "With no color there is no outline")

            renderer.ghostColor = CGColor(srgbRed: 0, green: 0.4, blue: 1, alpha: 0.2)

            let tinted = Canvas(width: 1000, height: 800)
            renderer.drawPageAndFrame(in: tinted.context, viewSize: size)
            #expect(tinted.isInked(Int(center.x), Int(center.y)))
        }

        /// The angle LPub3D prints the visible step at.
        private func stepAngle(of model: LDrawModel) -> Tuple3 {
            let index = (model.steps() as NSArray).indexOfObjectIdentical(to: model.visibleStep() as Any)

            return LDrawStepPartListPolicy.assemblyViewingAngle(forStepAt: UInt(index), inModel: model)
        }

        @Test("A view turned away from the step's angle is marked, and one written another way but turned the same is not")
        func turnedViewIsMarked() throws {
            let shown = shown(assembly: CGSize(width: 200, height: 100))
            let presenter = shown.presenter
            let angle = stepAngle(of: shown.fixture.main)

            shown.camera.setViewingAngle(angle)
            presenter.reload()
            #expect(presenter.isTurnedFromStepAngle == false)

            // The same turn, as other numbers. The middle turn is about z.
            shown.camera.setViewingAngle(Tuple3(x: angle.x + 180, y: angle.y + 180, z: 180 - angle.z))
            presenter.reload()
            #expect(presenter.isTurnedFromStepAngle == false)

            shown.camera.turn(toDegrees: 30)
            presenter.reload()
            #expect(presenter.isTurnedFromStepAngle)

            // Arranging takes the view's angle as the step's.
            try #require(presenter.beginArranging())
            presenter.reload()
            #expect(presenter.isTurnedFromStepAngle == false)
        }

        @Test("A turned view's strip is drawn across the top of the view, with its two buttons on it")
        func turnedViewStrip() throws {
            let renderer = LDrawStepOverlayRenderer()
            let size = Size2(width: 1000, height: 800)

            renderer.useAngleTitle = "Use This Angle"
            renderer.stepAngleTitle = "Back to Step's Angle"
            #expect(renderer.turnedViewStripRect(forViewSize: size).size.width == 0)

            renderer.turnedViewText = "Turned view: not what LPub3D prints"

            let strip = renderer.turnedViewStripRect(forViewSize: size)
            let use = renderer.rect(ofTurnedViewButton: .useAngle, forViewSize: size)
            let back = renderer.rect(ofTurnedViewButton: .stepAngle, forViewSize: size)

            #expect(abs(middle(strip).x - 500) <= 1)
            #expect(strip.origin.y > 0 && strip.origin.y < 40)

            for button in [use, back] {
                #expect(button.origin.x >= strip.origin.x && button.origin.y >= strip.origin.y)
                #expect(button.origin.x + button.size.width <= strip.origin.x + strip.size.width)
                #expect(button.origin.y + button.size.height <= strip.origin.y + strip.size.height)
            }
            #expect(use.origin.x + use.size.width < back.origin.x)

            let canvas = Canvas(width: 1000, height: 800)
            renderer.drawCallouts(in: canvas.context, viewSize: size)
            let ink = try #require(canvas.inkBounds)
            #expect(isSameBox(ink, strip))
        }

        @Test("Zoom to Fit while arranging fits the page, and keeps what was arranged")
        func arrangingFitKeepsWhatWasArranged() throws {
            let shown = try arranged()
            let presenter = shown.presenter

            shown.camera.origin.x += 85
            presenter.reload()
            shown.camera.zoom = 150
            presenter.reload()

            let scale = presenter.arrangedScale
            let offset = presenter.arrangedOffset
            let fit = LDrawStepPartListPolicy.pointsPerPageInchFittingPage(inHostSize: Size2(width: 1000, height: 800),
                                                                           inModel: shown.fixture.main)

            presenter.fitArrangedPage()
            presenter.reload()

            let presentation = try #require(presenter.presentation)

            #expect(abs(presentation.pointsPerPageInch - fit) < 0.0001)
            #expect(isClose(middle(presentation.pageRect), Point2(x: 500, y: 400)))
            #expect(abs(presenter.arrangedScale - scale) < 0.000001)
            #expect(isClose(presenter.arrangedOffset, offset))
        }

        @Test("A zoom the host makes to the page, held, changes the page's inch and not the step's scale")
        func arrangingHoldsAZoomOfThePage() throws {
            let shown = try arranged()
            let presenter = shown.presenter

            shown.camera.zoom = 150
            presenter.reload()
            #expect(abs(presenter.arrangedScale - 1.5) < 0.000001)

            // As Actual Size does. The host reads the page's inch at once, for
            // the zoom it shows.
            shown.camera.zoom = 100
            presenter.holdArrangedPage()
            #expect(abs(presenter.arrangedPointsPerInch - 64 / 1.5) < 0.0001)

            presenter.reload()

            #expect(abs(presenter.arrangedScale - 1.5) < 0.000001)
            #expect(abs(try #require(presenter.presentation).pointsPerPageInch - 64 / 1.5) < 0.0001)

            presenter.endArranging()
            #expect(presenter.arrangedPointsPerInch == 0)
        }

        @Test("With nothing to measure the previous step has no picture, and its outline still shows")
        func noPictureWithoutParts() throws {
            let shown = try arrangedAfterAStep()

            #expect(shown.presenter.previousStepPicture == nil)
            #expect(shown.presenter.previousStepOutline.isEmpty == false)
        }

        @Test("The previous step's picture is drawn faintly in its place, instead of the outline's fill")
        func previousStepPictureIsDrawn() throws {
            let renderer = LDrawStepOverlayRenderer()
            let size = Size2(width: 400, height: 300)
            let outline = [Point2(x: 50, y: 50), Point2(x: 350, y: 50), Point2(x: 350, y: 250), Point2(x: 50, y: 250)]
            let red = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

            red.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            red.fill(CGRect(x: 0, y: 0, width: 4, height: 4))

            renderer.ghostOutline = outline.withUnsafeBufferPointer { Data(buffer: $0) }
            renderer.ghostColor = CGColor(srgbRed: 0, green: 0.4, blue: 1, alpha: 0.2)
            renderer.ghostImage = red.makeImage()
            renderer.ghostRect = Box2(origin: Point2(x: 100, y: 100), size: Size2(width: 40, height: 40))

            let canvas = Canvas(width: 400, height: 300)
            renderer.drawPageAndFrame(in: canvas.context, viewSize: size)

            #expect(canvas.isInked(120, 120))
            #expect(canvas.isInked(60, 60) == false, "The outline is not filled under a picture")
        }

        @Test("Arranging needs a page")
        func arrangingNeedsAPage() throws {
            LDrawStepPartList.setUsesLPubScale(false)

            let shown = shown(assembly: CGSize(width: 200, height: 100))

            #expect(shown.presenter.beginArranging() == false)
            #expect(shown.presenter.isArranging == false)

            LDrawStepPartList.setUsesLPubScale(true)
        }
    }
}
