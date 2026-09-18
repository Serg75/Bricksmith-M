//
//  LDrawClassInspectorTests.swift
//  LDrawCoreTests
//
//  Finding a class's subclasses at run time, which is how the parser learns
//  every meta command class. The inspector is private to LDrawCore, so it is
//  reached through the runtime.
//
//  Created by Sergey Slobodenyuk on 2023-03-17.
//

import Testing
import Foundation
import LDrawCore

class InspectedRoot: NSObject {}
class InspectedLeaf: InspectedRoot {}
class InspectedBranch: InspectedRoot {}
class InspectedBranchLeaf: InspectedBranch {}

@Suite("Finding subclasses")
struct LDrawClassInspectorTests {

    private let inspector: AnyClass = NSClassFromString("LDrawClassInspector")!

    private func names(_ classes: [AnyClass]) -> Set<String> {
        Set(classes.map { NSStringFromClass($0) })
    }

    private func subclasses(of type: AnyClass) -> [AnyClass] {
        perform("subclassesFor:", on: inspector, with: type) ?? []
    }

    private func directSubclasses(of type: AnyClass) -> [AnyClass] {
        perform("firstLevelSubclassesFor:", on: inspector, with: type) ?? []
    }

    @Test("Every subclass is found, however deep")
    func findsAllSubclasses() {
        let found = subclasses(of: InspectedRoot.self)

        #expect(names(found) == names([InspectedLeaf.self, InspectedBranch.self, InspectedBranchLeaf.self]))
    }

    @Test("A class with no subclasses gives an empty list")
    func noSubclassesGivesNothing() {
        #expect(subclasses(of: InspectedLeaf.self).isEmpty)
    }

    @Test("Only the direct subclasses are found when asked for")
    func findsDirectSubclasses() {
        let found = directSubclasses(of: InspectedRoot.self)

        #expect(names(found) == names([InspectedLeaf.self, InspectedBranch.self]))
    }
}
