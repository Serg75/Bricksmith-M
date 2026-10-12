//
//  LDrawStepCalloutMenuItemTests.swift
//  LDrawStepEditingTests
//
//  What a host's menu offers on a callout's box and on a row of the parts list.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawStepEditing

@Suite("The menu on a callout")
struct LDrawStepCalloutMenuItemTests {

    private func keys(_ items: [LDrawStepCalloutMenuItem]) -> [String] {
        items.map { $0.isSeparator ? "-" : ($0.titleKey ?? "") }
    }

    @Test("On a later step: a divider before it, the other way to run, and removal after a line")
    func laterStepOffersEverything() throws {
        let fixture = CalloutFixture(stepCount: 3)
        let box = try fixture.box()
        let second = try #require(box.steps.dropFirst().first)

        let items = LDrawStepCalloutMenuItem.items(for: box, at: middle(of: second.rect), onPage: true)
        let otherWay = box.callout.isVertical ? "StepCalloutStepsAcross" : "StepCalloutStepsDown"

        #expect(keys(items) == ["StepCalloutDividerAdd", otherWay, "-", "StepCalloutRemove"])
        #expect(items.first?.stepNumber == 2)
        #expect(items.first?.edit?.kind == .rewrite)
        #expect(items.first?.title(fromLocalizedText: "Add Divider Before Step %ld") == "Add Divider Before Step 2")
        #expect(items.last?.title(fromLocalizedText: "Remove Callout") == "Remove Callout")
        #expect(items[2].edit == nil)
    }

    @Test("The first step starts a column anyway, so it offers no divider")
    func firstStepOffersNoDivider() throws {
        let fixture = CalloutFixture(stepCount: 3)
        let box = try fixture.box()
        let first = try #require(box.steps.first)

        let items = LDrawStepCalloutMenuItem.items(for: box, at: middle(of: first.rect), onPage: true)

        #expect(keys(items).contains("StepCalloutDividerAdd") == false)
        #expect(keys(items).last == "StepCalloutRemove")
    }

    @Test("A step that has a divider offers to take it away")
    func dividedStepOffersRemoval() throws {
        let fixture = CalloutFixture(stepCount: 3)
        let undivided = try #require(try fixture.box().steps.dropFirst().first)
        undivided.step.insert(CalloutFixture.parsed("CALLOUT DIVIDER"), at: 0)

        let box = try fixture.box()
        let second = try #require(box.steps.dropFirst().first)
        let items = LDrawStepCalloutMenuItem.items(for: box, at: middle(of: second.rect), onPage: true)

        #expect(second.hasDividerBefore)
        #expect(keys(items).first == "StepCalloutDividerRemove")
        #expect(items.first?.stepNumber == 2)
    }

    @Test("Off the page a box shows no steps, so only removal is offered")
    func offThePageOnlyRemoval() throws {
        let fixture = CalloutFixture(stepCount: 3)
        let box = try fixture.box(onPage: false)

        let items = LDrawStepCalloutMenuItem.items(for: box, at: middle(of: box.frameRect), onPage: false)

        #expect(keys(items) == ["StepCalloutRemove"])
    }

    @Test("A one-step submodel has no other way for its steps to run")
    func oneStepHasNothingToArrange() throws {
        let fixture = CalloutFixture(stepCount: 1)
        let box = try fixture.box()

        let items = LDrawStepCalloutMenuItem.items(for: box, at: middle(of: box.frameRect), onPage: true)

        #expect(keys(items) == ["StepCalloutRemove"])
    }

    @Test("A submodel's row of the parts list offers calling it out")
    func rowOffersCallingOut() throws {
        let file = LDrawFile()
        let main = LDrawMPDModel.model() as! LDrawMPDModel
        main.setModelName("main.ldr")
        file.addSubmodel(main)
        let sub = LDrawMPDModel.model() as! LDrawMPDModel
        sub.setModelName("sub.ldr")
        file.addSubmodel(sub)
        sub.addStep().add(CalloutFixture.part("3003.dat") as LDrawDirective)
        main.addStep().add(CalloutFixture.part("sub.ldr") as LDrawDirective)
        main.setStepDisplay(true)
        main.setMaximumStepIndexForStepDisplay(UInt(main.steps().count - 1))

        let color = LDrawColor()
        color.setColorCode(LDrawColorT(rawValue: 4)!)

        func row(_ name: String, isSubmodel: Bool) -> LDrawStepPartListEntry {
            LDrawStepPartListEntry(partName: name, displayTitle: name, color: color, quantity: 1,
                                   modelBounds: InvalidBox, isMissing: false, isSubmodel: isSubmodel)
        }

        let offered = LDrawStepCalloutMenuItem.items(for: row("sub.ldr", isSubmodel: true), inModel: main)
        let plain = LDrawStepCalloutMenuItem.items(for: row("3003.dat", isSubmodel: false), inModel: main)

        #expect(keys(offered) == ["StepCalloutAdd"])
        #expect(offered.first?.edit?.undoActionKey == "UndoStepCalloutAdd")
        #expect(plain.isEmpty)
    }
}
