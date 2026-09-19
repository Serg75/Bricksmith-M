//
//  LDrawStepPartListResizeTests.swift
//  LDrawFeaturesTests
//
//  Tests for grabbing an edge, turning a drag into a size the frame can draw,
//  and saying which axes the step itself pins.
//
//  This is all arithmetic and lookups, with no drawing, so a host on another
//  platform can call the same methods.
//
//  Created by Sergey Slobodenyuk on 2026-09-10.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures

@Suite("Resizing the parts list frame", .serialized)
final class LDrawStepPartListResizeTests {

    /// A 300x150 frame at the usual margin.
    private let frame = Box2(origin: Point2(x: 12, y: 12), size: Size2(width: 300, height: 150))

    private func step(_ directives: [LDrawDirective] = []) -> LDrawStep {
        let step = LDrawStep.empty() as! LDrawStep
        for directive in directives {
            step.add(directive)
        }
        return step
    }

    // MARK: - Hit-testing

    /// The overlay covers the whole viewport, so a click that is not on an
    /// edge must reach the model behind it. A point level with an edge but far
    /// from the frame is not on it. Where the edges meet, a tie goes to width.
    @Test("The right edge resizes width, the bottom edge height, the nearer edge wins at the corner, and nothing else is a handle", arguments: [
        (312, 80, .width),
        (150, 162, .height),
        (312, 162, .width),
        (313, 165, .width),
        (315, 163, .height),
        (309, 162, .height),
        (312, 159, .width),
        (150, 80, .none),
        (20, 20, .none),
        (500, 80, .none),
        (150, 400, .none),
        (312, 400, .none),
        (312, 300, .none),
    ] as [(Double, Double, LDrawStepPartListHandle)])
    func handleAtPoint(x: Double, y: Double, handle: LDrawStepPartListHandle) {
        #expect(LDrawStepPartListPolicy.handle(at: Point2(x: x, y: y), inFrame: frame) == handle)
    }

    @Test("An empty frame has no handles")
    func emptyFrameHasNoHandles() {
        let empty = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: 0, height: 0))

        #expect(LDrawStepPartListPolicy.handle(at: Point2(x: 0, y: 0), inFrame: empty) == .none)
    }

    // MARK: - Pins

    @Test("Each pin sits at the midpoint of the edge it pins")
    func pinsSitAtEdgeMidpoints() {
        let widthPin = LDrawStepPartListPolicy.pinRect(forAxis: .width, inFrame: frame)
        let heightPin = LDrawStepPartListPolicy.pinRect(forAxis: .height, inFrame: frame)

        #expect(abs((widthPin.origin.x + widthPin.size.width / 2) - 312) < 0.001)
        #expect(abs((widthPin.origin.y + widthPin.size.height / 2) - 87) < 0.001)

        #expect(abs((heightPin.origin.x + heightPin.size.width / 2) - 162) < 0.001)
        #expect(abs((heightPin.origin.y + heightPin.size.height / 2) - 162) < 0.001)
    }

    /// The pin must sit inside its edge's grab area, or a click on the pin
    /// would start a drag instead.
    @Test("A pin's center is on its edge's handle")
    func pinsSitOnTheirHandles() {
        let widthPin = LDrawStepPartListPolicy.pinRect(forAxis: .width, inFrame: frame)
        let center = Point2(x: widthPin.origin.x + widthPin.size.width / 2,
                            y: widthPin.origin.y + widthPin.size.height / 2)

        #expect(LDrawStepPartListPolicy.handle(at: center, inFrame: frame) == .width)
    }

    /// Only a pinned axis has a pin to click, and there it beats the edge.
    @Test("A drawn pin beats its edge, and an undrawn one is just edge")
    func pinsBeatTheirEdges() {
        let widthPin = LDrawStepPartListPolicy.pinRect(forAxis: .width, inFrame: frame)
        let heightPin = LDrawStepPartListPolicy.pinRect(forAxis: .height, inFrame: frame)
        let onWidthPin = Point2(x: widthPin.origin.x + widthPin.size.width / 2,
                                y: widthPin.origin.y + widthPin.size.height / 2)
        let onHeightPin = Point2(x: heightPin.origin.x + heightPin.size.width / 2,
                                 y: heightPin.origin.y + heightPin.size.height / 2)

        #expect(LDrawStepPartListPolicy.control(at: onWidthPin, inFrame: frame,
                                                widthPinned: true, heightPinned: false) == .widthPin)
        #expect(LDrawStepPartListPolicy.control(at: onWidthPin, inFrame: frame,
                                                widthPinned: false, heightPinned: true) == .widthEdge)
        #expect(LDrawStepPartListPolicy.control(at: onHeightPin, inFrame: frame,
                                                widthPinned: false, heightPinned: true) == .heightPin)
        #expect(LDrawStepPartListPolicy.control(at: Point2(x: 150, y: 80), inFrame: frame,
                                                widthPinned: true, heightPinned: true) == .none)

        let empty = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: 0, height: 0))
        #expect(LDrawStepPartListPolicy.control(at: Point2(x: 0, y: 0), inFrame: empty,
                                                widthPinned: true, heightPinned: true) == .none)
    }

    // MARK: - Drag arithmetic

    private let hugeHost = Size2(width: 10000, height: 10000)

    /// A part with a one-stud-deep box, seen straight on.
    private func entry(_ name: String, width: Double, height: Double) -> LDrawStepPartListEntry {
        LDrawStepPartListEntry(partName: name,
                               displayTitle: name,
                               color: nil,
                               quantity: 1,
                               modelBounds: Box3(min: Point3(x: 0, y: 0, z: 0),
                                                 max: Point3(x: width, y: height, z: 20)),
                               isMissing: false,
                               isSubmodel: false)
    }

    /// Packed with the default metrics, at 150 points per inch unless told
    /// otherwise.
    private func layout(_ entries: [LDrawStepPartListEntry],
                        _ mode: LPubPliConstrainMode = .area,
                        inches: Double = 0,
                        pointsPerInch: Double = 150) -> LDrawStepPartListLayout {
        var constraint = LDrawStepPartListLayout.defaultConstraint()
        constraint.mode = mode
        constraint.inches = Float(inches)
        var metrics = LDrawStepPartListLayout.defaultMetrics()
        metrics.pointsPerInch = pointsPerInch
        return LDrawStepPartListLayout.layout(forEntries: entries,
                                              constraint: constraint,
                                              viewTransform: IdentityMatrix4,
                                              metrics: metrics)
    }

    private func drag(_ axis: LPubPliAxis,
                      x: Double = 100,
                      y: Double = 100,
                      _ packed: LDrawStepPartListLayout?,
                      from origin: Point2? = nil,
                      host: Size2? = nil,
                      pointsPerPageInch: Double = 0,
                      inherited: Double = 0) -> Double {
        LDrawStepPartListPolicy.inches(forDraggingAxis: axis,
                                       toPoint: Point2(x: x, y: y),
                                       fromOrigin: origin ?? frame.origin,
                                       layout: packed,
                                       hostSize: host ?? hugeHost,
                                       pointsPerPageInch: pointsPerPageInch,
                                       inheritedInches: inherited)
    }

    /// Forty flat parts in cells of 46 by 22 points. One shelf of them is over
    /// 12 inches wide, and one part a shelf is over 7 inches tall, so neither
    /// limits a drag inside the band.
    private var flatParts: LDrawStepPartListLayout {
        layout((0..<40).map { entry("flat\($0).dat", width: 40, height: 4) })
    }

    /// Cells 26, 46 and 86 points wide and 42 tall with their count strip. One
    /// shelf is 170 by 54 points with the frame padding. The tallest packing
    /// puts the widest cell on its own shelf: 102 points.
    private var bricks: [LDrawStepPartListEntry] {
        [entry("one.dat", width: 20, height: 24),
         entry("two.dat", width: 40, height: 24),
         entry("four.dat", width: 80, height: 24)]
    }

    /// The frame's corner stays put, so the new size is the distance from that
    /// corner to the pointer. 375 points at 150 dpi is 2.5 inches.
    @Test("Dragging an edge asks for the distance from the frame's origin", arguments: [
        (.width, 12 + 375, 200, 2.5),
        (.height, 100, 12 + 300, 2.0),
    ] as [(LPubPliAxis, Double, Double, Double)])
    func dragGivesTheDistanceFromTheOrigin(axis: LPubPliAxis, x: Double, y: Double, inches: Double) {
        #expect(abs(drag(axis, x: x, y: y, flatParts) - inches) < 0.001)
    }

    /// Clamped while dragging, not on release, so the frame stops at the limit
    /// instead of snapping back later. A height is a ceiling that icons shrink
    /// under, so its floor is lower than a width's and a short height from an
    /// LPub3D file can be reached.
    @Test("A drag past the limits is clamped as it happens", arguments: [
        (.width, 0, 80, LDrawStepPartList.minimumWidthInInches()),
        (.width, 9000, 80, LDrawStepPartList.maximumWidthInInches()),
        (.height, 100, 0, LDrawStepPartList.minimumHeightInInches()),
        (.height, 100, 9000, LDrawStepPartList.maximumWidthInInches()),
    ] as [(LPubPliAxis, Double, Double, Double)])
    func dragIsClampedToTheEditableBand(axis: LPubPliAxis, x: Double, y: Double, limit: Double) {
        #expect(LDrawStepPartList.minimumHeightInInches() < LDrawStepPartList.minimumWidthInInches())

        #expect(drag(axis, x: x, y: y, flatParts) == limit)
    }

    @Test("A drag with no list on show asks for nothing")
    func dragWithoutALayoutAsksForNothing() {
        #expect(drag(.width, x: 400, nil) == 0)
    }

    /// Past one shelf the frame is drawn the same. The stop is rounded up to
    /// what CONSTRAIN writes, so the saved width still packs one shelf.
    @Test("A width drag stops where every part fits on one line, and that width is drawn")
    func widthDragStopsAtOneRow() {
        let packed = layout(bricks)
        let oneRow = packed.oneRowFrameWidth / packed.pointsPerInch
        let asked = drag(.width, x: 9000, packed)

        #expect(abs(packed.oneRowFrameWidth - 170) < 0.001)
        #expect(asked >= oneRow)
        #expect(asked - oneRow < 0.0002)

        let redrawn = layout(bricks, .width, inches: asked)
        #expect(redrawn.rowCount == 1)
        #expect(abs(redrawn.frameSize.width - packed.oneRowFrameWidth) < 0.001)
    }

    /// A single part is drawn smaller in a box less than its width over 0.6,
    /// so the stop is there: (26 / 0.6 + 12) / 150 inches.
    /// The frame closes up to its widest shelf, so a grab on its edge reads as
    /// the smallest width that packs the same, not as the WIDTH asked for or the
    /// pointer's distance from the corner. A part drawn smaller is sized from
    /// the WIDTH, so there the grab reads as that WIDTH. Either is rounded up to
    /// the 0.0001 in CONSTRAIN writes, which moves a capped part a hundredth of
    /// a point.
    @Test("Grabbing a closed-up edge repacks the same frame", arguments: [false, true])
    func grabbingAClosedUpEdgeKeepsTheFrame(withBeam: Bool) {
        let entries = withBeam ? bricks + [entry("beam.dat", width: 400, height: 8)] : bricks
        let packed = layout(entries, .width, inches: 2.0)
        let edge = frame.origin.x + packed.frameSize.width

        #expect(packed.frameSize.width < 300, "the frame closes up inside the WIDTH")
        #expect(packed.placements.contains { $0.isScaledDown } == withBeam)

        for grab in [edge - 3, edge, edge + 3] {
            let origin = LDrawStepPartListPolicy.dragOrigin(forAxis: .width,
                                                            grabbedAt: Point2(x: grab, y: 80),
                                                            layout: packed)
            let asked = drag(.width, x: grab, packed, from: origin)
            let redrawn = layout(entries, .width, inches: asked)

            #expect(redrawn.rowCount == packed.rowCount, "grab \(grab)")
            #expect(abs(redrawn.frameSize.width - packed.frameSize.width) < 0.02, "grab \(grab)")
            #expect(abs(redrawn.frameSize.height - packed.frameSize.height) < 0.02, "grab \(grab)")
        }
    }

    /// Two cells that cannot share a shelf each take one, and the widest shelf
    /// is one cell. Packed that narrow, the cell would pass its share and be
    /// drawn smaller, so the grab reads as the share's width instead.
    @Test("A grab keeps a lone cell under its share")
    func aGrabKeepsALoneCellUnderItsShare() {
        let entries = [entry("wide.dat", width: 150, height: 24), entry("wider.dat", width: 160, height: 24)]
        let packed = layout(entries, .width, inches: 2.0)
        let edge = frame.origin.x + packed.frameSize.width
        let origin = LDrawStepPartListPolicy.dragOrigin(forAxis: .width, grabbedAt: Point2(x: edge, y: 80), layout: packed)
        let redrawn = layout(entries, .width, inches: drag(.width, x: edge, packed, from: origin))

        #expect(packed.rowCount == 2)
        #expect(redrawn.placements.contains { $0.isScaledDown } == false)
        #expect(abs(redrawn.frameSize.width - packed.frameSize.width) < 0.001)
    }

    @Test("A list that fits on one line below the minimum width stops there")
    func oneRowBelowTheMinimumWins() {
        let packed = layout([entry("one.dat", width: 20, height: 20)])
        let oneRow = (26 / 0.6 + 12) / 150

        #expect(oneRow < LDrawStepPartList.minimumWidthInInches())

        for x in [0.0, 9000] {
            #expect(abs(drag(.width, x: x, packed) - oneRow) < 0.0002, "x \(x)")
        }
    }

    /// Below one shelf no packing fits and the one shelf is drawn. Above the
    /// packing as wide as the widest cell, that packing is always kept.
    @Test("A height drag stops between one shelf and the tallest packing")
    func heightDragStopsBetweenOneRowAndTheTallest() {
        let packed = layout(bricks)

        #expect(abs(packed.oneRowFrameHeight - 54) < 0.001)
        #expect(abs(packed.tallestFrameHeight - 102) < 0.001)

        let lowest = drag(.height, y: 0, packed)
        let highest = drag(.height, y: 9000, packed)

        #expect(lowest - 54.0 / 150 >= 0 && lowest - 54.0 / 150 < 0.0002)
        #expect(highest - 102.0 / 150 >= 0 && highest - 102.0 / 150 < 0.0002)
        #expect(abs(drag(.height, y: 12 + 75, packed) - 0.5) < 0.001)

        let short = layout(bricks, .height, inches: lowest)
        #expect(short.rowCount == 1)
        #expect(abs(short.frameSize.height - packed.oneRowFrameHeight) < 0.001)

        let tall = layout(bricks, .height, inches: highest)
        #expect(tall.rowCount == 2)
        #expect(abs(tall.frameSize.height - packed.tallestFrameHeight) < 0.001)
    }

    /// Past its share of the host a width is narrowed and a height shrinks the
    /// icons, so a drag stops there. The width stop is the same one a WIDTH
    /// from the document is narrowed to.
    @Test("A drag stops at the host's share, the same limit the frame is drawn with")
    func dragStopsAtTheHostsShare() {
        let narrow = Size2(width: 400, height: 10000)
        let short = Size2(width: 10000, height: 300)
        let width = drag(.width, x: 9000, flatParts, host: narrow)
        let height = drag(.height, y: 9000, flatParts, host: short)

        #expect(abs(width - (400 * 0.4) / 150) < 0.000001)
        #expect(abs(height - (300 * 0.6) / 150) < 0.000001)

        var constraint = LDrawStepPartListLayout.defaultConstraint()
        constraint.mode = .width
        constraint.inches = Float(width)

        let clamped = LDrawStepPartListPolicy.constraint(constraint,
                                                         clampedToHostSize: narrow,
                                                         pointsPerInch: 150,
                                                         pointsPerPageInch: 0)
        #expect(clamped.inches == Float(width))
    }

    /// On a 4 by 3 inch page at 150 points per inch a 0.6 share would stop a
    /// width at 2.24 in and a height at 1.64 in. The page less its 0.05 in
    /// margins stops them at 3.9 and 2.9 in, as the frame is drawn. On Letter
    /// the paper is past the band's 6 in, and still decides.
    @Test("On the page a drag stops at the page less its margins, not at a share or the band")
    func onThePageADragStopsAtThePaper() {
        let page = Size2(width: 4 * 150, height: 3 * 150)
        let width = drag(.width, x: 9000, flatParts, host: page, pointsPerPageInch: 150)
        let height = drag(.height, y: 9000, flatParts, host: page, pointsPerPageInch: 150)

        #expect(abs(width - 3.9) < 0.000001)
        #expect(abs(height - 2.9) < 0.000001)

        // Eighty cells make one shelf and the tallest packing both larger
        // than a Letter page.
        let many = layout((0..<80).map { entry("flat\($0).dat", width: 40, height: 4) })
        let letter = Size2(width: 8.5 * 150, height: 11 * 150)

        #expect(abs(drag(.width, x: 9000, many, host: letter, pointsPerPageInch: 150) - 8.4) < 0.000001)
        #expect(abs(drag(.height, y: 9000, many, host: letter, pointsPerPageInch: 150) - 10.9) < 0.000001)

        var constraint = LDrawStepPartListLayout.defaultConstraint()
        constraint.mode = .width
        constraint.inches = Float(width)

        let clamped = LDrawStepPartListPolicy.constraint(constraint,
                                                         clampedToHostSize: page,
                                                         pointsPerInch: 150,
                                                         pointsPerPageInch: 150)
        #expect(clamped.inches == Float(width))
    }

    // MARK: - Snapping to the inherited size

    /// 2.5 in is 375 points from the frame's corner, and 2 in is 300, at 150
    /// points per inch.
    @Test("A drag within a few points of the inherited size snaps to it")
    func dragSnapsToTheInheritedSize() {
        for offset in [-5.0, 5.0] {
            #expect(drag(.width, x: 12 + 375 + offset, flatParts, inherited: 2.5) == 2.5, "offset \(offset)")
            #expect(drag(.height, y: 12 + 300 + offset, flatParts, inherited: 2.0) == 2.0, "offset \(offset)")
        }

        #expect(abs(drag(.width, x: 12 + 375 + 7, flatParts, inherited: 2.5) - (2.5 + 7.0 / 150)) < 0.000001)
        #expect(abs(drag(.width, x: 12 + 375 + 1, flatParts) - (2.5 + 1.0 / 150)) < 0.000001)
    }

    /// So zooming in lets a size close to the inherited one be set.
    @Test("The snap distance is measured on screen")
    func snapDistanceIsMeasuredOnScreen() {
        let zoomed = layout((0..<40).map { entry("flat\($0).dat", width: 40, height: 4) }, pointsPerInch: 300)

        #expect(drag(.width, x: 12 + 2.53 * 150, flatParts, inherited: 2.5) == 2.5)
        #expect(abs(drag(.width, x: 12 + 2.53 * 300, zoomed, inherited: 2.5) - 2.53) < 0.000001)
    }

    /// The frame cannot be drawn past a stop, so the drag stays there and
    /// letting go writes a line. Just inside a stop, the stopped drag snaps.
    @Test("A stop wins over an inherited size past it")
    func stopWinsOverTheInheritedSize() {
        let floor = LDrawStepPartList.minimumWidthInInches()
        let ceiling = LDrawStepPartList.maximumWidthInInches()

        #expect(drag(.width, x: 0, flatParts, inherited: floor - 3.0 / 150) == floor)
        #expect(drag(.width, x: 9000, flatParts, inherited: ceiling + 3.0 / 150) == ceiling)
        #expect(drag(.width, x: 0, flatParts, inherited: floor + 3.0 / 150) == floor + 3.0 / 150)

        // One shelf of bricks is 54 points tall, so a HEIGHT 3 points lower
        // cannot be drawn.
        let packed = layout(bricks)
        #expect(drag(.height, y: 0, packed, inherited: 51.0 / 150) == drag(.height, y: 0, packed))
    }

    @Test("A drag let go on the inherited size removes the step's line, whatever it pinned")
    func dragLetGoOnTheInheritedSizeRemovesTheLine() throws {
        let document = LDrawModel.model() as! LDrawModel
        let header = try #require(document.steps().first as? LDrawStep)
        let own = constrain(.height, 1.5)
        let second = document.addStep()

        header.add(constrain(.width, 2.5, scope: .global))
        second.add(own)
        document.setStepDisplay(true)
        document.setMaximumStepIndexForStepDisplay(1)

        let inherited = LDrawStepPartListPolicy.inheritedInches(forAxis: .width, inModel: document)
        let snapped = drag(.width, x: 12 + 2.52 * 150, flatParts, inherited: inherited)
        let edit = LDrawStepPartListEdit.edit(settingAxis: .width,
                                              toInches: snapped,
                                              inStep: second,
                                              inheritedInches: inherited)

        #expect(snapped == 2.5)
        #expect(edit.kind == .remove)
        #expect(edit.existingDirective === own)
        #expect(edit.resetsAxis)
    }

    // MARK: - Which axes are pinned

    /// With nothing in the step neither edge is pinned. COLS, AREA and SQUARE
    /// pin neither edge. A GLOBAL
    /// or unscoped line carries on to later steps, so it is not this step's to
    /// clear.
    @Test("Only the step's own WIDTH or HEIGHT pins an axis", arguments: [
        (nil, .local, false, false),
        (.width, .local, true, false),
        (.height, .local, false, true),
        (.area, .local, false, false),
        (.square, .local, false, false),
        (.columns, .local, false, false),
        (.width, .global, false, false),
        (.width, .unspecified, false, false),
        (.height, .unspecified, false, false),
    ] as [(LPubPliConstrainMode?, LPubMetaScope, Bool, Bool)])
    func onlyTheStepsOwnWidthOrHeightPins(mode: LPubPliConstrainMode?,
                                          scope: LPubMetaScope,
                                          widthPinned: Bool,
                                          heightPinned: Bool) {
        let subject = step(mode.map { mode in [constrain(mode, 1.5, scope: scope)] } ?? [])

        #expect(LDrawStepPartListPolicy.isAxis(.width, pinnedInStep: subject) == widthPinned)
        #expect(LDrawStepPartListPolicy.isAxis(.height, pinnedInStep: subject) == heightPinned)
    }
}
