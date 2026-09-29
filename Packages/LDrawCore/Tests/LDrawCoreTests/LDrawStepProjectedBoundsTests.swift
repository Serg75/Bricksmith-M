//
//  LDrawStepProjectedBoundsTests.swift
//  UnitTests
//
//  Covers the projected bounds zoom to fit uses: in step display they cover
//  only the steps on display, like the model's 3D bounds.
//
//  Created by Sergey Slobodenyuk on 2026-09-29.
//

import Testing
import Foundation
import LDrawCore

@Suite("Zoom to fit sees only the steps on display")
struct LDrawStepProjectedBoundsTests {

    /// Two steps: a line 10 LDU long, then one 100 LDU long. Lines need no
    /// part library.
    private func twoStepModel() throws -> LDrawModel {
        let contents = "2 24 0 0 0 10 0 0\n0 STEP\n2 24 0 0 0 100 0 0\n"
        let file = try #require(LDrawFile.parse(fromFileContents: contents))
        return try #require(file.activeModel())
    }

    private func projectedWidth(of model: LDrawModel) -> Double {
        let bounds = model.projectedBoundingBox(withModelView: IdentityMatrix4,
                                                projection: IdentityMatrix4,
                                                view: V2MakeBox(0, 0, 100, 100))
        return bounds.max.x - bounds.min.x
    }

    @Test("At the first step only the short line counts")
    func firstStep() throws {
        let model = try twoStepModel()
        let allSteps = projectedWidth(of: model)

        model.setStepDisplay(true)
        model.setMaximumStepIndexForStepDisplay(0)

        #expect(projectedWidth(of: model) * 5 < allSteps)
    }

    @Test("At the last step both lines count")
    func lastStep() throws {
        let model = try twoStepModel()
        let allSteps = projectedWidth(of: model)

        model.setStepDisplay(true)
        model.setMaximumStepIndexForStepDisplay(1)

        #expect(projectedWidth(of: model) == allSteps)
    }
}
