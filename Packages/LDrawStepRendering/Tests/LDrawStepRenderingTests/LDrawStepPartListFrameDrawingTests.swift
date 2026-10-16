//
//  LDrawStepPartListFrameDrawingTests.swift
//  LDrawStepRenderingTests
//
//  The parts list's frame drawn on LPub3D's page in the file's style.
//
//  Created by Sergey Slobodenyuk on 2026-10-15.
//

import Testing
import Foundation
import CoreGraphics
import LDrawCore
import LDrawFeatures
import LDrawStepRendering

extension StepOverlayTests {

    @Suite("Drawing the parts list's frame in the file's style")
    final class LDrawStepPartListFrameDrawingTests {

        private let viewSize = Size2(width: 1000, height: 800)

        init() {
            LDrawStepPartList.setEnabled(true)
            LDrawStepPartList.setUsesLPubScale(true)
        }

        deinit {
            LDrawStepPartList.setEnabled(false)
            LDrawStepPartList.setUsesLPubScale(false)
        }

        private func lpub(_ text: String) -> LDrawDirective {
            let lines = ["0 !LPUB " + text, "0 STEP"]
            let step = LDrawStep(lines: lines, in: NSRange(location: 0, length: lines.count), parentGroup: nil)

            return (step!.subdirectives() as! [LDrawDirective])[0]
        }

        /// A one-step model with these lines, on a page.
        private func presentation(_ lines: [String]) -> LDrawStepPartListPresentation {
            let model = LDrawModel()
            let step = model.addStep()

            for line in ["PAGE SIZE 12.048 8"] + lines {
                step.add(lpub(line))
            }
            step.add(CalloutFixture.part("3001.dat") as LDrawDirective)
            model.setStepDisplay(true)
            model.setMaximumStepIndexForStepDisplay(0)

            var host = LDrawStepPartListHostState()
            host.viewSize = viewSize
            host.assemblyScale = 1
            host.pageCenterInView = Point2(x: 500, y: 400)

            return LDrawStepPartListPresentation(model: model, host: host)
        }

        /// The color at a point of the canvas, as 0 to 255 values.
        private func pixel(_ canvas: Canvas, _ x: Double, _ y: Double) -> [UInt8] {
            let pixels = canvas.context.data!.bindMemory(to: UInt8.self, capacity: canvas.width * canvas.height * 4)
            let index = (Int(y) * canvas.width + Int(x)) * 4

            return Array(UnsafeBufferPointer(start: pixels + index, count: 4))
        }

        @Test("The roadster's lines: a light blue fill with round corners and no outline")
        func roadsterStyle() throws {
            let presentation = presentation([
                "RESOLUTION GLOBAL 170 DPI",
                "PLI BORDER GLOBAL ROUND #66ccff 0 10 MARGINS 0.118109 0.11811",
                "PLI BACKGROUND GLOBAL COLOR \"#b8e7ff\"",
                "PLI INSTANCE_COUNT FONT GLOBAL \"Arial,30,-1,5,50,0,0,0,0,0\"",
            ])
            let renderer = LDrawStepOverlayRenderer()
            let canvas = Canvas(width: Int(viewSize.width), height: Int(viewSize.height))

            renderer.presentation = presentation
            renderer.drawPageAndFrame(in: canvas.context, viewSize: viewSize)

            let frame = presentation.frameRect
            let inch = presentation.pointsPerPageInch

            #expect(presentation.chrome.borderWidth == 0)
            #expect(abs(presentation.chrome.cornerRadius - 10.0 / 170.0 * inch) < 1e-9)
            // The border's margins pad the list. The list's own margin is
            // LPub3D's, the same as the page's.
            #expect(abs(frame.origin.x - presentation.pageRect.origin.x - 0.05 * inch) < 1e-6)
            #expect(abs(presentation.contentRect.origin.x - frame.origin.x - 0.11811 * inch) < 1e-6)

            // In the padding, and just inside the edge where an outline would be.
            let padding = pixel(canvas, frame.origin.x + 2, frame.origin.y + frame.size.height / 2)
            let edge = pixel(canvas, frame.origin.x + frame.size.width / 2, frame.origin.y + 1.5)

            for color in [padding, edge] {
                #expect(color == [0xb8, 0xe7, 0xff, 0xff])
            }

            // The corner is cut round, so the page shows there.
            let corner = pixel(canvas, frame.origin.x + 0.5, frame.origin.y + 0.5)
            #expect(corner != [0xb8, 0xe7, 0xff, 0xff])

            let count = try #require(presentation.countText)
            #expect(count.isBold == false)
            #expect(abs(count.fontSize - 30.0 / 170.0) < 1e-9)
        }

        @Test("A dashed red outline is drawn in the frame's edge")
        func dashedOutline() {
            let presentation = presentation(["PLI BORDER GLOBAL SQUARE 2 #ff0000 0.05"])
            let renderer = LDrawStepOverlayRenderer()
            let canvas = Canvas(width: Int(viewSize.width), height: Int(viewSize.height))

            renderer.presentation = presentation
            renderer.drawPageAndFrame(in: canvas.context, viewSize: viewSize)

            let frame = presentation.frameRect
            let line = presentation.chrome.borderWidth
            var red = 0
            var white = 0

            // Along the top edge, in the inner part of the line, where the
            // fill shows between the dashes.
            for x in stride(from: frame.origin.x + line, to: frame.origin.x + frame.size.width - line, by: 1) {
                let color = pixel(canvas, x, frame.origin.y + line * 0.8)
                if color == [0xff, 0, 0, 0xff] { red += 1 }
                if color == [0xff, 0xff, 0xff, 0xff] { white += 1 }
            }

            #expect(red > 0)
            #expect(white > 0)
        }
    }
}
