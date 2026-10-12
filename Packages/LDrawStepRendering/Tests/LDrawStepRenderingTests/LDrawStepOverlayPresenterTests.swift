//
//  LDrawStepOverlayPresenterTests.swift
//  LDrawStepRenderingTests
//
//  What a change to a file means for the overlay.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawStepRendering

extension StepOverlayTests {

    @Suite("What a change means for the overlay")
    struct LDrawStepOverlayPresenterTests {

        private func presenter(_ fixture: CalloutFixture) -> LDrawStepOverlayPresenter {
            let presenter = LDrawStepOverlayPresenter()
            presenter.model = fixture.main
            return presenter
        }

        @Test("A line of the model on display lays the step out again, and keeps the pictures")
        func lineOfTheModel() {
            let fixture = CalloutFixture()
            let part = CalloutFixture.part("3001.dat")
            fixture.step.add(part as LDrawDirective)

            #expect(presenter(fixture).change(forChangedObject: part) == .layout)
        }

        @Test("A line of a submodel may be in a picture, so the pictures go too")
        func lineOfASubmodel() throws {
            let fixture = CalloutFixture()
            let built = try #require((fixture.sub.steps() as? [LDrawStep])?.last)
            let part = CalloutFixture.part("3001.dat")
            built.add(part as LDrawDirective)

            #expect(presenter(fixture).change(forChangedObject: part) == [.layout, .pictures])
        }

        @Test("A color the model defines may be used anywhere")
        func colorOfTheModel() {
            let fixture = CalloutFixture()
            let color = LDrawColor()
            fixture.step.add(color as LDrawDirective)

            #expect(presenter(fixture).change(forChangedObject: color) == [.layout, .pictures])
        }

        @Test("A change outside the file, such as the part library, changes everything")
        func outsideTheFile() {
            let fixture = CalloutFixture()

            #expect(presenter(fixture).change(forChangedObject: nil) == [.layout, .pictures])
            #expect(presenter(fixture).change(forChangedObject: NSObject()) == [.layout, .pictures])
        }

        @Test("A line of another file means nothing here")
        func anotherFile() throws {
            let fixture = CalloutFixture()
            let other = CalloutFixture()
            let part = CalloutFixture.part("3001.dat")
            other.step.add(part as LDrawDirective)

            #expect(presenter(fixture).change(forChangedObject: part) == [])
        }

        @Test("Before anything is laid out, a camera move changes nothing")
        func cameraMoveWithNothingShown() {
            let fixture = CalloutFixture()

            #expect(presenter(fixture).changeForCameraMove() == [])
        }

        @Test("With no camera a step is laid out without arrows, and a reset forgets it")
        func noCamera() {
            let fixture = CalloutFixture()
            let presenter = presenter(fixture)
            presenter.viewSize = Size2(width: 800, height: 600)

            presenter.reload()

            #expect(presenter.presentation != nil)
            #expect(presenter.calloutArrows.isEmpty)

            presenter.reset()

            #expect(presenter.presentation == nil)
        }
    }
}
