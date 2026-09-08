//
//  LDrawStepGhostingTests.swift
//  UnitTests
//
//  Covers when step display fades everything already built, leaving only the
//  step on display solid.
//
//  The rule under test: the fade is a Steps-view reading aid, so it applies
//  only while step display is active, only when the user has asked for it, and
//  only once there is a step behind the current one to fade.
//
//  Nothing here draws. The fade itself is an alpha the model pushes on the
//  renderer as it walks the steps, and the UnitTests target is deliberately
//  renderer-free; what is testable, and what is easy to get wrong, is the
//  three-way condition that decides whether the push happens at all.
//
//  Created by Sergey Slobodenyuk on 2026-09-08.
//

import Testing
import Foundation
import LDrawCore

@Suite("Step display fades the steps already built", .serialized)
final class LDrawStepGhostingTests {

    /// Matches LDrawModel's process-wide default. Swift Testing instantiates a
    /// class suite once per test and releases it afterwards, so this puts the
    /// static back even when a test turns the preference on and then fails, or
    /// is the last one in the suite.
    deinit {
        LDrawModel.setGhostsPreviousSteps(false)
    }

    // MARK: - Fixtures

    /// Four steps, one part each. Only the step count matters here -- what the
    /// steps hold does not, because the fade spans whole steps.
    private func fourStepModel() -> LDrawModel {
        let model = LDrawModel()

        for _ in 0 ..< 4 {
            let step: LDrawStep = model.addStep()
            let part: LDrawDirective = LDrawPart()
            step.add(part)
        }

        return model
    }

    /// A model in Steps view mode, stopped at the given step.
    private func model(atStep index: Int) -> LDrawModel {
        let model = fourStepModel()

        model.setStepDisplay(true)
        model.setMaximumStepIndexForStepDisplay(UInt(index))

        return model
    }

    // MARK: - The preference

    @Test("Off by default, so step display looks the way it always has")
    func offByDefault() {
        #expect(LDrawModel.ghostsPreviousSteps() == false)
        #expect(model(atStep: 2).drawsPreviousStepsAsGhosts() == false)
    }

    @Test("Turning it on fades the steps behind the one on display")
    func turningItOnFadesEarlierSteps() {
        LDrawModel.setGhostsPreviousSteps(true)

        #expect(model(atStep: 2).drawsPreviousStepsAsGhosts() == true)
    }

    @Test("Setting the preference notifies only when the value changes")
    func settingThePreferencePostsANotificationOnlyOnChange() {
        LDrawModel.setGhostsPreviousSteps(false)

        var postCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(LDrawStepGhostingDidChangeNotification),
            object: nil,
            queue: nil) { _ in postCount += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        LDrawModel.setGhostsPreviousSteps(false)   // already false
        #expect(postCount == 0)

        LDrawModel.setGhostsPreviousSteps(true)
        #expect(postCount == 1)

        LDrawModel.setGhostsPreviousSteps(true)
        #expect(postCount == 1)
    }

    // MARK: - Where the fade applies

    @Test("All mode is left alone -- it has no current step to single out")
    func allModeIsUnaffected() {
        LDrawModel.setGhostsPreviousSteps(true)
        let model = fourStepModel()
        model.setStepDisplay(false)

        #expect(model.drawsPreviousStepsAsGhosts() == false)
    }

    @Test("On the first step there is nothing built yet, so nothing fades")
    func theFirstStepHasNothingBehindIt() {
        LDrawModel.setGhostsPreviousSteps(true)

        #expect(model(atStep: 0).drawsPreviousStepsAsGhosts() == false)
    }

    @Test("Advancing off the first step starts the fade")
    func advancingOffTheFirstStepStartsTheFade() {
        LDrawModel.setGhostsPreviousSteps(true)
        let model = self.model(atStep: 0)

        #expect(model.drawsPreviousStepsAsGhosts() == false)

        model.setMaximumStepIndexForStepDisplay(1)
        #expect(model.drawsPreviousStepsAsGhosts() == true)
    }

    @Test("Stepping back to the first step stops it again")
    func steppingBackToTheFirstStepStopsTheFade() {
        LDrawModel.setGhostsPreviousSteps(true)
        let model = self.model(atStep: 3)

        #expect(model.drawsPreviousStepsAsGhosts() == true)

        model.setMaximumStepIndexForStepDisplay(0)
        #expect(model.drawsPreviousStepsAsGhosts() == false)
    }

    @Test("Leaving step display stops it, and returning resumes it")
    func leavingAndRejoiningStepDisplay() {
        LDrawModel.setGhostsPreviousSteps(true)
        let model = self.model(atStep: 2)

        #expect(model.drawsPreviousStepsAsGhosts() == true)

        model.setStepDisplay(false)
        #expect(model.drawsPreviousStepsAsGhosts() == false)

        model.setStepDisplay(true)
        #expect(model.drawsPreviousStepsAsGhosts() == true)
    }

    @Test("Turning the preference back off stops the fade with no other change")
    func turningThePreferenceOffStopsTheFade() {
        LDrawModel.setGhostsPreviousSteps(true)
        let model = self.model(atStep: 2)

        #expect(model.drawsPreviousStepsAsGhosts() == true)

        LDrawModel.setGhostsPreviousSteps(false)

        // Read fresh at every draw, so the model needs no invalidation to
        // notice -- the host only has to ask for a redraw.
        #expect(model.drawsPreviousStepsAsGhosts() == false)
    }

    // MARK: - The alpha

    @Test("The ghost alpha is translucent rather than absent or solid")
    func ghostAlphaIsTranslucent() {
        // Shared with the removed-group ghosts: 0 would draw nothing at all and
        // 1 would leave the previous steps looking solid.
        #expect(LDRAW_GHOST_ALPHA > 0)
        #expect(LDRAW_GHOST_ALPHA < 1)
    }
}
