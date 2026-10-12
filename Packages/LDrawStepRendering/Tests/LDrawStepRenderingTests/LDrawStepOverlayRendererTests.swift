//
//  LDrawStepOverlayRendererTests.swift
//  LDrawStepRenderingTests
//
//  Where the overlay's drawing lands in a context.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//

import Testing
import Foundation
import CoreGraphics
import LDrawCore
import LDrawFeatures
import LDrawStepRendering

extension StepOverlayTests {

    @Suite("Drawing the overlay")
    struct LDrawStepOverlayRendererTests {

        private let viewSize = Size2(width: 400, height: 300)
        private let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

        private func entry(_ name: String, quantity: UInt = 1, isMissing: Bool = false) -> LDrawStepPartListEntry {
            LDrawStepPartListEntry(partName: name,
                                   displayTitle: name,
                                   color: nil,
                                   quantity: quantity,
                                   modelBounds: isMissing ? InvalidBox : Box3(min: Point3(x: 0, y: 0, z: 0),
                                                                              max: Point3(x: 40, y: 24, z: 20)),
                                   isMissing: isMissing,
                                   isSubmodel: false)
        }

        private func layout(_ entries: [LDrawStepPartListEntry]) -> LDrawStepPartListLayout {
            LDrawStepPartListLayout.layout(forEntries: entries,
                                           constraint: LDrawStepPartListLayout.defaultConstraint(),
                                           viewTransform: IdentityMatrix4,
                                           metrics: LDrawStepPartListLayout.defaultMetrics())
        }

        // MARK: - The way back

        @Test("With no title there is no button")
        func noButton() {
            let renderer = LDrawStepOverlayRenderer()
            let canvas = Canvas(width: 400, height: 300)

            renderer.drawCallouts(in: canvas.context, viewSize: viewSize)

            #expect(renderer.returnButtonRect(forViewSize: viewSize).size.width == 0)
            #expect(canvas.inkBounds == nil)
        }

        @Test("The button sits in the bottom left corner, as far in as the list is from the top")
        func buttonPlace() {
            let renderer = LDrawStepOverlayRenderer()
            renderer.returnTitle = "Step 3 of main.ldr"

            let button = renderer.returnButtonRect(forViewSize: viewSize)
            let margin = LDrawStepPartListPolicy.frameInset(forPointsPerPageInch: 0)

            #expect(button.origin.x == margin)
            #expect(button.origin.y + button.size.height == viewSize.height - margin)
            #expect(button.size.width > button.size.height)
        }

        @Test("The button is drawn where it is said to be")
        func buttonDrawing() throws {
            let renderer = LDrawStepOverlayRenderer()
            renderer.returnTitle = "Step 3 of main.ldr"
            renderer.listBackgroundColor = white

            let canvas = Canvas(width: 400, height: 300)
            renderer.drawCallouts(in: canvas.context, viewSize: viewSize)

            let button = renderer.returnButtonRect(forViewSize: viewSize)
            let ink = try #require(canvas.inkBounds)

            #expect(box(button, holds: ink))
            #expect(ink.size.width > button.size.width - 3)
            #expect(ink.size.height > button.size.height - 3)
        }

        // MARK: - A list's labels

        @Test("A list's counts are drawn in their cells' label frames")
        func labelsOfAList() throws {
            let packed = layout([entry("3001.dat", quantity: 2), entry("3002.dat", quantity: 12)])
            let canvas = Canvas(width: 400, height: 300)

            LDrawStepOverlayRenderer.drawLabels(of: packed,
                                                chrome: LDrawStepPartListPolicy.defaultChrome(),
                                                contentWidth: 400,
                                                overflowFormat: "+%lu",
                                                in: canvas.context)

            let ink = try #require(canvas.inkBounds)
            let labels = packed.placements.map(\.labelFrame)
            let left = try #require(labels.map(\.origin.x).min())
            let top = try #require(labels.map(\.origin.y).min())
            let right = try #require(labels.map { $0.origin.x + $0.size.width }.max())
            let bottom = try #require(labels.map { $0.origin.y + $0.size.height }.max())
            let around = Box2(origin: Point2(x: left, y: top), size: Size2(width: right - left, height: bottom - top))

            #expect(packed.placements.count == 2)
            #expect(box(around, holds: ink))
        }

        @Test("A part that is missing gets a box where its picture would be")
        func missingPart() throws {
            let packed = layout([entry("nosuch.dat", isMissing: true)])
            let placement = try #require(packed.placements.first)
            let canvas = Canvas(width: 400, height: 300)

            LDrawStepOverlayRenderer.drawLabels(of: packed,
                                                chrome: LDrawStepPartListPolicy.defaultChrome(),
                                                contentWidth: 400,
                                                overflowFormat: "+%lu",
                                                in: canvas.context)

            let ink = try #require(canvas.inkBounds)

            #expect(ink.origin.x <= placement.iconFrame.origin.x + 2)
            #expect(ink.origin.y <= placement.iconFrame.origin.y + 2)
        }

        @Test("An empty list draws nothing")
        func emptyList() {
            let canvas = Canvas(width: 400, height: 300)

            LDrawStepOverlayRenderer.drawLabels(of: layout([]),
                                                chrome: LDrawStepPartListPolicy.defaultChrome(),
                                                contentWidth: 400,
                                                overflowFormat: "+%lu",
                                                in: canvas.context)

            #expect(canvas.inkBounds == nil)
        }

        @Test("Drawing leaves the context as it found it")
        func contextIsRestored() {
            let renderer = LDrawStepOverlayRenderer()
            renderer.returnTitle = "Back"

            let canvas = Canvas(width: 400, height: 300)
            let before = canvas.context.ctm

            renderer.drawPageAndFrame(in: canvas.context, viewSize: viewSize)
            renderer.drawCallouts(in: canvas.context, viewSize: viewSize)

            #expect(canvas.context.ctm == before)
        }
    }
}
