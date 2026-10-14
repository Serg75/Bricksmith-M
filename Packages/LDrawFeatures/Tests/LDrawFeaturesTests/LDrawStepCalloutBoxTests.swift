//
//  LDrawStepCalloutBoxTests.swift
//  LDrawFeaturesTests
//
//  Tests for where a step's callout boxes go and where their arrows leave.
//
//  The fixtures run with no part catalog, so every submodel takes the
//  packer's stand-in size and an arrow points at where its part is placed.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures

extension StepPartListStaticSettings {

    @Suite("A step's callout boxes")
    struct LDrawStepCalloutBoxTests {

        // MARK: - Fixtures

        private func part(_ name: String, at position: Point3 = Point3(x: 0, y: 0, z: 0)) -> LDrawPart {
            let color = LDrawColor()
            color.setColorCode(LDrawColorT(rawValue: 4)!)

            var components = IdentityComponents
            components.translate = position

            let part = LDrawPart()
            part.setDisplayName(name, parse: false, in: nil)
            part.setLDrawColor(color)
            part.setTransformComponents(components)
            return part
        }

        private func lpub<Command: LPubCommand>(_ text: String) -> Command {
            let command = Command()
            command.lPubCommandString = text
            return command
        }

        @discardableResult
        private func addStep(to model: LDrawModel, _ directives: [LDrawDirective]) -> LDrawStep {
            let step = model.addStep()
            for directive in directives {
                step.add(directive)
            }
            return step
        }

        /// A file whose main model calls out `count` submodels in one step, each
        /// in a callout of its own. The caller keeps the file.
        private func fixture(callouts count: Int)
            -> (file: LDrawFile, model: LDrawModel, callouts: [LDrawStepCallout]) {
            let file = LDrawFile()
            let main = LDrawMPDModel.model() as! LDrawMPDModel
            main.setModelName("main.ldr")
            file.addSubmodel(main)

            var directives: [LDrawDirective] = []

            for index in 0..<count {
                let sub = LDrawMPDModel.model() as! LDrawMPDModel
                sub.setModelName("sub\(index).ldr")
                file.addSubmodel(sub)
                addStep(to: sub, [part("3003.dat")])

                let begin: LPubCallout = lpub("CALLOUT BEGIN")
                let end: LPubCallout = lpub("CALLOUT END")
                directives += [begin, part("sub\(index).ldr", at: Point3(x: Double(index) * 100, y: -24, z: 60)), end]
            }

            let step = addStep(to: main, directives)

            return (file, main, LDrawStepCallout.callouts(forStep: step))
        }

        private let view = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: 1000, height: 800))
        private let noList = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: 0, height: 0))

        /// What the boxes are told about the host. `pointsPerPageInch` above 0
        /// puts them on a page, where a box shows its steps.
        private func options(host: Box2? = nil,
                             list: Box2? = nil,
                             assembly: Box2? = nil,
                             pointsPerPageInch: Double = 0,
                             showsLists: Bool = true) -> LDrawStepCalloutBoxOptions {
            let metrics = LDrawStepPartListLayout.defaultMetrics()

            return LDrawStepCalloutBoxOptions(metrics: metrics,
                                              assemblyScale: metrics.baseScale,
                                              hostRect: host ?? view,
                                              listFrame: list ?? noList,
                                              assemblyRect: assembly ?? noList,
                                              pointsPerPageInch: pointsPerPageInch,
                                              listViewTransform: IdentityMatrix4,
                                              showsLists: ObjCBool(showsLists))
        }

        private func boxes(_ fixture: (file: LDrawFile, model: LDrawModel, callouts: [LDrawStepCallout]),
                           host: Box2? = nil,
                           list: Box2? = nil) -> [LDrawStepCalloutBox] {
            LDrawStepCalloutBox.boxes(forCallouts: fixture.callouts,
                                      inModel: fixture.model,
                                      options: options(host: host, list: list))
        }

        // MARK: - Placement

        @Test("With no list, the first box goes in the host's corner")
        func firstBoxGoesInTheCorner() throws {
            let fixture = fixture(callouts: 1)

            let box = try #require(boxes(fixture).first)
            let picture = try #require(box.pictures.first)
            let padding = LDrawStepPartListLayout.defaultMetrics().framePadding

            #expect(box.frameRect.origin.x == 12)
            #expect(box.frameRect.origin.y == 12)
            #expect(picture.rect.origin.y == 12 + padding)
            #expect(picture.rect.origin.x >= 12 + padding)
            #expect(picture.rect.origin.x + picture.rect.size.width <= 12 + box.frameRect.size.width - padding)
            #expect(picture.model.steps().count > 0)
        }

        @Test("Under a list, the boxes stack down its left edge")
        func boxesStackUnderTheList() throws {
            let fixture = fixture(callouts: 2)
            let list = Box2(origin: Point2(x: 12, y: 12), size: Size2(width: 200, height: 100))

            let result = boxes(fixture, list: list)
            let first = try #require(result.first)
            let second = try #require(result.last)

            #expect(result.count == 2)
            #expect(first.frameRect.origin.x == 12)
            #expect(first.frameRect.origin.y == 112 + 12)
            #expect(second.frameRect.origin.x == 12)
            #expect(second.frameRect.origin.y == first.frameRect.origin.y + first.frameRect.size.height + 12)
        }

        @Test("A box with no room below starts a new column, clear of the list")
        func crowdedBoxesStartANewColumn() throws {
            let fixture = fixture(callouts: 2)
            let list = Box2(origin: Point2(x: 12, y: 12), size: Size2(width: 200, height: 100))
            let height = try #require(boxes(fixture).first).frameRect.size.height

            // Room under the list for one box, not two.
            let host = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: 1000, height: 124 + height + 12 + 20))
            let result = boxes(fixture, host: host, list: list)
            let first = try #require(result.first)
            let second = try #require(result.last)

            #expect(first.frameRect.origin.y == 124)
            #expect(second.frameRect.origin.y == 12)
            #expect(second.frameRect.origin.x == 12 + 200 + 12)
        }

        @Test("On a page the boxes are placed inside the page")
        func boxesSitOnThePage() throws {
            let fixture = fixture(callouts: 1)
            let page = Box2(origin: Point2(x: 300, y: 200), size: Size2(width: 600, height: 500))
            let pageOptions = options(host: page, pointsPerPageInch: 100)

            let box = try #require(LDrawStepCalloutBox.boxes(forCallouts: fixture.callouts,
                                                             inModel: fixture.model,
                                                             options: pageOptions).first)
            let inset = LDrawStepPartListPolicy.frameInset(forPointsPerPageInch: 100)

            #expect(box.frameRect.origin.x == 300 + inset)
            #expect(box.frameRect.origin.y == 200 + inset)
        }

        /// The stand-in submodel packs 38 points wide, and 35 hundredths of this
        /// host is 35.
        @Test("A box wider than its share of the host is packed narrower")
        func wideBoxesAreNarrowed() throws {
            let fixture = fixture(callouts: 1)
            let narrow = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: 100, height: 800))

            let roomy = try #require(boxes(fixture).first)
            let box = try #require(boxes(fixture, host: narrow).first)

            #expect(roomy.frameRect.size.width > 35)
            #expect(box.frameRect.size.width <= 35.001)
        }

        @Test("No callouts, or a host with no size, gives no boxes")
        func nothingToPlace() {
            let fixture = fixture(callouts: 1)
            let empty = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: 0, height: 0))

            #expect(boxes(self.fixture(callouts: 0)).isEmpty)
            #expect(boxes(fixture, host: empty).isEmpty)
        }

        // MARK: - Off the page: the summary

        /// A file whose main model calls out sub.ldr, which builds 3003.dat and
        /// then 3004.dat. `before` goes ahead of the callout and `inside` after its
        /// placements. The caller keeps the file.
        private func calloutFixture(before: [LDrawDirective] = [],
                                    inside: [LDrawDirective] = [],
                                    placements: Int = 1,
                                    mode: String? = nil,
                                    steps: [[LDrawDirective]]? = nil)
            -> (file: LDrawFile, model: LDrawModel, callouts: [LDrawStepCallout]) {
            let file = LDrawFile()
            let main = LDrawMPDModel.model() as! LDrawMPDModel
            main.setModelName("main.ldr")
            file.addSubmodel(main)

            let sub = LDrawMPDModel.model() as! LDrawMPDModel
            sub.setModelName("sub.ldr")
            file.addSubmodel(sub)

            for directives in steps ?? [[part("3003.dat")], [part("3004.dat")]] {
                addStep(to: sub, directives)
            }

            let begin: LPubCallout = lpub("CALLOUT BEGIN" + (mode.map { " \($0)" } ?? ""))
            let end: LPubCallout = lpub("CALLOUT END")
            let placed = (0..<placements).map { part("sub.ldr", at: Point3(x: Double($0) * 100, y: 0, z: 0)) }
            let step = addStep(to: main, before + [begin] + placed + inside + [end])

            return (file, main, LDrawStepCallout.callouts(forStep: step))
        }

        private func handedOver() -> LPubCalloutPliPerStep {
            lpub("CALLOUT PLI PER_STEP FALSE")
        }

        private func onPage(_ fixture: (file: LDrawFile, model: LDrawModel, callouts: [LDrawStepCallout]),
                            showsLists: Bool = true) throws -> LDrawStepCalloutBox {
            let pageOptions = options(pointsPerPageInch: 100, showsLists: showsLists)

            return try #require(LDrawStepCalloutBox.boxes(forCallouts: fixture.callouts,
                                                          inModel: fixture.model,
                                                          options: pageOptions).first)
        }

        @Test("A box shows its submodel finished, and says how many steps build it")
        func summaryShowsTheFinishedSubmodel() throws {
            let box = try #require(boxes(calloutFixture(before: [handedOver()])).first)
            let picture = try #require(box.pictures.first)

            #expect(box.pictures.count == 1)
            #expect(picture.isPartsList == false)
            #expect(picture.layout?.placements.count == 1)
            #expect(box.summarizedStepCount == 2)
            #expect(box.labels.isEmpty)
            #expect(box.dividerCount == 0)
        }

        @Test("A one-step submodel gets no steps badge")
        func oneStepNeedsNoBadge() throws {
            let box = try #require(boxes(calloutFixture(before: [handedOver()], steps: [[part("3003.dat")]])).first)

            #expect(box.summarizedStepCount == 0)
        }

        /// With LPub3D's default the step's own list has none of the callout's
        /// parts, so the box has to show them.
        @Test("A box lists its own parts under the finished submodel")
        func summaryListsItsOwnParts() throws {
            let box = try #require(boxes(calloutFixture()).first)
            let finished = try #require(box.pictures.first)
            let list = try #require(box.pictures.last)

            #expect(box.pictures.count == 2)
            #expect(list.isPartsList)
            #expect(list.layout?.placements.count == 2)
            #expect(list.rect.origin.y >= finished.rect.origin.y + finished.rect.size.height)
            #expect(list.rect.origin.y + list.rect.size.height <= box.frameRect.origin.y + box.frameRect.size.height)
        }

        @Test("A box lists no parts when the step's list has them, or the step hides its list")
        func summaryLeavesPartsToTheStep() throws {
            let handed = try #require(boxes(calloutFixture(before: [handedOver()])).first)
            #expect(handed.pictures.count == 1)

            let fixture = calloutFixture()
            let hidden = try #require(LDrawStepCalloutBox.boxes(forCallouts: fixture.callouts,
                                                                inModel: fixture.model,
                                                                options: options(showsLists: false)).first)
            #expect(hidden.pictures.count == 1)
        }

        // MARK: - On the page: the steps

        @Test("On the page a box shows a picture for each step that builds something")
        func stripShowsEachStep() throws {
            let comment = LDrawComment()
            let fixture = calloutFixture(before: [handedOver()],
                                         steps: [[part("3003.dat")], [comment], [part("3004.dat")]])
            let box = try onPage(fixture)

            #expect(box.pictures.count == 2)
            #expect(box.pictures.allSatisfy { $0.layout == nil })
            #expect(box.summarizedStepCount == 0)
        }

        @Test("A step's picture holds everything built up to that step")
        func stripPicturesAddUp() throws {
            let box = try onPage(calloutFixture(before: [handedOver()]))
            let first = try #require(box.pictures.first?.model.steps().first as? LDrawStep)
            let second = try #require(box.pictures.last?.model.steps().first as? LDrawStep)

            #expect(first.subdirectives().count == 1)
            #expect(second.subdirectives().count == 2)
            #expect(box.pictures.first?.contentKey != box.pictures.last?.contentKey)
        }

        /// A host shows the picture it has at another size while the zoom changes.
        @Test("A picture names what it shows the same way at every size")
        func subjectKeyIgnoresTheScale() throws {
            let fixture = calloutFixture(before: [handedOver()])
            var doubled = options(pointsPerPageInch: 100)
            doubled.assemblyScale *= 2

            let small = try #require(onPage(fixture).pictures.first)
            let large = try #require(LDrawStepCalloutBox.boxes(forCallouts: fixture.callouts,
                                                               inModel: fixture.model,
                                                               options: doubled).first?.pictures.first)

            #expect(large.subjectKey == small.subjectKey)
            #expect(large.contentKey != small.contentKey)
        }

        /// One callout of two submodels, which a summary packs as a small list.
        private func twoSubmodels() -> (file: LDrawFile, model: LDrawModel, callouts: [LDrawStepCallout]) {
            let file = LDrawFile()
            let main = LDrawMPDModel.model() as! LDrawMPDModel
            main.setModelName("main.ldr")
            file.addSubmodel(main)

            for name in ["first.ldr", "second.ldr"] {
                let sub = LDrawMPDModel.model() as! LDrawMPDModel
                sub.setModelName(name)
                file.addSubmodel(sub)
                addStep(to: sub, [part("3003.dat")])
            }

            let begin: LPubCallout = lpub("CALLOUT BEGIN")
            let end: LPubCallout = lpub("CALLOUT END")
            let step = addStep(to: main, [begin, part("first.ldr"), part("second.ldr"), end])

            return (file, main, LDrawStepCallout.callouts(forStep: step))
        }

        private func middle(_ box: Box2) -> Point2 {
            Point2(x: box.origin.x + box.size.width / 2, y: box.origin.y + box.size.height / 2)
        }

        @Test("Off the page, a point on a submodel's row of the box gives that submodel")
        func summaryKnowsTheSubmodelAtAPoint() throws {
            let fixture = twoSubmodels()
            let box = try #require(boxes(fixture).first)
            let picture = try #require(box.pictures.first)
            let placements = try #require(picture.layout?.placements)

            try #require(placements.count == 2)

            for placement in placements {
                var point = middle(placement.cellFrame)
                point.x += picture.rect.origin.x
                point.y += picture.rect.origin.y

                #expect((box.submodel(at: point) as? LDrawMPDModel)?.modelName() == placement.entry.partName)
            }
        }

        @Test("On the page, a point on a step gives the submodel the step is of")
        func stripKnowsTheSubmodelAtAPoint() throws {
            let box = try onPage(twoSubmodels())

            try #require(box.steps.count == 2)

            for step in box.steps {
                #expect(box.submodel(at: middle(step.rect)) === step.step.enclosingModel())
            }
            #expect(box.submodel(at: middle(box.steps[0].rect)) !== box.submodel(at: middle(box.steps[1].rect)))
        }

        @Test("A point beside the submodels gives the nearest one")
        func nearestSubmodelBesideThem() throws {
            let box = try onPage(twoSubmodels())
            let first = box.steps[0].rect
            let last = box.steps[1].rect
            let before = Point2(x: first.origin.x - 500, y: first.origin.y - 500)
            let after = Point2(x: last.origin.x + last.size.width + 500, y: last.origin.y + last.size.height + 500)

            #expect(box.submodel(at: before) === box.steps[0].step.enclosingModel())
            #expect(box.submodel(at: after) === box.steps[1].step.enclosingModel())
        }

        @Test("A box of one submodel gives it for any point")
        func oneSubmodelAtAnyPoint() throws {
            let fixture = calloutFixture(before: [handedOver()])
            let submodel = try #require(fixture.callouts.first?.submodels.first)
            let offPage = try #require(boxes(fixture).first)
            let paged = try onPage(fixture)

            #expect(offPage.submodel(at: offPage.frameRect.origin) === submodel)
            #expect(paged.submodel(at: paged.frameRect.origin) === submodel)
            #expect(paged.submodel(at: Point2(x: -1000, y: 5000)) === submodel)
        }

        /// The picture a host has at another size stands in while the zoom
        /// changes, so it must be a picture of the same arrangement.
        @Test("The same parts on other shelves are another subject")
        func subjectKeySeesTheArrangement() throws {
            let fixture = twoSubmodels()
            // Too narrow for the two side by side, wide enough for each at full size.
            let narrow = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: 180, height: 800))
            let wide = try #require(boxes(fixture).first?.pictures.first)
            let stacked = try #require(boxes(fixture, host: narrow).first?.pictures.first)
            let again = try #require(boxes(fixture).first?.pictures.first)

            #expect(wide.layout?.placements.map(\.rowIndex) == [0, 0])
            #expect(stacked.layout?.placements.map(\.rowIndex) == [0, 1])
            #expect(wide.subjectKey != stacked.subjectKey)
            #expect(wide.subjectKey == again.subjectKey)
        }

        @Test("The steps run down, each in the middle of the column")
        func stripRunsDown() throws {
            let box = try onPage(calloutFixture(before: [handedOver()]))
            let first = try #require(box.pictures.first).rect
            let second = try #require(box.pictures.last).rect

            #expect(second.origin.y >= first.origin.y + first.size.height)
            #expect(abs((first.origin.x + first.size.width / 2) - (second.origin.x + second.size.width / 2)) < 0.001)
        }

        @Test("ALLOC HORIZONTAL runs the steps across")
        func stripRunsAcross() throws {
            let across: LPubCalloutAlloc = lpub("CALLOUT ALLOC HORIZONTAL")
            let box = try onPage(calloutFixture(before: [handedOver()], inside: [across]))
            let first = try #require(box.pictures.first).rect
            let second = try #require(box.pictures.last).rect

            #expect(second.origin.x >= first.origin.x + first.size.width)
            #expect(abs((first.origin.y + first.size.height / 2) - (second.origin.y + second.size.height / 2)) < 0.001)
        }

        @Test("A DIVIDER starts a new column, with a line between the two")
        func dividerStartsAGroup() throws {
            let divider: LPubCallout = lpub("CALLOUT DIVIDER")
            let fixture = calloutFixture(before: [handedOver()],
                                         steps: [[part("3003.dat")], [divider, part("3004.dat")], [part("3005.dat")]])
            let box = try onPage(fixture)
            let rects = box.pictures.map { $0.rect }
            let line = box.dividerRect(at: 0)

            #expect(rects.count == 3)
            #expect(box.dividerCount == 1)
            #expect(line.origin.x >= rects[0].origin.x + rects[0].size.width)
            #expect(rects[1].origin.x >= line.origin.x + line.size.width)
            #expect(rects[2].origin.y >= rects[1].origin.y + rects[1].size.height)
            #expect(line.size.height > line.size.width)
        }

        @Test("A DIVIDER after a step's parts splits it from the next step")
        func dividerAfterTheParts() throws {
            let divider: LPubCallout = lpub("CALLOUT DIVIDER")
            let fixture = calloutFixture(before: [handedOver()],
                                         steps: [[part("3003.dat"), divider], [part("3004.dat")]])
            let box = try onPage(fixture)

            #expect(box.pictures.count == 2)
            #expect(box.dividerCount == 1)
        }

        // MARK: - One submodel in two colors

        /// sub.ldr placed in red and, turned a quarter, in blue. The second step
        /// calls out the blue one alone.
        private func twoColors(mode: String?) -> (file: LDrawFile, model: LDrawModel, steps: [LDrawStep]) {
            let file = LDrawFile()
            let main = LDrawMPDModel.model() as! LDrawMPDModel
            main.setModelName("main.ldr")
            file.addSubmodel(main)
            let sub = LDrawMPDModel.model() as! LDrawMPDModel
            sub.setModelName("sub.ldr")
            file.addSubmodel(sub)
            addStep(to: sub, [part("3003.dat")])
            addStep(to: sub, [part("3004.dat")])

            func blue() -> LDrawPart {
                let color = LDrawColor()
                color.setColorCode(LDrawColorT(rawValue: 1)!)

                var components = IdentityComponents
                components.rotate = Tuple3(x: 0, y: 90, z: 0)

                let placed = part("sub.ldr")
                placed.setLDrawColor(color)
                placed.setTransformComponents(components)
                return placed
            }

            let text = "CALLOUT BEGIN" + (mode.map { " \($0)" } ?? "")
            let begin: LPubCallout = lpub(text)
            let end: LPubCallout = lpub("CALLOUT END")
            let both = addStep(to: main, [handedOver(), begin, part("sub.ldr"), blue(), end])
            let beginAlone: LPubCallout = lpub(text)
            let endAlone: LPubCallout = lpub("CALLOUT END")
            let alone = addStep(to: main, [beginAlone, blue(), endAlone])

            return (file, main, [both, alone])
        }

        @Test("A rotated callout turns each row by a placement of its own color")
        func rotatedRowsTurnByTheirOwnPlacement() throws {
            let fixture = twoColors(mode: "ROTATED")
            let both = try onPage((fixture.file, fixture.model, LDrawStepCallout.callouts(forStep: fixture.steps[0])))
            let alone = try onPage((fixture.file, fixture.model, LDrawStepCallout.callouts(forStep: fixture.steps[1])))

            try #require(both.pictures.count == 2 && alone.pictures.count == 1)
            #expect(both.pictures[1].contentKey == alone.pictures[0].contentKey,
                    "the blue one is turned as it is placed")
            #expect(both.pictures[0].rect.size.width != both.pictures[1].rect.size.width
                    || both.pictures[0].contentKey != both.pictures[1].contentKey)
        }

        @Test("A submodel placed in two colors has its steps counted once")
        func twoColorsCountTheStepsOnce() throws {
            let fixture = twoColors(mode: nil)
            let callout = try #require(LDrawStepCallout.callouts(forStep: fixture.steps[0]).first)

            #expect(callout.entries.count == 2)
            #expect(callout.stepCount == 2)
        }

        @Test("A submodel placed in two colors shows its steps once, with a count of every placement")
        func twoColorsShowTheStepsOnce() throws {
            let fixture = twoColors(mode: nil)
            let box = try onPage((fixture.file, fixture.model, LDrawStepCallout.callouts(forStep: fixture.steps[0])))

            #expect(box.pictures.count == 2)
            #expect(box.steps.map(\.number) == [1, 2])
            #expect(box.labels.filter { $0.isStepNumber == false }.map(\.text) == ["×2"])
        }

        @Test("Shown finished, a submodel placed in two colors keeps a picture for each color")
        func twoColorsFinishedKeepTheirRows() throws {
            let fixture = twoColors(mode: "ASSEMBLED")
            let box = try onPage((fixture.file, fixture.model, LDrawStepCallout.callouts(forStep: fixture.steps[0])))

            #expect(box.pictures.count == 2)
            #expect(box.pictures[0].contentKey != box.pictures[1].contentKey)
        }

        // MARK: - On the page: the steps and their dividers

        @Test("A strip lists the steps it shows, and says which of them a divider can go before")
        func stripListsItsSteps() throws {
            let divider: LPubCallout = lpub("CALLOUT DIVIDER")
            let fixture = calloutFixture(before: [handedOver()],
                                         steps: [[part("3003.dat")], [divider, part("3004.dat")], [part("3005.dat")]])
            let box = try onPage(fixture)
            let submodel = try #require(fixture.callouts.first?.submodels.first)
            // A new model starts with a step of its own, which builds nothing.
            let inFile = (submodel.steps() as! [LDrawStep]).filter { LDrawStepCallout.stepBuildsSomething($0) }
            let steps = box.steps

            #expect(steps.map(\.number) == [1, 2, 3])
            #expect(steps.map(\.isFirstOfSubmodel) == [true, false, false])
            #expect(steps.map(\.hasDividerBefore) == [false, true, false])

            for (index, shown) in steps.enumerated() {
                #expect(shown.step === inFile[index])
            }
        }

        @Test("A step that builds nothing is not listed, and the numbers skip it")
        func emptyStepsAreNotListed() throws {
            let hidden: LPubCommand = lpubLine("PLI BEGIN IGN")
            let fixture = calloutFixture(before: [handedOver()],
                                         steps: [[part("3003.dat")], [hidden], [part("3004.dat")]])
            let box = try onPage(fixture)
            let submodel = try #require(fixture.callouts.first?.submodels.first)
            let inFile = submodel.steps() as! [LDrawStep]

            #expect(box.steps.map(\.number) == [1, 2])
            #expect(box.steps.last?.step === inFile.last)
        }

        @Test("A point on a step's picture gives that step")
        func aPointGivesItsStep() throws {
            let divider: LPubCallout = lpub("CALLOUT DIVIDER")
            let fixture = calloutFixture(before: [handedOver()],
                                         steps: [[part("3003.dat")], [divider, part("3004.dat")], [part("3005.dat")]])
            let box = try onPage(fixture)
            let pictures = box.pictures.filter { $0.isPartsList == false }

            try #require(pictures.count == 3)

            for (index, picture) in pictures.enumerated() {
                let middle = Point2(x: picture.rect.origin.x + picture.rect.size.width / 2,
                                    y: picture.rect.origin.y + picture.rect.size.height / 2)

                #expect(box.step(at: middle)?.number == UInt(index + 1))
            }
        }

        @Test("The steps' shares and the room between two columns fill the inside of the box")
        func sharesFillTheBox() throws {
            let divider: LPubCallout = lpub("CALLOUT DIVIDER")
            let border = "CALLOUT BORDER GLOBAL SQUARE Black 0.04 MARGINS 0.2 0.3"
            let box = try styled([border], steps: [[part("3003.dat")], [divider, part("3004.dat")], [part("3005.dat")]])
            let frame = box.frameRect

            // 0.24 and 0.34 inch of padding at 100 points to the inch.
            let inside = Box2(origin: Point2(x: frame.origin.x + 24, y: frame.origin.y + 34),
                              size: Size2(width: frame.size.width - 48, height: frame.size.height - 68))
            let line = box.dividerRect(at: 0)
            var area = 0.0

            for shown in box.steps {
                area += shown.rect.size.width * shown.rect.size.height

                #expect(shown.rect.origin.x >= inside.origin.x - 0.001)
                #expect(shown.rect.origin.y >= inside.origin.y - 0.001)
                #expect(shown.rect.origin.x + shown.rect.size.width <= inside.origin.x + inside.size.width + 0.001)
                #expect(shown.rect.origin.y + shown.rect.size.height <= inside.origin.y + inside.size.height + 0.001)
            }

            // What is left is the band the line runs down: the line and LPub3D's
            // 0.05 inch on each side of it.
            let band = (line.size.width + 10) * inside.size.height
            #expect(abs(area + band - inside.size.width * inside.size.height) < 0.01)
        }

        @Test("A point on the line between two columns, or beside it, gives the step after the line")
        func aPointOnTheLineGivesTheStepAfter() throws {
            let divider: LPubCallout = lpub("CALLOUT DIVIDER")
            let fixture = calloutFixture(before: [handedOver()],
                                         steps: [[part("3003.dat")], [divider, part("3004.dat")], [part("3005.dat")]])
            let box = try onPage(fixture)
            let line = box.dividerRect(at: 0)
            let level = line.origin.y + line.size.height / 2

            #expect(box.step(at: Point2(x: line.origin.x + line.size.width / 2, y: level))?.number == 2)
            #expect(box.step(at: Point2(x: line.origin.x - 3, y: level))?.number == 2, "in the room before the line")
            #expect(box.step(at: Point2(x: line.origin.x + line.size.width + 3, y: level))?.number == 2)
        }

        @Test("A point in the box's padding, or outside the box, gives no step")
        func aPointOffTheStepsGivesNone() throws {
            let box = try styled(["CALLOUT BORDER GLOBAL SQUARE Black 0.04 MARGINS 0.2 0.3"])
            let frame = box.frameRect

            #expect(box.step(at: Point2(x: frame.origin.x + 2, y: frame.origin.y + 2)) == nil)
            #expect(box.step(at: Point2(x: frame.origin.x - 20, y: frame.origin.y - 20)) == nil)
        }

        @Test("A box that shows its submodels finished lists no steps")
        func finishedSubmodelsHaveNoSteps() throws {
            let summary = try #require(boxes(calloutFixture(before: [handedOver()])).first)
            let assembled = try onPage(calloutFixture(before: [handedOver()], mode: "ASSEMBLED"))
            let frame = assembled.frameRect

            #expect(summary.steps.isEmpty)
            #expect(assembled.steps.isEmpty)
            #expect(assembled.step(at: Point2(x: frame.origin.x + frame.size.width / 2,
                                              y: frame.origin.y + frame.size.height / 2)) == nil)
        }

        @Test("A moved box takes its steps with it")
        func stepsMoveWithTheBox() throws {
            let fixture = calloutFixture(before: [handedOver()])
            let first = try #require(LDrawStepCalloutBox.boxes(forCallouts: fixture.callouts,
                                                               inModel: fixture.model,
                                                               options: options(pointsPerPageInch: 100)).first)
            let page = Box2(origin: Point2(x: 300, y: 200), size: Size2(width: 600, height: 500))
            let pageOptions = options(host: page, pointsPerPageInch: 100)
            let moved = try #require(LDrawStepCalloutBox.boxes(forCallouts: fixture.callouts,
                                                               inModel: fixture.model,
                                                               options: pageOptions).first)
            let shift = Point2(x: moved.frameRect.origin.x - first.frameRect.origin.x,
                               y: moved.frameRect.origin.y - first.frameRect.origin.y)

            try #require(first.steps.count == 2 && moved.steps.count == 2)
            #expect(shift.x != 0 || shift.y != 0)

            for (here, there) in zip(first.steps, moved.steps) {
                #expect(abs(there.rect.origin.x - here.rect.origin.x - shift.x) < 0.001)
                #expect(abs(there.rect.origin.y - here.rect.origin.y - shift.y) < 0.001)
            }
        }

        @Test("Steps are numbered when there is more than one, unless the file hides the numbers")
        func stripNumbersItsSteps() throws {
            let numbered = try onPage(calloutFixture(before: [handedOver()]))
            #expect(numbered.labels.filter { $0.isStepNumber }.map { $0.text } == ["1", "2"])

            let single = try onPage(calloutFixture(before: [handedOver()], steps: [[part("3003.dat")]]))
            #expect(single.labels.isEmpty)

            let off: LPubAssemShowStepNumber = lpub("ASSEM SHOW_STEP_NUMBER GLOBAL FALSE")
            let hidden = try onPage(calloutFixture(before: [handedOver(), off]))
            #expect(hidden.labels.isEmpty)
        }

        @Test("A submodel placed twice gets its count in its last step")
        func stripCountsItsInstances() throws {
            let box = try onPage(calloutFixture(before: [handedOver()], placements: 2))
            let counts = box.labels.filter { $0.isStepNumber == false }
            let count = try #require(counts.first)
            let last = try #require(box.pictures.last).rect

            #expect(counts.count == 1)
            #expect(count.text == "×2")
            #expect(count.rect.origin.y + count.rect.size.height > last.origin.y)
            #expect(count.rect.origin.x + count.rect.size.width <= box.frameRect.origin.x + box.frameRect.size.width)
        }

        @Test("A callout that shows its submodel finished gets one picture and no numbers")
        func finishedCalloutIsOnePicture() throws {
            for mode in ["ASSEMBLED", "ROTATED"] {
                let box = try onPage(calloutFixture(mode: mode))
                let step = try #require(box.pictures.first?.model.steps().first as? LDrawStep)

                #expect(box.pictures.count == 1, "\(mode)")
                #expect(step.subdirectives().count == 2, "\(mode)")
                #expect(box.labels.isEmpty, "\(mode)")
            }
        }

        /// LPub3D's default: each step in the box has a parts list of its own.
        @Test("Each step lists its own parts unless the step's list has them")
        func stripListsEachStepsParts() throws {
            let box = try onPage(calloutFixture())
            let lists = box.pictures.filter { $0.isPartsList }

            #expect(box.pictures.count == 4)
            #expect(lists.count == 2)
            #expect(lists.allSatisfy { $0.layout?.placements.count == 1 })

            let hidden = try onPage(calloutFixture(), showsLists: false)
            #expect(hidden.pictures.count == 2)
        }

        @Test("Everything a box holds is inside its frame")
        func stripStaysInsideItsFrame() throws {
            let divider: LPubCallout = lpub("CALLOUT DIVIDER")
            let fixture = calloutFixture(placements: 2,
                                         steps: [[part("3003.dat")], [divider, part("3004.dat")], [part("3005.dat")]])
            let box = try onPage(fixture)
            let frame = box.frameRect
            var rects = box.pictures.map { $0.rect } + box.labels.map { $0.rect }

            for index in 0..<Int(box.dividerCount) {
                rects.append(box.dividerRect(at: UInt(index)))
            }

            for rect in rects {
                #expect(rect.origin.x >= frame.origin.x)
                #expect(rect.origin.y >= frame.origin.y)
                #expect(rect.origin.x + rect.size.width <= frame.origin.x + frame.size.width + 0.001)
                #expect(rect.origin.y + rect.size.height <= frame.origin.y + frame.size.height + 0.001)
            }
        }

        // MARK: - On the page: where the box goes

        private let page = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: 1000, height: 800))
        private let assembly = Box2(origin: Point2(x: 400, y: 300), size: Size2(width: 200, height: 100))

        /// LPub3D's margin between a callout and what it is placed against, at
        /// 100 points to the page inch.
        private var margin: Double { LDrawStepPartListPolicy.frameInset(forPointsPerPageInch: 100) }

        private func placed(_ line: String?, assembly: Box2? = nil, list: Box2? = nil) throws -> Box2 {
            var inside: [LDrawDirective] = []

            if let line {
                let placement: LPubPlacement = lpub(line)
                inside.append(placement)
            }

            let fixture = calloutFixture(before: [handedOver()], inside: inside, steps: [[part("3003.dat")]])
            let options = options(host: page, list: list, assembly: assembly ?? self.assembly, pointsPerPageInch: 100)

            return try #require(LDrawStepCalloutBox.boxes(forCallouts: fixture.callouts,
                                                          inModel: fixture.model,
                                                          options: options).first).frameRect
        }

        @Test("With no PLACEMENT line a box goes to the right of the assembly, in the middle")
        func defaultPlacementIsRightCenter() throws {
            let frame = try placed(nil)

            #expect(frame.origin.x == 600 + margin)
            #expect(abs(frame.origin.y - (300 + (100 - frame.size.height) / 2)) < 0.001)
        }

        @Test("Outside, a side puts the box past that edge, and the second word says where along it")
        func outsidePlacements() throws {
            let below = try placed("CALLOUT PLACEMENT BOTTOM CENTER ASSEM OUTSIDE")
            #expect(abs(below.origin.x - (400 + (200 - below.size.width) / 2)) < 0.001)
            #expect(below.origin.y == 400 + margin)

            let above = try placed("CALLOUT PLACEMENT TOP LEFT ASSEM OUTSIDE")
            #expect(above.origin.x == 400)
            #expect(above.origin.y == 300 - above.size.height - margin)

            let aboveRight = try placed("CALLOUT PLACEMENT TOP RIGHT ASSEM OUTSIDE")
            #expect(abs(aboveRight.origin.x - (600 - aboveRight.size.width)) < 0.001)

            let rightBottom = try placed("CALLOUT PLACEMENT RIGHT BOTTOM ASSEM OUTSIDE")
            #expect(rightBottom.origin.x == 600 + margin)
            #expect(abs(rightBottom.origin.y - (400 - rightBottom.size.height)) < 0.001)

            let left = try placed("CALLOUT PLACEMENT LEFT TOP ASSEM OUTSIDE")
            #expect(left.origin.x == 400 - left.size.width - margin)
            #expect(left.origin.y == 300)
        }

        @Test("Outside, a corner puts the box diagonally past it")
        func outsideCorners() throws {
            let topLeft = try placed("CALLOUT PLACEMENT TOP_LEFT ASSEM OUTSIDE")
            #expect(topLeft.origin.x == 400 - topLeft.size.width - margin)
            #expect(topLeft.origin.y == 300 - topLeft.size.height - margin)

            let bottomRight = try placed("CALLOUT PLACEMENT BOTTOM_RIGHT ASSEM OUTSIDE")
            #expect(bottomRight.origin.x == 600 + margin)
            #expect(bottomRight.origin.y == 400 + margin)
        }

        @Test("Inside, the box sits against the edge from within")
        func insidePlacements() throws {
            let big = Box2(origin: Point2(x: 200, y: 200), size: Size2(width: 600, height: 400))

            let corner = try placed("CALLOUT PLACEMENT BOTTOM_RIGHT ASSEM INSIDE", assembly: big)
            #expect(abs(corner.origin.x - (800 - corner.size.width - margin)) < 0.001)
            #expect(abs(corner.origin.y - (600 - corner.size.height - margin)) < 0.001)

            let bottom = try placed("CALLOUT PLACEMENT BOTTOM ASSEM INSIDE", assembly: big)
            #expect(abs(bottom.origin.x - (200 + (600 - bottom.size.width) / 2)) < 0.001)
            #expect(abs(bottom.origin.y - (600 - bottom.size.height - margin)) < 0.001)

            let middle = try placed("CALLOUT PLACEMENT CENTER ASSEM INSIDE", assembly: big)
            #expect(abs(middle.origin.x - (200 + (600 - middle.size.width) / 2)) < 0.001)
            #expect(abs(middle.origin.y - (200 + (400 - middle.size.height) / 2)) < 0.001)
        }

        @Test("The offset moves the box by a share of what it is placed against")
        func offsetsAreSharesOfTheAnchor() throws {
            let plain = try placed("CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE")
            let moved = try placed("CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE 0.1 -0.2")

            #expect(abs(moved.origin.x - (plain.origin.x + 20)) < 0.001)
            #expect(abs(moved.origin.y - (plain.origin.y - 20)) < 0.001)
        }

        @Test("A box placed against the page or the parts list uses that, not the assembly")
        func otherAnchors() throws {
            let onPage = try placed("CALLOUT PLACEMENT TOP_LEFT PAGE INSIDE")
            #expect(onPage.origin.x == margin)
            #expect(onPage.origin.y == margin)

            let list = Box2(origin: Point2(x: 10, y: 10), size: Size2(width: 150, height: 60))
            let byList = try placed("CALLOUT PLACEMENT BOTTOM LEFT PLI OUTSIDE", list: list)
            #expect(byList.origin.x == 10)
            #expect(byList.origin.y == 70 + margin)

            // Anything Bricksmith does not draw stands for the assembly.
            let byGroup = try placed("CALLOUT PLACEMENT RIGHT CENTER MULTI_STEP OUTSIDE")
            #expect(byGroup.origin.x == 600 + margin)
        }

        @Test("A box goes where the file says even when that is off the page, as in LPub3D")
        func boxesMayLeaveThePage() throws {
            let atTheEdge = Box2(origin: Point2(x: 850, y: 20), size: Size2(width: 140, height: 60))

            let right = try placed("CALLOUT PLACEMENT RIGHT CENTER ASSEM OUTSIDE", assembly: atTheEdge)
            #expect(right.origin.x == 990 + margin)
            #expect(right.origin.x + right.size.width > 1000)

            let above = try placed("CALLOUT PLACEMENT TOP CENTER ASSEM OUTSIDE", assembly: atTheEdge)
            #expect(above.origin.y < 0)
        }

        // MARK: - On the page: how the box looks

        private func styled(_ lines: [String],
                            placements: Int = 1,
                            steps: [[LDrawDirective]]? = nil) throws -> LDrawStepCalloutBox {
            let metas: [LDrawDirective] = lines.map { text in
                let command: LPubCommand = lpubLine(text)
                return command
            }

            return try onPage(calloutFixture(before: [handedOver()] + metas, placements: placements, steps: steps))
        }

        /// Parses the text, so the line gets the class the file would give it.
        private func lpubLine(_ text: String) -> LPubCommand {
            let lines = ["0 !LPUB " + text, "0 STEP"]
            let step = LDrawStep(lines: lines, in: NSRange(location: 0, length: lines.count), parentGroup: nil)

            return (step!.subdirectives() as! [LDrawDirective])[0] as! LPubCommand
        }

        @Test("The room inside a box is its border's margin and thickness")
        func borderPadsTheBox() throws {
            let box = try styled(["CALLOUT BORDER GLOBAL SQUARE Black 0.04 MARGINS 0.2 0.3"],
                                 steps: [[part("3003.dat")]])
            let picture = try #require(box.pictures.first).rect

            #expect(abs(picture.origin.x - box.frameRect.origin.x - 24) < 0.001)
            #expect(abs(picture.origin.y - box.frameRect.origin.y - 34) < 0.001)
            #expect(abs(box.frameRect.size.width - (picture.size.width + 48)) < 0.001)
            #expect(abs(box.frameRect.size.height - (picture.size.height + 68)) < 0.001)
        }

        @Test("A box with no border keeps the margin and loses the thickness")
        func noBorderNoThickness() throws {
            let box = try styled(["CALLOUT BORDER GLOBAL NONE MARGINS 0.2 0.3"], steps: [[part("3003.dat")]])
            let picture = try #require(box.pictures.first).rect

            #expect(abs(picture.origin.x - box.frameRect.origin.x - 20) < 0.001)
            #expect(box.style?.borderShape == LPubBorderShape.none)
        }

        @Test("Two steps of a box are one ASSEM margin apart")
        func assemblyMarginsSeparateTheSteps() throws {
            let off = "ASSEM SHOW_STEP_NUMBER GLOBAL FALSE"
            let down = try styled([off, "CALLOUT ASSEM MARGINS GLOBAL 0.5 0.25"])
            let rects = down.pictures.map { $0.rect }

            #expect(abs(rects[1].origin.y - (rects[0].origin.y + rects[0].size.height + 25)) < 0.001)

            let across = try styled([off, "CALLOUT ASSEM MARGINS GLOBAL 0.5 0.25", "CALLOUT ALLOC HORIZONTAL"])
            let side = across.pictures.map { $0.rect }

            #expect(abs(side[1].origin.x - (side[0].origin.x + side[0].size.width + 50)) < 0.001)
        }

        @Test("The line between two groups is as thick as SEPARATOR says, with its margin on each side")
        func separatorDividesTheGroups() throws {
            let divider: LPubCallout = lpub("CALLOUT DIVIDER")
            let lines = ["ASSEM SHOW_STEP_NUMBER GLOBAL FALSE", "CALLOUT SEPARATOR GLOBAL 0.02 #4c4c4c 0.3 0.1"]
            let box = try styled(lines, steps: [[part("3003.dat")], [divider, part("3004.dat")]])
            let rects = box.pictures.map { $0.rect }
            let line = box.dividerRect(at: 0)

            #expect(abs(line.size.width - 2) < 0.001)
            #expect(abs(line.origin.x - (rects[0].origin.x + rects[0].size.width + 30)) < 0.001)
            #expect(abs(rects[1].origin.x - (line.origin.x + line.size.width + 30)) < 0.001)
        }

        @Test("A step's number is as tall as its FONT, read as dots at the file's resolution")
        func fontSizesTheStepNumbers() throws {
            let small = try styled(["CALLOUT STEP_NUMBER FONT GLOBAL \"Arial,30,-1,5,50,0,0,0,0,0\""])
            let large = try styled(["CALLOUT STEP_NUMBER FONT GLOBAL \"Arial,60,-1,5,50,0,0,0,0,0\""])
            let smallLabel = try #require(small.labels.first { $0.isStepNumber }).rect
            let largeLabel = try #require(large.labels.first { $0.isStepNumber }).rect

            // 30 dots at 150 to the inch is a fifth of an inch: 20 points here.
            #expect(abs(smallLabel.size.height - (20 * 1.15 + 2 * 4.0 / 150.0 * 100)) < 0.001)
            #expect(largeLabel.size.height > smallLabel.size.height * 1.8)
            #expect(small.style?.stepNumberText.fontFamily == "Arial")
            #expect(small.style?.stepNumberText.isBold == false)
        }

        @Test("The count of a box built twice takes the INSTANCE_COUNT font and its color")
        func fontSizesTheCount() throws {
            let box = try styled(["CALLOUT INSTANCE_COUNT FONT GLOBAL \"Arial,48,-1,5,75,1,0,0,0,0\"",
                                  "CALLOUT INSTANCE_COUNT FONT_COLOR GLOBAL #ff0000"],
                                 placements: 2, steps: [[part("3003.dat")]])
            let count = try #require(box.labels.first { $0.isStepNumber == false })
            let text = try #require(box.style?.countText)

            #expect(abs(text.fontSize - 48.0 / 150.0) < 1e-9)
            #expect(text.isBold)
            #expect(text.isItalic)
            #expect(text.color.red == 1.0)
            #expect(text.color.green == 0.0)
            #expect(count.rect.size.height > text.fontSize * 100)
        }

        @Test("Off the page a box has no style of the file's")
        func noStyleOffThePage() throws {
            let fixture = calloutFixture(before: [handedOver()])
            let box = try #require(boxes(fixture).first)

            #expect(box.style == nil)
        }

        // MARK: - Arrows

        /// LPub3D draws the arrows the file lists, so a box that only explains
        /// something can have none.
        @Test("A callout with no POINTER line has no arrows")
        func noPointerNoArrow() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)

            #expect(box.tipCount == 0)
        }

        @Test("A box has one arrow for each pointer, to where a part is placed")
        func tipsAreThePlacements() throws {
            let file = LDrawFile()
            let main = LDrawMPDModel.model() as! LDrawMPDModel
            main.setModelName("main.ldr")
            file.addSubmodel(main)
            let sub = LDrawMPDModel.model() as! LDrawMPDModel
            sub.setModelName("sub.ldr")
            file.addSubmodel(sub)
            addStep(to: sub, [part("3003.dat")])

            let begin: LPubCallout = lpub("CALLOUT BEGIN")
            let end: LPubCallout = lpub("CALLOUT END")
            let first: LPubCalloutPointer = lpub("CALLOUT POINTER TOP_LEFT 0.367 0.656 0")
            let second: LPubCalloutPointer = lpub("CALLOUT POINTER TOP 0.392 0.521 0.399 0")
            let step = addStep(to: main, [begin,
                                          part("sub.ldr", at: Point3(x: 90, y: -40, z: -10)),
                                          part("sub.ldr", at: Point3(x: -30, y: -40, z: -10)),
                                          first, second,
                                          end])

            let box = try #require(boxes((file, main, LDrawStepCallout.callouts(forStep: step))).first)

            #expect(box.tipCount == 2)
            #expect(box.tipModelPoint(at: 0).x == 90)
            #expect(box.tipModelPoint(at: 1).x == -30)
            #expect(box.tipModelPoint(at: 1).y == -40)
        }

        @Test("There are never more arrows than placements, nor than pointers")
        func arrowsAreTheFewerOfTheTwo() throws {
            let file = LDrawFile()
            let main = LDrawMPDModel.model() as! LDrawMPDModel
            main.setModelName("main.ldr")
            file.addSubmodel(main)
            let sub = LDrawMPDModel.model() as! LDrawMPDModel
            sub.setModelName("sub.ldr")
            file.addSubmodel(sub)
            addStep(to: sub, [part("3003.dat")])

            let begin: LPubCallout = lpub("CALLOUT BEGIN")
            let end: LPubCallout = lpub("CALLOUT END")
            let pointer: LPubCalloutPointer = lpub("CALLOUT POINTER TOP_LEFT 0.367 0.656 0")
            let extra: LPubCalloutPointer = lpub("CALLOUT POINTER TOP 0.392 0.521 0.399 0")

            let onePointer = addStep(to: main, [begin, part("sub.ldr"), part("sub.ldr"), pointer, end])
            #expect(boxes((file, main, LDrawStepCallout.callouts(forStep: onePointer))).first?.tipCount == 1)

            let begin2: LPubCallout = lpub("CALLOUT BEGIN")
            let end2: LPubCallout = lpub("CALLOUT END")
            let pointer2: LPubCalloutPointer = lpub("CALLOUT POINTER TOP_LEFT 0.367 0.656 0")
            let onePlacement = addStep(to: main, [begin2, part("sub.ldr"), pointer2, extra, end2])
            #expect(boxes((file, main, LDrawStepCallout.callouts(forStep: onePlacement))).first?.tipCount == 1)
        }

        /// A square outline 100 wide with its corner at these coordinates, with a
        /// point in the middle that is no corner.
        private func square(atX x: Double, y: Double) -> Data {
            var points = [Point2(x: x, y: y), Point2(x: x + 100, y: y), Point2(x: x + 100, y: y + 100),
                          Point2(x: x, y: y + 100), Point2(x: x + 50, y: y + 50)]
            return Data(bytes: &points, count: points.count * MemoryLayout<Point2>.stride)
        }

        /// How near a corner an arrow may leave a box off the page, in points.
        private let arrowInset = 7.0

        /// How far short of an outline an arrow stops off the page, in points.
        private let arrowGap = 4.0

        /// How far apart two arrows leave one edge off the page, in points.
        private let arrowSpacing = 6.0

        /// The arrows a box draws to these middles, in their order.
        private func arrows(of box: LDrawStepCalloutBox,
                            to middles: [Point2],
                            outlines: [Data] = []) -> [LDrawStepCalloutArrow] {
            var points = middles
            let data = Data(bytes: &points, count: points.count * MemoryLayout<Point2>.stride)
            let drawn = box.arrows(toMiddles: data, outlines: outlines)
            let stride = MemoryLayout<LDrawStepCalloutArrow>.stride

            return (0..<drawn.count / stride).map { index in
                drawn.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: index * stride, as: LDrawStepCalloutArrow.self)
                }
            }
        }

        /// The one arrow a box draws to a middle.
        private func arrow(of box: LDrawStepCalloutBox,
                           to middle: Point2,
                           outline: Data? = nil) throws -> LDrawStepCalloutArrow {
            try #require(arrows(of: box, to: [middle], outlines: outline.map { [$0] } ?? []).first)
        }

        /// Whether two arrows cross between their starts and the middles they are
        /// aimed at.
        private func cross(_ first: LDrawStepCalloutArrow, _ firstMiddle: Point2,
                           _ second: LDrawStepCalloutArrow, _ secondMiddle: Point2) -> Bool {
            func side(_ origin: Point2, _ end: Point2, _ point: Point2) -> Double {
                (end.x - origin.x) * (point.y - origin.y) - (end.y - origin.y) * (point.x - origin.x)
            }
            let a = side(first.start, firstMiddle, second.start) * side(first.start, firstMiddle, secondMiddle)
            let b = side(second.start, secondMiddle, first.start) * side(second.start, secondMiddle, firstMiddle)

            return a < 0 && b < 0
        }

        @Test("An arrow leaves the box at the point of its edge nearest the placement's middle")
        func arrowLeavesFromTheNearestEdge() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width
            let level = frame.origin.y + frame.size.height / 2
            let across = frame.origin.x + frame.size.width / 2

            // Straight out to the right: the same height on the right edge.
            var arrow = try arrow(of: box, to: Point2(x: right + 300, y: level))
            #expect(arrow.start.x == right)
            #expect(arrow.start.y == level)

            // Straight up: the same place along the top edge.
            arrow = try self.arrow(of: box, to: Point2(x: across, y: frame.origin.y - 300))
            #expect(arrow.start.x == across)
            #expect(arrow.start.y == frame.origin.y)
        }

        @Test("An arrow to a point past a corner leaves the nearer edge, a little way from the corner")
        func arrowKeepsClearOfTheCorners() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width
            let bottom = frame.origin.y + frame.size.height
            let alongSide = min(arrowInset, frame.size.height / 2)
            let alongBottom = min(arrowInset, frame.size.width / 2)

            // Further to the right than down: the right edge, short of its bottom.
            var arrow = try arrow(of: box, to: Point2(x: right + 300, y: bottom + 200))
            #expect(arrow.start.x == right)
            #expect(abs(arrow.start.y - (bottom - alongSide)) < 0.0001)

            // Further down than to the right: the bottom edge, short of its right.
            arrow = try self.arrow(of: box, to: Point2(x: right + 100, y: bottom + 300))
            #expect(arrow.start.y == bottom)
            #expect(abs(arrow.start.x - (right - alongBottom)) < 0.0001)

            // Up and to the left: the top edge, short of its left.
            arrow = try self.arrow(of: box, to: Point2(x: frame.origin.x - 50, y: frame.origin.y - 400))
            #expect(arrow.start.y == frame.origin.y)
            #expect(abs(arrow.start.x - (frame.origin.x + alongBottom)) < 0.0001)

            // A point over the edge but close to its end is kept clear as well.
            arrow = try self.arrow(of: box, to: Point2(x: right - 1, y: bottom + 300))
            #expect(abs(arrow.start.x - (right - alongBottom)) < 0.0001)
        }

        @Test("On the page an arrow keeps clear of a corner by the border's radius and half its margin")
        func arrowInsetOnThePage() throws {
            // A radius of 15 dots is a tenth of an inch at 150 to the inch.
            let box = try styled(["CALLOUT BORDER GLOBAL ROUND Black 0.02 15 MARGINS 0.1 0.2"])
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width
            let bottom = frame.origin.y + frame.size.height

            var arrow = try arrow(of: box, to: Point2(x: right + 100, y: bottom + 300))
            #expect(abs(arrow.start.x - (right - min(15, frame.size.width / 2))) < 0.0001)

            arrow = try self.arrow(of: box, to: Point2(x: right + 300, y: bottom + 100))
            #expect(abs(arrow.start.y - (bottom - min(20, frame.size.height / 2))) < 0.0001)
        }

        @Test("A square box with no margin still keeps an arrow off its corner")
        func arrowInsetHasAFloor() throws {
            let box = try styled(["CALLOUT BORDER GLOBAL SQUARE Black 0.02 MARGINS 0 0"])
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width
            let bottom = frame.origin.y + frame.size.height

            // The space two arrows keep between them: 0.08 inch at 100 points
            // to the page inch.
            let arrow = try arrow(of: box, to: Point2(x: right + 100, y: bottom + 300))
            #expect(abs(arrow.start.x - (right - min(8, frame.size.width / 2))) < 0.0001)
        }

        @Test("Two arrows past one corner leave the edge a small space apart")
        func arrowsFromOneCornerLeaveApart() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width
            let bottom = frame.origin.y + frame.size.height
            let nearCorner = bottom - arrowInset

            let drawn = arrows(of: box, to: [Point2(x: right + 300, y: bottom + 200),
                                             Point2(x: right + 400, y: bottom + 100)])
            let starts = drawn.map(\.start.y).sorted()

            try #require(drawn.count == 2)
            #expect(drawn.allSatisfy { $0.start.x == right })
            #expect(abs(starts[1] - nearCorner) < 0.0001, "one keeps the place a lone arrow has")
            #expect(abs(starts[0] - (nearCorner - arrowSpacing)) < 0.0001, "the other is further from the corner")
        }

        @Test("Arrows past one corner leave in the order that keeps them from crossing")
        func arrowsFromOneCornerDoNotCross() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width
            let bottom = frame.origin.y + frame.size.height

            // Both past the bottom right corner: one far down, one barely.
            let steep = Point2(x: right + 310, y: bottom + 300)
            let flat = Point2(x: right + 300, y: bottom + 20)

            for middles in [[steep, flat], [flat, steep]] {
                let drawn = arrows(of: box, to: middles)
                let toSteep = drawn[middles[0].y == steep.y ? 0 : 1]
                let toFlat = drawn[middles[0].y == steep.y ? 1 : 0]

                #expect(toSteep.start.y > toFlat.start.y, "the one going further down leaves nearer the corner")
                #expect(cross(drawn[0], middles[0], drawn[1], middles[1]) == false)
            }
        }

        @Test("Arrows to placements one behind the other leave a small space apart")
        func arrowsOnOneLineLeaveApart() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width
            let top = frame.origin.y + arrowInset

            // Both level with the same point of the right edge.
            let drawn = arrows(of: box, to: [Point2(x: right + 400, y: top), Point2(x: right + 200, y: top)])

            try #require(drawn.count == 2)
            #expect(abs(abs(drawn[0].start.y - drawn[1].start.y) - arrowSpacing) < 0.0001)
            #expect(drawn[1].start.y == top, "the nearer one keeps the straight way")
        }

        @Test("Arrows that start further apart than the space stay where they are")
        func arrowsFarApartStayPut() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)
            let frame = box.frameRect
            let bottom = frame.origin.y + frame.size.height
            let first = frame.origin.x + arrowInset
            let second = first + arrowSpacing + 3

            let drawn = arrows(of: box, to: [Point2(x: first, y: bottom + 300), Point2(x: second, y: bottom + 200)])

            try #require(drawn.count == 2)
            #expect(drawn[0].start.x == first)
            #expect(drawn[1].start.x == second)
        }

        @Test("Arrows on different edges do not move each other")
        func arrowsOnOtherEdgesStayPut() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width
            let bottom = frame.origin.y + frame.size.height

            // Past the same corner, but one leaves the side and one the bottom.
            let drawn = arrows(of: box, to: [Point2(x: right + 300, y: bottom + 200),
                                             Point2(x: right + 100, y: bottom + 300)])

            try #require(drawn.count == 2)
            #expect(drawn[0].start.x == right)
            #expect(abs(drawn[0].start.y - (bottom - min(arrowInset, frame.size.height / 2))) < 0.0001)
            #expect(drawn[1].start.y == bottom)
            #expect(abs(drawn[1].start.x - (right - min(arrowInset, frame.size.width / 2))) < 0.0001)
        }

        @Test("On the page the space between two arrows is 0.08 inch")
        func arrowSpacingOnThePage() throws {
            let box = try onPage(calloutFixture(before: [handedOver()], steps: [[part("3003.dat")]]))
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width
            let bottom = frame.origin.y + frame.size.height

            let drawn = arrows(of: box, to: [Point2(x: right + 300, y: bottom + 200),
                                             Point2(x: right + 400, y: bottom + 100)])

            // 100 points to the page inch.
            try #require(drawn.count == 2)
            #expect(abs(abs(drawn[0].start.y - drawn[1].start.y) - 8) < 0.0001)
        }

        @Test("More arrows than an edge has room for share it out evenly")
        func crowdedArrowsShareTheEdge() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width
            let bottom = frame.origin.y + frame.size.height
            let low = frame.origin.y + arrowInset
            let high = bottom - arrowInset
            let count = Int((high - low) / arrowSpacing) + 4

            // All past the bottom right corner, fanned out.
            let middles = (0..<count).map { Point2(x: right + 2000, y: bottom + 10 + Double($0) * 40) }
            let drawn = arrows(of: box, to: middles)
            let starts = drawn.map(\.start.y).sorted()
            let step = (high - low) / Double(count - 1)

            try #require(drawn.count == count)
            #expect(abs(starts[0] - low) < 0.0001)
            #expect(abs(starts[count - 1] - high) < 0.0001)

            for index in 1..<count {
                #expect(abs(starts[index] - starts[index - 1] - step) < 0.0001)
            }
        }

        @Test("No two arrows of a box cross, wherever its placements are")
        func arrowsNeverCross() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)
            let frame = box.frameRect
            let middleX = frame.origin.x + frame.size.width / 2
            let middleY = frame.origin.y + frame.size.height / 2
            var seed: UInt64 = 20261003

            // The same numbers on every run.
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 11) / Double(UInt64(1) << 53)
            }

            for _ in 0..<200 {
                let count = 2 + Int(next() * 7)
                var middles: [Point2] = []

                // Close to the box and far from it, on every side.
                while middles.count < count {
                    let reach = (next() < 0.5) ? 60.0 : 600.0
                    let point = Point2(x: middleX + (next() - 0.5) * 2 * (frame.size.width / 2 + reach),
                                       y: middleY + (next() - 0.5) * 2 * (frame.size.height / 2 + reach))
                    let isInside = point.x >= frame.origin.x && point.x <= frame.origin.x + frame.size.width
                        && point.y >= frame.origin.y && point.y <= frame.origin.y + frame.size.height

                    if isInside == false {
                        middles.append(point)
                    }
                }

                let drawn = arrows(of: box, to: middles)
                try #require(drawn.count == count)

                for first in 0..<count {
                    for second in (first + 1)..<count {
                        #expect(cross(drawn[first], middles[first], drawn[second], middles[second]) == false,
                                "\(middles[first]) and \(middles[second])")
                    }
                }
            }
        }

        @Test("With no outline to stop at, an arrow's tip is the placement's middle")
        func arrowWithNoOutlineGoesToTheMiddle() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)
            let frame = box.frameRect
            let middle = Point2(x: frame.origin.x + frame.size.width + 300, y: frame.origin.y + frame.size.height / 2)

            var arrow = try arrow(of: box, to: middle)
            #expect(arrow.tip.x == middle.x && arrow.tip.y == middle.y)

            // Two points make no outline.
            var pair = [Point2(x: 0, y: 0), Point2(x: 5000, y: 5000)]
            let line = Data(bytes: &pair, count: pair.count * MemoryLayout<Point2>.stride)

            arrow = try self.arrow(of: box, to: middle, outline: line)
            #expect(arrow.tip.x == middle.x && arrow.tip.y == middle.y)
        }

        @Test("An arrow stops just short of the placement's outline, on its way to the middle")
        func arrowStopsAtTheOutline() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width
            let level = frame.origin.y + frame.size.height / 2

            // A square whose near edge is 250 past the box and whose middle is
            // 300 past it, level with the arrow's start.
            let outline = square(atX: right + 250, y: level - 50)
            let middle = Point2(x: right + 300, y: level)
            let arrow = try arrow(of: box, to: middle, outline: outline)

            #expect(arrow.start.x == right)
            #expect(abs(arrow.tip.x - (right + 250 - arrowGap)) < 0.0001)
            #expect(abs(arrow.tip.y - level) < 0.0001)
        }

        @Test("Each arrow stops at its own placement's outline")
        func arrowsStopAtTheirOwnOutlines() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width
            let high = frame.origin.y + arrowInset
            let low = frame.origin.y + frame.size.height - arrowInset

            let outlines = [square(atX: right + 250, y: high - 50), square(atX: right + 450, y: low - 50)]
            let drawn = arrows(of: box,
                               to: [Point2(x: right + 300, y: high), Point2(x: right + 500, y: low)],
                               outlines: outlines)

            try #require(drawn.count == 2)
            #expect(abs(drawn[0].tip.x - (right + 250 - arrowGap)) < 0.0001)
            #expect(abs(drawn[1].tip.x - (right + 450 - arrowGap)) < 0.0001)
        }

        @Test("On the page the space before the outline is LPub3D's margin")
        func arrowGapOnThePage() throws {
            let box = try onPage(calloutFixture(before: [handedOver()], steps: [[part("3003.dat")]]))
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width
            let level = frame.origin.y + frame.size.height / 2

            let arrow = try arrow(of: box,
                                  to: Point2(x: right + 300, y: level),
                                  outline: square(atX: right + 250, y: level - 50))

            // 0.05 inch at 100 points to the page inch.
            #expect(abs(arrow.tip.x - (right + 250 - 5)) < 0.0001)
        }

        @Test("An outline closer than that space leaves the tip at the arrow's start")
        func arrowGapNeverGoesBehindTheStart() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width
            let level = frame.origin.y + frame.size.height / 2

            let arrow = try arrow(of: box,
                                  to: Point2(x: right + 52, y: level),
                                  outline: square(atX: right + 2, y: level - 50))

            #expect(arrow.tip.x == arrow.start.x && arrow.tip.y == arrow.start.y)
        }

        @Test("Stopping at the outline keeps the arrow on the line to the middle")
        func arrowKeepsItsAngle() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width
            let bottom = frame.origin.y + frame.size.height

            // Down and to the right, so the arrow runs at a slant.
            let outline = square(atX: right + 250, y: bottom + 150)
            let middle = Point2(x: right + 300, y: bottom + 200)
            let arrow = try arrow(of: box, to: middle, outline: outline)

            let whole = (x: middle.x - arrow.start.x, y: middle.y - arrow.start.y)
            let drawn = (x: arrow.tip.x - arrow.start.x, y: arrow.tip.y - arrow.start.y)
            let length = (whole.x * whole.x + whole.y * whole.y).squareRoot()

            #expect(abs(whole.x * drawn.y - whole.y * drawn.x) < 0.0001, "the tip is on the line to the middle")
            #expect(arrow.tip.x < middle.x && arrow.tip.y < middle.y, "and short of the middle")

            // The line meets the square's near side 250 across. The tip is the
            // space short of that, along the line.
            #expect(abs(arrow.tip.x - (right + 250 - arrowGap * whole.x / length)) < 0.0001)
        }

        @Test("An arrow that starts inside the outline goes to the middle")
        func arrowFromInsideTheOutline() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width

            // The square reaches back over the box's edge.
            let outline = square(atX: right - 20, y: frame.origin.y - 40)
            let middle = Point2(x: right + 30, y: frame.origin.y + 10)
            let arrow = try arrow(of: box, to: middle, outline: outline)

            #expect(arrow.tip.x == middle.x && arrow.tip.y == middle.y)
        }

        @Test("A middle inside the box gets no arrow, and the others keep their order")
        func middleInsideTheBoxHasNoArrow() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)
            let frame = box.frameRect
            let right = frame.origin.x + frame.size.width
            let level = frame.origin.y + frame.size.height / 2
            let inside = Point2(x: frame.origin.x + 2, y: frame.origin.y + 2)

            #expect(arrows(of: box, to: [inside]).isEmpty)
            #expect(arrows(of: box, to: []).isEmpty)

            let drawn = arrows(of: box, to: [Point2(x: frame.origin.x - 300, y: level),
                                             inside,
                                             Point2(x: right + 300, y: level)])

            try #require(drawn.count == 2)
            #expect(drawn[0].start.x == frame.origin.x)
            #expect(drawn[1].start.x == right)
        }

        @Test("With no part catalog a placement has no outline, and an index past the arrows gives none")
        func outlinesNeedACatalog() throws {
            let box = try #require(boxes(fixture(callouts: 1)).first)

            #expect(box.tipOutlinePoints(at: 0).isEmpty)
            #expect(box.tipOutlinePoints(at: 99).isEmpty)
        }
    }
}
