//
//  LDrawStepPartListPreferencesTests.swift
//  UnitTests
//
//  Tests for the settings the host pushes in, and for whether a list is shown.
//
//  Created by Sergey Slobodenyuk on 2026-09-10.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures

/// Holds every suite that changes the LDrawStepPartList settings, so those
/// suites run one at a time. The settings are process-wide.
@Suite(.serialized) struct StepPartListStaticSettings {}

extension StepPartListStaticSettings {

    @Suite("Step parts list preferences", .serialized)
    final class LDrawStepPartListPreferencesTests {

        deinit {
            LDrawStepPartList.setEnabled(false)
            LDrawStepPartList.setUsesLPubScale(false)
        }

        // MARK: - Fixtures

        private func show(_ visible: Bool, scope: LPubMetaScope) -> LPubPliShow {
            let word = scope == .global ? "GLOBAL " : scope == .local ? "LOCAL " : ""
            let directive = LPubPliShow()
            directive.lPubCommandString = "PLI SHOW \(word)\(visible ? "TRUE" : "FALSE")"
            return directive
        }

        private func pageSize(_ width: Double, _ height: Double) -> LPubPageSize {
            let directive = LPubPageSize()
            directive.lPubCommandString = "PAGE SIZE \(width) \(height)"
            return directive
        }

        private func part() -> LDrawPart {
            let part = LDrawPart()
            part.setDisplayName("3001.dat", parse: false, in: nil)
            return part
        }

        @discardableResult
        private func addStep(to model: LDrawModel, _ directives: [LDrawDirective]) -> LDrawStep {
            let step = model.addStep()
            for directive in directives {
                step.add(directive)
            }
            return step
        }

        /// A two-step model displaying its second step.
        private func steppedModel(firstStep: [LDrawDirective] = [],
                                  secondStep: [LDrawDirective] = []) -> LDrawModel {
            let model = LDrawModel()
            addStep(to: model, firstStep + [part()])
            addStep(to: model, secondStep + [part()])
            model.setStepDisplay(true)
            model.setMaximumStepIndexForStepDisplay(1)
            return model
        }

        // MARK: - Enabling

        @Test("Enabling it shows a list for an ordinary step, with no page")
        func enablingShowsTheList() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(false)
            let model = steppedModel()

            #expect(LDrawStepPartList.isShown(forVisibleStepOf: model) == true)
            #expect(LDrawStepPartListPolicy.showsListOrPage(inModel: model) == true)
            #expect(LDrawStepPartListPolicy.drawsPage(inModel: model) == false)
        }

        @Test("There is nothing to show without a model")
        func nilModelShowsNothing() {
            LDrawStepPartList.setEnabled(true)

            #expect(LDrawStepPartList.isShown(forVisibleStepOf: nil) == false)
        }

        // MARK: - PLI SHOW

        @Test("A step saying SHOW FALSE suppresses its list")
        func localShowFalseSuppresses() {
            LDrawStepPartList.setEnabled(true)
            let model = steppedModel(secondStep: [show(false, scope: .local)])

            #expect(LDrawStepPartList.isShown(forVisibleStepOf: model) == false)
        }

        @Test("A neighboring step's suppression does not carry over")
        func suppressionIsPerStep() {
            LDrawStepPartList.setEnabled(true)
            let model = steppedModel(firstStep: [show(false, scope: .local)])

            // Displaying step two, which says nothing.
            #expect(LDrawStepPartList.isShown(forVisibleStepOf: model) == true)

            model.setMaximumStepIndexForStepDisplay(0)
            #expect(LDrawStepPartList.isShown(forVisibleStepOf: model) == false)
        }

        @Test("A GLOBAL SHOW FALSE in the header suppresses every step")
        func globalShowFalseSuppresses() {
            LDrawStepPartList.setEnabled(true)
            let model = steppedModel(firstStep: [show(false, scope: .global)])

            #expect(LDrawStepPartList.isShown(forVisibleStepOf: model) == false)
        }

        @Test("A step's own SHOW overrides the document's")
        func localOverridesGlobal() {
            LDrawStepPartList.setEnabled(true)
            let model = steppedModel(firstStep: [show(false, scope: .global)],
                                     secondStep: [show(true, scope: .local)])

            #expect(LDrawStepPartList.isShown(forVisibleStepOf: model) == true)
        }

        /// Files come from other people; the preference is the user's own.
        @Test("SHOW TRUE cannot override the preference being off")
        func documentsCannotForceTheListOn() {
            LDrawStepPartList.setEnabled(false)

            #expect(LDrawStepPartList.isShown(forVisibleStepOf: steppedModel()) == false)
            #expect(LDrawStepPartList.isShown(forVisibleStepOf:
                        steppedModel(secondStep: [show(true, scope: .local)])) == false)
            #expect(LDrawStepPartList.isShown(forVisibleStepOf:
                        steppedModel(firstStep: [show(true, scope: .global)])) == false)
        }

        @Test("The last SHOW in a step is the one that counts")
        func laterLinesWin() {
            LDrawStepPartList.setEnabled(true)
            let model = steppedModel(secondStep: [show(true, scope: .local),
                                                  show(false, scope: .local)])

            #expect(LDrawStepPartList.isShown(forVisibleStepOf: model) == false)
        }

        @Test("An unscoped SHOW FALSE hides every later step")
        func unscopedShowFalseCarriesForward() {
            LDrawStepPartList.setEnabled(true)
            let model = steppedModel(firstStep: [show(false, scope: .unspecified)])

            #expect(LDrawStepPartList.isShown(forVisibleStepOf: model) == false)
        }

        @Test("A GLOBAL SHOW FALSE in a later step hides from there on, not before")
        func globalShowFalseHoldsFromItsStep() {
            LDrawStepPartList.setEnabled(true)
            let model = steppedModel(secondStep: [show(false, scope: .global)])

            #expect(LDrawStepPartList.isShown(forVisibleStepOf: model) == false)

            model.setMaximumStepIndexForStepDisplay(0)
            #expect(LDrawStepPartList.isShown(forVisibleStepOf: model) == true)
        }

        @Test("The top model's SHOW FALSE reaches a submodel placed after it, and a submodel's own SHOW FALSE does not reach a later one")
        func showFalseFollowsPlacements() {
            LDrawStepPartList.setEnabled(true)

            func placing(_ name: String) -> LDrawPart {
                let part = LDrawPart()
                part.setDisplayName(name, parse: false, in: nil)
                return part
            }
            @discardableResult
            func submodel(_ name: String, in file: LDrawFile, _ directives: [LDrawDirective]) -> LDrawMPDModel {
                let model = LDrawMPDModel.model() as! LDrawMPDModel
                model.setModelName(name)
                file.addSubmodel(model)
                for directive in directives {
                    (model.steps().first as! LDrawStep).add(directive)
                }
                return model
            }

            // Models find their file through a weak link, so the files are
            // kept to the end.
            let hiding = LDrawFile()
            defer { withExtendedLifetime(hiding) {} }
            submodel("main.ldr", in: hiding, [show(false, scope: .global), placing("sub.ldr")])
            let hidden = submodel("sub.ldr", in: hiding, [part()])

            #expect(LDrawStepPartList.isShown(forVisibleStepOf: hidden) == false)

            let siblings = LDrawFile()
            defer { withExtendedLifetime(siblings) {} }
            submodel("main.ldr", in: siblings, [placing("a.ldr"), placing("b.ldr")])
            submodel("a.ldr", in: siblings, [show(false, scope: .unspecified), part()])
            let later = submodel("b.ldr", in: siblings, [part()])

            #expect(LDrawStepPartList.isShown(forVisibleStepOf: later) == true)
        }

        // MARK: - LPub3D's page

        @Test("The page is drawn only in Steps mode with both preferences on and a measured page")
        func pageNeedsStepsModePreferencesAndSize() {
            LDrawStepPartList.setEnabled(true)
            let model = steppedModel(firstStep: [pageSize(8.5, 11)])

            LDrawStepPartList.setUsesLPubScale(false)
            #expect(LDrawStepPartListPolicy.drawsPage(inModel: model) == false)

            LDrawStepPartList.setUsesLPubScale(true)
            #expect(LDrawStepPartListPolicy.drawsPage(inModel: model) == true)
            #expect(LDrawStepPartListPolicy.drawsPage(inModel: steppedModel()) == false)
            #expect(LDrawStepPartListPolicy.drawsPage(inModel: nil) == false)

            // A PAGE SIZE holds from where it is written, so a step before it
            // has no page.
            let later = steppedModel(secondStep: [pageSize(8.5, 11)])
            #expect(LDrawStepPartListPolicy.drawsPage(inModel: later) == true)
            later.setMaximumStepIndexForStepDisplay(0)
            #expect(LDrawStepPartListPolicy.drawsPage(inModel: later) == false)

            LDrawStepPartList.setEnabled(false)
            #expect(LDrawStepPartListPolicy.drawsPage(inModel: model) == false)

            LDrawStepPartList.setEnabled(true)
            model.setStepDisplay(false)
            #expect(LDrawStepPartListPolicy.drawsPage(inModel: model) == false)
        }

        /// LPub3D prints the page whether or not the step has a parts list.
        @Test("A step that hides its list keeps its page")
        func hiddenListKeepsThePage() {
            LDrawStepPartList.setEnabled(true)
            let model = steppedModel(firstStep: [pageSize(8.5, 11)],
                                     secondStep: [show(false, scope: .local)])

            #expect(LDrawStepPartList.isShown(forVisibleStepOf: model) == false)

            LDrawStepPartList.setUsesLPubScale(false)
            #expect(LDrawStepPartListPolicy.showsListOrPage(inModel: model) == false)

            LDrawStepPartList.setUsesLPubScale(true)
            #expect(LDrawStepPartListPolicy.drawsPage(inModel: model) == true)
            #expect(LDrawStepPartListPolicy.showsListOrPage(inModel: model) == true)
        }

        @Test("Outside Steps mode nothing is shown")
        func nothingOutsideStepsMode() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let model = steppedModel(firstStep: [pageSize(8.5, 11)])

            #expect(LDrawStepPartListPolicy.showsListOrPage(inModel: model) == true)

            model.setStepDisplay(false)

            #expect(LDrawStepPartListPolicy.showsListOrPage(inModel: model) == false)
            #expect(LDrawStepPartListPolicy.drawsPage(inModel: model) == false)
        }

        // MARK: - What the host draws

        private func host(assemblyScale: Double = 0,
                          preview: LPubPliAxis? = nil,
                          inches: Double = 0) -> LDrawStepPartListHostState {
            var host = LDrawStepPartListHostState()
            host.viewSize = Size2(width: 1000, height: 800)
            host.assemblyScale = assemblyScale
            host.anchorInView = Point2(x: 500, y: 400)
            if let axis = preview {
                host.hasPreview = true
                host.previewAxis = axis
                host.previewInches = inches
            }
            return host
        }

        @Test("Off the page the list takes four tenths of the view, with no page and no pins")
        func offThePageTheListFitsTheView() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(false)
            let model = steppedModel(secondStep: [constrain(.width, 1.0)])

            let presentation = LDrawStepPartListPresentation(model: model, host: host(assemblyScale: 1))
            let layout = try #require(presentation.layout)

            #expect(presentation.isOnPage == false)
            #expect(presentation.pageRect.size.width == 0)
            #expect(presentation.widthPinned == false)
            #expect(layout.frameSize.width <= 400)
            #expect(presentation.iconModel != nil)

            // Off the page the frame sits 12 points in from the view's corner.
            #expect(presentation.frameRect.origin.x == 12)
            #expect(presentation.frameRect.origin.y == 12)
            #expect(presentation.contentRect.size.width > 0)
        }

        /// The document's CONSTRAIN is in page inches, so with no page to measure
        /// them on it is ignored, even with the preference on.
        @Test("With the page preference on but no measured page, the list is off the page")
        func noMeasuredPageMeansOffThePage() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let model = steppedModel(secondStep: [constrain(.width, 1.0)])

            let presentation = LDrawStepPartListPresentation(model: model, host: host(assemblyScale: 1))

            #expect(presentation.isOnPage == false)
            #expect(presentation.pointsPerPageInch == 0)
            #expect(presentation.widthPinned == false)
        }

        @Test("On a measured page the page is centered on the anchor, and the step's own line pins its axis")
        func onThePageTheStepPinsItsAxis() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let model = steppedModel(firstStep: [pageSize(8.5, 11)],
                                     secondStep: [constrain(.width, 2.0)])

            let presentation = LDrawStepPartListPresentation(model: model, host: host(assemblyScale: 1))
            let page = presentation.pageRect

            #expect(presentation.isOnPage)
            #expect(abs(page.size.width - 8.5 * presentation.pointsPerPageInch) < 0.0001)
            #expect(abs(page.origin.x + page.size.width / 2 - 500) < 0.0001)
            #expect(abs(page.origin.y + page.size.height / 2 - 400) < 0.0001)
            #expect(presentation.widthPinned)
            #expect(presentation.heightPinned == false)

            // The frame sits in the page's corner, and the icons inside its
            // padding.
            let frame = presentation.frameRect
            let content = presentation.contentRect
            let margin = 0.05 * presentation.pointsPerPageInch
            let padding = 0.08125 * presentation.pointsPerPageInch

            #expect(abs(frame.origin.x - (page.origin.x + margin)) < 0.0001)
            #expect(abs(frame.origin.y - (page.origin.y + margin)) < 0.0001)
            #expect(abs(content.origin.x - (frame.origin.x + padding)) < 0.0001)
            #expect(abs(content.size.width - (frame.size.width - 2 * padding)) < 0.0001)
        }

        @Test("During a drag the pins show what letting go would leave")
        func aDragPreviewsItsPins() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let model = steppedModel(firstStep: [pageSize(8.5, 11)],
                                     secondStep: [constrain(.width, 2.0)])

            let presentation = LDrawStepPartListPresentation(model: model,
                                                             host: host(assemblyScale: 1, preview: .height, inches: 1.0))

            #expect(presentation.heightPinned)
            #expect(presentation.widthPinned == false)
        }

        @Test("A step with nothing to list is still drawn on its page")
        func anEmptyStepKeepsItsPage() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let model = LDrawModel()
            addStep(to: model, [pageSize(8.5, 11), part()])
            addStep(to: model, [])
            model.setStepDisplay(true)
            model.setMaximumStepIndexForStepDisplay(1)

            let presentation = LDrawStepPartListPresentation(model: model, host: host(assemblyScale: 1))

            #expect(presentation.layout == nil)
            #expect(presentation.pageRect.size.width > 0)
            #expect(presentation.frameRect.size.width == 0)
        }

        @Test("A press on a pin clicks it, a press on an edge starts a resize, and a press inside does neither")
        func theTrackerFollowsOnePress() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let model = steppedModel(firstStep: [pageSize(8.5, 11)],
                                     secondStep: [constrain(.width, 2.0)])
            let presentation = LDrawStepPartListPresentation(model: model, host: host(assemblyScale: 1))
            let frame = presentation.frameRect
            let tracker = LDrawStepPartListResizeTracker()

            try #require(frame.size.width > 0)

            let widthPin = LDrawStepPartListPolicy.pinRect(forAxis: .width, inFrame: frame)
            let onWidthPin = Point2(x: widthPin.origin.x + widthPin.size.width / 2,
                                    y: widthPin.origin.y + widthPin.size.height / 2)
            #expect(tracker.begin(at: onWidthPin, presentation: presentation) == .widthPin)
            #expect(tracker.isResizing == false)

            let inside = Point2(x: frame.origin.x + frame.size.width / 2, y: frame.origin.y + frame.size.height / 2)
            #expect(tracker.begin(at: inside, presentation: presentation) == .none)
            #expect(tracker.inchesForDrag(to: inside, presentation: presentation) == 0)

            let bottomEdge = Point2(x: frame.origin.x + frame.size.width / 4, y: frame.origin.y + frame.size.height)
            #expect(tracker.begin(at: bottomEdge, presentation: presentation) == .heightEdge)
            #expect(tracker.isResizing)
            #expect(tracker.axis == .height)
            #expect(tracker.inchesForDrag(to: bottomEdge, presentation: presentation) > 0)

            tracker.end()
            #expect(tracker.isResizing == false)
            #expect(tracker.inchesForDrag(to: bottomEdge, presentation: presentation) == 0)
        }
    }
}
