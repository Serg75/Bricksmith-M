//
//  LDrawGroupSuppressionTests.swift
//  UnitTests
//
//  Covers how LDrawModel derives what an `0 !LPUB REMOVE GROUP` command does to
//  the MLCAD groups it names.
//
//  The rule under test: a removal is in scope once the step declaring it is on
//  display, and it then applies to that group's members wherever they sit --
//  including steps that placed them earlier on. That backwards reach is the
//  point of the command. A model swaps a placeholder out for the real thing by
//  grouping the placeholder, building on top of it for a while, and removing the
//  group at the step where the real part goes in.
//
//  Fixtures are built rather than parsed. Parsing a type-1 line pre-loads the
//  referenced file through LDrawPartLibrary, which asserts unless a renderer has
//  registered itself -- and the UnitTests target is deliberately renderer-free.
//  Suppression is derived from group names alone, so an unnamed part is a
//  faithful stand-in.
//
//  Created by Sergey Slobodenyuk on 2026-09-03.
//

import Testing
import Foundation
import LDrawCore

@Suite("Removed MLCAD groups drop out of the visualization engine", .serialized)
final class LDrawGroupSuppressionTests {

    /// Matches LDrawModel's process-wide defaults (hide in steps on, ghosting
    /// off). Swift Testing instantiates a class suite once per test and
    /// releases it afterwards, so this puts the statics back even when a test
    /// pins a non-default pair and then fails, or is the last one in the suite.
    deinit {
        LDrawModel.setHidesRemovedGroupsInStepDisplay(true)
        LDrawModel.setShowsRemovedGroupsAsGhosts(false)
    }

    // MARK: - Fixtures

    /// A part carrying the given MLCAD group name.
    private func part(inGroup group: String?) -> LDrawPart {
        let part = LDrawPart()
        part.group = group
        return part
    }

    /// An `0 !LPUB REMOVE GROUP "<group>"` command.
    private func removal(of group: String) -> LPubRemoveGroup {
        let removal = LPubRemoveGroup()
        removal.groupName = group
        return removal
    }

    /// A synthesized band carrying the given MLCAD group name. The other
    /// groupable kind, and the one whose gating is easiest to get wrong,
    /// because it holds its geometry rather than referring to a part file.
    private func band(inGroup group: String?) -> LDrawLSynth {
        let band = LDrawLSynth()
        band.group = group
        return band
    }

    /// Appends a step holding the given directives.
    @discardableResult
    private func addStep(to model: LDrawModel,
                         containing directives: [LDrawDirective]) -> LDrawStep {
        let step = model.addStep()
        for directive in directives {
            step.add(directive)
        }
        return step
    }

    /// The placeholder-swap shape, reduced to four steps:
    ///
    ///     step 0  a part in group "doors" (the placeholder)
    ///     step 1  an ungrouped part built on top of it
    ///     step 2  REMOVE GROUP "doors", plus the real ungrouped part
    ///     step 3  an ungrouped part
    ///
    /// So the removal in step two has to reach backwards to the placeholder that
    /// step zero placed.
    private func placeholderSwapModel() -> LDrawModel {
        let model = LDrawModel()

        addStep(to: model, containing: [part(inGroup: "doors")])
        addStep(to: model, containing: [part(inGroup: nil)])
        addStep(to: model, containing: [removal(of: "doors"), part(inGroup: nil)])
        addStep(to: model, containing: [part(inGroup: nil)])

        return model
    }

    private func directives(inStep index: Int, of model: LDrawModel) throws -> [LDrawDirective] {
        let step = try #require(model.steps()[index] as? LDrawStep)
        return try #require(step.subdirectives() as? [LDrawDirective])
    }

    /// The step-zero "doors" placeholder.
    private func placeholder(of model: LDrawModel) throws -> LDrawPart {
        try #require(directives(inStep: 0, of: model).first as? LDrawPart)
    }

    /// Both preferences are process-wide C statics, so every test states the
    /// pair it wants rather than inheriting whatever ran last. The suite is
    /// `.serialized` for the same reason: Swift Testing would otherwise run
    /// these concurrently and they would race on those statics.
    ///
    /// `deinit` restores the documented defaults afterwards, so a leftover
    /// cannot leak to a later suite in this process.
    private func pinPreferences(hideInSteps: Bool = true, ghost: Bool = false) {
        LDrawModel.setHidesRemovedGroupsInStepDisplay(hideInSteps)
        LDrawModel.setShowsRemovedGroupsAsGhosts(ghost)
    }

    // MARK: - Step scan

    @Test("A step reports the groups its own commands remove")
    func stepReportsItsOwnRemovals() throws {
        let model = placeholderSwapModel()
        let firstStepRemovals = NSMutableSet()
        let removingStepRemovals = NSMutableSet()

        try #require(model.steps()[0] as? LDrawStep).addRemovedGroupNames(to: firstStepRemovals)
        try #require(model.steps()[2] as? LDrawStep).addRemovedGroupNames(to: removingStepRemovals)


        #expect(firstStepRemovals.count == 0)
        #expect(removingStepRemovals == NSMutableSet(object: "doors"))
    }

    // MARK: - All mode

    @Test("A removal reaches back to a group placed by an earlier step")
    func removalReachesBackToAnEarlierStep() throws {
        pinPreferences()
        let model = placeholderSwapModel()
        model.setStepDisplay(false)

        model.updateGroupSuppressionIfNeeded()

        // The placeholder sits in step zero and the removal in step two. All
        // mode has every removal in scope, so the finished assembly drops it.
        #expect(try placeholder(of: model).groupVisibility == .hidden)
    }

    @Test("Ungrouped parts are left alone")
    func ungroupedPartsAreUntouched() throws {
        pinPreferences()
        let model = placeholderSwapModel()
        model.setStepDisplay(false)

        model.updateGroupSuppressionIfNeeded()

        for stepIndex in 0..<model.steps().count {
            for case let part as LDrawPart in try directives(inStep: stepIndex, of: model) where part.group == nil {
                #expect(part.groupVisibility == .visible)
            }
        }
    }

    @Test("With no removal in the model nothing is suppressed")
    func withNoRemovalsNothingIsSuppressed() throws {
        pinPreferences()
        let model = LDrawModel()
        addStep(to: model, containing: [part(inGroup: "doors")])
        model.setStepDisplay(false)

        model.updateGroupSuppressionIfNeeded()

        #expect(try placeholder(of: model).groupVisibility == .visible)
    }

    @Test("An empty group name never matches")
    func emptyGroupNamesNeverMatch() throws {
        pinPreferences()
        let model = LDrawModel()
        addStep(to: model, containing: [removal(of: ""), part(inGroup: nil)])
        model.setStepDisplay(false)

        model.updateGroupSuppressionIfNeeded()

        let part = try #require(directives(inStep: 0, of: model)[1] as? LDrawPart)
        #expect(part.groupVisibility == .visible)
    }

    // MARK: - Step display

    @Test("Before the removing step the group is still visible, and editable")
    func beforeTheRemovingStepGroupIsVisible() throws {
        pinPreferences()
        let model = placeholderSwapModel()
        model.setStepDisplay(true)
        model.setMaximumStepIndexForStepDisplay(1)

        model.updateGroupSuppressionIfNeeded()

        #expect(try placeholder(of: model).groupVisibility == .visible)
    }

    @Test("Reaching the removing step makes the group disappear")
    func atTheRemovingStepGroupDisappears() throws {
        pinPreferences()
        let model = placeholderSwapModel()
        model.setStepDisplay(true)
        model.setMaximumStepIndexForStepDisplay(2)

        model.updateGroupSuppressionIfNeeded()

        #expect(try placeholder(of: model).groupVisibility == .hidden)
    }

    @Test("Past the removing step the group stays gone")
    func pastTheRemovingStepGroupStaysGone() throws {
        pinPreferences()
        let model = placeholderSwapModel()
        model.setStepDisplay(true)
        model.setMaximumStepIndexForStepDisplay(3)

        model.updateGroupSuppressionIfNeeded()

        #expect(try placeholder(of: model).groupVisibility == .hidden)
    }

    @Test("Advancing onto the removing step re-derives")
    func advancingOntoTheRemovingStepReDerives() throws {
        pinPreferences()
        let model = placeholderSwapModel()
        let placeholder = try placeholder(of: model)
        model.setStepDisplay(true)

        model.setMaximumStepIndexForStepDisplay(1)
        model.updateGroupSuppressionIfNeeded()
        #expect(placeholder.groupVisibility == .visible)

        model.setMaximumStepIndexForStepDisplay(2)
        model.updateGroupSuppressionIfNeeded()
        #expect(placeholder.groupVisibility == .hidden)
    }

    @Test("Stepping back before the removal brings the group back")
    func steppingBackBeforeTheRemovalBringsTheGroupBack() throws {
        pinPreferences()
        let model = placeholderSwapModel()
        let placeholder = try placeholder(of: model)
        model.setStepDisplay(true)

        model.setMaximumStepIndexForStepDisplay(2)
        model.updateGroupSuppressionIfNeeded()
        #expect(placeholder.groupVisibility == .hidden)

        model.setMaximumStepIndexForStepDisplay(0)
        model.updateGroupSuppressionIfNeeded()
        #expect(placeholder.groupVisibility == .visible)
    }

    @Test("Leaving step display brings every removal into scope")
    func leavingStepDisplayBringsEveryRemovalIntoScope() throws {
        pinPreferences()
        let model = placeholderSwapModel()
        let placeholder = try placeholder(of: model)

        model.setStepDisplay(true)
        model.setMaximumStepIndexForStepDisplay(0)
        model.updateGroupSuppressionIfNeeded()
        #expect(placeholder.groupVisibility == .visible)

        model.setStepDisplay(false)
        model.updateGroupSuppressionIfNeeded()
        #expect(placeholder.groupVisibility == .hidden)
    }

    // MARK: - The hide-in-steps preference

    @Test("With hiding off, step display keeps a removed group on screen")
    func withHidingOffStepDisplayKeepsRemovedGroups() throws {
        pinPreferences(hideInSteps: false)
        let model = placeholderSwapModel()
        model.setStepDisplay(true)
        model.setMaximumStepIndexForStepDisplay(3)

        model.updateGroupSuppressionIfNeeded()

        // Past the removing step, but the preference opts step display out.
        #expect(try placeholder(of: model).groupVisibility == .visible)
    }

    @Test("With hiding off, All mode still applies removals")
    func withHidingOffAllModeStillHidesThem() throws {
        pinPreferences(hideInSteps: false)
        let model = placeholderSwapModel()
        model.setStepDisplay(false)

        model.updateGroupSuppressionIfNeeded()

        #expect(try placeholder(of: model).groupVisibility == .hidden)
    }

    // MARK: - The ghost preference

    @Test("With ghosting on, All mode ghosts instead of hiding")
    func withGhostingOnAllModeGhostsInsteadOfHiding() throws {
        pinPreferences(ghost: true)
        let model = placeholderSwapModel()
        model.setStepDisplay(false)

        model.updateGroupSuppressionIfNeeded()

        #expect(try placeholder(of: model).groupVisibility == .ghosted)
    }

    @Test("With ghosting on, step display still hides")
    func withGhostingOnStepDisplayStillHides() throws {
        pinPreferences(ghost: true)
        let model = placeholderSwapModel()
        model.setStepDisplay(true)
        model.setMaximumStepIndexForStepDisplay(2)

        model.updateGroupSuppressionIfNeeded()

        // Ghosting is an All-mode reading aid; stepping through the build shows
        // what the builder actually has in front of them.
        #expect(try placeholder(of: model).groupVisibility == .hidden)
    }

    @Test("With ghosting on, only the removed group ghosts")
    func withGhostingOnUnremovedGroupsStayPlainVisible() throws {
        pinPreferences(ghost: true)
        let model = placeholderSwapModel()
        model.setStepDisplay(false)

        model.updateGroupSuppressionIfNeeded()

        let lastPart = try #require(directives(inStep: 3, of: model)[0] as? LDrawPart)
        #expect(lastPart.groupVisibility == .visible)
    }

    @Test("The ghost alpha is translucent rather than absent or solid")
    func ghostAlphaIsTranslucent() {
        // The renderers scale a ghost's alpha by this, so 0 would draw nothing
        // at all -- indistinguishable from dropping the group -- and 1 would
        // defeat the point.
        #expect(LDRAW_GHOST_ALPHA > 0)
        #expect(LDRAW_GHOST_ALPHA < 1)
    }

    // MARK: - Re-derivation
    //
    // Neither preference can invalidate a model's cache flag -- they are
    // process-wide globals -- so each model has to notice on its own that the
    // settings it last derived under have changed.

    @Test("Toggling the hide preference re-derives without invalidation")
    func togglingTheHidePreferenceReDerives() throws {
        pinPreferences()
        let model = placeholderSwapModel()
        let placeholder = try placeholder(of: model)
        model.setStepDisplay(true)
        model.setMaximumStepIndexForStepDisplay(3)
        model.updateGroupSuppressionIfNeeded()
        #expect(placeholder.groupVisibility == .hidden)

        LDrawModel.setHidesRemovedGroupsInStepDisplay(false)
        model.updateGroupSuppressionIfNeeded()
        #expect(placeholder.groupVisibility == .visible)

        LDrawModel.setHidesRemovedGroupsInStepDisplay(true)
        model.updateGroupSuppressionIfNeeded()
        #expect(placeholder.groupVisibility == .hidden)
    }

    @Test("Toggling the ghost preference re-derives without invalidation")
    func togglingGhostingReDerives() throws {
        pinPreferences()
        let model = placeholderSwapModel()
        let placeholder = try placeholder(of: model)
        model.setStepDisplay(false)
        model.updateGroupSuppressionIfNeeded()
        #expect(placeholder.groupVisibility == .hidden)

        LDrawModel.setShowsRemovedGroupsAsGhosts(true)
        model.updateGroupSuppressionIfNeeded()
        #expect(placeholder.groupVisibility == .ghosted)

        LDrawModel.setShowsRemovedGroupsAsGhosts(false)
        model.updateGroupSuppressionIfNeeded()
        #expect(placeholder.groupVisibility == .hidden)
    }

    @Test("Setting a preference notifies only when the value changes")
    func settingAPreferencePostsANotificationOnlyOnChange() {
        pinPreferences()

        var postCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(LDrawGroupSuppressionDidChangeNotification),
            object: nil,
            queue: nil) { _ in postCount += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        LDrawModel.setHidesRemovedGroupsInStepDisplay(true)   // already true
        #expect(postCount == 0)

        LDrawModel.setHidesRemovedGroupsInStepDisplay(false)
        #expect(postCount == 1)

        LDrawModel.setHidesRemovedGroupsInStepDisplay(false)
        #expect(postCount == 1)
    }

    @Test("Regrouping a part re-derives suppression")
    func regroupingAPartReDerivesSuppression() throws {
        pinPreferences()
        let model = placeholderSwapModel()
        model.setStepDisplay(false)
        model.updateGroupSuppressionIfNeeded()

        // An ungrouped part joins the removed group.
        let lastPart = try #require(directives(inStep: 3, of: model)[0] as? LDrawPart)
        lastPart.group = "doors"
        model.updateGroupSuppressionIfNeeded()

        #expect(lastPart.groupVisibility == .hidden)
    }

    @Test("Regrouping twice still re-derives")
    func regroupingTwiceStillReDerives() throws {
        pinPreferences()
        let model = placeholderSwapModel()
        model.setStepDisplay(false)
        model.updateGroupSuppressionIfNeeded()

        let lastPart = try #require(directives(inStep: 3, of: model)[0] as? LDrawPart)

        // GroupSuppression is invalidated on the model rather than routed up
        // through the observers, so the second change has to land as well as
        // the first. A cache bit stuck dirty on the part would break this.
        lastPart.group = "doors"
        model.updateGroupSuppressionIfNeeded()
        lastPart.group = nil
        model.updateGroupSuppressionIfNeeded()

        #expect(lastPart.groupVisibility == .visible)
    }

    @Test("Retargeting the removal re-derives suppression")
    func retargetingTheRemovalReDerivesSuppression() throws {
        pinPreferences()
        let model = placeholderSwapModel()
        model.setStepDisplay(false)
        model.updateGroupSuppressionIfNeeded()

        let removal = try #require(directives(inStep: 2, of: model)[0] as? LPubRemoveGroup)
        removal.groupName = "windows"
        model.updateGroupSuppressionIfNeeded()

        #expect(try placeholder(of: model).groupVisibility == .visible,
                "doors is no longer removed")
    }

    // MARK: - The one gate behind drawing, bounds and picking
    //
    // Each groupable answers `isOmitted` once and gates all three on it, so
    // they cannot drift apart and leave something invisible but still
    // clickable, or gone from the screen but still holding the model's
    // bounding box open. That the gates *are* wired to it is a claim about
    // geometry, which needs a part library and so cannot be asserted in this
    // renderer-free target; what is checked here is the answer they gate on.

    @Test("A part is omitted when hidden by hand or dropped by a removal, but not when ghosted")
    func partOmissionTruthTable() {
        let part = LDrawPart()
        #expect(part.isOmitted == false)

        part.setHidden(true)
        #expect(part.isOmitted == true)

        part.setHidden(false)
        part.groupVisibility = .hidden
        #expect(part.isOmitted == true)

        // A ghost draws, and stays selectable so it can be edited.
        part.groupVisibility = .ghosted
        #expect(part.isOmitted == false)

        // Hiding by hand and removing the group are independent; neither
        // overwrites the other.
        part.setHidden(true)
        part.groupVisibility = .visible
        #expect(part.isOmitted == true)
    }

    @Test("A synthesized band answers omission the same way a part does")
    func bandOmissionTruthTable() {
        let band = band(inGroup: nil)
        #expect(band.isOmitted == false)

        band.setHidden(true)
        #expect(band.isOmitted == true)

        band.setHidden(false)
        band.groupVisibility = .hidden
        #expect(band.isOmitted == true)

        band.groupVisibility = .ghosted
        #expect(band.isOmitted == false)
    }

    @Test("A removal reaches a synthesized band, not just parts")
    func removalReachesASynthesizedBand() throws {
        pinPreferences()
        let model = LDrawModel()
        let hose = band(inGroup: "hoses")
        addStep(to: model, containing: [hose])
        addStep(to: model, containing: [removal(of: "hoses")])
        model.setStepDisplay(false)

        model.updateGroupSuppressionIfNeeded()

        #expect(hose.groupVisibility == .hidden)
        #expect(hose.isOmitted == true)
    }

    @Test("A ghosted band is not omitted, so it stays editable")
    func ghostedBandStaysEditable() throws {
        pinPreferences(ghost: true)
        let model = LDrawModel()
        let hose = band(inGroup: "hoses")
        addStep(to: model, containing: [hose])
        addStep(to: model, containing: [removal(of: "hoses")])
        model.setStepDisplay(false)

        model.updateGroupSuppressionIfNeeded()

        #expect(hose.groupVisibility == .ghosted)
        #expect(hose.isOmitted == false)
    }
}
