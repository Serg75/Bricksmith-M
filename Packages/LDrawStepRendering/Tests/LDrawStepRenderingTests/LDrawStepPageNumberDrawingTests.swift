//
//  LDrawStepPageNumberDrawingTests.swift
//  LDrawStepRenderingTests
//
//  Where the page's number lands in a context.
//
//  Created by Sergey Slobodenyuk on 2026-10-18.
//

import Testing
import Foundation
import CoreGraphics
import LDrawCore
import LDrawFeatures
import LDrawStepRendering

extension StepOverlayTests {

    @Suite("Drawing the page's number", .serialized)
    final class LDrawStepPageNumberDrawingTests {

        deinit {
            LDrawStepPartList.setEnabled(false)
            LDrawStepPartList.setUsesLPubScale(false)
            LDrawStepPartList.setShowsPageNumber(false)
        }

        /// Parses the text, so the line gets the class the file would give it.
        private func lpub(_ text: String) -> LDrawDirective {
            let lines = ["0 !LPUB " + text, "0 STEP"]
            let step = LDrawStep(lines: lines, in: NSRange(location: 0, length: lines.count), parentGroup: nil)

            return (step!.subdirectives() as! [LDrawDirective])[0]
        }

        /// The second of three steps on a letter page, with no parts list. The
        /// caller keeps the file.
        private func presentation(showsNumber: Bool) -> (LDrawFile, LDrawStepPartListPresentation) {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
            LDrawStepPartList.setShowsPageNumber(showsNumber)

            let file = LDrawFile()
            let model = LDrawMPDModel.model() as! LDrawMPDModel
            model.setModelName("main.ldr")
            file.addSubmodel(model)

            for index in 0..<3 {
                let step = model.addStep()
                if index == 0 {
                    for text in ["PAGE SIZE 8.5 11", "PLI SHOW FALSE"] {
                        step.add(lpub(text))
                    }
                }
                step.add(CalloutFixture.part("3001.dat") as LDrawDirective)
            }
            // A new model starts with an empty step of its own.
            model.setStepDisplay(true)
            model.setMaximumStepIndexForStepDisplay(2)

            var host = LDrawStepPartListHostState()
            host.viewSize = Size2(width: 1000, height: 800)
            host.assemblyScale = 1
            host.pageCenterInView = Point2(x: 500, y: 400)

            return (file, LDrawStepPartListPresentation(model: model, host: host))
        }

        /// What the renderer draws on the page itself, leaving out the dimming
        /// around it.
        private func drawPage(of presentation: LDrawStepPartListPresentation) -> Canvas {
            let renderer = LDrawStepOverlayRenderer()
            renderer.presentation = presentation

            let canvas = Canvas(width: 1000, height: 800)
            let page = presentation.pageRect

            canvas.context.clip(to: CGRect(x: page.origin.x, y: page.origin.y,
                                           width: page.size.width, height: page.size.height))
            renderer.drawPageAndFrame(in: canvas.context, viewSize: Size2(width: 1000, height: 800))
            return canvas
        }

        @Test("The number is drawn in the room kept for it")
        func numberIsDrawn() throws {
            let (file, presentation) = presentation(showsNumber: true)
            let ink = try #require(drawPage(of: presentation).inkBounds)

            withExtendedLifetime(file) {}
            #expect(presentation.pageNumber == "2")
            #expect(box(presentation.pageNumberRect, holds: ink))
            #expect(ink.size.height > presentation.pageNumberRect.size.height / 3)
        }

        @Test("A host that does not show the number gets nothing on the page")
        func numberIsHidden() {
            let (file, presentation) = presentation(showsNumber: false)

            withExtendedLifetime(file) {}
            #expect(drawPage(of: presentation).inkBounds == nil)
        }
    }
}
