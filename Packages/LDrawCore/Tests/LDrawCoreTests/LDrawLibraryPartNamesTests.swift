//
//  LDrawLibraryPartNamesTests.swift
//  UnitTests
//
//  Tests for listing the library parts a model uses.
//
//  Created by Sergey Slobodenyuk on 2026-11-06.
//

import Testing
import Foundation
import LDrawCore

@Suite("Library parts of a model")
struct LDrawLibraryPartNamesTests {

    private func part(_ name: String) -> LDrawPart {
        let part = LDrawPart()
        part.setDisplayName(name, parse: false, in: nil)
        return part
    }

    private func submodel(_ name: String, in file: LDrawFile, _ parts: [LDrawPart]) {
        let model = LDrawMPDModel.model() as! LDrawMPDModel
        model.setModelName(name)
        file.addSubmodel(model)
        let step = model.addStep()
        for part in parts {
            step.add(part as LDrawDirective)
        }
    }

    @Test("The library parts at any depth are named, and submodels are left out")
    func libraryPartNames() {
        let file = LDrawFile()
        submodel("main.ldr", in: file, [part("3001.dat"), part("sub.ldr")])
        submodel("sub.ldr", in: file, [part("s\\3001s01.dat"), part("3001.dat")])

        #expect(LDrawUtilities.libraryPartNames(in: file) == ["3001.dat", "s\\3001s01.dat"])
    }
}
