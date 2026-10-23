//
//  LDrawStepPartListPolicyTests.swift
//  LDrawFeaturesTests
//
//  Tests for where the frame goes, how big it may get, and the document
//  settings it reads: scale, page size and CONSTRAIN.
//
//  These are decisions rather than drawing, so they can be checked without a
//  window.
//
//  Created by Sergey Slobodenyuk on 2026-09-10.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures

/// The most room a frame may take in a host, as the policy works it out.
private func room(in host: Size2, pointsPerPageInch: Double) -> Size2 {
    LDrawStepPartListPolicy.allowedFrameSize(inHostSize: host, pointsPerPageInch: pointsPerPageInch)
}

func constrain(_ mode: LPubPliConstrainMode,
               _ inches: Double = 0,
               scope: LPubMetaScope = .local) -> LPubPliConstrain {
    let directive = LPubPliConstrain()
    directive.scope = scope
    directive.mode = mode
    directive.inches = inches
    return directive
}

/// A view whose model is drawn a little larger than its zoom says, as a
/// perspective view draws a part nearer the camera.
final class FakePageView: NSObject, LDrawStepPartListPageView {
    var zoom: CGFloat = 100
    var foreshortening = 1.25
    var scrolledTo: Point3?

    func zoomPercentage() -> CGFloat { zoom }
    func setZoomPercentage(_ newPercentage: CGFloat) { zoom = newPercentage }
    func pointsPerLDU(atModelPoint modelPoint: Point3) -> Double { Double(zoom) / 100 * foreshortening }
    func scrollCenter(toModelPoint modelPoint: Point3) { scrolledTo = modelPoint }
}

extension StepPartListStaticSettings {

    @Suite("Placing the parts list frame")
    struct LDrawStepPartListPolicyTests {

        private let viewport = Size2(width: 800, height: 600)

        // MARK: - Frame placement

        @Test("The frame sits in the top-left corner, inset by the margin")
        func frameSitsTopLeft() {
            let rect = LDrawStepPartListPolicy.frameRect(forFrameSize: Size2(width: 200, height: 150),
                                                         inHostSize: viewport,
                                                         pointsPerPageInch: 0)

            #expect(rect.origin.x == 12)
            #expect(rect.origin.y == 12)
            #expect(rect.size.width == 200)
            #expect(rect.size.height == 150)
        }

        @Test("A frame larger than the viewport is trimmed to what the margins leave, never below zero")
        func oversizedFrameIsTrimmed() {
            let tiny = LDrawStepPartListPolicy.frameRect(forFrameSize: Size2(width: 500, height: 400),
                                                         inHostSize: Size2(width: 40, height: 30),
                                                         pointsPerPageInch: 0)
            #expect(tiny.size.width == 16)
            #expect(tiny.size.height == 6)

            let none = LDrawStepPartListPolicy.frameRect(forFrameSize: Size2(width: 100, height: 100),
                                                         inHostSize: Size2(width: 0, height: 0),
                                                         pointsPerPageInch: 0)
            #expect(none.size.width == 0)
            #expect(none.size.height == 0)
        }

        /// LPub3D's page and parts list margins are both 0.05 in, so the zoom
        /// does not move the corner on the paper.
        @Test("On the page the frame sits LPub3D's margin in from the corner at any zoom")
        func onThePageTheFrameSitsLPubsMarginIn() {
            for pointsPerPageInch in [32.0, 64, 200] {
                let page = Size2(width: 8.5 * pointsPerPageInch, height: 11 * pointsPerPageInch)
                let rect = LDrawStepPartListPolicy.frameRect(forFrameSize: Size2(width: 100, height: 100),
                                                             inHostSize: page,
                                                             pointsPerPageInch: pointsPerPageInch)

                #expect(abs(rect.origin.x - 0.05 * pointsPerPageInch) < 0.0001, "at \(pointsPerPageInch)")
                #expect(abs(rect.origin.y - 0.05 * pointsPerPageInch) < 0.0001, "at \(pointsPerPageInch)")

                let trimmed = LDrawStepPartListPolicy.frameRect(forFrameSize: Size2(width: 20 * pointsPerPageInch,
                                                                                    height: 20 * pointsPerPageInch),
                                                                inHostSize: page,
                                                                pointsPerPageInch: pointsPerPageInch)

                #expect(abs(trimmed.size.width - 8.4 * pointsPerPageInch) < 0.0001, "at \(pointsPerPageInch)")
                #expect(abs(trimmed.size.height - 10.9 * pointsPerPageInch) < 0.0001, "at \(pointsPerPageInch)")
            }
        }

        // MARK: - Height budget

        /// Six tenths of the viewport, less two 6 point paddings. A viewport too
        /// small for those gets a 1 point budget, since 0 would mean no limit.
        @Test("The height budget comes from the viewport")
        func metricsTakeTheirHeightBudgetFromTheViewport() {
            for (height, budget) in [(600.0, 348.0), (400, 228), (1200, 708), (10, 1)] {
                let allowed = room(in: Size2(width: 800, height: height), pointsPerPageInch: 0)
                let metrics = LDrawStepPartListPolicy.metrics(LDrawStepPartListLayout.defaultMetrics(),
                                                              fittingAllowedSize: allowed)

                #expect(abs(metrics.maximumHeight - budget) < 0.0001, "at \(height)")
            }

            #expect(LDrawStepPartListLayout.defaultMetrics().maximumHeight == 0,
                    "the packer's own default is unbounded; the viewport is what bounds it")
        }

        /// 0.6 * 600 - 36. The padding is the one passed in, not the
        /// default 6 points.
        @Test("The budget leaves room for the padding it is given")
        func theBudgetLeavesRoomForItsOwnPadding() {
            var metrics = LDrawStepPartListLayout.defaultMetrics()
            metrics.framePadding = 18

            let allowed = room(in: viewport, pointsPerPageInch: 0)
            let fitted = LDrawStepPartListPolicy.metrics(metrics, fittingAllowedSize: allowed)

            #expect(abs(fitted.maximumHeight - 324) < 0.0001)
        }

        /// The page less two 0.05 in margins and two 0.08125 in paddings, fitted
        /// after scaling. It is the same paper height at every zoom.
        @Test("On the page the height budget is the page less its margins and padding, at any zoom")
        func onThePageTheBudgetIsThePageLessMarginsAndPadding() {
            for pointsPerPageInch in [32.0, 64, 200] {
                let scaled = LDrawStepPartListPolicy.metrics(LDrawStepPartListLayout.defaultMetrics(),
                                                             scaledToPointsPerPageInch: pointsPerPageInch)
                let page = Size2(width: 8.5 * pointsPerPageInch, height: 11 * pointsPerPageInch)
                let allowed = room(in: page, pointsPerPageInch: pointsPerPageInch)
                let fitted = LDrawStepPartListPolicy.metrics(scaled, fittingAllowedSize: allowed)

                #expect(abs(fitted.maximumHeight - (11 - 0.1 - 2 * 0.08125) * pointsPerPageInch) < 0.0001, "at \(pointsPerPageInch)")
            }
        }

        // MARK: - Clamping a pinned width

        /// A WIDTH is a printed page width. Eleven inches at 150 dpi is 1650
        /// points, which would fill any viewport, so it is clamped for display.
        /// The document keeps the value it was given.
        @Test("A page-sized width is clamped to a fraction of the viewport")
        func aPageSizedWidthIsClamped() {
            var constraint = LDrawStepPartListLayout.defaultConstraint()
            constraint.mode = .width
            constraint.inches = 11.0

            let allowed = room(in: viewport, pointsPerPageInch: 0).width
            let clamped = LDrawStepPartListPolicy.constraint(constraint,
                                                             clampedToAllowedWidth: allowed,
                                                             pointsPerInch: 150)

            // Four tenths of 800 points, at 150 dpi.
            #expect(abs(Double(clamped.inches) - 320.0 / 150.0) < 0.0001)
        }

        /// LPub3D never limits a parts list by a share of its page. A 0.6 share
        /// would narrow a WIDTH of 5 to 0.6 * 8.5 - 24 / P inches.
        @Test("On the page a WIDTH is limited by the paper, not by a share")
        func onThePageAWidthIsLimitedByThePaper() {
            for pointsPerPageInch in [32.0, 150] {
                let page = Size2(width: 8.5 * pointsPerPageInch, height: 11 * pointsPerPageInch)

                for (asked, drawn) in [(11.0, 8.4), (5.0, 5.0)] {
                    var constraint = LDrawStepPartListLayout.defaultConstraint()
                    constraint.mode = .width
                    constraint.inches = Float(asked)

                    let allowed = room(in: page, pointsPerPageInch: pointsPerPageInch).width
                    let clamped = LDrawStepPartListPolicy.constraint(constraint,
                                                                     clampedToAllowedWidth: allowed,
                                                                     pointsPerInch: pointsPerPageInch)

                    #expect(abs(Double(clamped.inches) - drawn) < 0.0001, "\(asked) at \(pointsPerPageInch)")
                }
            }
        }

        /// The other modes take their width from the parts and are bounded by the
        /// height budget, so they need no clamp.
        @Test("A width that fits, and every other mode, is left alone")
        func onlyAnOversizedWidthIsClamped() {
            let cases: [(LPubPliConstrainMode, Float)] = [(.width, 2.0),
                                                          (.area, 11.0),
                                                          (.square, 11.0),
                                                          (.height, 11.0),
                                                          (.columns, 11.0)]

            for (mode, value) in cases {
                var constraint = LDrawStepPartListLayout.defaultConstraint()
                constraint.mode = mode
                constraint.inches = value
                constraint.columns = 4

                let allowed = room(in: viewport, pointsPerPageInch: 0).width
                let clamped = LDrawStepPartListPolicy.constraint(constraint,
                                                                 clampedToAllowedWidth: allowed,
                                                                 pointsPerInch: 150)

                #expect(clamped.inches == value, "\(mode)")
                #expect(clamped.columns == 4, "\(mode)")
            }
        }

        // MARK: - Text

        /// A cell with no number under it is unclear: one part, or a count that is
        /// missing. LPub3D and the printed books both show the 1x.
        @Test("Every entry gets a multiplier, including a single part")
        func everyEntryIsLabeled() {
            #expect(LDrawStepPartListLayout.quantityText(forQuantity: 1) == "1×")
            #expect(LDrawStepPartListLayout.quantityText(forQuantity: 2) == "2×")
            #expect(LDrawStepPartListLayout.quantityText(forQuantity: 17) == "17×")

            // A zero quantity should never happen, but it must not read as "0x".
            #expect(LDrawStepPartListLayout.quantityText(forQuantity: 0) == "1×")
        }

        // MARK: - LPub3D's scale

        /// A model whose steps carry these lines, in order.
        private func model(_ lines: [[LDrawDirective]]) -> LDrawModel {
            let model = LDrawModel.model() as! LDrawModel

            for (index, directives) in lines.enumerated() {
                let step = index == 0 ? (model.steps().first as! LDrawStep) : model.addStep()

                for directive in directives {
                    step.add(directive)
                }
            }
            return model
        }

        private func modelScale(_ branch: LPubModelScaleBranch, _ value: Double,
                                scope: LPubMetaScope = .unspecified) -> LPubModelScale {
            let keyword = branch == .assembly ? "ASSEM" : branch == .bom ? "BOM" : "PLI"
            let word = scope == .global ? "GLOBAL " : scope == .local ? "LOCAL " : ""
            let directive = LPubModelScale()
            directive.lPubCommandString = "\(keyword) MODEL_SCALE \(word)\(value)"
            return directive
        }

        private func resolution(_ value: Double, _ unit: LPubResolutionUnit = .dotsPerInch) -> LPubResolution {
            let directive = LPubResolution()
            directive.lPubCommandString = "RESOLUTION \(value) \(unit == .dotsPerCentimeter ? "DPCM" : "DPI")"
            return directive
        }

        /// LPub3D's own defaults are 150 dots to the inch at life size. Off the
        /// page the list is always read at 150.
        @Test("A silent document gets LPub3D's defaults")
        func defaultsWhenTheFileSaysNothing() {
            let empty = model([[]])

            #expect(LDrawStepPartListPolicy.modelScale(forBranch: .pli, inModel: empty) == 1.0)
            #expect(LDrawStepPartListLayout.defaultMetrics().pointsPerInch == 150)
        }

        /// ASSEM sizes the assembly picture and BOM the bill of materials. A file
        /// often sets all three to different values.
        @Test("Each branch sizes its own picture")
        func branchesAreKeptApart() {
            let all = model([[modelScale(.pli, 1.0), modelScale(.assembly, 1.7), modelScale(.bom, 0.5)]])

            #expect(LDrawStepPartListPolicy.modelScale(forBranch: .pli, inModel: all) == 1.0)
            #expect(LDrawStepPartListPolicy.modelScale(forBranch: .assembly, inModel: all) == 1.7)

            let assemblyOnly = model([[modelScale(.assembly, 1.7), modelScale(.bom, 0.5)]])

            #expect(LDrawStepPartListPolicy.modelScale(forBranch: .pli, inModel: assemblyOnly) == 1.0)
        }

        private func pageSize(_ width: Double, _ height: Double) -> LPubPageSize {
            let directive = LPubPageSize()
            directive.lPubCommandString = "PAGE SIZE \(width) \(height)"
            return directive
        }

        private func orientation(landscape: Bool) -> LPubPageOrientation {
            let directive = LPubPageOrientation()
            directive.lPubCommandString = "PAGE ORIENTATION \(landscape ? "LANDSCAPE" : "PORTRAIT")"
            return directive
        }

        /// ORIENTATION says which measurement is the long side, so a page stands
        /// the same way up however the file wrote it, and no file is turned twice.
        @Test("The page is measured in the document's own unit, then stood the right way up")
        func pageSizeFollowsOrientationAndUnit() {
            // With no ORIENTATION the measurements stand as written.
            let asWritten = LDrawStepPartListPolicy.pageSizeInInches(inModel: model([[pageSize(12.048, 8.0)]]))
            #expect(abs(asWritten.width - 12.048) < 0.0001)
            #expect(asWritten.height == 8.0)

            let portrait = LDrawStepPartListPolicy.pageSizeInInches(inModel: model([[pageSize(8.5, 11),
                                                                                     orientation(landscape: false)]]))
            #expect(portrait.width == 8.5)
            #expect(portrait.height == 11)

            for written in [pageSize(8.5, 11), pageSize(11, 8.5)] {
                let turned = LDrawStepPartListPolicy.pageSizeInInches(inModel: model([[written,
                                                                                       orientation(landscape: true)]]))
                #expect(turned.width == 11)
                #expect(turned.height == 8.5)
            }

            // Only the unit counts, not the dots.
            let dpi = LDrawStepPartListPolicy.pageSizeInInches(inModel: model([[resolution(300), pageSize(8.5, 11)]]))
            #expect(dpi.width == 8.5)
            #expect(dpi.height == 11)

            // A document written in centimeters measures its page in them too.
            let metric = model([[resolution(100, .dotsPerCentimeter), pageSize(21.0, 29.7)]])
            #expect(abs(LDrawStepPartListPolicy.pageSizeInInches(inModel: metric).width - 21.0 / 2.54) < 0.0001)
            #expect(abs(LDrawStepPartListPolicy.pageSizeInInches(inModel: metric).height - 29.7 / 2.54) < 0.0001)
        }

        /// The hosts are 600 by 1000 and 1600 by 600 points inside the fit's
        /// 6 point margin.
        @Test("A page that follows the host's shape grows on one side, and fits at the same scale")
        func pageFollowsTheHostShape() {
            let document = model([[pageSize(12.048, 8.0)]])
            let tall = Size2(width: 612, height: 1012)
            let wide = Size2(width: 1612, height: 612)
            let tallFit = LDrawStepPartListPolicy.assemblyScaleFittingPage(inHostSize: tall, inModel: document)
            let wideFit = LDrawStepPartListPolicy.assemblyScaleFittingPage(inHostSize: wide, inModel: document)

            // Off, the page is the file's.
            let asWritten = LDrawStepPartListPolicy.pageSizeInInches(inModel: document, forHostSize: tall)
            #expect(abs(asWritten.width - 12.048) < 0.0001)
            #expect(asWritten.height == 8.0)

            LDrawStepPartList.setPageFollowsHostShape(true)
            defer { LDrawStepPartList.setPageFollowsHostShape(false) }

            let taller = LDrawStepPartListPolicy.pageSizeInInches(inModel: document, forHostSize: tall)
            #expect(abs(taller.width - 12.048) < 0.0001)
            #expect(abs(taller.height - 12.048 * 1000 / 600) < 0.0001)

            let wider = LDrawStepPartListPolicy.pageSizeInInches(inModel: document, forHostSize: wide)
            #expect(abs(wider.width - 8.0 * 1600 / 600) < 0.0001)
            #expect(wider.height == 8.0)

            #expect(abs(LDrawStepPartListPolicy.assemblyScaleFittingPage(inHostSize: tall, inModel: document)
                        - tallFit) < 0.0001)
            #expect(abs(LDrawStepPartListPolicy.assemblyScaleFittingPage(inHostSize: wide, inModel: document)
                        - wideFit) < 0.0001)

            let page = LDrawStepPartListPolicy.pageRect(centeredOn: Point2(x: 306, y: 506), assemblyScale: tallFit,
                                                        hostSize: tall, inModel: document)
            #expect(abs(page.size.width - 600) < 0.01)
            #expect(abs(page.size.height - 1000) < 0.01)
        }

        /// The page must not move as the reader steps through, so it is anchored to
        /// the whole model and not to the steps on display.
        @Test("The page anchor ignores step display")
        func pageAnchorIgnoresStepDisplay() {
            let document = model([[line(from: Point3(x: 0, y: 0, z: 0), to: Point3(x: 10, y: 0, z: 0))],
                                  [line(from: Point3(x: 90, y: 0, z: 0), to: Point3(x: 100, y: 0, z: 0))]])

            let whole = LDrawStepPartListPolicy.pageAnchor(inModel: document)
            #expect(abs(whole.x - 50.0) < 0.0001)

            document.setStepDisplay(true)
            document.setMaximumStepIndexForStepDisplay(0)

            // The first step alone is centered on 5, but the page stays on 50.
            #expect(abs(document.boundingBox3().max.x - 10.0) < 0.0001, "step display has to be in force")
            #expect(abs(LDrawStepPartListPolicy.pageAnchor(inModel: document).x - 50.0) < 0.0001)
        }

        @Test("The pinned anchor stays put across edits until forgotten")
        func pinnedAnchorHoldsUntilForgotten() {
            let document = model([[line(from: Point3(x: 0, y: 0, z: 0), to: Point3(x: 10, y: 0, z: 0))],
                                  [line(from: Point3(x: 90, y: 0, z: 0), to: Point3(x: 100, y: 0, z: 0))]])
            document.setStepDisplay(true)

            let pin = LDrawStepPartListPageAnchor()
            #expect(abs(pin.anchor(forModel: document).x - 50.0) < 0.0001)

            (document.steps()[1] as! LDrawStep).add(line(from: Point3(x: 290, y: 0, z: 0),
                                                         to: Point3(x: 300, y: 0, z: 0)))
            #expect(abs(pin.anchor(forModel: document).x - 50.0) < 0.0001, "an edit keeps the page where it is")

            // The model now runs from 0 to 300.
            pin.invalidate()
            #expect(abs(pin.anchor(forModel: document).x - 150.0) < 0.0001)
        }

        /// The host measures how much bigger perspective draws the model beside
        /// the anchor, at the angle each step is laid out at.
        @Test("The drawn scale is measured once and kept until it is forgotten")
        func drawnScaleRatioIsKeptUntilForgotten() {
            let pin = LDrawStepPartListPageAnchor()
            let view = FakePageView()
            let document = model([[line(from: Point3(x: 0, y: 0, z: 0), to: Point3(x: 100, y: 0, z: 0))]])

            #expect(abs(pin.drawnScaleRatio(of: document, in: view) - 1.25) < 0.0001)

            // Kept while the camera is turned.
            view.foreshortening = 2
            #expect(abs(pin.drawnScaleRatio(of: document, in: view) - 1.25) < 0.0001)

            // Measured again for another step, or after the anchor is.
            pin.forgetDrawnScale()
            #expect(abs(pin.drawnScaleRatio(of: document, in: view) - 2) < 0.0001)

            view.foreshortening = 1.5
            pin.invalidate()
            #expect(abs(pin.drawnScaleRatio(of: document, in: view) - 1.5) < 0.0001)

            // A measure that cannot be read keeps the zoom, and is not taken again.
            pin.forgetDrawnScale()
            view.foreshortening = 0
            #expect(pin.drawnScaleRatio(of: document, in: view) == 1)

            view.foreshortening = 3
            #expect(pin.drawnScaleRatio(of: document, in: view) == 1)
        }

        @Test("A ratio belongs to the model it was measured in")
        func drawnScaleRatioIsForgottenForAnotherModel() {
            let pin = LDrawStepPartListPageAnchor()
            let view = FakePageView()
            let first = model([[line(from: Point3(x: 0, y: 0, z: 0), to: Point3(x: 100, y: 0, z: 0))]])
            let second = model([[line(from: Point3(x: 0, y: 0, z: 0), to: Point3(x: 0, y: 100, z: 0))]])

            #expect(abs(pin.drawnScaleRatio(of: first, in: view) - 1.25) < 0.0001)

            view.foreshortening = 2
            #expect(abs(pin.drawnScaleRatio(of: first, in: view) - 1.25) < 0.0001)
            #expect(abs(pin.drawnScaleRatio(of: second, in: view) - 2) < 0.0001)
        }

        /// The host centers each step on the page and keeps the model point
        /// that is drawn at the page's middle.
        @Test("The page center is the anchor until the host sets one, and is forgotten with the anchor")
        func pageCenterIsKeptUntilForgotten() {
            let document = model([[line(from: Point3(x: 0, y: 0, z: 0), to: Point3(x: 10, y: 0, z: 0))]])
            let other = model([[line(from: Point3(x: 100, y: 0, z: 0), to: Point3(x: 110, y: 0, z: 0))]])
            let pin = LDrawStepPartListPageAnchor()

            #expect(pin.hasPageCenter(forModel: document) == false)
            #expect(abs(pin.pageCenter(forModel: document).x - 5.0) < 0.0001)

            pin.setPageCenter(Point3(x: 40, y: 2, z: 3), forModel: document)
            #expect(pin.hasPageCenter(forModel: document))
            #expect(pin.pageCenter(forModel: document).x == 40)
            #expect(abs(pin.anchor(forModel: document).x - 5.0) < 0.0001, "the anchor is still the model's middle")

            // Another model has no center of its own, and takes this one's away.
            #expect(pin.hasPageCenter(forModel: other) == false)
            #expect(abs(pin.pageCenter(forModel: other).x - 105.0) < 0.0001)
            #expect(pin.hasPageCenter(forModel: document) == false)

            pin.setPageCenter(Point3(x: 40, y: 2, z: 3), forModel: document)
            pin.invalidate()
            #expect(pin.hasPageCenter(forModel: document) == false)
            #expect(abs(pin.pageCenter(forModel: document).x - 5.0) < 0.0001)
        }

        /// While the camera is turned, the callouts are placed against the
        /// box the assembly had on the page before the turn.
        @Test("The assembly's box is kept on the page, and follows the page's middle and scale")
        func assemblyRectIsKeptOnThePage() {
            let pin = LDrawStepPartListPageAnchor()
            let measured = Box2(origin: Point2(x: 450, y: 380), size: Size2(width: 60, height: 40))

            #expect(pin.hasAssemblyRect == false)
            #expect(pin.assemblyRect(aroundPageCenter: Point2(x: 500, y: 400), pointsPerPageInch: 100).size.width == 0)

            pin.noteAssemblyRect(measured, aroundPageCenter: Point2(x: 500, y: 400), pointsPerPageInch: 100)
            #expect(pin.hasAssemblyRect)

            // The same page gives the same box back.
            let same = pin.assemblyRect(aroundPageCenter: Point2(x: 500, y: 400), pointsPerPageInch: 100)
            #expect(abs(same.origin.x - 450) < 0.0001)
            #expect(abs(same.size.height - 40) < 0.0001)

            // A page moved and drawn half as big takes the box with it.
            let moved = pin.assemblyRect(aroundPageCenter: Point2(x: 300, y: 200), pointsPerPageInch: 50)
            #expect(abs(moved.origin.x - 275) < 0.0001)
            #expect(abs(moved.origin.y - 190) < 0.0001)
            #expect(abs(moved.size.width - 30) < 0.0001)
        }

        @Test("The assembly's box is forgotten with the anchor, with another model, and when it has no area")
        func assemblyRectIsForgotten() {
            let document = model([[line(from: Point3(x: 0, y: 0, z: 0), to: Point3(x: 10, y: 0, z: 0))]])
            let other = model([[line(from: Point3(x: 100, y: 0, z: 0), to: Point3(x: 110, y: 0, z: 0))]])
            let pin = LDrawStepPartListPageAnchor()
            let measured = Box2(origin: Point2(x: 450, y: 380), size: Size2(width: 60, height: 40))
            let middle = Point2(x: 500, y: 400)

            _ = pin.anchor(forModel: document)
            pin.noteAssemblyRect(measured, aroundPageCenter: middle, pointsPerPageInch: 100)
            pin.forgetAssemblyRect()
            #expect(pin.hasAssemblyRect == false)

            pin.noteAssemblyRect(measured, aroundPageCenter: middle, pointsPerPageInch: 100)
            pin.invalidate()
            #expect(pin.hasAssemblyRect == false)

            _ = pin.anchor(forModel: document)
            pin.noteAssemblyRect(measured, aroundPageCenter: middle, pointsPerPageInch: 100)
            _ = pin.anchor(forModel: other)
            #expect(pin.hasAssemblyRect == false)

            pin.noteAssemblyRect(measured, aroundPageCenter: middle, pointsPerPageInch: 100)
            pin.noteAssemblyRect(Box2(origin: middle, size: Size2(width: 0, height: 0)),
                                 aroundPageCenter: middle, pointsPerPageInch: 100)
            #expect(pin.hasAssemblyRect == false)

            pin.noteAssemblyRect(measured, aroundPageCenter: middle, pointsPerPageInch: 0)
            #expect(pin.hasAssemblyRect == false)
        }

        @Test("A scaled-down part's badge takes the marker color, with the fill as its text")
        func scaledDownBadgesTakeTheMarkerColor() {
            let chrome = LDrawStepPartListPolicy.defaultChrome()
            let plain = LDrawStepPartListPolicy.badgeStyle(forScaledDownPart: false, chrome: chrome)
            let scaled = LDrawStepPartListPolicy.badgeStyle(forScaledDownPart: true, chrome: chrome)

            #expect(plain.fillRGBA == chrome.annotationFillRGBA)
            #expect(plain.borderRGBA == chrome.annotationBorderRGBA)
            #expect(plain.textRGBA == chrome.annotationTextRGBA)
            #expect(scaled.fillRGBA == chrome.markerRGBA)
            #expect(scaled.borderRGBA == chrome.markerRGBA)
            #expect(scaled.textRGBA == chrome.annotationFillRGBA)

            let notice = LDrawStepPartListPolicy.overflowNoticeRect(forContentWidth: 200, chrome: chrome)
            #expect(notice.origin.y == 0)
            #expect(notice.size.width == 200)
            #expect(notice.size.height == chrome.labelPointSize + 2)
        }

        /// The frame is the viewport's color moved a tenth of the way to white
        /// on a dark viewport, or to black on a light one.
        @Test("The frame's background moves a tenth away from the viewport's")
        func theBackgroundMovesAwayFromTheViewport() {
            var dark = [Double](repeating: 0, count: 4)
            var light = [Double](repeating: 0, count: 4)

            LDrawStepPartListPolicy.getListBackgroundRGBA(&dark, forViewportRGBA: [0.2, 0.2, 0.2, 1])
            LDrawStepPartListPolicy.getListBackgroundRGBA(&light, forViewportRGBA: [0.9, 0.8, 0.7, 1])

            #expect(abs(dark[0] - 0.28) < 0.0001)
            #expect(abs(light[0] - 0.81) < 0.0001)
            #expect(abs(light[2] - 0.63) < 0.0001)
            #expect(dark[3] == 1)
        }

        @Test("Another model is measured again")
        func anotherModelIsMeasuredAgain() {
            let a = model([[line(from: Point3(x: 0, y: 0, z: 0), to: Point3(x: 10, y: 0, z: 0))]])
            let b = model([[line(from: Point3(x: 100, y: 0, z: 0), to: Point3(x: 110, y: 0, z: 0))]])
            let pin = LDrawStepPartListPageAnchor()

            #expect(abs(pin.anchor(forModel: a).x - 5.0) < 0.0001)
            #expect(abs(pin.anchor(forModel: b).x - 105.0) < 0.0001)

            // Measured again on the way back, so an edit made meanwhile counts.
            (a.steps().first as! LDrawStep).add(line(from: Point3(x: 290, y: 0, z: 0),
                                                     to: Point3(x: 300, y: 0, z: 0)))
            #expect(abs(pin.anchor(forModel: a).x - 150.0) < 0.0001)
        }

        @Test("No model pins nothing")
        func noModelPinsNothing() {
            let a = model([[line(from: Point3(x: 0, y: 0, z: 0), to: Point3(x: 10, y: 0, z: 0))]])
            let pin = LDrawStepPartListPageAnchor()

            #expect(abs(pin.anchor(forModel: a).x - 5.0) < 0.0001)

            let none = pin.anchor(forModel: nil)
            #expect(none.x == 0 && none.y == 0 && none.z == 0)
        }

        private func line(from start: Point3, to end: Point3) -> LDrawLine {
            let line = LDrawLine()
            line.setVertex1(start)
            line.setVertex2(end)
            return line
        }

        /// An unscoped line holds from where it is written, so a later one wins.
        @Test("A later line wins, and lines past the visible step do not")
        func laterLinesWin() {
            let document = model([[modelScale(.pli, 1.0)],
                                  [modelScale(.pli, 3.0)],
                                  [modelScale(.pli, 9.0)]])

            // Nothing is on display, so the whole model is read and the last line
            // stands.
            #expect(LDrawStepPartListPolicy.modelScale(forBranch: .pli, inModel: document) == 9.0)

            document.setMaximumStepIndexForStepDisplay(1)
            document.setStepDisplay(true)
            #expect(LDrawStepPartListPolicy.modelScale(forBranch: .pli, inModel: document) == 3.0)
        }

        /// A LOCAL applies to its own step only. A GLOBAL or an unscoped line
        /// stays in force for the steps after it.
        @Test("A LOCAL line is its step's alone, an unscoped one carries forward")
        func localDoesNotLeakIntoLaterSteps() {
            let local = modelScale(.pli, 3.0, scope: .local)

            let document = model([[modelScale(.pli, 1.0)],
                                  [local],
                                  []])

            document.setStepDisplay(true)

            document.setMaximumStepIndexForStepDisplay(1)
            #expect(LDrawStepPartListPolicy.modelScale(forBranch: .pli, inModel: document) == 3.0)

            document.setMaximumStepIndexForStepDisplay(2)
            #expect(LDrawStepPartListPolicy.modelScale(forBranch: .pli, inModel: document) == 1.0,
                    "the LOCAL in step 2 must not reach step 3")

            // With nothing on display the whole model is read, and the LOCAL in
            // step 2 still does not count.
            document.setStepDisplay(false)
            #expect(LDrawStepPartListPolicy.modelScale(forBranch: .pli, inModel: document) == 1.0)
        }

        @Test("A LOCAL in the visible step beats the header's GLOBAL")
        func localBeatsGlobalInItsOwnStep() {
            let global = modelScale(.pli, 1.0, scope: .global)
            let local = modelScale(.pli, 3.0, scope: .local)

            let document = model([[global], [local]])
            document.setStepDisplay(true)
            document.setMaximumStepIndexForStepDisplay(1)

            #expect(LDrawStepPartListPolicy.modelScale(forBranch: .pli, inModel: document) == 3.0)
        }

        // MARK: - The document's CONSTRAIN

        @Test("A GLOBAL CONSTRAIN in the header is the default for every step")
        func globalConstrainIsInherited() {
            let document = model([[constrain(.width, 3.25, scope: .global)],
                                  []])
            document.setStepDisplay(true)
            document.setMaximumStepIndexForStepDisplay(1)

            let constraint = LDrawStepPartListPolicy.constraint(forVisibleStepOfModel: document)
            #expect(constraint.mode == .width)
            #expect(constraint.inches == 3.25)

            #expect(LDrawStepPartListPolicy.inheritedInches(forAxis: .width, inModel: document) == 3.25)
            #expect(LDrawStepPartListPolicy.inheritedInches(forAxis: .height, inModel: document) == 0)
        }

        @Test("A step's own CONSTRAIN beats the header's GLOBAL")
        func stepConstrainBeatsGlobal() {
            let document = model([[constrain(.width, 3.25, scope: .global)],
                                  [constrain(.height, 1.5)]])
            document.setStepDisplay(true)
            document.setMaximumStepIndexForStepDisplay(1)

            let constraint = LDrawStepPartListPolicy.constraint(forVisibleStepOfModel: document)
            #expect(constraint.mode == .height)
            #expect(constraint.inches == 1.5)
        }

        /// A GLOBAL carries on to later steps, so a resize inserts a new line
        /// instead of rewriting it.
        @Test("A GLOBAL is not the step's own CONSTRAIN")
        func globalIsNotTheStepsOwn() {
            let document = model([[constrain(.width, 3.25, scope: .global)]])
            let header = document.steps().first as! LDrawStep

            #expect(LDrawStepPartListPolicy.constrainDirective(inStep: header) == nil)
            #expect(LDrawStepPartListPolicy.inheritedInches(forAxis: .width, inModel: document) == 3.25)
        }

        @Test("With no CONSTRAIN the page packs by AREA, and nothing is inherited")
        func noConstrainPacksByArea() {
            let document = model([[]])
            let constraint = LDrawStepPartListPolicy.constraint(forVisibleStepOfModel: document)

            #expect(constraint.mode == .area)
            #expect(LDrawStepPartListPolicy.inheritedInches(forAxis: .width, inModel: document) == 0)
        }

        /// Off the page the document's CONSTRAIN lines are not read at all.
        @Test("Off the page the shelves are four tenths of the view wide")
        func offThePageShelvesTakeFourTenths() {
            let host = Size2(width: 1000, height: 800)
            let constraint = LDrawStepPartListPolicy.viewportConstraint(forHostSize: host, pointsPerInch: 150)

            #expect(constraint.mode == .width)
            #expect(abs(Double(constraint.inches) - 400.0 / 150.0) < 0.0001)
            #expect(LDrawStepPartListPolicy.viewportConstraint(forHostSize: host, pointsPerInch: 0).mode == .area)
        }

        // MARK: - Scope, as LPub3D reads it

        /// A meta made from its text, as opening a file makes it.
        private func parsed<T: LPubCommand>(_ type: T.Type, _ text: String) -> T {
            let command = T()
            command.lPubCommandString = text
            return command
        }

        private func placing(_ name: String) -> LDrawPart {
            let part = LDrawPart()
            part.setDisplayName(name, parse: false, in: nil)
            return part
        }

        /// A submodel added to the file, with these lines in its steps. The caller
        /// must keep the file to the end of the test, with
        /// `defer { withExtendedLifetime(file) {} }`, because models link to it
        /// weakly and names resolve through it.
        @discardableResult
        private func submodel(_ name: String, in file: LDrawFile, _ lines: [[LDrawDirective]]) -> LDrawMPDModel {
            let model = LDrawMPDModel.model() as! LDrawMPDModel
            model.setModelName(name)
            file.addSubmodel(model)

            for (index, directives) in lines.enumerated() {
                let step = index == 0 ? (model.steps().first as! LDrawStep) : model.addStep()

                for directive in directives {
                    step.add(directive)
                }
            }
            return model
        }

        private func display(_ model: LDrawModel, step index: UInt) {
            model.setStepDisplay(true)
            model.setMaximumStepIndexForStepDisplay(index)
        }

        /// The width a CONSTRAIN line in force gives the visible step, or nil
        /// when no line does.
        private func pinnedWidth(_ model: LDrawModel) -> Float? {
            let line = LDrawStepPartListPolicy.directiveInForce(forStep: model.visibleStep(), excluding: nil) {
                $0 is LPubPliConstrain
            }
            let constraint = LDrawStepPartListPolicy.constraint(forVisibleStepOfModel: model)

            guard line != nil, constraint.mode == .width else {
                return nil
            }
            return constraint.inches
        }

        @Test("An unscoped CONSTRAIN holds for the steps after it")
        func unscopedConstrainCarriesForward() {
            let document = model([[constrain(.width, 2, scope: .unspecified)], [], []])
            display(document, step: 2)

            let constraint = LDrawStepPartListPolicy.constraint(forVisibleStepOfModel: document)
            #expect(constraint.mode == .width)
            #expect(constraint.inches == 2)
            #expect(pinnedWidth(document) == 2)
        }

        @Test("A GLOBAL outside the header holds from its own step on")
        func globalHoldsFromWhereItIsWritten() {
            let document = model([[], [constrain(.width, 3, scope: .global)], []])

            display(document, step: 0)
            #expect(pinnedWidth(document) == nil)

            display(document, step: 2)
            #expect(pinnedWidth(document) == 3)
        }

        @Test("A LOCAL CONSTRAIN holds for its own step only")
        func localConstrainIsItsStepsAlone() {
            let document = model([[constrain(.width, 2, scope: .unspecified)],
                                  [constrain(.width, 3, scope: .local)],
                                  []])

            display(document, step: 1)
            #expect(pinnedWidth(document) == 3)

            display(document, step: 2)
            #expect(pinnedWidth(document) == 2)
        }

        @Test("A line after a LOCAL in the same step holds for that step only")
        func lineAfterALocalStaysInItsStep() {
            let document = model([[constrain(.width, 3, scope: .local), constrain(.width, 4, scope: .unspecified)],
                                  []])

            display(document, step: 0)
            #expect(pinnedWidth(document) == 4)

            display(document, step: 1)
            #expect(pinnedWidth(document) == nil)
        }

        @Test("A submodel starts from what held where it is first placed")
        func submodelStartsFromItsPlacement() throws {
            let file = LDrawFile()
            defer { withExtendedLifetime(file) {} }
            let own = constrain(.width, 2, scope: .unspecified)

            submodel("main.ldr", in: file, [[constrain(.width, 3, scope: .global), placing("sub.ldr")],
                                            [constrain(.width, 5, scope: .unspecified)]])
            let sub = submodel("sub.ldr", in: file, [[own, placing("3001.dat")],
                                                     [placing("3001.dat")]])

            display(sub, step: 0)
            #expect(pinnedWidth(sub) == 2)

            display(sub, step: 1)
            #expect(pinnedWidth(sub) == 2)

            let firstStep = try #require(sub.steps().first as? LDrawStep)
            let without = LDrawStepPartListPolicy.directiveInForce(forStep: firstStep, excluding: own) {
                $0 is LPubPliConstrain
            } as? LPubPliConstrain

            #expect(without?.inches == 3, "the parent's later WIDTH 5 comes after the placement")
        }

        /// The kept walk gives the same answers, skips a submodel that does not
        /// lead to the target, and is gone once the block ends.
        @Test("Cached lookups agree with fresh ones and do not outlive their block")
        func cachedLookupsAgreeAndExpire() throws {
            let file = LDrawFile()
            defer { withExtendedLifetime(file) {} }

            submodel("main.ldr", in: file, [[constrain(.width, 3, scope: .global), placing("side.ldr"),
                                             placing("sub.ldr")]])
            submodel("side.ldr", in: file, [[constrain(.width, 9, scope: .unspecified)]])
            let sub = submodel("sub.ldr", in: file, [[placing("3001.dat")]])
            display(sub, step: 0)

            let fresh = pinnedWidth(sub)
            var cached: Float?
            LDrawStepPartListPolicy.withCachedLookups {
                cached = pinnedWidth(sub)
                #expect(pinnedWidth(sub) == cached, "asked twice inside the block")
            }

            #expect(fresh == 3, "the side model's WIDTH 9 stays in the side model")
            #expect(cached == fresh)

            // An edit after the block is seen, because nothing was kept.
            let main = try #require(file.model(withName: "main.ldr"))
            (main.steps().first as? LDrawStep)?.insert(constrain(.width, 4, scope: .unspecified), at: 1)
            #expect(pinnedWidth(sub) == 4)
        }

        @Test("The first placement in file order decides, through nested submodels")
        func firstPlacementDecides() {
            let file = LDrawFile()
            defer { withExtendedLifetime(file) {} }

            submodel("main.ldr", in: file, [[placing("a.ldr")],
                                            [constrain(.width, 4, scope: .unspecified), placing("b.ldr")]])
            submodel("a.ldr", in: file, [[constrain(.width, 2, scope: .unspecified), placing("target.ldr")]])
            submodel("b.ldr", in: file, [[placing("target.ldr")]])
            let target = submodel("target.ldr", in: file, [[placing("3001.dat")]])

            #expect(pinnedWidth(target) == 2)
        }

        @Test("A submodel's lines do not reach a later sibling")
        func submodelLinesDoNotLeak() {
            let file = LDrawFile()
            defer { withExtendedLifetime(file) {} }

            submodel("main.ldr", in: file, [[placing("a.ldr")], [placing("b.ldr")]])
            submodel("a.ldr", in: file, [[modelScale(.pli, 3)]])
            let b = submodel("b.ldr", in: file, [[placing("3001.dat")]])

            #expect(LDrawStepPartListPolicy.modelScale(forBranch: .pli, inModel: b) == 1)
        }

        @Test("A LOCAL before the placement does not reach the submodel")
        func parentLocalDoesNotReachTheSubmodel() {
            let file = LDrawFile()
            defer { withExtendedLifetime(file) {} }

            submodel("main.ldr", in: file, [[constrain(.width, 3, scope: .local), placing("sub.ldr")]])
            let sub = submodel("sub.ldr", in: file, [[placing("3001.dat")]])

            #expect(pinnedWidth(sub) == nil)
        }

        @Test("A placement inside PART BEGIN IGN is not followed")
        func ignoredPlacementIsNotFollowed() {
            let file = LDrawFile()
            defer { withExtendedLifetime(file) {} }

            submodel("main.ldr", in: file, [[parsed(LPubPliIgnore.self, "PART BEGIN IGN"),
                                             constrain(.width, 3, scope: .unspecified),
                                             placing("sub.ldr"),
                                             parsed(LPubPliIgnore.self, "PART END")],
                                            [constrain(.width, 5, scope: .unspecified), placing("sub.ldr")]])
            let sub = submodel("sub.ldr", in: file, [[placing("3001.dat")]])

            #expect(pinnedWidth(sub) == 5)
        }

        @Test("A submodel placed nowhere starts from nothing")
        func unplacedSubmodelStartsFromNothing() {
            let file = LDrawFile()
            defer { withExtendedLifetime(file) {} }

            submodel("main.ldr", in: file, [[constrain(.width, 3, scope: .global)]])
            let loose = submodel("loose.ldr", in: file, [[placing("3001.dat")]])

            #expect(pinnedWidth(loose) == nil)
        }

        @Test("A placement loop does not hang")
        func placementLoopEnds() {
            let file = LDrawFile()
            defer { withExtendedLifetime(file) {} }

            submodel("main.ldr", in: file, [[constrain(.width, 3, scope: .global), placing("a.ldr")]])
            submodel("a.ldr", in: file, [[placing("b.ldr")]])
            submodel("b.ldr", in: file, [[placing("a.ldr")]])
            let target = submodel("target.ldr", in: file, [[placing("3001.dat")]])

            #expect(pinnedWidth(target) == nil)
        }

        @Test("A submodel shown alone gets the top model's RESOLUTION, MODEL_SCALE and PAGE SIZE")
        func submodelGetsTheTopModelsPage() {
            let file = LDrawFile()
            defer { withExtendedLifetime(file) {} }

            submodel("main.ldr", in: file, [[parsed(LPubResolution.self, "RESOLUTION GLOBAL 100 DPCM"),
                                             modelScale(.assembly, 1.15, scope: .global),
                                             parsed(LPubPageSize.self, "PAGE SIZE GLOBAL 21 29.7"),
                                             placing("sub.ldr")]])
            let sub = submodel("sub.ldr", in: file, [[placing("3001.dat")]])

            #expect(abs(LDrawStepPartListPolicy.modelScale(forBranch: .assembly, inModel: sub) - 1.15) < 0.0001)

            let page = LDrawStepPartListPolicy.pageSizeInInches(inModel: sub)
            #expect(abs(page.width - 21.0 / 2.54) < 0.0001, "measured in the top model's centimeters")
            #expect(abs(page.height - 29.7 / 2.54) < 0.0001)
        }

        @Test("PART_ROTATION and RESOLUTION keep holding after a LOCAL step")
        func partRotationAndResolutionOutliveTheirStep() {
            let rotated = model([[parsed(LPubPliPartRotation.self, "PLI PART_ROTATION LOCAL 0 90 0 ABS")], []])
            display(rotated, step: 1)

            let turned = V3MulPointByProjMatrix(Point3(x: 40, y: 0, z: 0),
                                                LDrawStepPartListPolicy.partListViewTransform(inModel: rotated))
            #expect(abs(turned.x) < 0.001 && abs(turned.z + 40) < 0.001)

            let metric = model([[parsed(LPubResolution.self, "RESOLUTION LOCAL 100 DPCM"), pageSize(21, 29.7)], []])
            display(metric, step: 1)

            #expect(abs(LDrawStepPartListPolicy.pageSizeInInches(inModel: metric).width - 21.0 / 2.54) < 0.0001)
        }

        @Test("The inherited width is what holds without the step's own line")
        func inheritedWidthLeavesOutTheStepsOwnLine() {
            let later = model([[constrain(.width, 2, scope: .unspecified)], [constrain(.width, 3, scope: .local)]])
            display(later, step: 1)
            #expect(LDrawStepPartListPolicy.inheritedInches(forAxis: .width, inModel: later) == 2)

            let before = model([[constrain(.width, 2, scope: .unspecified), constrain(.width, 3, scope: .local)]])
            #expect(LDrawStepPartListPolicy.inheritedInches(forAxis: .width, inModel: before) == 2)

            let after = model([[constrain(.width, 3, scope: .local), constrain(.width, 4, scope: .unspecified)]])
            #expect(LDrawStepPartListPolicy.inheritedInches(forAxis: .width, inModel: after) == 3)

            let file = LDrawFile()
            defer { withExtendedLifetime(file) {} }
            submodel("main.ldr", in: file, [[constrain(.width, 3, scope: .global), placing("sub.ldr")]])
            let sub = submodel("sub.ldr", in: file, [[constrain(.width, 2, scope: .local), placing("3001.dat")]])
            #expect(LDrawStepPartListPolicy.inheritedInches(forAxis: .width, inModel: sub) == 3)

            let height = model([[constrain(.height, 1, scope: .unspecified)], [constrain(.width, 3, scope: .local)]])
            display(height, step: 1)
            #expect(LDrawStepPartListPolicy.inheritedInches(forAxis: .width, inModel: height) == 0)
            #expect(LDrawStepPartListPolicy.inheritedInches(forAxis: .height, inModel: height) == 1)
        }

        @Test("The step's own CONSTRAIN is its last one, only when it holds for this step alone")
        func stepsOwnConstrainHoldsForItAlone() {
            func step(_ directives: [LDrawDirective]) -> LDrawStep {
                let step = LDrawStep.empty() as! LDrawStep
                for directive in directives {
                    step.add(directive)
                }
                return step
            }

            #expect(LDrawStepPartListPolicy.constrainDirective(inStep: step([constrain(.width, 2, scope: .unspecified)])) == nil)
            #expect(LDrawStepPartListPolicy.constrainDirective(inStep: step([constrain(.width, 3, scope: .global)])) == nil)

            let local = constrain(.width, 3, scope: .local)
            #expect(LDrawStepPartListPolicy.constrainDirective(inStep: step([constrain(.width, 2, scope: .unspecified), local])) === local)

            let width = constrain(.width, 4, scope: .unspecified)
            #expect(LDrawStepPartListPolicy.constrainDirective(inStep: step([constrain(.height, 1, scope: .local), width])) === width)
        }

        // MARK: - LPub3D's parts list angle

        /// The parts list is drawn from 23, -45, not from Bricksmith's 3D view,
        /// unless the document says otherwise.
        @Test("The parts list angle is the document's, else LPub3D's 23, -45")
        func partListAngleFollowsTheDocument() {
            func sample(_ transform: Matrix4) -> Point3 {
                V3MulPointByProjMatrix(Point3(x: 40, y: 10, z: 20), transform)
            }

            let silent = sample(LDrawStepPartListPolicy.partListViewTransform(inModel: model([[]])))
            let lpubDefault = sample(LDrawStepPartListLayout.viewTransform(latitude: 23, longitude: -45))
            #expect(abs(silent.x - lpubDefault.x) < 0.001 && abs(silent.y - lpubDefault.y) < 0.001)

            let angles = LPubPliCameraAngles()
            angles.lPubCommandString = "PLI CAMERA_ANGLES GLOBAL 0 0"
            let front = sample(LDrawStepPartListPolicy.partListViewTransform(inModel: model([[angles]])))
            #expect(abs(front.x - 40) < 0.001 && abs(front.y - 10) < 0.001, "FRONT is no rotation")

            let assembly = LPubPliCameraAngles()
            assembly.lPubCommandString = "ASSEM CAMERA_ANGLES GLOBAL 0 0"
            let unturned = sample(LDrawStepPartListPolicy.partListViewTransform(inModel: model([[assembly]])))
            #expect(abs(unturned.x - lpubDefault.x) < 0.001 && abs(unturned.y - lpubDefault.y) < 0.001,
                    "The assembly's angles do not turn the parts list")
        }

        /// The part turns first, then the camera looks at it. ABS replaces the
        /// camera, unless CAMERA_ANGLES names a custom viewpoint. REL keeps the
        /// camera, and no type applies nothing.
        @Test("PART_ROTATION turns the part before the camera, and ABS replaces the camera")
        func partRotationCombinesWithTheCamera() {
            func meta<T: LPubCommand>(_ type: T.Type, _ text: String) -> T {
                let command = T()
                command.lPubCommandString = text
                return command
            }
            func view(_ directives: [LDrawDirective]) -> Matrix4 {
                LDrawStepPartListPolicy.partListViewTransform(inModel: model([directives]))
            }
            func close(_ a: Point3, _ b: Point3) -> Bool {
                abs(a.x - b.x) < 0.001 && abs(a.y - b.y) < 0.001 && abs(a.z - b.z) < 0.001
            }

            let alongX = Point3(x: 40, y: 0, z: 0)
            let turnedX = Point3(x: 0, y: 0, z: -40)		// 90 degrees about Y
            let camera = LDrawStepPartListLayout.viewTransform(latitude: 23, longitude: -45)

            // ABS: straight on, so only the rotation shows.
            let absolute = V3MulPointByProjMatrix(alongX, view([meta(LPubPliPartRotation.self, "PLI PART_ROTATION 0 90 0 ABS")]))
            #expect(close(absolute, turnedX))

            // REL: rotated, then through the default camera.
            let relative = V3MulPointByProjMatrix(alongX, view([meta(LPubPliPartRotation.self, "PLI PART_ROTATION 0 90 0 REL")]))
            #expect(close(relative, V3MulPointByProjMatrix(turnedX, camera)))

            // No type: no rotation, just the default camera.
            let untyped = V3MulPointByProjMatrix(alongX, view([meta(LPubPliPartRotation.self, "PLI PART_ROTATION 0 90 0")]))
            #expect(close(untyped, V3MulPointByProjMatrix(alongX, camera)))

            // ABS under a custom viewpoint keeps that viewpoint.
            let custom = V3MulPointByProjMatrix(alongX, view([meta(LPubPliCameraAngles.self, "PLI CAMERA_ANGLES LAT_LON 23 -45"),
                                                              meta(LPubPliPartRotation.self, "PLI PART_ROTATION 0 90 0 ABS")]))
            #expect(close(custom, V3MulPointByProjMatrix(turnedX, camera)))
        }

        // MARK: - LPub3D's assembly angle

        /// The step's ROTSTEP turns the model, then the ASSEM camera angles look
        /// at it in place of Bricksmith's 3D view. ABS drops the camera, unless
        /// the angles name a custom viewpoint.
        @Test("The assembly is seen through ASSEM CAMERA_ANGLES after its ROTSTEP")
        func assemblyAngleCombinesRotstepAndCamera() {
            func angles(_ text: String) -> LPubPliCameraAngles {
                let command = LPubPliCameraAngles()
                command.lPubCommandString = text
                return command
            }
            func rotated(_ type: LDrawStepRotationT, _ angle: Tuple3, _ directives: [LDrawDirective] = []) -> LDrawModel {
                let document = model([directives])
                let step = document.steps().first as! LDrawStep
                step.setStepRotationType(type)
                step.setRotationAngle(angle)
                return document
            }
            func seen(_ point: Point3, _ document: LDrawModel, step: UInt = 0) -> Point3 {
                let angle = LDrawStepPartListPolicy.assemblyViewingAngle(forStepAt: step, inModel: document)
                return V3MulPointByProjMatrix(point, Matrix4Rotate(IdentityMatrix4, angle))
            }
            func close(_ a: Point3, _ b: Point3, _ tolerance: Double = 0.001) -> Bool {
                abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance && abs(a.z - b.z) < tolerance
            }

            let point = Point3(x: 40, y: 10, z: 20)
            let quarterTurn = Tuple3(x: 0, y: 90, z: 0)
            let turned = V3MulPointByProjMatrix(point, Matrix4Rotate(IdentityMatrix4, quarterTurn))

            // No line: the model's own angle.
            let silent = model([[]])
            let own = silent.rotationAngleForStep(at: 0)
            let silentAngle = LDrawStepPartListPolicy.assemblyViewingAngle(forStepAt: 0, inModel: silent)
            #expect(silentAngle.x == own.x && silentAngle.y == own.y && silentAngle.z == own.z)

            // LPub3D's default is Bricksmith's 3D view, to MLCad's rounding.
            let lpubDefault = seen(point, model([[angles("ASSEM CAMERA_ANGLES 23 45")]]))
            #expect(close(lpubDefault, seen(point, silent), 0.05))

            // FRONT and no rotation: nothing turns.
            #expect(close(seen(point, model([[angles("ASSEM CAMERA_ANGLES FRONT")]])), point))

            // REL, then the camera: FRONT leaves only the rotation.
            #expect(close(seen(point, rotated(.relative, quarterTurn, [angles("ASSEM CAMERA_ANGLES FRONT")])), turned))

            // REL, then a camera from the top.
            let top = LDrawStepPartListLayout.viewTransform(latitude: 90, longitude: 0)
            #expect(close(seen(point, rotated(.relative, quarterTurn, [angles("ASSEM CAMERA_ANGLES TOP")])),
                          V3MulPointByProjMatrix(turned, top)))

            // ABS: the camera looks straight on.
            #expect(close(seen(point, rotated(.absolute, quarterTurn, [angles("ASSEM CAMERA_ANGLES 30 60")])), turned))

            // ABS under a custom viewpoint keeps it.
            let custom = LDrawStepPartListLayout.viewTransform(latitude: 30, longitude: 60)
            #expect(close(seen(point, rotated(.absolute, quarterTurn, [angles("ASSEM CAMERA_ANGLES LAT_LON 30 60")])),
                          V3MulPointByProjMatrix(turned, custom)))

            // A LOCAL line ends with its step.
            let local = model([[angles("ASSEM CAMERA_ANGLES LOCAL 0 0")], []])
            #expect(close(seen(point, local, step: 0), point))
            #expect(close(seen(point, local, step: 1), seen(point, silent), 0.05))

            // The parts list's angles do not turn the assembly.
            #expect(close(seen(point, model([[angles("PLI CAMERA_ANGLES 0 0")]])), seen(point, silent)))
        }

        @Test("A view reads back as LPub3D's angles, from straight above and below too")
        func latitudeAndLongitudeOfAView() {
            func sees(_ a: Matrix4, as b: Matrix4) -> Bool {
                [Point3(x: 40, y: 10, z: 20), Point3(x: -5, y: 30, z: 7)].allSatisfy { point in
                    let p = V3MulPointByProjMatrix(point, a)
                    let q = V3MulPointByProjMatrix(point, b)
                    return abs(p.x - q.x) < 0.01 && abs(p.y - q.y) < 0.01 && abs(p.z - q.z) < 0.01
                }
            }

            for (latitude, longitude) in [(23.0, 45.0), (0, 0), (0, 180), (90, 0), (-90, 0), (90, 30), (-90, -60), (45, -120)] {
                let view = LDrawStepPartListLayout.viewTransform(latitude: latitude, longitude: longitude)
                var readLatitude = 0.0
                var readLongitude = 0.0

                #expect(LDrawStepPartListLayout.getLatitude(&readLatitude, longitude: &readLongitude, ofViewTransform: view))
                #expect(sees(LDrawStepPartListLayout.viewTransform(latitude: readLatitude, longitude: readLongitude), as: view),
                        "\(latitude), \(longitude)")
            }

            var latitude = 0.0
            var longitude = 0.0
            let tilted = Matrix4Rotate(IdentityMatrix4, Tuple3(x: 10, y: 20, z: 30))

            #expect(LDrawStepPartListLayout.getLatitude(&latitude, longitude: &longitude, ofViewTransform: tilted) == false)
        }

        // MARK: - LPub3D's page
        //
        // The tests below are all measured against one number: how many points a
        // page inch covers at the zoom the viewport is at.

        /// The viewport draws one LDU at so many points, and LPub3D draws it at
        /// 1/64 inch times the ASSEM scale. Together they give points per page
        /// inch.
        @Test("A page inch is read back from the zoom the assembly is drawn at")
        func pageInchFollowsTheAssemblyScale() {
            let document = model([[modelScale(.assembly, 2.0)]])

            // One LDU per point means the page is 32 points to the inch, because
            // at ASSEM 2.0 an LDU is 2/64 inch of it.
            #expect(abs(LDrawStepPartListPolicy.pointsPerPageInch(forAssemblyScale: 1.0,
                                                                 inModel: document) - 32.0) < 0.0001)

            // Zooming in doubles it: the same page, seen bigger.
            #expect(abs(LDrawStepPartListPolicy.pointsPerPageInch(forAssemblyScale: 2.0,
                                                                 inModel: document) - 64.0) < 0.0001)
        }

        /// The proportion is the ratio of the two MODEL_SCALEs.
        @Test("The list keeps its proportion to the step at any zoom")
        func partListKeepsItsProportionToTheAssembly() {
            let document = model([[modelScale(.pli, 3.0), modelScale(.assembly, 1.5)]])

            for zoom in [0.5, 1.0, 4.0] {
                let icons = LDrawStepPartListPolicy.partListScale(forAssemblyScale: zoom, inModel: document)

                #expect(abs(icons - zoom * 3.0 / 1.5) < 0.0001, "at \(zoom)")
            }
        }

        @Test("The outline is a length on the page, so it grows with the zoom")
        func outlineGrowsWithThePage() {
            let atFit = LDrawStepPartListPolicy.outlineWidth(forPointsPerPageInch: 75)
            let zoomedIn = LDrawStepPartListPolicy.outlineWidth(forPointsPerPageInch: 150)

            #expect(atFit > 0.5 && atFit < 1.5)
            #expect(abs(zoomedIn - 2.0 * atFit) < 0.0001)

            // Off the page parts keep their usual edge lines.
            #expect(LDrawStepPartListPolicy.outlineWidth(forPointsPerPageInch: 0) == 0)
        }

        @Test("Zoomed far into the page, the outline stops growing")
        func outlineStopsGrowing() {
            let far = LDrawStepPartListPolicy.outlineWidth(forPointsPerPageInch: 2_000)
            let farther = LDrawStepPartListPolicy.outlineWidth(forPointsPerPageInch: 10_000)

            #expect(far == 2.0)
            #expect(farther == 2.0)
        }

        @Test("A fit aims the drawn scale at the page, and a resize keeps the magnification")
        func theFitterAimsTheDrawnScale() {
            let document = model([[pageSize(8.5, 11), line(from: Point3(x: 0, y: 0, z: 0),
                                                           to: Point3(x: 100, y: 0, z: 0))]])
            let fitter = LDrawStepPartListPageFitter(pageAnchor: LDrawStepPartListPageAnchor())
            let view = FakePageView()
            let size = Size2(width: 1000, height: 800)
            let target = LDrawStepPartListPolicy.assemblyScaleFittingPage(inHostSize: size, inModel: document)

            #expect(fitter.fitPage(of: document, in: view, viewSize: size, keepingMagnification: false))
            #expect(abs(view.pointsPerLDU(atModelPoint: Point3(x: 0, y: 0, z: 0)) - target) < 0.0001)
            #expect(abs((view.scrolledTo?.x ?? -1) - 50) < 0.0001, "centered on the anchor")
            #expect(fitter.fittedViewSize.width == 1000)

            // A resize scales the zoom by how much the fit changed.
            let before = view.zoom
            let larger = Size2(width: 2000, height: 1600)
            let grown = LDrawStepPartListPolicy.assemblyScaleFittingPage(inHostSize: larger, inModel: document) / target
            #expect(fitter.fitPage(of: document, in: view, viewSize: larger, keepingMagnification: true))
            #expect(abs(Double(view.zoom) - Double(before) * grown) < 0.0001)
        }

        /// At ASSEM 2.0 an LDU is 2/64 inch of the page, so one point per LDU is
        /// 32 points to the inch.
        @Test("The page's scale in a view is read from its zoom and the ratio kept with the anchor")
        func thePageScaleIsReadFromTheView() {
            let document = model([[modelScale(.assembly, 2.0)]])
            let fitter = LDrawStepPartListPageFitter(pageAnchor: LDrawStepPartListPageAnchor())
            let view = FakePageView()

            // The view draws 1.25 times as big as its zoom says.
            #expect(abs(fitter.pointsPerPageInch(of: document, in: view) - 40) < 0.0001)

            view.zoom = 300
            #expect(abs(fitter.pointsPerPageInch(of: document, in: view) - 120) < 0.0001)

            // Kept while the camera is turned, and measured again for a step.
            view.foreshortening = 2
            #expect(abs(fitter.pointsPerPageInch(of: document, in: view) - 120) < 0.0001)

            fitter.pageAnchor.forgetDrawnScale()
            #expect(abs(fitter.pointsPerPageInch(of: document, in: view) - 192) < 0.0001)
        }

        /// A fit changes how big the page is drawn, and never how big the model
        /// is on it: the model is drawn at the fitted scale, whatever the zoom
        /// was.
        @Test("A fit draws the model at the fitted scale from any zoom")
        func aFitSetsTheFittedZoom() throws {
            let document = model([[pageSize(8.5, 11), modelScale(.assembly, 0.75)]])
            let fitter = LDrawStepPartListPageFitter(pageAnchor: LDrawStepPartListPageAnchor())
            let view = FakePageView()
            let size = Size2(width: 1000, height: 800)
            let target = LDrawStepPartListPolicy.assemblyScaleFittingPage(inHostSize: size, inModel: document)

            for zoom: CGFloat in [40, 140, 900] {
                view.zoom = zoom
                try #require(fitter.fitPage(of: document, in: view, viewSize: size, keepingMagnification: false))

                #expect(abs(Double(view.zoom) / 100 * view.foreshortening - target) < 0.000001, "from \(zoom)")
            }
        }

        @Test("Zooming to a page scale gives that scale in one go")
        func thePageIsZoomedToAScale() {
            let document = model([[modelScale(.assembly, 2.0)]])
            let fitter = LDrawStepPartListPageFitter(pageAnchor: LDrawStepPartListPageAnchor())
            let view = FakePageView()

            #expect(fitter.showPage(of: document, in: view, atPointsPerPageInch: 100))
            #expect(abs(Double(view.zoom) - 250) < 0.0001)
            #expect(abs(fitter.pointsPerPageInch(of: document, in: view) - 100) < 0.0001)
            #expect(view.scrolledTo == nil, "the host scrolls")

            // A scale that is not above 0 leaves the zoom alone.
            #expect(fitter.showPage(of: document, in: view, atPointsPerPageInch: 0) == false)
            #expect(abs(Double(view.zoom) - 250) < 0.0001)
        }

        /// What the host does when another model or step goes on display: the
        /// ratio is measured again, and the zoom makes up for it and for the
        /// new scale.
        @Test("Another model's page is shown at the size the last one had")
        func anotherModelKeepsThePageSize() {
            let parent = model([[modelScale(.assembly, 2.0)]])
            let submodel = model([[modelScale(.assembly, 0.5)]])
            let fitter = LDrawStepPartListPageFitter(pageAnchor: LDrawStepPartListPageAnchor())
            let view = FakePageView()

            view.zoom = 180
            let held = fitter.pointsPerPageInch(of: parent, in: view)

            // The submodel is nearer the camera.
            view.foreshortening = 1.6

            #expect(abs(fitter.pointsPerPageInch(of: submodel, in: view) - held) > 1, "a different size at first")
            #expect(fitter.showPage(of: submodel, in: view, atPointsPerPageInch: held))
            #expect(abs(fitter.pointsPerPageInch(of: submodel, in: view) - held) < 0.0001)

            // Back again, as far from the camera as before: the zoom it had too.
            view.foreshortening = 1.25
            #expect(fitter.showPage(of: parent, in: view, atPointsPerPageInch: held))
            #expect(abs(Double(view.zoom) - 180) < 0.0001)
        }

        @Test("A document that does not measure its page is not fitted")
        func anUnmeasuredPageIsNotFitted() {
            let fitter = LDrawStepPartListPageFitter(pageAnchor: LDrawStepPartListPageAnchor())
            let view = FakePageView()

            #expect(fitter.fitPage(of: model([[]]), in: view,
                                   viewSize: Size2(width: 1000, height: 800), keepingMagnification: false) == false)
            #expect(view.zoom == 100)
            #expect(view.scrolledTo == nil)
        }

        /// As LPub3D's Fit Page: the whole page shows, 6 points in from the sides
        /// or from the top and bottom, whichever the page reaches first.
        @Test("Fitting the page shows all of it")
        func fittingThePageShowsAllOfIt() {
            let document = model([[pageSize(12.0, 8.0), orientation(landscape: true),
                                   modelScale(.assembly, 1.0)]])

            // A short window fits the height, a tall one the width.
            for (host, fitsWidth) in [(Size2(width: 1200, height: 400), false),
                                      (Size2(width: 1200, height: 2000), true)] {
                let scale = LDrawStepPartListPolicy.assemblyScaleFittingPage(inHostSize: host, inModel: document)
                let center = Point2(x: host.width / 2.0, y: host.height / 2.0)
                let rect = LDrawStepPartListPolicy.pageRect(centeredOn: center, assemblyScale: scale, hostSize: host,
                                                            inModel: document)

                if fitsWidth {
                    #expect(abs(rect.size.width - (host.width - 12)) < 0.0001)
                    #expect(rect.size.height <= host.height - 12)
                } else {
                    #expect(abs(rect.size.height - (host.height - 12)) < 0.0001)
                    #expect(rect.size.width <= host.width - 12)
                }

                // Still the page's own shape.
                #expect(abs(rect.size.width / rect.size.height - 12.0 / 8.0) < 0.0001)
            }
        }

        /// The page goes where the step is, not where the window is. The caller
        /// passes a projected model point, and moving that point moves the page.
        @Test("The page follows the point it is centered on")
        func thePageFollowsItsCenter() {
            let document = model([[pageSize(12.0, 8.0), orientation(landscape: true)]])

            let host = Size2(width: 1000, height: 800)
            let first = LDrawStepPartListPolicy.pageRect(centeredOn: Point2(x: 100, y: 100),
                                                         assemblyScale: 1.0, hostSize: host, inModel: document)
            let panned = LDrawStepPartListPolicy.pageRect(centeredOn: Point2(x: 160, y: 90),
                                                          assemblyScale: 1.0, hostSize: host, inModel: document)

            #expect(abs(panned.origin.x - first.origin.x - 60.0) < 0.0001)
            #expect(abs(panned.origin.y - first.origin.y + 10.0) < 0.0001)
            #expect(panned.size.width == first.size.width)
        }

        /// A named page gives nothing to measure, and a table of page sizes of our
        /// own could disagree with LPub3D's. A guessed page would frame a document
        /// that never asked for one.
        @Test("An unmeasured page has no size, fits nothing and draws nothing")
        func anUnmeasuredPageDrawsNothing() {
            let silent = model([[]])

            let size = LDrawStepPartListPolicy.pageSizeInInches(inModel: silent)
            #expect(size.width == 0)
            #expect(size.height == 0)

            #expect(LDrawStepPartListPolicy.assemblyScaleFittingPage(inHostSize: Size2(width: 800, height: 600), inModel: silent) == 0.0)

            let rect = LDrawStepPartListPolicy.pageRect(centeredOn: Point2(x: 400, y: 300), assemblyScale: 1.0,
                                                        hostSize: Size2(width: 1000, height: 800), inModel: silent)
            #expect(rect.size.width == 0.0)
            #expect(rect.size.height == 0.0)
        }

        /// The text is measured against the icons, not against the resolution.
        @Test("The frame keeps its proportions to the icons on the page")
        func theWholeFrameScalesWithTheIcons() {
            let base = LDrawStepPartListLayout.defaultMetrics()
            let document = model([[]])

            for assemblyScale in [0.5, 1.0, 4.0] {
                let pointsPerPageInch = LDrawStepPartListPolicy.pointsPerPageInch(forAssemblyScale: assemblyScale,
                                                                        inModel: document)
                let iconScale = LDrawStepPartListPolicy.partListScale(forAssemblyScale: assemblyScale,
                                                                       inModel: document)
                let scaled = LDrawStepPartListPolicy.metrics(base, scaledToPointsPerPageInch: pointsPerPageInch)
                let chrome = LDrawStepPartListPolicy.chrome(LDrawStepPartListPolicy.defaultChrome(),
                                                            scaledToPointsPerPageInch: pointsPerPageInch)

                // How much bigger the icons are than they are off the page.
                let grow = iconScale / base.baseScale

                #expect(scaled.pointsPerInch == pointsPerPageInch)
                #expect(abs(scaled.labelHeight - base.labelHeight * grow) < 0.0001, "at \(assemblyScale)")
                #expect(abs(scaled.cellPadding - base.cellPadding * grow) < 0.0001, "at \(assemblyScale)")
                #expect(abs(scaled.minimumScale - base.minimumScale * grow) < 0.0001, "at \(assemblyScale)")

                // The chrome is scaled by the same ratio, or the text stops
                // fitting the room the packer kept for it.
                #expect(abs(chrome.labelPointSize
                          - LDrawStepPartListPolicy.defaultChrome().labelPointSize * grow) < 0.0001)
            }
        }

        /// LPub3D pads its parts list by the border's 0.05 in margin and its
        /// 1/32 in line, so a WIDTH leaves the same room for the parts.
        @Test("The padding on the page is LPub3D's border margin and line")
        func thePaddingOnThePageIsLPubsBorder() {
            let base = LDrawStepPartListLayout.defaultMetrics()

            for pointsPerPageInch in [32.0, 64, 200] {
                let onPage = LDrawStepPartListPolicy.metrics(base, scaledToPointsPerPageInch: pointsPerPageInch)

                #expect(abs(onPage.framePadding - 0.08125 * pointsPerPageInch) < 0.0001, "at \(pointsPerPageInch)")
            }
        }

        /// LPub3D's default parts list border is square.
        @Test("On the page the frame uses LPub3D's border")
        func onThePageTheFrameUsesLPubsBorder() {
            let base = LDrawStepPartListPolicy.defaultChrome()

            for pointsPerPageInch in [32.0, 64, 200] {
                let chrome = LDrawStepPartListPolicy.chrome(base, scaledToPointsPerPageInch: pointsPerPageInch)

                #expect(abs(chrome.borderWidth - pointsPerPageInch / 32) < 0.0001, "at \(pointsPerPageInch)")
                #expect(chrome.cornerRadius == 0, "at \(pointsPerPageInch)")
            }
        }
    }
}
