//
//  LDrawObserverTests.swift
//  UnitTests
//
//  Tests for observers that stop observing while they are told something.
//  The parts use a submodel of their own file, so the part library is never
//  used.
//
//  Created by Sergey Slobodenyuk on 2026-11-04.
//

import Testing
import Foundation
import LDrawCore

@Suite("Observers that stop observing while told something")
struct LDrawObserverTests {

    /// A main model that uses one submodel 20 times, like a wheel uses its rim
    /// segment. Each use observes it once it is resolved. That is more than one
    /// batch of an enumeration, which is when a change during it is caught. The
    /// parts are named without preloading their files, which would need the
    /// library.
    private func file() throws -> (LDrawFile, [LDrawPart]) {
        let file = LDrawFile()
        let main = try #require(LDrawMPDModel.model() as? LDrawMPDModel)
        let sub = try #require(LDrawMPDModel.model() as? LDrawMPDModel)
        let step = main.addStep()
        var parts: [LDrawPart] = []

        main.setModelName("main.ldr")
        sub.setModelName("sub.ldr")
        file.addSubmodel(main)
        file.addSubmodel(sub)
        for _ in 0..<20 {
            let part = LDrawPart()
            part.setDisplayName("sub.ldr", parse: false, in: nil)
            step.add(part as LDrawDirective)
            parts.append(part)
        }

        for part in parts {
            #expect(part.partIsMissing() == false)
        }
        return (file, parts)
    }

    @Test("A submodel used by several parts can leave its file")
    func submodelLeavesFile() throws {
        let (file, parts) = try file()
        let sub = try #require(file.model(withName: "sub.ldr"))

        #expect(parts.count == 20)
        file.remove(sub as LDrawDirective)
        #expect(file.modelNames() as? [String] == ["main.ldr"])
    }

    @Test("A file whose submodel several parts use can be freed")
    func fileFreed() throws {
        weak var freed: LDrawFile?

        try autoreleasepool {
            let (file, _) = try file()
            freed = file
        }
        #expect(freed == nil)
    }
}
