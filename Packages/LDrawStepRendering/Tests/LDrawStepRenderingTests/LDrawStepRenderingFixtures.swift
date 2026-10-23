//
//  LDrawStepRenderingFixtures.swift
//  LDrawStepRenderingTests
//
//  A callout of a submodel laid out as a box, and a bitmap to draw into.
//
//  The directives are built in memory. Their parts name no file, so nothing is
//  loaded from a part library.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//

import Testing
import Foundation
import CoreGraphics
import LDrawCore
import LDrawFeatures
import LDrawStepEditing
import LDrawTestSupport

/// Holds every suite of this target, so they run one test at a time. A layout
/// keeps its lookups in one place for the whole process while it runs, and the
/// parts list's settings are process-wide too, so this also waits for the other
/// test targets' suites that use them.
@Suite(.serialized, .usesStepSettings) struct StepOverlayTests {}

/// A file whose main model calls out sub.ldr in its one step. The caller keeps
/// the file, which owns the models.
struct CalloutFixture {

    let file = LDrawFile()
    let main = LDrawMPDModel.model() as! LDrawMPDModel
    let sub = LDrawMPDModel.model() as! LDrawMPDModel
    let step: LDrawStep

    init(stepCount: Int = 1) {
        main.setModelName("main.ldr")
        file.addSubmodel(main)
        sub.setModelName("sub.ldr")
        file.addSubmodel(sub)

        for _ in 0..<stepCount {
            sub.addStep().add(CalloutFixture.part("3003.dat") as LDrawDirective)
        }

        let begin = LPubCallout()
        begin.lPubCommandString = "CALLOUT BEGIN"
        let end = LPubCallout()
        end.lPubCommandString = "CALLOUT END"

        step = main.addStep()

        for directive in [begin, CalloutFixture.part("sub.ldr"), end] as [LDrawDirective] {
            step.add(directive)
        }
    }

    static func part(_ name: String) -> LDrawPart {
        let color = LDrawColor()
        color.setColorCode(LDrawColorT(rawValue: 4)!)

        let part = LDrawPart()
        part.setDisplayName(name, parse: false, in: nil)
        part.setLDrawColor(color)
        return part
    }

    var callout: LDrawStepCallout {
        get throws { try #require(LDrawStepCallout.callouts(forStep: step).first) }
    }

    /// The callout's box on a page where one inch covers this many points.
    func box(pointsPerPageInch: Double = 100) throws -> LDrawStepCalloutBox {
        let metrics = LDrawStepPartListLayout.defaultMetrics()
        let nothing = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: 0, height: 0))
        let page = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: 1000, height: 800))
        let assembly = Box2(origin: Point2(x: 400, y: 300), size: Size2(width: 200, height: 100))
        let options = LDrawStepCalloutBoxOptions(metrics: metrics,
                                                 assemblyScale: metrics.baseScale * pointsPerPageInch / 100,
                                                 hostRect: page,
                                                 listFrame: nothing,
                                                 assemblyRect: assembly,
                                                 pointsPerPageInch: pointsPerPageInch,
                                                 listViewTransform: IdentityMatrix4,
                                                 showsLists: true)

        return try #require(LDrawStepCalloutBox.boxes(forCallouts: LDrawStepCallout.callouts(forStep: step),
                                                      inModel: main,
                                                      options: options).first)
    }
}

/// A clear bitmap whose top left corner is the origin, with y running down.
final class Canvas {

    let width: Int
    let height: Int
    let context: CGContext

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
    }

    /// Whether the pixel at this column and row, from the top left, was drawn on.
    func isInked(_ x: Int, _ y: Int) -> Bool {
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)

        return pixels[(y * width + x) * 4 + 3] != 0
    }

    /// The box around every pixel that was drawn on, or nil when none was.
    var inkBounds: Box2? {
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1

        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] != 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }

        guard maxX >= 0 else { return nil }

        return Box2(origin: Point2(x: Double(minX), y: Double(minY)),
                    size: Size2(width: Double(maxX - minX + 1), height: Double(maxY - minY + 1)))
    }
}

/// Whether `inner` lies in `outer`, give or take a pixel of soft edge.
func box(_ outer: Box2, holds inner: Box2) -> Bool {
    inner.origin.x >= outer.origin.x - 1
        && inner.origin.y >= outer.origin.y - 1
        && inner.origin.x + inner.size.width <= outer.origin.x + outer.size.width + 1
        && inner.origin.y + inner.size.height <= outer.origin.y + outer.size.height + 1
}

/// Makes an edit's changes, without the undo.
final class ApplyingHost: NSObject, LDrawStepCalloutEditHost {

    func add(_ newDirective: LDrawDirective, toParent parent: LDrawContainer, at index: Int) {
        parent.insert(newDirective, at: index)
    }

    func delete(_ doomedDirective: LDrawDirective) {
        doomedDirective.enclosingDirective()?.remove(doomedDirective)
    }

    func preserveDirectiveState(_ directive: LDrawDirective) {
    }
}
