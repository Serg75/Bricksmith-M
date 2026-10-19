//
//  LDrawStepPartListStyleTests.swift
//  LDrawFeaturesTests
//
//  How the step's parts list looks on LPub3D's page: which PLI lines are in
//  force for the step, what LPub3D draws when the file says nothing, and what
//  the presentation gives the host.
//
//  Created by Sergey Slobodenyuk on 2026-10-15.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawTestSupport

extension StepPartListStaticSettings {

    @Suite("A parts list's style", .serialized)
    final class LDrawStepPartListStyleTests {

        deinit {
            LDrawStepPartList.setEnabled(false)
            LDrawStepPartList.setUsesLPubScale(false)
            LDrawStepPartList.setShowsPageNumber(false)
        }

        // MARK: - Fixtures

        /// Parses the text, so the line gets the class the file would give it.
        private func lpub(_ text: String) -> LDrawDirective {
            let lines = ["0 !LPUB " + text, "0 STEP"]
            let step = LDrawStep(lines: lines, in: NSRange(location: 0, length: lines.count), parentGroup: nil)

            return (step!.subdirectives() as! [LDrawDirective])[0]
        }

        private func part() -> LDrawPart {
            let part = LDrawPart()
            part.setDisplayName("3001.dat", parse: false, in: nil)
            return part
        }

        /// A two-step model displaying its second step, with these lines in
        /// each step.
        private func model(first: [String] = [], second: [String] = []) -> LDrawModel {
            let model = LDrawModel()

            for lines in [first, second] {
                let step = model.addStep()
                for line in lines {
                    step.add(lpub(line))
                }
                step.add(part() as LDrawDirective)
            }
            model.setStepDisplay(true)
            model.setMaximumStepIndexForStepDisplay(1)
            return model
        }

        private func expectColor(_ color: LPubColorComponents,
                                 _ red: Double, _ green: Double, _ blue: Double,
                                 sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(abs(color.red - red) < 0.001, sourceLocation: sourceLocation)
            #expect(abs(color.green - green) < 0.001, sourceLocation: sourceLocation)
            #expect(abs(color.blue - blue) < 0.001, sourceLocation: sourceLocation)
        }

        private func host(assembly: Box2? = nil) -> LDrawStepPartListHostState {
            var host = LDrawStepPartListHostState()
            host.viewSize = Size2(width: 1000, height: 800)
            host.assemblyScale = 1
            host.pageCenterInView = Point2(x: 500, y: 400)
            if let assembly {
                host.assemblyRect = assembly
            }
            return host
        }

        /// The list of a step on a letter page, with these lines.
        private func onPage(_ lines: [String], assembly: Box2? = nil) -> LDrawStepPartListPresentation {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)

            return LDrawStepPartListPresentation(model: model(first: ["PAGE SIZE 8.5 11"] + lines),
                                                 host: host(assembly: assembly))
        }

        private func expectNear(_ value: Double, _ expected: Double,
                                sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(abs(value - expected) < 1e-6, "\(value) is not \(expected)", sourceLocation: sourceLocation)
        }

        // MARK: - LPub3D's own style

        @Test("With no lines the list is LPub3D's: a thin black square, white inside, bold Arial 36")
        func defaults() {
            let style = LDrawStepPartListStyle(visibleStepOf: model())

            #expect(style.borderShape == .square)
            #expect(style.borderLineStyle == .solid)
            expectColor(style.borderColor, 0, 0, 0)
            #expect(abs(style.borderThickness - 1.0 / 32.0) < 1e-9)
            #expect(style.cornerRadius == 0)
            #expect(abs(style.borderMargins.width - 0.05) < 1e-9)
            #expect(style.hasFill)
            expectColor(style.fillColor, 1, 1, 1)
            #expect(abs(style.margins.height - 0.05) < 1e-9)
            #expect(style.countText.fontFamily == "Arial")
            #expect(abs(style.countText.fontSize - 36.0 / 150.0) < 1e-9)
            #expect(style.countText.isBold)
            expectColor(style.countText.color, 0, 0, 0)
        }

        // MARK: - The file's lines

        @Test("The file's PLI lines style the list, in its unit and resolution")
        func fileLinesApply() {
            let style = LDrawStepPartListStyle(visibleStepOf: model(first: [
                "RESOLUTION GLOBAL 300 DPI",
                "PLI BORDER GLOBAL ROUND 2 #336699 0.02 30 MARGINS 0.1 0.2",
                "PLI BACKGROUND GLOBAL COLOR #ffffcc",
                "PLI MARGINS GLOBAL 0.3 0.4",
                "PLI INSTANCE_COUNT FONT GLOBAL \"Helvetica,60,-1,5,50,0,0,0,0,0\"",
                "PLI INSTANCE_COUNT FONT_COLOR GLOBAL #ff0000",
            ]))

            #expect(style.borderShape == .round)
            #expect(style.borderLineStyle == .dash)
            expectColor(style.borderColor, 0.2, 0.4, 0.6)
            #expect(abs(style.borderThickness - 0.02) < 1e-9)
            #expect(abs(style.cornerRadius - 30.0 / 300.0) < 1e-9)
            #expect(abs(style.borderMargins.height - 0.2) < 1e-9)
            expectColor(style.fillColor, 1, 1, 0.8)
            #expect(abs(style.margins.width - 0.3) < 1e-9)
            #expect(style.countText.fontFamily == "Helvetica")
            #expect(abs(style.countText.fontSize - 60.0 / 300.0) < 1e-9)
            #expect(style.countText.isBold == false)
            expectColor(style.countText.color, 1, 0, 0)
        }

        @Test("A LOCAL line styles its own step only")
        func localLineEndsWithItsStep() {
            let local = LDrawStepPartListStyle(visibleStepOf: model(second: ["PLI BORDER LOCAL NONE"]))
            #expect(local.borderShape == .none)
            #expect(local.borderThickness == 0)

            let carried = model(first: ["PLI BORDER LOCAL NONE"])
            #expect(LDrawStepPartListStyle(visibleStepOf: carried).borderShape == .square)
        }

        @Test("A see-through list has no fill")
        func transparentBackground() {
            let style = LDrawStepPartListStyle(visibleStepOf: model(first: ["PLI BACKGROUND TRANSPARENT"]))
            #expect(style.hasFill == false)

            let chrome = style.chrome(from: LDrawStepPartListPolicy.defaultChrome(), pointsPerPageInch: 100)
            #expect(chrome.fill == .clear)
        }

        @Test("CALLOUT and PLI lines keep to their own boxes")
        func branchesStayApart() throws {
            let style = LDrawStepPartListStyle(visibleStepOf: model(first: [
                "CALLOUT BORDER GLOBAL ROUND #ff0000 0.1 15",
                "CALLOUT BACKGROUND GLOBAL TRANSPARENT",
                "CALLOUT MARGINS GLOBAL 0.5 0.5",
            ]))

            #expect(style.borderShape == .square)
            #expect(style.hasFill)
            #expect(abs(style.margins.width - 0.05) < 1e-9)
        }

        // MARK: - What the host draws

        @Test("The metrics and chrome take the padding, the count's room, the outline and the fill")
        func appliedToMetricsAndChrome() {
            let style = LDrawStepPartListStyle(visibleStepOf: model(first: [
                "PLI BORDER GLOBAL ROUND 3 #336699 0.04 15 MARGINS 0.1 0.2",
                "PLI BACKGROUND GLOBAL COLOR #ccccff",
            ]))
            let scale = 100.0
            let metrics = style.metrics(from: LDrawStepPartListLayout.defaultMetrics(), pointsPerPageInch: scale)
            let chrome = style.chrome(from: LDrawStepPartListPolicy.defaultChrome(), pointsPerPageInch: scale)

            // The larger margin and the line, on every side.
            #expect(abs(metrics.framePadding - 24) < 1e-9)
            #expect(abs(metrics.labelHeight - style.countText.size(forCharacterCount: 1).height * scale) < 1e-9)
            #expect(abs(chrome.borderWidth - 4) < 1e-9)
            #expect(abs(chrome.cornerRadius - 15.0 / 150.0 * scale) < 1e-9)
            #expect(chrome.borderLineStyle == LPubLineStyle.dot.rawValue)
            #expect(chrome.fill == .color)
            #expect(abs(chrome.fillRGBA.2 - 1) < 1e-9)
        }

        @Test("The size badges take the font and color of PLI ANNOTATE")
        func annotationFont() throws {
            let style = LDrawStepPartListStyle(visibleStepOf: model(first: [
                "RESOLUTION GLOBAL 300 DPI",
                "PLI ANNOTATE FONT GLOBAL \"Times,30,-1,5,50,1,0,0,0,0\"",
                "PLI ANNOTATE FONT_COLOR GLOBAL \"#0080ff\"",
            ]))
            let text = try #require(style.annotationText)

            #expect(text.fontFamily == "Times")
            expectNear(text.fontSize, 30.0 / 300.0)
            #expect(text.isBold == false)
            #expect(text.isItalic)
            #expect(style.hasAnnotationColor)
            expectColor(style.annotationColor, 0, 128.0 / 255.0, 1)

            // The count keeps its own font.
            expectNear(style.countText.fontSize, 36.0 / 300.0)

            let scale = 100.0
            let plainMetrics = LDrawStepPartListLayout.defaultMetrics()
            let metrics = style.metrics(from: plainMetrics, pointsPerPageInch: scale)
            let chrome = style.chrome(from: LDrawStepPartListPolicy.defaultChrome(), pointsPerPageInch: scale)
            let one = text.size(forCharacterCount: 1)
            let two = text.size(forCharacterCount: 2)

            expectNear(metrics.annotationHeight,
                       one.height * scale + plainMetrics.annotationHeight - plainMetrics.labelHeight)
            expectNear(metrics.annotationCharacterWidth, (two.width - one.width) * scale)
            expectNear(chrome.annotationPointSize, 0.1 * scale)
            expectNear(chrome.labelPointSize, 36.0 / 300.0 * scale)
            expectNear(chrome.annotationTextRGBA.1, 128.0 / 255.0)
            expectNear(chrome.annotationTextRGBA.2, 1)
        }

        @Test("With no ANNOTATE line a badge is written as big as a count, in the chrome's color")
        func noAnnotationFont() {
            let style = LDrawStepPartListStyle(visibleStepOf: model())
            let plainChrome = LDrawStepPartListPolicy.defaultChrome()
            let metrics = style.metrics(from: LDrawStepPartListLayout.defaultMetrics(), pointsPerPageInch: 100)
            let chrome = style.chrome(from: plainChrome, pointsPerPageInch: 100)

            #expect(style.annotationText == nil)
            #expect(style.hasAnnotationColor == false)
            expectNear(metrics.annotationCharacterWidth, metrics.labelCharacterWidth)
            expectNear(chrome.annotationPointSize, plainChrome.annotationPointSize)
            expectNear(chrome.annotationTextRGBA.0, plainChrome.annotationTextRGBA.0)
        }

        @Test("A color alone colors the badges and leaves their font")
        func annotationColorAlone() {
            let style = LDrawStepPartListStyle(visibleStepOf: model(first: ["PLI ANNOTATE FONT_COLOR GLOBAL #ff0000"]))
            let chrome = style.chrome(from: LDrawStepPartListPolicy.defaultChrome(), pointsPerPageInch: 100)

            #expect(style.annotationText == nil)
            #expect(style.hasAnnotationColor)
            expectNear(chrome.annotationTextRGBA.0, 1)
            expectNear(chrome.annotationTextRGBA.1, 0)
        }

        @Test("The callouts keep their own badge size when the list's badges take the file's")
        func annotationFontStaysInTheList() throws {
            let presentation = onPage(["PLI ANNOTATE FONT GLOBAL \"Arial,90,-1,5,50,0,0,0,0,0\""])

            #expect(try #require(presentation.annotationText).fontFamily == "Arial")
            #expect(presentation.chrome.annotationPointSize > presentation.calloutChrome.annotationPointSize)
        }

        @Test("On the page the list is drawn in the file's style, and a wide margin moves it in")
        func presentationOnThePage() throws {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)

            let plain = LDrawStepPartListPresentation(model: model(first: ["PAGE SIZE 8.5 11"]), host: host())
            let styled = LDrawStepPartListPresentation(model: model(first: [
                "PAGE SIZE 8.5 11",
                "PLI BORDER GLOBAL SQUARE 1 #ff0000 0.1 MARGINS 0.2 0.2",
                "PLI MARGINS GLOBAL 0.5 0.25",
                "PLI INSTANCE_COUNT FONT_COLOR GLOBAL #00ff00",
            ]), host: host())

            #expect(plain.isOnPage && styled.isOnPage)

            let inch = styled.pointsPerPageInch
            let plainFrame = plain.frameRect
            let frame = styled.frameRect
            let content = styled.contentRect

            // LPub3D's own look: a white fill and a square black line.
            #expect(plain.chrome.fill == .color)
            #expect(plain.chrome.cornerRadius == 0)
            #expect(try #require(plain.countText).fontSize > 0)

            #expect(abs(frame.origin.x - plainFrame.origin.x - 0.45 * inch) < 1e-6)
            #expect(abs(frame.origin.y - plainFrame.origin.y - 0.2 * inch) < 1e-6)
            #expect(abs(content.origin.x - frame.origin.x - 0.3 * inch) < 1e-6)
            #expect(abs(styled.chrome.borderWidth - 0.1 * inch) < 1e-6)
            #expect(abs(styled.chrome.borderRGBA.0 - 1) < 1e-9)
            expectColor(try #require(styled.countText).color, 0, 1, 0)
        }

        // MARK: - Where the list goes

        @Test("PAGE MARGINS move the list in from the page's corner, when wider than the list's")
        func pageMarginsMoveTheList() {
            let presentation = onPage(["PAGE MARGINS GLOBAL 0.35 0.15", "PLI MARGINS GLOBAL 0.2 0.2"])
            let inch = presentation.pointsPerPageInch
            let page = presentation.pageRect
            let frame = presentation.frameRect

            expectNear(frame.origin.x - page.origin.x, 0.35 * inch)
            expectNear(frame.origin.y - page.origin.y, 0.2 * inch)
            #expect(presentation.growsLeftward == false)
            #expect(presentation.growsUpward == false)
        }

        @Test("A list placed in the page's bottom right corner grows up and to the left")
        func bottomRightOfThePage() {
            let presentation = onPage(["PLI PLACEMENT BOTTOM_RIGHT PAGE INSIDE"])
            let inch = presentation.pointsPerPageInch
            let page = presentation.pageRect
            let frame = presentation.frameRect

            expectNear(page.origin.x + page.size.width - (frame.origin.x + frame.size.width), 0.05 * inch)
            expectNear(page.origin.y + page.size.height - (frame.origin.y + frame.size.height), 0.05 * inch)
            #expect(presentation.growsLeftward)
            #expect(presentation.growsUpward)
        }

        @Test("An offset moves the list by a share of the page")
        func offsetOnThePage() {
            let plain = onPage(["PLI PLACEMENT TOP_LEFT PAGE INSIDE"])
            let moved = onPage(["PLI PLACEMENT TOP_LEFT PAGE INSIDE 0.1 0.05"])
            let page = plain.pageRect

            expectNear(moved.frameRect.origin.x - plain.frameRect.origin.x, 0.1 * page.size.width)
            expectNear(moved.frameRect.origin.y - plain.frameRect.origin.y, 0.05 * page.size.height)
        }

        @Test("A list placed against what is not drawn goes in the page's top left corner")
        func unreadPlacementFallsBack() {
            let plain = onPage([])
            let besideNumber = onPage(["PLI PLACEMENT LOCAL RIGHT TOP STEP_NUMBER OUTSIDE -1.82442 1.02133"])
            let outsidePage = onPage(["PLI PLACEMENT TOP_LEFT PAGE OUTSIDE"])

            #expect(besideNumber.frameRect.origin.x == plain.frameRect.origin.x)
            #expect(besideNumber.frameRect.origin.y == plain.frameRect.origin.y)
            #expect(outsidePage.frameRect.origin.x == plain.frameRect.origin.x)
        }

        @Test("A list placed against the assembly sits beside it, and is centered with it")
        func besideTheAssembly() {
            let assembly = Box2(origin: Point2(x: 450, y: 350), size: Size2(width: 100, height: 100))
            let presentation = onPage(["PLI PLACEMENT LEFT TOP ASSEM OUTSIDE"], assembly: assembly)
            let inch = presentation.pointsPerPageInch
            let frame = presentation.frameRect

            expectNear(assembly.origin.x - (frame.origin.x + frame.size.width), 0.05 * inch)
            expectNear(frame.origin.y, assembly.origin.y)
            #expect(presentation.growsLeftward)
            #expect(presentation.growsUpward == false)

            // The step's middle is the middle of the assembly and the list together.
            let left = frame.origin.x
            let right = assembly.origin.x + assembly.size.width
            let bottom = max(assembly.origin.y + assembly.size.height, frame.origin.y + frame.size.height)

            #expect(presentation.hasStepCenter)
            expectNear(presentation.stepCenterInView.x, (left + right) / 2)
            expectNear(presentation.stepCenterInView.y, (assembly.origin.y + bottom) / 2)
            #expect(presentation.placementKey.contains("PLI PLACEMENT LEFT TOP ASSEM OUTSIDE"))
        }

        /// A one-step model of many different parts on a letter page, with
        /// these lines.
        private func widePage(_ lines: [String], assembly: Box2? = nil) -> LDrawStepPartListPresentation {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)

            let model = LDrawModel()
            let step = model.addStep()

            for line in ["PAGE SIZE 8.5 11"] + lines {
                step.add(lpub(line))
            }
            for index in 0..<40 {
                let part = LDrawPart()
                part.setDisplayName("part\(index).dat", parse: false, in: nil)
                step.add(part as LDrawDirective)
            }
            model.setStepDisplay(true)
            model.setMaximumStepIndexForStepDisplay(0)

            return LDrawStepPartListPresentation(model: model, host: host(assembly: assembly))
        }

        @Test("A list too wide for the page less its margins wraps, and is not cut")
        func wideListWraps() throws {
            let presentation = widePage(["PLI MARGINS GLOBAL 1.0 1.0", "PLI CONSTRAIN LOCAL COLS 40"])
            let layout = try #require(presentation.layout)
            let room = presentation.pageRect.size.width - 2 * presentation.pointsPerPageInch

            #expect(layout.rowCount > 1)
            #expect(layout.frameSize.width <= room + 1e-6)
            #expect(presentation.frameRect.size.width == layout.frameSize.width)
            #expect(presentation.frameRect.size.height == layout.frameSize.height)
        }

        @Test("A WIDTH wider than the page less its margins is narrowed to it")
        func widthIsNarrowedToTheRoom() throws {
            let presentation = widePage(["PLI MARGINS GLOBAL 1.0 1.0", "PLI CONSTRAIN LOCAL WIDTH 8"])
            let layout = try #require(presentation.layout)
            let room = presentation.pageRect.size.width - 2 * presentation.pointsPerPageInch

            #expect(layout.frameSize.width <= room + 1e-6)
            #expect(presentation.frameRect.size.width == layout.frameSize.width)
        }

        @Test("A list beside the assembly is drawn at its own size")
        func listOnTheAssemblyIsNotCut() throws {
            let assembly = Box2(origin: Point2(x: 450, y: 350), size: Size2(width: 100, height: 100))
            let presentation = widePage(["PLI PLACEMENT BOTTOM LEFT ASSEM OUTSIDE"], assembly: assembly)
            let layout = try #require(presentation.layout)

            #expect(presentation.frameRect.size.width == layout.frameSize.width)
            #expect(presentation.frameRect.size.height == layout.frameSize.height)
        }

        /// The width a drag of the right edge far past the page asks for.
        private func widthDraggedFarRight(_ presentation: LDrawStepPartListPresentation) -> Double {
            let frame = presentation.frameRect
            let edge = Point2(x: frame.origin.x + frame.size.width, y: frame.origin.y + frame.size.height / 2)
            let tracker = LDrawStepPartListResizeTracker()

            #expect(tracker.begin(at: edge, presentation: presentation) == .widthEdge)

            let inches = tracker.inchesForDrag(to: Point2(x: edge.x + 5000, y: edge.y), presentation: presentation)
            tracker.end()
            return inches
        }

        @Test("A drag stops at the page less the larger margins, wide or narrow")
        func dragStopsAtTheRoom() {
            let wide = widePage(["PLI MARGINS GLOBAL 1.0 1.0"])
            let inch = wide.pointsPerPageInch

            expectNear(wide.allowedFrameSize.width, wide.pageRect.size.width - 2 * inch)
            expectNear(widthDraggedFarRight(wide), 8.5 - 2.0)

            // Narrower than LPub3D's own 0.05 inch, so the drag goes further.
            let narrow = widePage(["PAGE MARGINS GLOBAL 0.01 0.01", "PLI MARGINS GLOBAL 0.01 0.01"])
            expectNear(widthDraggedFarRight(narrow), 8.5 - 0.02)
        }

        @Test("A style that resizes a list centered with the assembly changes the placement key")
        func styleIsInTheKey() {
            let assembly = Box2(origin: Point2(x: 450, y: 350), size: Size2(width: 100, height: 100))
            let line = "PLI PLACEMENT LEFT TOP ASSEM OUTSIDE"
            let plain = onPage([line], assembly: assembly).placementKey

            for change in ["PLI INSTANCE_COUNT FONT GLOBAL \"Arial,60,-1,5,75,0,0,0,0,0\"",
                           "PLI BORDER GLOBAL SQUARE Black 0.1 MARGINS 0.2 0.2",
                           "PLI MARGINS GLOBAL 0.3 0.3",
                           "PAGE MARGINS GLOBAL 0.4 0.4"] {
                #expect(onPage([line, change], assembly: assembly).placementKey != plain, "\(change)")
            }

            // A list against the page does not move the step.
            let onPageKey = onPage(["PLI PLACEMENT TOP_LEFT PAGE INSIDE"]).placementKey
            let restyled = onPage(["PLI PLACEMENT TOP_LEFT PAGE INSIDE", "PLI MARGINS GLOBAL 0.3 0.3"]).placementKey
            #expect(onPageKey == restyled)
        }

        @Test("A list that grows leftward is resized from its left edge")
        func resizeFromTheLeftEdge() throws {
            let presentation = onPage(["PLI PLACEMENT TOP_RIGHT PAGE INSIDE"])
            let frame = presentation.frameRect
            let middleY = frame.origin.y + frame.size.height / 2
            let leftEdge = Point2(x: frame.origin.x, y: middleY)
            let rightEdge = Point2(x: frame.origin.x + frame.size.width, y: middleY)

            #expect(presentation.control(at: leftEdge) == .widthEdge)
            #expect(presentation.control(at: rightEdge) == .none)

            let pin = presentation.pinRect(forAxis: .width)
            #expect(abs(pin.origin.x + pin.size.width / 2 - frame.origin.x) < 1e-6)

            let tracker = LDrawStepPartListResizeTracker()
            #expect(tracker.begin(at: leftEdge, presentation: presentation) == .widthEdge)

            let wider = tracker.inchesForDrag(to: Point2(x: leftEdge.x - 40, y: middleY), presentation: presentation)
            let narrower = tracker.inchesForDrag(to: Point2(x: leftEdge.x + 40, y: middleY), presentation: presentation)

            #expect(wider > narrower)
            tracker.end()
        }

        // MARK: - The page's color

        @Test("A PAGE BACKGROUND COLOR line gives the page its color")
        func pageColor() {
            let style = LDrawStepPartListStyle(visibleStepOf: model(first: [
                "PAGE BACKGROUND GLOBAL COLOR \"#66ccff\"",
                "PLI BACKGROUND GLOBAL COLOR #ff0000",
                "CALLOUT BACKGROUND GLOBAL COLOR #00ff00",
            ]))

            #expect(style.hasPageColor)
            expectColor(style.pageColor, 0.4, 0.8, 1)
            expectColor(style.fillColor, 1, 0, 0)
        }

        @Test("With no color line, or another kind of background, the host keeps its own color")
        func noPageColor() {
            #expect(LDrawStepPartListStyle(visibleStepOf: model()).hasPageColor == false)
            #expect(LDrawStepPartListStyle(visibleStepOf: model(first: ["PAGE BACKGROUND GLOBAL TRANSPARENT"]))
                        .hasPageColor == false)
            #expect(LDrawStepPartListStyle(visibleStepOf: model(first: ["PAGE BACKGROUND GLOBAL PICTURE cover.png"]))
                        .hasPageColor == false)
        }

        @Test("A LOCAL page color holds for its own step")
        func localPageColor() {
            let local = LDrawStepPartListStyle(visibleStepOf: model(first: ["PAGE BACKGROUND GLOBAL COLOR #ffffff"],
                                                                    second: ["PAGE BACKGROUND LOCAL COLOR #000000"]))
            expectColor(local.pageColor, 0, 0, 0)

            let carried = model(first: ["PAGE BACKGROUND LOCAL COLOR #000000"])
            #expect(LDrawStepPartListStyle(visibleStepOf: carried).hasPageColor == false)
        }

        @Test("The presentation gives the page's color on the page only")
        func pageColorInThePresentation() {
            let presentation = onPage(["PAGE BACKGROUND GLOBAL COLOR #66ccff"])

            #expect(presentation.hasPageColor)
            expectColor(presentation.pageColor, 0.4, 0.8, 1)

            LDrawStepPartList.setUsesLPubScale(false)

            let offPage = LDrawStepPartListPresentation(model: model(first: ["PAGE BACKGROUND GLOBAL COLOR #66ccff"]),
                                                        host: host())
            #expect(offPage.hasPageColor == false)
        }

        @Test("Off the page the list keeps Bricksmith's own look")
        func presentationOffThePage() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(false)

            let presentation = LDrawStepPartListPresentation(model: model(first: [
                "PLI BORDER GLOBAL SQUARE 1 #ff0000 0.1",
                "PLI BACKGROUND GLOBAL COLOR #ff0000",
                "PLI ANNOTATE FONT GLOBAL \"Arial,90,-1,5,50,0,0,0,0,0\"",
            ]), host: host())

            #expect(presentation.isOnPage == false)
            #expect(presentation.chrome.fill == .host)
            #expect(presentation.chrome.borderWidth == LDrawStepPartListPolicy.defaultChrome().borderWidth)
            #expect(presentation.countText == nil)
            #expect(presentation.annotationText == nil)
        }

        // MARK: - The page's number

        private typealias NumberedPage = (file: LDrawFile, presentation: LDrawStepPartListPresentation)

        /// A file whose first model has `count` steps of one part each, showing
        /// the one before the last, on a letter page at 100 dots to the inch.
        /// The lines are in the first step. The caller keeps the file.
        private func numberedPage(_ lines: [String], steps count: Int = 2, showsNumber: Bool = true) -> NumberedPage {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            LDrawStepPartList.setShowsPageNumber(showsNumber)

            let file = LDrawFile()
            let model = LDrawMPDModel.model() as! LDrawMPDModel
            model.setModelName("main.ldr")
            file.addSubmodel(model)

            for index in 0..<count {
                let step = model.addStep()
                if index == 0 {
                    for line in ["PAGE SIZE 8.5 11", "RESOLUTION 100 DPI"] + lines {
                        step.add(lpub(line))
                    }
                }
                step.add(part() as LDrawDirective)
            }
            // A new model starts with an empty step of its own.
            model.setStepDisplay(true)
            model.setMaximumStepIndexForStepDisplay(UInt(model.steps().count - 2))

            return (file, LDrawStepPartListPresentation(model: model, host: host()))
        }

        @Test("The page's number is LPub3D's: bold Arial 24 in black, in the bottom right corner")
        func pageNumberDefaults() throws {
            let (file, presentation) = numberedPage([], steps: 3)
            let text = try #require(presentation.pageNumberText)
            let page = presentation.pageRect
            let number = presentation.pageNumberRect
            let margin = 0.05 * presentation.pointsPerPageInch

            withExtendedLifetime(file) {}
            #expect(presentation.pageNumber == "2")
            #expect(text.fontFamily == "Arial")
            expectNear(text.fontSize, 24.0 / 100.0)
            #expect(text.isBold)
            expectColor(text.color, 0, 0, 0)
            expectNear(number.origin.x + number.size.width, page.origin.x + page.size.width - margin)
            expectNear(number.origin.y + number.size.height, page.origin.y + page.size.height - margin)
        }

        @Test("A symbol outside plain ASCII takes the room of two characters")
        func textSizeCountsSymbols() {
            let text = LDrawStepPartListStyle(visibleStepOf: model()).countText

            expectNear(text.size(for: "12/3").width, text.size(forCharacterCount: 4).width)
            expectNear(text.size(for: "➟12").width, text.size(forCharacterCount: 4).width)
        }

        @Test("The page's number takes the file's font, color and margins")
        func pageNumberFromTheFile() throws {
            let (file, presentation) = numberedPage([
                "PAGE MARGINS 0.15 0.15",
                "PAGE NUMBER MARGINS 0.1 0.3",
                "PAGE NUMBER FONT \"Times,72,-1,5,50,0,0,0,0,0\"",
                "PAGE NUMBER FONT_COLOR \"#ff0000\"",
            ], steps: 3)
            let text = try #require(presentation.pageNumberText)
            let page = presentation.pageRect
            let number = presentation.pageNumberRect
            let scale = presentation.pointsPerPageInch

            withExtendedLifetime(file) {}
            #expect(text.fontFamily == "Times")
            expectNear(text.fontSize, 0.72)
            #expect(text.isBold == false)
            expectColor(text.color, 1, 0, 0)
            expectNear(number.size.width, text.size(forCharacterCount: 1).width * scale)

            // The larger of the page's margin and the number's, on each side.
            expectNear(number.origin.x + number.size.width, page.origin.x + page.size.width - 0.15 * scale)
            expectNear(number.origin.y + number.size.height, page.origin.y + page.size.height - 0.3 * scale)
        }

        @Test("PAGE NUMBER PLACEMENT puts the number, and an even page toggles it")
        func pageNumberPlacement() {
            let topLeft = numberedPage(["PAGE NUMBER PLACEMENT TOP_LEFT PAGE INSIDE"], steps: 3)
            let page = topLeft.presentation.pageRect
            let margin = 0.05 * topLeft.presentation.pointsPerPageInch

            expectNear(topLeft.presentation.pageNumberRect.origin.x, page.origin.x + margin)
            expectNear(topLeft.presentation.pageNumberRect.origin.y, page.origin.y + margin)

            let even = numberedPage(["PAGE TOGGLE_PAGE_NUMBER_PLACEMENT TRUE"], steps: 3)

            #expect(even.presentation.pageNumber == "2")
            expectNear(even.presentation.pageNumberRect.origin.x, even.presentation.pageRect.origin.x + margin)

            let odd = numberedPage(["PAGE TOGGLE_PAGE_NUMBER_PLACEMENT TRUE"], steps: 2)
            let oddRect = odd.presentation.pageNumberRect

            #expect(odd.presentation.pageNumber == "1")
            expectNear(oddRect.origin.x + oddRect.size.width,
                       odd.presentation.pageRect.origin.x + odd.presentation.pageRect.size.width - margin)
            withExtendedLifetime([topLeft.file, even.file, odd.file]) {}
        }

        @Test("No number when the file or the host hides it")
        func pageNumberHidden() {
            let hiddenByFile = numberedPage(["PAGE DISPLAY_PAGE_NUMBER FALSE"])
            let hiddenByHost = numberedPage([], showsNumber: false)

            #expect(hiddenByFile.presentation.pageNumber == nil)
            #expect(hiddenByHost.presentation.pageNumber == nil)
            #expect(hiddenByHost.presentation.pageNumberText == nil)
            withExtendedLifetime([hiddenByFile.file, hiddenByHost.file]) {}
        }
    }
}
