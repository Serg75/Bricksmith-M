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
import LDrawTestSupport

/// Holds every suite that changes the LDrawStepPartList settings or lays out
/// by them, so those suites run one at a time. The settings are process-wide,
/// so this also waits for the other test targets' suites that use them.
@Suite(.serialized, .usesStepSettings) struct StepPartListStaticSettings {}

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
            #expect(LDrawStepPartListPolicy.showsAnything(inModel: model) == true)
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
            #expect(LDrawStepPartListPolicy.showsAnything(inModel: model) == false)

            LDrawStepPartList.setUsesLPubScale(true)
            #expect(LDrawStepPartListPolicy.drawsPage(inModel: model) == true)
            #expect(LDrawStepPartListPolicy.showsAnything(inModel: model) == true)
        }

        @Test("Outside Steps mode nothing is shown")
        func nothingOutsideStepsMode() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let model = steppedModel(firstStep: [pageSize(8.5, 11)])

            #expect(LDrawStepPartListPolicy.showsAnything(inModel: model) == true)

            model.setStepDisplay(false)

            #expect(LDrawStepPartListPolicy.showsAnything(inModel: model) == false)
            #expect(LDrawStepPartListPolicy.drawsPage(inModel: model) == false)
        }

        // MARK: - What the host draws

        private func host(assemblyScale: Double = 0,
                          preview: LPubPliAxis? = nil,
                          inches: Double = 0) -> LDrawStepPartListHostState {
            var host = LDrawStepPartListHostState()
            host.viewSize = Size2(width: 1000, height: 800)
            host.assemblyScale = assemblyScale
            host.pageCenterInView = Point2(x: 500, y: 400)
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

        @Test("On a measured page the page is centered where the host says, and the step's own line pins its axis")
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

        // MARK: - Callouts

        private func lpub(_ text: String) -> LDrawDirective {
            let lines = ["0 !LPUB " + text, "0 STEP"]
            let step = LDrawStep(lines: lines, in: NSRange(location: 0, length: lines.count), parentGroup: nil)
            return (step!.subdirectives() as! [LDrawDirective])[0]
        }

        /// A file whose main model shows a step that calls out sub.ldr and also
        /// places a part. `extra` goes before the callout, and `inside` between
        /// its two lines. The caller keeps the file.
        private func calloutModel(_ extra: [LDrawDirective] = [],
                                  inside: [LDrawDirective] = []) -> (file: LDrawFile, model: LDrawModel) {
            let file = LDrawFile()
            let main = LDrawMPDModel.model() as! LDrawMPDModel
            main.setModelName("main.ldr")
            file.addSubmodel(main)
            let sub = LDrawMPDModel.model() as! LDrawMPDModel
            sub.setModelName("sub.ldr")
            file.addSubmodel(sub)
            addStep(to: sub, [part()])

            let placement = LDrawPart()
            placement.setDisplayName("sub.ldr", parse: false, in: nil)
            let begin = LPubCallout()
            begin.lPubCommandString = "CALLOUT BEGIN"
            let end = LPubCallout()
            end.lPubCommandString = "CALLOUT END"

            addStep(to: main, extra + [begin, placement] + inside + [end, part()])
            main.setStepDisplay(true)
            main.setMaximumStepIndexForStepDisplay(UInt(main.steps().count - 1))

            return (file, main)
        }

        @Test("A step's callout gets a box under the list's frame")
        func calloutBoxSitsUnderTheList() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(false)
            let fixture = calloutModel()

            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host(assemblyScale: 1))
            let box = try #require(presentation.calloutBoxes.first)
            let frame = presentation.frameRect

            #expect(presentation.calloutBoxes.count == 1)
            #expect(frame.size.height > 0)
            #expect(box.frameRect.origin.x == frame.origin.x)
            #expect(box.frameRect.origin.y == frame.origin.y + frame.size.height + 12)
        }

        @Test("A step that hides its list still shows its callouts")
        func hiddenListKeepsItsCallouts() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(false)
            let fixture = calloutModel([show(false, scope: .local)])

            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host(assemblyScale: 1))
            let box = try #require(presentation.calloutBoxes.first)

            #expect(presentation.layout == nil)
            #expect(box.frameRect.origin.x == 12)
            #expect(box.frameRect.origin.y == 12)
        }

        @Test("On the page the callout's box sits on the page, at life size")
        func calloutBoxOnThePage() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let fixture = calloutModel([pageSize(8.5, 11)])

            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: host(assemblyScale: 2))
            let box = try #require(presentation.calloutBoxes.first)
            let picture = try #require(box.pictures.first)
            let page = presentation.pageRect

            #expect(presentation.isOnPage)
            #expect(box.frameRect.origin.x >= page.origin.x)
            #expect(box.frameRect.origin.y >= page.origin.y)
            #expect(abs(picture.zoomPercentage - presentation.pointsPerPageInch / 64.0 * 100.0) < 0.0001)
        }

        @Test("On the page a callout's box is placed against the assembly the host measured")
        func calloutBoxFollowsTheAssembly() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let fixture = calloutModel([pageSize(8.5, 11)])
            var measured = host(assemblyScale: 2)
            measured.assemblyRect = Box2(origin: Point2(x: 450, y: 380), size: Size2(width: 60, height: 40))

            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: measured)
            let box = try #require(presentation.calloutBoxes.first)
            let margin = 0.05 * presentation.pointsPerPageInch

            // LPub3D's default: to the right of the assembly, in the middle,
            // its default margin away.
            #expect(abs(box.frameRect.origin.x - (510 + margin)) < 0.001)
            #expect(abs(box.frameRect.origin.y + box.frameRect.size.height / 2 - 400) < 0.001)

            // Off the page the measurement is not read.
            LDrawStepPartList.setUsesLPubScale(false)
            let stacked = LDrawStepPartListPresentation(model: fixture.model, host: measured)
            #expect(stacked.calloutBoxes.first?.frameRect.origin.x == 12)
        }

        @Test("The box keeps the room its MARGINS line asks for")
        func calloutBoxKeepsItsMargins() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let fixture = calloutModel([pageSize(8.5, 11), lpub("CALLOUT MARGINS GLOBAL 0.25 0.1")])
            var measured = host(assemblyScale: 2)
            measured.assemblyRect = Box2(origin: Point2(x: 450, y: 380), size: Size2(width: 60, height: 40))

            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: measured)
            let box = try #require(presentation.calloutBoxes.first)

            #expect(abs(box.frameRect.origin.x - (510 + 0.25 * presentation.pointsPerPageInch)) < 0.001)
        }

        @Test("The step's place on the page is the middle of the assembly and the callouts against it")
        func stepCenterIsTheMiddleOfAssemblyAndCallouts() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let fixture = calloutModel([pageSize(8.5, 11)])
            var measured = host(assemblyScale: 2)
            measured.assemblyRect = Box2(origin: Point2(x: 450, y: 380), size: Size2(width: 60, height: 40))

            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: measured)
            let box = try #require(presentation.calloutBoxes.first).frameRect
            let top = min(380, box.origin.y)
            let bottom = max(420, box.origin.y + box.size.height)

            #expect(presentation.hasStepCenter)
            #expect(abs(presentation.stepCenterInView.x - (450 + box.origin.x + box.size.width) / 2) < 0.001)
            #expect(abs(presentation.stepCenterInView.y - (top + bottom) / 2) < 0.001)

            // Asked for or not, the page stays where the host has it.
            #expect(abs(presentation.pageRect.origin.x + presentation.pageRect.size.width / 2 - 500) < 0.001)
        }

        @Test("A callout that has been dragged does not count toward the step's place")
        func draggedCalloutsDoNotCount() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            var measured = host(assemblyScale: 2)
            measured.assemblyRect = Box2(origin: Point2(x: 100, y: 200), size: Size2(width: 60, height: 40))

            // With an offset the box is where the file's author left it, and
            // the assembly alone is centered.
            let dragged = calloutModel([pageSize(8.5, 11)],
                                       inside: [lpub("CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.5 0")])
            let alone = LDrawStepPartListPresentation(model: dragged.model, host: measured)

            #expect(alone.calloutBoxes.count == 1)
            #expect(abs(alone.stepCenterInView.x - 130) < 0.001)
            #expect(abs(alone.stepCenterInView.y - 220) < 0.001)

            // The same line with no offset counts.
            let placed = calloutModel([pageSize(8.5, 11)],
                                      inside: [lpub("CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE")])
            let together = LDrawStepPartListPresentation(model: placed.model, host: measured)
            let box = try #require(together.calloutBoxes.first).frameRect

            #expect(abs(together.stepCenterInView.x - (100 + box.origin.x + box.size.width) / 2) < 0.001)

            // A box placed against something Bricksmith does not draw stands by
            // the assembly, but LPub3D does not center it with the assembly.
            let grouped = calloutModel([pageSize(8.5, 11)],
                                       inside: [lpub("CALLOUT PLACEMENT RIGHT CENTER MULTI_STEP OUTSIDE")])
            let group = LDrawStepPartListPresentation(model: grouped.model, host: measured)

            #expect(abs(group.stepCenterInView.x - 130) < 0.001)
        }

        /// What a host does when a PLACEMENT line changes: it has the step
        /// centered again and keeps the page where it is, so the model moves.
        private func centered(_ model: LDrawModel,
                              _ host: LDrawStepPartListHostState) -> (LDrawStepPartListPresentation,
                                                                     LDrawStepPartListHostState) {
            let measured = LDrawStepPartListPresentation(model: model, host: host)
            var moved = host
            moved.assemblyRect.origin.x += host.pageCenterInView.x - measured.stepCenterInView.x
            moved.assemblyRect.origin.y += host.pageCenterInView.y - measured.stepCenterInView.y

            return (LDrawStepPartListPresentation(model: model, host: moved), moved)
        }

        @Test("A centered box that is dragged stays where it is dropped, though the assembly moves to the middle")
        func firstDropLandsWhereItWasLetGo() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let placement = try #require(lpub("CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE") as? LPubPlacement)
            let fixture = calloutModel([pageSize(8.5, 11)], inside: [placement])
            var measured = host(assemblyScale: 2)
            measured.assemblyRect = Box2(origin: Point2(x: 450, y: 380), size: Size2(width: 60, height: 40))

            // The step as a host shows it: centered, with the box counted.
            let (before, shown) = centered(fixture.model, measured)
            let box = try #require(before.calloutBoxes.first)
            let drop = Point2(x: box.frameRect.origin.x + 30, y: box.frameRect.origin.y + 20)
            var offset = Point2(x: 0, y: 0)

            try #require(abs(before.stepCenterInView.x - 500) < 0.001)
            try #require(box.getPlacementOffset(&offset, forOrigin: drop))

            placement.lPubCommandString = String(format: "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE %.4f %.4f",
                                                 offset.x, offset.y)

            let (after, settled) = centered(fixture.model, shown)
            let dropped = try #require(after.calloutBoxes.first).frameRect

            // The assembly is in the middle on its own now, so it has moved.
            #expect(abs(after.stepCenterInView.x - 500) < 0.001)
            #expect(abs(after.stepCenterInView.y - 400) < 0.001)
            #expect(abs(settled.assemblyRect.origin.x - 470) < 0.001)
            #expect(abs(settled.assemblyRect.origin.x - shown.assemblyRect.origin.x) > 1)

            // The offset is written to four decimals of a box 60 by 40 points.
            #expect(abs(dropped.origin.x - drop.x) < 0.01)
            #expect(abs(dropped.origin.y - drop.y) < 0.01)
        }

        @Test("A box that was dragged before moves nothing else when it is dragged again")
        func laterDropsMoveNothingElse() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let text = "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.2000 0.1000"
            let placement = try #require(lpub(text) as? LPubPlacement)
            let fixture = calloutModel([pageSize(8.5, 11)], inside: [placement])
            var measured = host(assemblyScale: 2)
            measured.assemblyRect = Box2(origin: Point2(x: 450, y: 380), size: Size2(width: 60, height: 40))

            let (before, shown) = centered(fixture.model, measured)
            let box = try #require(before.calloutBoxes.first)
            let drop = Point2(x: box.frameRect.origin.x + 30, y: box.frameRect.origin.y + 20)
            var offset = Point2(x: 0, y: 0)

            try #require(box.getPlacementOffset(&offset, forOrigin: drop))

            #expect(abs(offset.x - (0.2 + 30.0 / 60.0)) < 0.0001)
            #expect(abs(offset.y - (0.1 + 20.0 / 40.0)) < 0.0001)

            placement.lPubCommandString = String(format: "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE %.4f %.4f",
                                                 offset.x, offset.y)

            let (after, settled) = centered(fixture.model, shown)
            let dropped = try #require(after.calloutBoxes.first).frameRect

            #expect(abs(settled.assemblyRect.origin.x - shown.assemblyRect.origin.x) < 0.001)
            #expect(abs(dropped.origin.x - drop.x) < 0.01)
            #expect(abs(dropped.origin.y - drop.y) < 0.01)
        }

        @Test("The row under a point is the one whose cell holds it")
        func rowUnderAPoint() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(false)
            let model = steppedModel()

            let presentation = LDrawStepPartListPresentation(model: model, host: host(assemblyScale: 1))
            let cell = try #require(presentation.layout?.placements.first)
            let content = presentation.contentRect
            let inside = Point2(x: content.origin.x + cell.cellFrame.origin.x + cell.cellFrame.size.width / 2,
                                y: content.origin.y + cell.cellFrame.origin.y + cell.cellFrame.size.height / 2)

            #expect(presentation.entry(at: inside) === cell.entry)
            #expect(presentation.entry(at: Point2(x: content.origin.x - 5, y: content.origin.y - 5)) == nil)
            #expect(presentation.entry(at: Point2(x: 900, y: 700)) == nil)
        }

        @Test("With no callout the assembly alone is put in the middle of the page")
        func stepCenterOfAnAssemblyAlone() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let model = steppedModel(firstStep: [pageSize(8.5, 11)])
            var measured = host(assemblyScale: 2)
            measured.assemblyRect = Box2(origin: Point2(x: 100, y: 200), size: Size2(width: 60, height: 40))

            let presentation = LDrawStepPartListPresentation(model: model, host: measured)

            #expect(presentation.hasStepCenter)
            #expect(abs(presentation.stepCenterInView.x - 130) < 0.001)
            #expect(abs(presentation.stepCenterInView.y - 220) < 0.001)

            // With nothing measured there is no place to work out.
            let unmeasured = LDrawStepPartListPresentation(model: model, host: host(assemblyScale: 2))
            #expect(unmeasured.hasStepCenter == false)
        }

        @Test("An ASSEM PLACEMENT offset moves the step by that share of the page")
        func stepCenterTakesTheAssemblyOffset() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let line = lpub("ASSEM PLACEMENT LOCAL CENTER PAGE INSIDE 0.1 -0.05")
            let model = steppedModel(firstStep: [pageSize(8.5, 11)], secondStep: [line])
            var measured = host(assemblyScale: 2)
            measured.assemblyRect = Box2(origin: Point2(x: 100, y: 200), size: Size2(width: 60, height: 40))

            let presentation = LDrawStepPartListPresentation(model: model, host: measured)
            let page = presentation.pageRect.size

            // The assembly sits right of and above the middle, so the middle
            // is left of and below the assembly.
            #expect(abs(presentation.stepCenterInView.x - (130 - 0.1 * page.width)) < 0.001)
            #expect(abs(presentation.stepCenterInView.y - (220 + 0.05 * page.height)) < 0.001)
        }

        /// The host is wider than an 8.5 by 11 page, so the page grows wider,
        /// with the file's page in its middle.
        @Test("On a page that follows the host's shape the step keeps its place on the file's page")
        func stepCenterOnAGrownPage() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let line = lpub("ASSEM PLACEMENT LOCAL LEFT PAGE INSIDE 0.1 -0.05")
            let model = steppedModel(firstStep: [pageSize(8.5, 11)], secondStep: [line])
            var measured = host(assemblyScale: 2)
            measured.assemblyRect = Box2(origin: Point2(x: 100, y: 200), size: Size2(width: 60, height: 40))

            let onFilePage = LDrawStepPartListPresentation(model: model, host: measured)

            LDrawStepPartList.setPageFollowsHostShape(true)
            defer { LDrawStepPartList.setPageFollowsHostShape(false) }

            let onGrownPage = LDrawStepPartListPresentation(model: model, host: measured)

            #expect(onGrownPage.pageRect.size.width > onFilePage.pageRect.size.width + 1)
            #expect(abs(onGrownPage.pageRect.size.height - onFilePage.pageRect.size.height) < 0.001)
            #expect(abs(onGrownPage.stepCenterInView.x - onFilePage.stepCenterInView.x) < 0.001)
            #expect(abs(onGrownPage.stepCenterInView.y - onFilePage.stepCenterInView.y) < 0.001)
        }

        @Test("A callout placed against the page does not count toward the step's place")
        func pageCalloutsDoNotCount() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let fixture = calloutModel([pageSize(8.5, 11)],
                                       inside: [lpub("CALLOUT PLACEMENT BOTTOM_RIGHT PAGE INSIDE")])
            var measured = host(assemblyScale: 2)
            measured.assemblyRect = Box2(origin: Point2(x: 100, y: 200), size: Size2(width: 60, height: 40))

            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: measured)

            #expect(presentation.calloutBoxes.count == 1)
            #expect(abs(presentation.stepCenterInView.x - 130) < 0.001)
            #expect(abs(presentation.stepCenterInView.y - 220) < 0.001)
        }

        /// A divider makes the box taller or wider, and the box is centered
        /// with the assembly.
        @Test("The placement key changes when a divider is put into a callout's submodel")
        func placementKeyFollowsTheDividers() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let fixture = calloutModel([pageSize(8.5, 11)])
            let submodel = try #require(fixture.file.submodels().last as? LDrawModel)
            let second = addStep(to: submodel, [part()])
            let before = LDrawStepPartListPresentation(model: fixture.model, host: host(assemblyScale: 2)).placementKey

            let divider = LPubCallout()
            divider.lPubCommandString = "CALLOUT DIVIDER"
            second.insert(divider, at: 0)

            let divided = LDrawStepPartListPresentation(model: fixture.model, host: host(assemblyScale: 2)).placementKey
            #expect(divided != before)

            second.remove(divider)

            #expect(LDrawStepPartListPresentation(model: fixture.model, host: host(assemblyScale: 2)).placementKey
                    == before)
        }

        @Test("The placement key changes when the steps of a callout are turned")
        func placementKeyFollowsTheDirection() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let alloc = lpub("CALLOUT ALLOC LOCAL VERTICAL")
            let fixture = calloutModel([pageSize(8.5, 11)], inside: [alloc])
            let before = LDrawStepPartListPresentation(model: fixture.model, host: host(assemblyScale: 2)).placementKey

            (alloc as! LPubCalloutAlloc).lPubCommandString = "CALLOUT ALLOC LOCAL HORIZONTAL"

            #expect(LDrawStepPartListPresentation(model: fixture.model, host: host(assemblyScale: 2)).placementKey
                    != before)
        }

        @Test("The placement key changes when a PLACEMENT line of the step does")
        func placementKeyFollowsTheLines() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let placement = lpub("CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.1 0.2")
            let fixture = calloutModel([pageSize(8.5, 11)], inside: [placement])
            let before = LDrawStepPartListPresentation(model: fixture.model, host: host(assemblyScale: 2)).placementKey

            #expect(before.contains("0.1 0.2"))
            #expect(LDrawStepPartListPresentation(model: fixture.model, host: host(assemblyScale: 2)).placementKey
                    == before)

            (placement as! LPubPlacement).lPubCommandString = "CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.3 0.2"

            #expect(LDrawStepPartListPresentation(model: fixture.model, host: host(assemblyScale: 2)).placementKey
                    != before)
        }

        /// Any line that resizes a box centered with the assembly moves the
        /// step's center.
        @Test("The placement key changes when a box centered with the assembly changes size")
        func placementKeyFollowsTheBoxSize() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let border = lpub("CALLOUT BORDER LOCAL SQUARE Black 0.03 MARGINS 0.05 0.05")
            let fixture = calloutModel([pageSize(8.5, 11)], inside: [border])
            var measured = host(assemblyScale: 2)
            measured.assemblyRect = Box2(origin: Point2(x: 100, y: 200), size: Size2(width: 60, height: 40))

            let before = LDrawStepPartListPresentation(model: fixture.model, host: measured).placementKey

            #expect(LDrawStepPartListPresentation(model: fixture.model, host: measured).placementKey == before)

            (border as! LPubCalloutBorder).lPubCommandString = "CALLOUT BORDER LOCAL SQUARE Black 0.03 MARGINS 0.5 0.5"

            #expect(LDrawStepPartListPresentation(model: fixture.model, host: measured).placementKey != before)
        }

        @Test("The placement key is the same at every zoom")
        func placementKeyIgnoresTheZoom() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let fixture = calloutModel([pageSize(8.5, 11)])
            var near = host(assemblyScale: 2)
            near.assemblyRect = Box2(origin: Point2(x: 100, y: 200), size: Size2(width: 60, height: 40))
            var far = host(assemblyScale: 0.7)
            far.assemblyRect = Box2(origin: Point2(x: 35, y: 70), size: Size2(width: 21, height: 14))

            let presentation = LDrawStepPartListPresentation(model: fixture.model, host: near)

            #expect(presentation.calloutBoxes.count == 1)
            #expect(presentation.placementKey.contains("x"), "the box's size is in the key")
            #expect(LDrawStepPartListPresentation(model: fixture.model, host: far).placementKey
                    == presentation.placementKey)
        }

        @Test("An ASSEM PLACEMENT line is part of the placement key")
        func placementKeyHasTheAssemblyLine() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let line = lpub("ASSEM PLACEMENT LOCAL CENTER PAGE INSIDE 0.1 -0.05")
            let plain = steppedModel(firstStep: [pageSize(8.5, 11)])
            let moved = steppedModel(firstStep: [pageSize(8.5, 11)], secondStep: [line])

            #expect(LDrawStepPartListPresentation(model: plain, host: host(assemblyScale: 2)).placementKey == "")
            #expect(LDrawStepPartListPresentation(model: moved, host: host(assemblyScale: 2)).placementKey
                    .contains("0.1 -0.05"))
        }

        @Test("A callout drag shows the box where it is held, even off the page")
        func draggedCalloutIsPreviewed() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            let fixture = calloutModel([pageSize(8.5, 11)])
            var measured = host(assemblyScale: 2)
            measured.assemblyRect = Box2(origin: Point2(x: 450, y: 380), size: Size2(width: 60, height: 40))

            let page = LDrawStepPartListPresentation(model: fixture.model, host: measured).pageRect

            measured.hasCalloutPreview = true
            measured.calloutPreviewBox = 0
            measured.calloutPreviewPoint = Point2(x: page.origin.x + 30, y: page.origin.y + 40)

            let held = try #require(LDrawStepPartListPresentation(model: fixture.model, host: measured)
                .calloutBoxes.first).frameRect
            #expect(abs(held.origin.x - (page.origin.x + 30)) < 0.001)
            #expect(abs(held.origin.y - (page.origin.y + 40)) < 0.001)

            // LPub3D lets a box leave the page, so the drag does too.
            measured.calloutPreviewPoint = Point2(x: page.origin.x - 500, y: page.origin.y - 500)

            let outside = try #require(LDrawStepPartListPresentation(model: fixture.model, host: measured)
                .calloutBoxes.first).frameRect
            #expect(abs(outside.origin.x - (page.origin.x - 500)) < 0.001)
            #expect(abs(outside.origin.y - (page.origin.y - 500)) < 0.001)
        }

        @Test("A step that hides its list is still shown for its callouts")
        func calloutsKeepTheOverlayUp() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(false)

            let hidden = steppedModel(secondStep: [show(false, scope: .local)])
            #expect(LDrawStepPartListPolicy.showsAnything(inModel: hidden) == false)

            let fixture = calloutModel([show(false, scope: .local)])
            #expect(LDrawStepPartListPolicy.showsAnything(inModel: fixture.model) == true)

            LDrawStepPartList.setEnabled(false)
            #expect(LDrawStepPartListPolicy.showsAnything(inModel: fixture.model) == false)
        }

        @Test("A step with no callouts has no boxes")
        func noCalloutsNoBoxes() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(false)

            let presentation = LDrawStepPartListPresentation(model: steppedModel(), host: host(assemblyScale: 1))

            #expect(presentation.calloutBoxes.isEmpty)
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
