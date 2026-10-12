//
//  LDrawStepCalloutPictureStoreTests.swift
//  LDrawStepRenderingTests
//
//  When a callout's picture is drawn again, and when the one kept is shown.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//

import Testing
import Foundation
import CoreGraphics
import LDrawCore
import LDrawFeatures
import LDrawStepRendering

/// Hands out one-pixel pictures, and counts them.
private final class CountingSource: NSObject, LDrawStepCalloutPictureSource {

    var count = 0

    func newImage(of model: LDrawModel, center: Point3, zoomPercentage: Double, size: Size2,
                  scale: Double) -> CGImage? {
        count += 1

        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

        return context.makeImage()
    }
}

extension StepOverlayTests {

    @Suite("The pictures of a callout's box")
    struct LDrawStepCalloutPictureStoreTests {

        private func store(_ source: CountingSource) -> LDrawStepCalloutPictureStore {
            let store = LDrawStepCalloutPictureStore()
            store.source = source
            return store
        }

        @Test("A picture is drawn once, and kept")
        func drawnOnce() throws {
            let fixture = CalloutFixture()
            let box = try fixture.box()
            let source = CountingSource()
            let store = store(source)

            store.makePictures(for: [box], waitingForZoom: false)

            let drawn = source.count
            #expect(drawn == box.pictures.count)
            #expect(drawn > 0)

            store.makePictures(for: [try fixture.box()], waitingForZoom: false)

            #expect(source.count == drawn)
            #expect(store.image(for: try #require(box.pictures.first)) != nil)
        }

        @Test("While a zoom runs, the picture on show stands in for one of another size")
        func keptThroughAZoom() throws {
            let fixture = CalloutFixture()
            let source = CountingSource()
            let store = store(source)
            let small = try fixture.box(pointsPerPageInch: 100)
            let large = try fixture.box(pointsPerPageInch: 150)
            let smallPicture = try #require(small.pictures.first)
            let largePicture = try #require(large.pictures.first)

            store.makePictures(for: [small], waitingForZoom: false)
            let drawn = source.count
            let shown = try #require(store.image(for: smallPicture))

            #expect(largePicture.rect.size.width != smallPicture.rect.size.width)
            #expect(largePicture.subjectKey == smallPicture.subjectKey)

            store.makePictures(for: [large], waitingForZoom: true)

            #expect(source.count == drawn)
            #expect(store.image(for: largePicture) === shown)
        }

        @Test("Without waiting, a picture of another size is drawn at once")
        func redrawnAtAnotherSize() throws {
            let fixture = CalloutFixture()
            let source = CountingSource()
            let store = store(source)

            store.makePictures(for: [try fixture.box(pointsPerPageInch: 100)], waitingForZoom: false)
            let drawn = source.count

            store.makePictures(for: [try fixture.box(pointsPerPageInch: 150)], waitingForZoom: false)

            #expect(source.count > drawn)
        }

        @Test("A screen with other pixels gets pictures of its own")
        func anotherScale() throws {
            let fixture = CalloutFixture()
            let box = try fixture.box()
            let source = CountingSource()
            let store = store(source)

            store.makePictures(for: [box], waitingForZoom: false)
            let drawn = source.count

            store.scale = 1
            store.makePictures(for: [box], waitingForZoom: false)

            #expect(source.count == drawn * 2)
        }

        @Test("Discarded pictures are drawn again, even while a zoom runs")
        func discarded() throws {
            let fixture = CalloutFixture()
            let box = try fixture.box()
            let source = CountingSource()
            let store = store(source)

            store.makePictures(for: [box], waitingForZoom: false)
            let drawn = source.count

            store.discardPictures()
            #expect(store.image(for: try #require(box.pictures.first)) == nil)

            store.makePictures(for: [box], waitingForZoom: true)
            #expect(source.count == drawn * 2)
        }

        @Test("With nothing to draw pictures, there are none")
        func noSource() throws {
            let fixture = CalloutFixture()
            let box = try fixture.box()
            let store = LDrawStepCalloutPictureStore()

            store.makePictures(for: [box], waitingForZoom: false)

            #expect(store.image(for: try #require(box.pictures.first)) == nil)
        }
    }
}
