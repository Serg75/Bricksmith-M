//
//  LDrawStepCalloutPathTests.swift
//  LDrawStepRenderingTests
//
//  The way back from a called-out submodel to the step that calls it out.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawStepRendering

extension StepOverlayTests {

    @Suite("The path through callouts")
    struct LDrawStepCalloutPathTests {

        private func take(_ path: LDrawStepCalloutPath,
                          among models: [LDrawModel]) -> (model: LDrawModel, stepIndex: Int, ratio: Double)? {
            var model: LDrawModel?
            var stepIndex = 0
            var ratio = 0.0

            guard path.takeReturn(model: &model, stepIndex: &stepIndex, drawnScaleRatio: &ratio, among: models),
                  let model else {
                return nil
            }
            return (model, stepIndex, ratio)
        }

        @Test("A callout leads to its submodel, when that is one the host can show")
        func submodelOfACallout() throws {
            let fixture = CalloutFixture()
            let callout = try fixture.callout

            let both: [LDrawModel] = [fixture.main, fixture.sub]

            #expect(LDrawStepCalloutPath.submodel(of: callout, preferring: nil, among: both,
                                                  otherThan: fixture.main) === fixture.sub)
            #expect(LDrawStepCalloutPath.submodel(of: callout, preferring: nil, among: [fixture.main],
                                                  otherThan: fixture.main) == nil)
            #expect(LDrawStepCalloutPath.submodel(of: callout, preferring: nil, among: both,
                                                  otherThan: fixture.sub) == nil)
        }

        @Test("A callout of two submodels leads past the one on display, and past one that cannot be shown")
        func submodelOfACalloutOfTwo() throws {
            let fixture = CalloutFixture()
            let other = LDrawMPDModel.model() as! LDrawMPDModel
            other.setModelName("other.ldr")
            fixture.file.addSubmodel(other)
            other.addStep().add(CalloutFixture.part("3004.dat") as LDrawDirective)
            fixture.step.insert(CalloutFixture.part("other.ldr"), at: 2)

            let callout = try fixture.callout
            let all: [LDrawModel] = [fixture.main, fixture.sub, other]

            #expect(callout.submodels.count == 2)
            #expect(LDrawStepCalloutPath.submodel(of: callout, preferring: nil, among: all,
                                                  otherThan: fixture.main) === fixture.sub)
            #expect(LDrawStepCalloutPath.submodel(of: callout, preferring: nil, among: all,
                                                  otherThan: fixture.sub) === other)
            #expect(LDrawStepCalloutPath.submodel(of: callout, preferring: nil, among: [fixture.main, other],
                                                  otherThan: fixture.main) === other)
        }

        @Test("The submodel that was clicked is the one a callout of two leads to")
        func clickedSubmodelComesFirst() throws {
            let fixture = CalloutFixture()
            let other = LDrawMPDModel.model() as! LDrawMPDModel
            other.setModelName("other.ldr")
            fixture.file.addSubmodel(other)
            other.addStep().add(CalloutFixture.part("3004.dat") as LDrawDirective)
            fixture.step.insert(CalloutFixture.part("other.ldr"), at: 2)

            let callout = try fixture.callout
            let all: [LDrawModel] = [fixture.main, fixture.sub, other]

            #expect(LDrawStepCalloutPath.submodel(of: callout, preferring: other, among: all,
                                                  otherThan: fixture.main) === other)
            #expect(LDrawStepCalloutPath.submodel(of: callout, preferring: fixture.sub, among: all,
                                                  otherThan: fixture.main) === fixture.sub)

            // One that cannot be shown, or is no submodel of the callout, gives the first that can.
            #expect(LDrawStepCalloutPath.submodel(of: callout, preferring: other, among: [fixture.main, fixture.sub],
                                                  otherThan: fixture.main) === fixture.sub)
            #expect(LDrawStepCalloutPath.submodel(of: callout, preferring: other, among: all,
                                                  otherThan: other) === fixture.sub)
            #expect(LDrawStepCalloutPath.submodel(of: callout, preferring: fixture.main, among: all,
                                                  otherThan: nil) === fixture.sub)
        }

        @Test("With no step left there is no way back")
        func emptyPath() {
            let fixture = CalloutFixture()
            let path = LDrawStepCalloutPath()

            #expect(path.isEmpty)
            #expect(path.returnModel == nil)
            #expect(path.returnStepNumber == 0)
            #expect(take(path, among: [fixture.main]) == nil)
        }

        @Test("The step that was left is the way back, and is named from 1")
        func leaveAndReturn() throws {
            let fixture = CalloutFixture()
            let path = LDrawStepCalloutPath()

            path.leave(fixture.main, atStepIndex: 1, drawnScaleRatio: 1.25)

            #expect(path.isEmpty == false)
            #expect(path.returnModel === fixture.main)
            #expect(path.returnStepNumber == 2)

            let back = try #require(take(path, among: [fixture.main, fixture.sub]))

            #expect(back.model === fixture.main)
            #expect(back.stepIndex == 1)
            #expect(back.ratio == 1.25)
            #expect(path.isEmpty)
        }

        @Test("Steps are taken back in the order they were left, last first")
        func nestedCallouts() throws {
            let fixture = CalloutFixture(stepCount: 2)
            let path = LDrawStepCalloutPath()
            let models: [LDrawModel] = [fixture.main, fixture.sub]

            path.leave(fixture.main, atStepIndex: 1, drawnScaleRatio: 1)
            path.leave(fixture.sub, atStepIndex: 2, drawnScaleRatio: 2)

            #expect(try #require(take(path, among: models)).model === fixture.sub)
            #expect(path.returnModel === fixture.main)
            #expect(try #require(take(path, among: models)).model === fixture.main)
            #expect(path.isEmpty)
        }

        @Test("A model that lost steps since it was left is shown at its last step")
        func lostSteps() throws {
            let fixture = CalloutFixture()
            let path = LDrawStepCalloutPath()
            let stepCount = fixture.main.steps().count

            path.leave(fixture.main, atStepIndex: stepCount + 5, drawnScaleRatio: 1)

            #expect(try #require(take(path, among: [fixture.main])).stepIndex == stepCount - 1)
        }

        @Test("A model that is gone ends the whole way back")
        func deletedModel() {
            let fixture = CalloutFixture()
            let path = LDrawStepCalloutPath()

            path.leave(fixture.main, atStepIndex: 1, drawnScaleRatio: 1)
            path.leave(fixture.sub, atStepIndex: 1, drawnScaleRatio: 1)

            #expect(take(path, among: [fixture.main]) == nil)
            #expect(path.isEmpty)
        }

        @Test("Choosing a model another way forgets the path")
        func removeAll() {
            let fixture = CalloutFixture()
            let path = LDrawStepCalloutPath()

            path.leave(fixture.main, atStepIndex: 1, drawnScaleRatio: 1)
            path.removeAll()

            #expect(path.isEmpty)
            #expect(path.returnModel == nil)
        }
    }
}
