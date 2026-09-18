//
//  LDrawStepPartListTests.swift
//  UnitTests
//
//  Tests for what a step's parts list carries and what it leaves out.
//
//  The fixtures are built, not parsed, and run with no part catalog: a title
//  falls back to the part name, and nothing is reported missing.
//
//  Created by Sergey Slobodenyuk on 2026-09-09.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures

extension StepPartListStaticSettings {

    @Suite("A step's parts list", .serialized)
    final class LDrawStepPartListTests {

        deinit {
            LDrawStepPartList.setIncludesSubmodels(false)
            LDrawStepPartList.setPartOrientations(nil)
            LDrawStepPartList.setFollowsStepRotation(true)
        }

        // MARK: - Fixtures

        /// LDraw color codes as raw values, so the tests do not depend on the
        /// Swift names of the LDrawColorT cases.
        private static let blue: Int32 = 1
        private static let green: Int32 = 2
        private static let red: Int32 = 4

        private func color(_ code: Int32) -> LDrawColor {
            let color = LDrawColor()
            color.setColorCode(LDrawColorT(rawValue: code)!)
            return color
        }

        private func part(_ name: String,
                          _ code: Int32 = LDrawStepPartListTests.red,
                          group: String? = nil,
                          hidden: Bool = false) -> LDrawPart {
            let part = LDrawPart()
            part.setDisplayName(name, parse: false, in: nil)
            part.setLDrawColor(color(code))
            part.group = group
            part.setHidden(hidden)
            return part
        }

        private func removal(of group: String) -> LPubRemoveGroup {
            let removal = LPubRemoveGroup()
            removal.groupName = group
            return removal
        }

        private func ignoreBegin(_ branch: LPubPliIgnoreBranch = .pli) -> LPubPliIgnore {
            let bracket = LPubPliIgnore()
            bracket.lPubCommandString = "\(branch == .part ? "PART" : "PLI") BEGIN IGN"
            return bracket
        }

        private func ignoreEnd(_ branch: LPubPliIgnoreBranch = .pli) -> LPubPliIgnore {
            let bracket = LPubPliIgnore()
            bracket.lPubCommandString = "\(branch == .part ? "PART" : "PLI") END"
            return bracket
        }

        private func substitute(_ name: String, _ code: Int? = nil) -> LPubPliSubstitute {
            let bracket = LPubPliSubstitute()
            bracket.lPubCommandString = "PLI BEGIN SUB \(name)" + (code.map { " \($0)" } ?? "")
            return bracket
        }

        private func step(_ directives: [LDrawDirective]) -> LDrawStep {
            let step = LDrawStep.empty() as! LDrawStep
            for directive in directives {
                step.add(directive)
            }
            return step
        }

        /// A new model comes with a blank step, so use the step this returns.
        @discardableResult
        private func addStep(to model: LDrawModel, _ directives: [LDrawDirective]) -> LDrawStep {
            let step = model.addStep()
            for directive in directives {
                step.add(directive)
            }
            return step
        }

        /// A submodel added to the file. The caller must keep the file, because
        /// a directive's link to its parent is weak and names resolve through it.
        @discardableResult
        private func submodel(_ name: String, in file: LDrawFile, description: String? = nil) -> LDrawMPDModel {
            let model = LDrawMPDModel.model() as! LDrawMPDModel
            model.setModelName(name)
            if let description = description {
                model.setModelDescription(description)
            }
            file.addSubmodel(model)
            return model
        }

        private func entries(_ directives: [LDrawDirective]) -> [LDrawStepPartListEntry] {
            LDrawStepPartList.entries(forStep: step(directives))
        }

        private func names(_ entries: [LDrawStepPartListEntry]) -> [String] {
            entries.map(\.partName)
        }

        // MARK: - Grouping

        @Test("The same design in two colors is two rows")
        func sameDesignDifferentColorsAreSeparateEntries() {
            let result = entries([part("3001.dat", Self.red), part("3001.dat", Self.blue)])

            #expect(result.count == 2)
            #expect(result.allSatisfy { $0.quantity == 1 })
            #expect(Set(result.map { $0.color?.colorCode().rawValue }) == [Self.red, Self.blue])
        }

        @Test("The same design in the same color is one row with a count")
        func repeatedPartAccumulates() throws {
            let result = entries([part("3001.dat"), part("3001.dat"), part("3001.dat")])

            #expect(result.count == 1)
            #expect(try #require(result.first).quantity == 3)
        }

        @Test("Grouping is by canonical reference name, not the typed spelling")
        func groupingUsesTheCanonicalName() throws {
            let result = entries([part("3001.DAT"), part("3001.dat")])

            #expect(result.count == 1)
            #expect(try #require(result.first).partName == "3001.dat")
        }

        // MARK: - Hidden parts

        @Test("Hidden and visible instances share one row")
        func hiddenAndVisibleInstancesShareARow() throws {
            let mixed = entries([part("3001.dat", hidden: true), part("3001.dat")])

            #expect(mixed.count == 1)
            #expect(try #require(mixed.first).quantity == 2)
        }

        // MARK: - Removed groups

        @Test("A part dropped by REMOVE GROUP is not listed")
        func removedGroupPartIsExcluded() {
            let model = LDrawModel()
            addStep(to: model, [part("3001.dat", group: "jig"),
                                part("3002.dat"),
                                removal(of: "jig")])
            model.setStepDisplay(false)
            model.updateGroupSuppressionIfNeeded()

            let result = LDrawStepPartList.entries(forStep: model.steps()[0] as? LDrawStep)

            #expect(names(result) == ["3002.dat"])
        }

        /// A ghost shows something taken out of the build, not something being
        /// placed now.
        @Test("A ghosted part is not listed either")
        func ghostedGroupPartIsExcluded() {
            let jig = part("3001.dat", group: "jig")
            jig.groupVisibility = .ghosted

            #expect(entries([jig]).isEmpty)
        }

        @Test("Hidden and removed are not the same thing")
        func hiddenAndRemovedAreDistinct() {
            let hidden = part("3001.dat", hidden: true)
            let removed = part("3002.dat")
            removed.groupVisibility = .hidden

            #expect(names(entries([hidden, removed])) == ["3001.dat"])
        }

        // MARK: - PLI BEGIN IGN

        @Test("Parts inside an ignore range are excluded")
        func ignoreRangeIsExcluded() {
            let result = entries([part("3001.dat"),
                                  ignoreBegin(),
                                  part("3002.dat"),
                                  part("3003.dat"),
                                  ignoreEnd(),
                                  part("3004.dat")])

            #expect(names(result) == ["3001.dat", "3004.dat"])
        }

        @Test("An unterminated ignore range swallows the rest of the step")
        func unterminatedIgnoreRangeRunsToTheEnd() {
            let result = entries([part("3001.dat"), ignoreBegin(), part("3002.dat")])

            #expect(names(result) == ["3001.dat"])
        }

        /// The PART bracket wraps an alternate or a spare part.
        @Test("Parts inside a PART BEGIN IGN range are excluded")
        func partIgnoreRangeIsExcluded() {
            let result = entries([part("3001.dat"),
                                  ignoreBegin(.part),
                                  part("3002.dat"),
                                  ignoreEnd(.part),
                                  part("3004.dat")])

            #expect(names(result) == ["3001.dat", "3004.dat"])
        }

        @Test("A PART END does not close a PLI range, nor a PLI END a PART range")
        func ignoreBranchesCloseOnlyThemselves() {
            let pliThenPartEnd = entries([ignoreBegin(.pli),
                                          part("3001.dat"),
                                          ignoreEnd(.part),
                                          part("3002.dat"),
                                          ignoreEnd(.pli),
                                          part("3003.dat")])

            #expect(names(pliThenPartEnd) == ["3003.dat"])

            let partThenPliEnd = entries([ignoreBegin(.part),
                                          part("3001.dat"),
                                          ignoreEnd(.pli),
                                          part("3002.dat"),
                                          ignoreEnd(.part),
                                          part("3003.dat")])

            #expect(names(partThenPliEnd) == ["3003.dat"])
        }

        // MARK: - LPub3D's PLI control file

        /// When the icons follow the step, they line up with the assembly, so
        /// nothing is turned.
        @Test("A part in the control file is oriented, in LPub3D's model only")
        func controlFileOrientsInLPubModelOnly() throws {
            let file = LDrawPartListOrientations(string: "1 0 0 0 0 0 0 1 1 0 0 0 1 0 32523.dat")
            LDrawStepPartList.setPartOrientations(file)

            LDrawStepPartList.setFollowsStepRotation(false)
            let lpub = entries([part("32523.dat"), part("3001.dat")])
            let beam = try #require(lpub.first { $0.partName == "32523.dat" })
            let brick = try #require(lpub.first { $0.partName == "3001.dat" })

            let turned = V3MulPointByProjMatrix(Point3(x: 1, y: 0, z: 0), beam.listOrientation)
            #expect(abs(turned.y - 1) < 1e-9, "the file's matrix")
            let untouched = V3MulPointByProjMatrix(Point3(x: 1, y: 0, z: 0), brick.listOrientation)
            #expect(untouched.x == 1, "not listed, not turned")

            LDrawStepPartList.setFollowsStepRotation(true)
            let following = entries([part("32523.dat")])
            let straight = V3MulPointByProjMatrix(Point3(x: 1, y: 0, z: 0), try #require(following.first).listOrientation)
            #expect(straight.x == 1)
        }

        // MARK: - PLI BEGIN SUB

        /// A hinge plate is one part in the bag, but LDraw draws its two halves.
        @Test("A SUB range lists its substitute once, and nothing inside it")
        func substituteReplacesItsRange() {
            let result = entries([part("3001.dat"),
                                  substitute("2429c01.dat", 15),
                                  part("2429.dat"),
                                  part("2430.dat"),
                                  ignoreEnd(),
                                  part("3023.dat")])

            #expect(names(result).sorted() == ["2429c01.dat", "3001.dat", "3023.dat"])
            #expect(result.first { $0.partName == "2429c01.dat" }?.quantity == 1)
        }

        @Test("A SUB naming a submodel of the file lists that submodel as a part")
        func substituteNamingASubmodelListsIt() throws {
            let file = LDrawFile()
            let main = submodel("fender left white part.ldr", in: file)
            let hinge = submodel("2429c01.ldr", in: file, description: "hinge plate part")

            addStep(to: hinge, [part("2429.dat"), part("2430.dat")])

            let step = addStep(to: main, [substitute("2429c01.ldr", 15),
                                          part("2429.dat"),
                                          part("2430.dat"),
                                          ignoreEnd(),
                                          part("3023.dat")])

            LDrawStepPartList.setIncludesSubmodels(false)
            let result = LDrawStepPartList.entries(forStep: step)

            #expect(names(result).sorted() == ["2429c01.ldr", "3023.dat"])

            let listed = try #require(result.first { $0.partName == "2429c01.ldr" })
            #expect(listed.isSubmodel == true)
            #expect(listed.displayTitle == "hinge plate part")
            #expect(listed.color?.colorCode().rawValue == 15)
        }

        @Test("A PART IGN range inside a SUB does not hide the substitute")
        func partIgnoreInsideSubstituteKeepsTheSubstitute() {
            let result = entries([substitute("2429c01.dat", 15),
                                  ignoreBegin(.part),
                                  part("2429.dat"),
                                  part("2430.dat"),
                                  ignoreEnd(.part),
                                  ignoreEnd(),
                                  part("3023.dat")])

            #expect(names(result).sorted() == ["2429c01.dat", "3023.dat"])
        }

        /// An edge line has a color too, but it is not a part.
        @Test("A SUB with no color takes the first part's")
        func substituteWithoutColorTakesTheFirstPart() throws {
            let edge = LDrawLine()
            edge.setLDrawColor(color(Self.green))

            let result = entries([substitute("2429c01.dat"),
                                  edge,
                                  part("2429.dat", Self.blue),
                                  part("2430.dat", Self.red),
                                  ignoreEnd()])

            let hinge = try #require(result.first)
            #expect(hinge.partName == "2429c01.dat")
            #expect(hinge.color?.colorCode().rawValue == Self.blue)
        }

        @Test("Two SUB ranges for the same part count twice")
        func repeatedSubstitutesCount() {
            let result = entries([substitute("2429c01.dat", 15), part("2429.dat"), ignoreEnd(),
                                  substitute("2429c01.dat", 15), part("2429.dat"), ignoreEnd()])

            #expect(result.count == 1)
            #expect(result.first?.quantity == 2)
        }

        /// Ranges share the PLI END, so each END closes the range opened last.
        @Test("PLI ranges nest, and an unterminated SUB still lists its substitute")
        func pliRangesNest() {
            let hidden = entries([ignoreBegin(),
                                  substitute("2429c01.dat", 15), part("2429.dat"), ignoreEnd(),
                                  part("3001.dat"),
                                  ignoreEnd(),
                                  part("3023.dat")])

            #expect(names(hidden) == ["3023.dat"])

            let open = entries([part("3001.dat"), substitute("2429c01.dat", 15), part("2429.dat")])

            #expect(names(open).sorted() == ["2429c01.dat", "3001.dat"])
        }

        @Test("Nested ignore ranges need matching ends")
        func nestedIgnoreRangesNest() {
            let result = entries([ignoreBegin(),
                                  ignoreBegin(),
                                  part("3001.dat"),
                                  ignoreEnd(),
                                  part("3002.dat"),
                                  ignoreEnd(),
                                  part("3003.dat")])

            #expect(names(result) == ["3003.dat"])
        }

        /// A PLI END closes either kind of range, so an END with nothing open must
        /// be harmless.
        @Test("An END with nothing open is a no-op")
        func strayEndIsHarmless() {
            let result = entries([ignoreEnd(), part("3001.dat")])

            #expect(names(result) == ["3001.dat"])
        }

        // MARK: - Containers

        @Test("A part inside a texture is listed, and ranges inside it still apply")
        func partInsideATextureIsListed() {
            let texture = LDrawTexture()
            for directive in [part("3001.dat"), ignoreBegin(), part("3003.dat"), ignoreEnd()] as [LDrawDirective] {
                texture.add(directive)
            }

            #expect(names(entries([texture, part("3002.dat")])) == ["3001.dat", "3002.dat"])
        }

        // MARK: - Submodels

        /// Builds main.ldr placing sub.ldr and 3001.dat, with sub.ldr holding the
        /// given directives in one step.
        private func stepPlacingSubmodel(holding directives: [LDrawDirective]) -> (file: LDrawFile, step: LDrawStep) {
            let file = LDrawFile()
            let main = submodel("main.ldr", in: file)
            let sub = submodel("sub.ldr", in: file)

            addStep(to: sub, directives)

            return (file, addStep(to: main, [part("sub.ldr"), part("3001.dat")]))
        }

        @Test("A submodel whose parts are all inside PART BEGIN IGN is not listed")
        func submodelWithOnlyIgnoredPartsIsNotListed() {
            LDrawStepPartList.setIncludesSubmodels(true)

            let fixture = stepPlacingSubmodel(holding: [ignoreBegin(.part),
                                                        part("44567a.dat"),
                                                        part("3003.dat"),
                                                        ignoreEnd(.part)])

            #expect(names(LDrawStepPartList.entries(forStep: fixture.step)) == ["3001.dat"])
        }

        @Test("One part outside the range keeps the submodel listed")
        func submodelWithAListedPartIsListed() {
            LDrawStepPartList.setIncludesSubmodels(true)

            let fixture = stepPlacingSubmodel(holding: [ignoreBegin(.part),
                                                        part("44567a.dat"),
                                                        ignoreEnd(.part),
                                                        part("3003.dat")])

            #expect(names(LDrawStepPartList.entries(forStep: fixture.step)).sorted() == ["3001.dat", "sub.ldr"])
        }

        @Test("A submodel holding only an empty submodel is not listed")
        func submodelHoldingOnlyAnEmptySubmodelIsNotListed() {
            LDrawStepPartList.setIncludesSubmodels(true)

            let fixture = stepPlacingSubmodel(holding: [part("inner.ldr")])
            let inner = submodel("inner.ldr", in: fixture.file)
            addStep(to: inner, [ignoreBegin(), part("3003.dat"), ignoreEnd()])

            #expect(names(LDrawStepPartList.entries(forStep: fixture.step)) == ["3001.dat"])
        }

        @Test("A submodel that declares itself a part is listed as one")
        func inlinePartIsListedAsAPart() throws {
            let file = LDrawFile()
            let main = submodel("main.ldr", in: file)
            let whip = submodel("88704 orig.ldr", in: file, description: "Minifig Whip Bent Flexible")

            let typeLine = LDrawMetaCommand()
            typeLine.commandString = "!LDRAW_ORG Unofficial_Part"
            (whip.steps().first as! LDrawStep).add(typeLine)
            addStep(to: whip, [part("s\\88704s01.dat"), part("4-4cylc.dat")])

            let step = addStep(to: main, [part("88704 orig.ldr"), part("3001.dat")])

            LDrawStepPartList.setIncludesSubmodels(false)
            let result = LDrawStepPartList.entries(forStep: step)

            #expect(names(result).sorted() == ["3001.dat", "88704 orig.ldr"])

            let whipEntry = try #require(result.first { $0.partName == "88704 orig.ldr" })
            #expect(whipEntry.displayTitle == "Minifig Whip Bent Flexible")
            #expect(whipEntry.quantity == 1)
        }

        /// With no catalog only the folder in the name marks a subpart or a
        /// primitive, so a bare primitive name is still listed.
        @Test("A subpart or hi-res primitive reference is not listed")
        func subpartsAndPrimitivesAreNotListed() {
            let result = entries([part("s\\88704s01.dat"),
                                  part("48\\4-4cyli.dat"),
                                  part("8\\4-4edge.dat"),
                                  part("S\\93247s01.dat"),
                                  part("3001.dat")])

            #expect(names(result) == ["3001.dat"])
        }

        @Test("A submodel built only of what parts are built of is a part")
        func headerlessHandBuiltPartIsAPart() throws {
            let file = LDrawFile()

            let main   = submodel("main.ldr", in: file, description: "main")
            let bent   = submodel("88704 bent.ldr", in: file, description: "Minifig Whip, bent")
            let handle = submodel("88704 handle.ldr", in: file, description: "handle")
            let hose   = submodel("88704 hose.ldr", in: file, description: "hose")
            let half   = submodel("88704 hose part half.ldr", in: file, description: "half")

            addStep(to: half,   [LDrawQuadrilateral(), LDrawQuadrilateral(), LDrawConditionalLine()])
            addStep(to: hose,   [LDrawLSynth(), part("88704 hose part half.ldr"), part("88704 hose part half.ldr")])
            addStep(to: handle, [part("s\\93247s01.dat"), part("s\\93247s01.dat"), part("48\\3-8edge.dat")])
            addStep(to: bent,   [part("88704 handle.ldr"), part("88704 hose.ldr")])

            let step = addStep(to: main, [part("88704 bent.ldr"), part("3001.dat")])

            #expect(LDrawStepPartList.isPartLike(half))
            #expect(LDrawStepPartList.isPartLike(hose))
            #expect(LDrawStepPartList.isPartLike(handle))
            #expect(LDrawStepPartList.isPartLike(bent))
            #expect(LDrawStepPartList.isPartLike(main) == false)

            LDrawStepPartList.setIncludesSubmodels(false)
            let result = LDrawStepPartList.entries(forStep: step)

            #expect(names(result).sorted() == ["3001.dat", "88704 bent.ldr"])
            let whip = try #require(result.first { $0.partName == "88704 bent.ldr" })
            #expect(whip.displayTitle == "Minifig Whip, bent")

            // Inside the part there is no list at all, however far down.
            for model in [bent, handle, hose, half] {
                #expect(LDrawStepPartList.entries(forStep: model.steps().last as? LDrawStep).isEmpty, "\(model.modelName())")
            }
        }

        @Test("One catalog part, or an empty model, makes a submodel an assembly")
        func aRealPartOrNothingIsNotAPart() {
            let file = LDrawFile()
            let assembly = submodel("assembly.ldr", in: file)
            let empty = submodel("empty.ldr", in: file)
            let metasOnly = submodel("metas.ldr", in: file)

            addStep(to: assembly, [part("s\\93247s01.dat"), LDrawLine(), part("3001.dat")])
            let comment = LDrawMetaCommand()
            comment.commandString = "// nothing to see"
            addStep(to: metasOnly, [comment])

            #expect(LDrawStepPartList.isPartLike(assembly) == false)
            #expect(LDrawStepPartList.isPartLike(empty) == false)
            #expect(LDrawStepPartList.isPartLike(metasOnly) == false)
            #expect(LDrawStepPartList.isPartLike(nil) == false)
        }

        /// Two submodels that only place each other say nothing about each
        /// other. Calling them parts would leave both with no parts list.
        @Test("Submodels that only place each other are not parts")
        func mutuallyReferencingSubmodelsAreNotParts() {
            LDrawStepPartList.setIncludesSubmodels(true)

            let file = LDrawFile()
            let first = submodel("a.ldr", in: file)
            let second = submodel("b.ldr", in: file)

            let firstStep = addStep(to: first, [part("b.ldr")])
            addStep(to: second, [part("a.ldr")])

            #expect(LDrawStepPartList.isPartLike(first) == false)
            #expect(LDrawStepPartList.isPartLike(second) == false)

            #expect(names(LDrawStepPartList.entries(forStep: firstStep)) == ["b.ldr"],
                    "a step of an assembly still lists what it places")
        }

        /// A cycle with a real part in it: the part decides, not the loop.
        @Test("A cycle that holds a part is still an assembly both ways round")
        func mutuallyReferencingSubmodelsWithAPartAreNotParts() {
            LDrawStepPartList.setIncludesSubmodels(true)

            let file = LDrawFile()
            let first = submodel("a.ldr", in: file)
            let second = submodel("b.ldr", in: file)

            addStep(to: first, [part("b.ldr")])
            addStep(to: second, [part("a.ldr"), part("3001.dat")])

            #expect(LDrawStepPartList.isPartLike(first) == false)
            #expect(LDrawStepPartList.isPartLike(second) == false)
        }

        @Test("A submodel reference is excluded by default")
        func submodelReferenceIsExcludedByDefault() {
            let fixture = stepPlacingSubmodel(holding: [part("3003.dat")])

            let result = LDrawStepPartList.entries(forStep: fixture.step)

            #expect(names(result) == ["3001.dat"])
        }

        @Test("An included submodel is one row for the reference, not its contents")
        func includedSubmodelIsOneRow() throws {
            LDrawStepPartList.setIncludesSubmodels(true)
            let fixture = stepPlacingSubmodel(holding: [part("3003.dat")])

            let result = LDrawStepPartList.entries(forStep: fixture.step)

            #expect(names(result).sorted() == ["3001.dat", "sub.ldr"])

            let submodelEntry = try #require(result.first { $0.partName == "sub.ldr" })
            #expect(submodelEntry.isSubmodel == true)
            #expect(submodelEntry.quantity == 1)
        }

        // MARK: - Scope

        @Test("Only the visible step is listed, not the ones before it")
        func earlierStepsAreExcluded() {
            let model = LDrawModel()
            addStep(to: model, [part("3001.dat")])
            addStep(to: model, [part("3002.dat")])
            addStep(to: model, [part("3003.dat")])
            model.setStepDisplay(true)
            model.setMaximumStepIndexForStepDisplay(1)

            let result = LDrawStepPartList.entries(forVisibleStepOf: model)

            #expect(names(result) == ["3002.dat"])
        }

        @Test("A nil or empty step, or a nil model, gives an empty list rather than nil")
        func nilInputsGiveEmptyLists() {
            #expect(LDrawStepPartList.entries(forStep: nil).isEmpty)
            #expect(LDrawStepPartList.entries(forVisibleStepOf: nil).isEmpty)
            #expect(entries([]).isEmpty)
        }

        @Test("Directives that are not parts are ignored")
        func nonPartDirectivesAreIgnored() {
            let comment = LDrawComment()
            let line = LDrawLine()

            #expect(names(entries([comment, line, part("3001.dat")])) == ["3001.dat"])
        }

        // MARK: - Ordering

        /// With no catalog every entry has invalid bounds, so the sizes tie and
        /// the name and color keys decide.
        @Test("Equal-sized entries sort by name, then color code")
        func tiesSortByNameThenColor() {
            let result = entries([part("3002.dat", Self.blue),
                                  part("3001.dat", Self.red),
                                  part("3001.dat", Self.blue)])

            #expect(names(result) == ["3001.dat", "3001.dat", "3002.dat"])
            #expect(result[0].color?.colorCode().rawValue == Self.blue)  // 1 sorts before
            #expect(result[1].color?.colorCode().rawValue == Self.red)   // 4
        }
    }
}
