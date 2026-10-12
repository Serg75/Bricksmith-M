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

/// A camera that looks straight at the model and draws it flat: a model point
/// lands at its x and y times the zoom, from where the origin is drawn.
private final class FlatCamera: NSObject, LDrawStepOverlayCamera {

    var zoom: CGFloat = 100
    var origin = CGPoint(x: 500, y: 400)
    var angle = Tuple3(x: 0, y: 0, z: 0)
    var scrollCount = 0

    private var scale: CGFloat { zoom / 100 }

    func zoomPercentage() -> CGFloat { zoom }

    func setZoomPercentage(_ newPercentage: CGFloat) { zoom = newPercentage }

    func pointsPerLDU(atModelPoint modelPoint: Point3) -> Double { Double(scale) }

    func scrollCenter(toModelPoint modelPoint: Point3) {
        scrollModelPoint(modelPoint, toViewPoint: CGPoint(x: 500, y: 400))
    }

    func viewingAngle() -> Tuple3 { angle }

    func viewPoint(forModelPoint modelPoint: Point3) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(modelPoint.x) * scale, y: origin.y + CGFloat(modelPoint.y) * scale)
    }

    func modelPoint(forViewPoint viewPoint: CGPoint, depthReferencePoint depthPoint: Point3) -> Point3 {
        Point3(x: Double((viewPoint.x - origin.x) / scale),
               y: Double((viewPoint.y - origin.y) / scale),
               z: depthPoint.z)
    }

    func viewRect(forModelPoints points: Data) -> CGRect {
        .zero
    }

    func viewPoints(forModelPoints points: Data) -> Data {
        Data()
    }

    func scrollModelPoint(_ modelPoint: Point3, toViewPoint viewPoint: CGPoint) {
        origin = CGPoint(x: viewPoint.x - CGFloat(modelPoint.x) * scale,
                         y: viewPoint.y - CGFloat(modelPoint.y) * scale)
        scrollCount += 1
    }
}

extension StepOverlayTests {

    @Suite("The page against a camera")
    final class LDrawStepOverlayPageTests {

        init() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
        }

        deinit {
            LDrawStepPartList.setEnabled(false)
            LDrawStepPartList.setUsesLPubScale(false)
        }

        // MARK: - Fixtures

        /// A model showing its one step, a camera on it, and a presenter that
        /// has laid the step out once. The step has a page of its own size.
        /// With `callsOut` it also calls sub.ldr out. Without, it places
        /// nothing. Either way nothing is asked of a part library.
        private func shown(callsOut: Bool = false)
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

            fixture.step.insert(pageSize, at: 0)
            fixture.main.setStepDisplay(true)
            fixture.main.setMaximumStepIndexForStepDisplay(UInt(fixture.main.steps().count - 1))

            let camera = FlatCamera()
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
        private func writeOffset(in fixture: CalloutFixture) {
            let placement = LPubPlacement()
            placement.lPubCommandString = "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.2000 0.1000"
            fixture.step.insert(placement, at: fixture.step.subdirectives().count - 1)
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
