//
//  LDrawFileFlattenTests.swift
//  UnitTests
//
//  Tests for flattening a part file whose models use each other. The parts
//  are added without reading their files, which would need the part library.
//
//  Created by Sergey Slobodenyuk on 2026-11-07.
//

import Testing
import Foundation
import LDrawCore

@Suite("Flattening a part file")
struct LDrawFileFlattenTests {

    private func use(_ name: String) -> LDrawDirective {
        let part = LDrawPart()
        part.setDisplayName(name, parse: false, in: nil)
        return part
    }

    private func triangle() throws -> LDrawDirective {
        let file = try #require(LDrawFile.parse(fromFileContents: "3 16 0 0 0 1 0 0 0 1 0\n"))
        let found = try #require(file.firstModel().allEnclosedElements().first { $0 is LDrawTriangle })
        return try #require((found as AnyObject).copy() as? LDrawDirective)
    }

    private func addModel(_ name: String, to file: LDrawFile, _ directives: [LDrawDirective]) throws {
        let model = try #require(LDrawMPDModel.model() as? LDrawMPDModel)
        model.setModelName(name)
        file.addSubmodel(model)
        let step = model.addStep()
        for directive in directives {
            step.add(directive)
        }
    }

    @Test("A model gets the faces of a submodel used two levels down")
    func nestedSubmodels() throws {
        let file = LDrawFile()
        try addModel("main.dat", to: file, [use("mid.dat")])
        try addModel("mid.dat", to: file, [use("leaf.dat"), use("leaf.dat")])
        try addModel("leaf.dat", to: file, [try triangle()])

        file.optimizeStructure()
        let elements = file.firstModel().allEnclosedElements()

        #expect(elements.filter { $0 is LDrawTriangle }.count == 2)
        #expect(elements.contains { $0 is LDrawPart } == false)
    }
}
