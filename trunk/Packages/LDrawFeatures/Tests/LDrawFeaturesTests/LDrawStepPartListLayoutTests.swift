//
//  LDrawStepPartListLayoutTests.swift
//  UnitTests
//
//  Tests for the packer: five constrain modes, oversized parts, the
//  legibility floor, where a resize drag stops, and the rule that a layout
//  depends only on its inputs.
//
//  Every fixture uses the identity view transform, so an entry's projected
//  extent is the X and Y extent of the bounds it was given. That keeps the
//  arithmetic here checkable by hand.
//
//  Nothing here touches a part library, a view or a GPU.
//
//  Created by Sergey Slobodenyuk on 2026-09-10.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures

@Suite("Packing a step's parts list")
struct LDrawStepPartListLayoutTests {

    // MARK: - Fixtures

    private func entry(_ name: String,
                       title: String? = nil,
                       width: Double = 20,
                       height: Double = 20,
                       depth: Double = 20,
                       quantity: UInt = 1) -> LDrawStepPartListEntry {
        LDrawStepPartListEntry(partName: name,
                               displayTitle: title ?? name,
                               color: nil,
                               quantity: quantity,
                               modelBounds: Box3(min: Point3(x: 0, y: 0, z: 0),
                                                 max: Point3(x: width, y: height, z: depth)),
                               isMissing: false,
                               isSubmodel: false)
    }

    private func boundlessEntry(_ name: String) -> LDrawStepPartListEntry {
        LDrawStepPartListEntry(partName: name,
                               displayTitle: name,
                               color: nil,
                               quantity: 1,
                               modelBounds: InvalidBox,
                               isMissing: true,
                               isSubmodel: false)
    }

    private func metrics(maxHeight: Double = 0,
                         cellWidthFraction: Double = 0.6) -> LDrawStepPartListMetrics {
        var metrics = LDrawStepPartListLayout.defaultMetrics()
        metrics.maximumHeight = maxHeight
        metrics.maximumCellWidthFraction = cellWidthFraction
        return metrics
    }

    private func constraint(_ mode: LPubPliConstrainMode,
                            inches: Float = 0,
                            columns: Int = 0) -> LDrawStepPartListConstraint {
        var constraint = LDrawStepPartListLayout.defaultConstraint()
        constraint.mode = mode
        constraint.inches = inches
        constraint.columns = columns
        return constraint
    }

    private func layout(_ entries: [LDrawStepPartListEntry],
                        _ constraint: LDrawStepPartListConstraint,
                        _ metrics: LDrawStepPartListMetrics? = nil) -> LDrawStepPartListLayout {
        LDrawStepPartListLayout.layout(forEntries: entries,
                                       constraint: constraint,
                                       viewTransform: IdentityMatrix4,
                                       metrics: metrics ?? self.metrics())
    }

    /// A spread of shapes: some plates, a tall one, and a long beam.
    private var mixedEntries: [LDrawStepPartListEntry] {
        [entry("3005.dat", width: 20, height: 24),
         entry("3001.dat", width: 40, height: 24),
         entry("3003.dat", width: 40, height: 24),
         entry("3024.dat", width: 20, height: 8),
         entry("3010.dat", width: 80, height: 24),
         entry("3009.dat", width: 120, height: 24)]
    }

    /// Two small parts and a beam far too long for a two-inch box.
    private var beamEntries: [LDrawStepPartListEntry] {
        [entry("3001.dat", width: 40, height: 24),
         entry("beam.dat", width: 640, height: 20),
         entry("3024.dat", width: 20, height: 8)]
    }

    /// A plate far too wide for a one-inch box.
    private var bigPlate: LDrawStepPartListEntry {
        entry("bigplate.dat", width: 480, height: 24, depth: 640)
    }

    /// The big plate in a one-inch box, where it is capped.
    private var cappedPlateLayout: LDrawStepPartListLayout {
        layout([bigPlate], constraint(.width, inches: 1.0))
    }

    /// How wide each shelf is: the sum of its cells.
    private func rowWidths(_ result: LDrawStepPartListLayout) -> [Double] {
        var widthByRow: [UInt: Double] = [:]
        for placement in result.placements {
            widthByRow[UInt(placement.rowIndex), default: 0] += placement.cellFrame.size.width
        }
        return Array(widthByRow.values)
    }

    private func middleX(_ box: Box2) -> Double {
        box.origin.x + box.size.width / 2
    }

    private func maxY(_ box: Box2) -> Double {
        box.origin.y + box.size.height
    }

    // MARK: - Degenerate input

    @Test("No entries is an empty layout, not a crash")
    func emptyEntriesGiveAnEmptyLayout() {
        let result = layout([], constraint(.area))

        #expect(result.placements.isEmpty)
        #expect(result.rowCount == 0)
        #expect(result.contentSize.width == 0)
        #expect(result.contentSize.height == 0)
        #expect(result.frameSize.width == 0)
        #expect(result.overflowCount == 0)
        #expect(result.oneRowFrameWidth == 0)
        #expect(result.oneRowFrameHeight == 0)
        #expect(result.tallestFrameHeight == 0)
    }

    /// A broken reference and a synthesized part both arrive with no bounds.
    /// They still need a cell, or the list would be shorter than the step.
    @Test("An entry with no bounds still gets a cell")
    func boundlessEntriesStillGetCells() throws {
        let result = layout([boundlessEntry("brokenref.dat"), entry("3001.dat")], constraint(.area))

        #expect(result.placements.count == 2)

        let broken = try #require(result.placements.first { $0.entry.partName == "brokenref.dat" })
        #expect(broken.cellFrame.size.width > 0)
        #expect(broken.cellFrame.size.height > 0)
        #expect(broken.annotationText == nil)
    }

    // MARK: - WIDTH

    /// Two inches is 288 points of content. The first shelf takes 126, 86
    /// and 46 points, and the next 46 would pass 288.
    @Test("A width wraps the shelves, and the box closes up to the widest")
    func widthWrapsAndClosesUp() {
        let settings = metrics()
        let result = layout(mixedEntries, constraint(.width, inches: 2.0), settings)

        #expect(result.rowCount == 2)
        #expect(abs(result.contentSize.width - 258) < 0.001)
        #expect(abs(result.contentSize.width - (rowWidths(result).max() ?? 0)) < 0.001)
        #expect(abs(result.frameSize.width - (258 + 2 * settings.framePadding)) < 0.001)
    }

    /// The parser never writes such a width, but a caller can build one by
    /// hand, and packing must not divide by zero or loop.
    @Test("A width of zero or less still produces a layout")
    func nonPositiveWidthStillLaysOut() {
        for inches: Float in [0, -2] {
            let result = layout(mixedEntries, constraint(.width, inches: inches))

            #expect(result.placements.count + Int(result.overflowCount) == mixedEntries.count, "\(inches)")
            #expect(result.frameSize.width > 0, "\(inches)")
            #expect(result.frameSize.height > 0, "\(inches)")
            #expect(result.scale > 0, "\(inches)")
        }
    }

    /// A box with no extent on an axis, such as a flat decal, is still a real
    /// box, so it must not give a zero-sized cell or an infinite scale.
    @Test("An entry with zero-extent bounds still gets a cell")
    func zeroExtentBoundsGetACell() {
        let flat = entry("decal", width: 40, height: 0, depth: 40)
        let point = entry("dot", width: 0, height: 0, depth: 0)

        let result = layout([flat, point, entry("3001.dat")], constraint(.width, inches: 2.0))

        #expect(result.placements.count == 3)
        #expect(result.scale.isFinite && result.scale > 0)

        for placement in result.placements {
            #expect(placement.cellFrame.size.width > 0, "\(placement.entry.partName)")
            #expect(placement.cellFrame.size.height > 0, "\(placement.entry.partName)")
        }
    }

    @Test("No shelf runs past the pinned width")
    func rowsStayInsideThePinnedWidth() {
        let settings = metrics()
        let result = layout(mixedEntries, constraint(.width, inches: 2.0), settings)

        for width in rowWidths(result) {
            #expect(width <= result.contentSize.width + 0.001)
            #expect(width <= 2.0 * settings.pointsPerInch - 2 * settings.framePadding + 0.001)
        }
    }

    /// A cell cannot shrink below its labels, so a box pinned narrower than
    /// that grows to hold it.
    @Test("A width narrower than a cell still holds every cell")
    func aTinyWidthStillHoldsEveryCell() {
        let result = layout(mixedEntries, constraint(.width, inches: 0.1))

        #expect(result.placements.count == mixedEntries.count)
        for placement in result.placements {
            #expect(placement.cellFrame.origin.x + placement.cellFrame.size.width
                    <= result.contentSize.width + 0.001,
                    "\(placement.entry.partName)")
        }
    }

    // MARK: - Oversized parts

    /// At one common scale a 1x32 beam would fill the box or shrink everything
    /// else, so it is capped on its own and marked.
    @Test("A cell too wide for the box is scaled down on its own")
    func oversizedEntryIsCappedAndMarked() throws {
        let result = layout(beamEntries, constraint(.width, inches: 2.0))

        let beam = try #require(result.placements.first { $0.entry.partName == "beam.dat" })
        #expect(beam.isScaledDown == true)
        #expect(beam.scale < result.scale)
        #expect(beam.cellFrame.size.width <= result.contentSize.width + 0.001)

        // The others keep the common scale.
        for placement in result.placements where placement.entry.partName != "beam.dat" {
            #expect(placement.isScaledDown == false)
            #expect(placement.scale == result.scale)
        }
    }

    @Test("A capped cell gets a shelf to itself, centered")
    func oversizedEntryOwnsItsRow() throws {
        let result = layout(beamEntries, constraint(.width, inches: 2.0))
        let beam = try #require(result.placements.first { $0.entry.partName == "beam.dat" })

        let roommates = result.placements.filter { $0.rowIndex == beam.rowIndex }
        #expect(roommates.count == 1)

        let leftGap = beam.cellFrame.origin.x
        let rightGap = result.contentSize.width - (beam.cellFrame.origin.x + beam.cellFrame.size.width)
        #expect(abs(leftGap - rightGap) < 0.001)
    }

    @Test("A part small enough for the limit is not capped")
    func ordinaryEntriesAreNotCapped() {
        let result = layout([entry("3001.dat", width: 40, height: 24)], constraint(.width, inches: 2.0))

        #expect(result.placements.allSatisfy { !$0.isScaledDown })
    }

    /// The cap keeps one huge part from crowding out a box whose width came
    /// from outside. The searching modes take their width from the cells, so
    /// capping there would shrink the part that set the width.
    @Test("Only a pinned width caps a cell")
    func onlyPinnedWidthsCap() {
        for mode in [LPubPliConstrainMode.area, .square, .height, .columns] {
            let result = layout([bigPlate], constraint(mode, inches: 4.0, columns: 1))

            #expect(result.placements.allSatisfy { !$0.isScaledDown }, "\(mode)")
        }

        #expect(cappedPlateLayout.placements.first?.isScaledDown == true)
    }

    // MARK: - Measuring a submodel by its parts

    private func points(_ list: [Point3]) -> Data {
        list.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func corners(of box: Box3) -> [Point3] {
        var result: [Point3] = []
        for x in [box.min.x, box.max.x] { for y in [box.min.y, box.max.y] { for z in [box.min.z, box.max.z] {
            result.append(Point3(x: x, y: y, z: z))
        } } }
        return result
    }

    /// One box around a submodel is stretched by the part that reaches
    /// furthest, which leaves a blank band beside the icon. The corners of its
    /// parts are what it really occupies.
    @Test("A submodel measured by its parts gets a tighter cell than its box")
    func outlinePointsTightenTheCell() throws {
        // An L: a long bar along x and a long bar along z, meeting at a corner.
        let alongX = Box3(min: Point3(x: 0, y: 0, z: 0), max: Point3(x: 160, y: 20, z: 20))
        let alongZ = Box3(min: Point3(x: 0, y: 0, z: 0), max: Point3(x: 20, y: 20, z: 160))
        let box = Box3(min: Point3(x: 0, y: 0, z: 0), max: Point3(x: 160, y: 20, z: 160))

        let angle = LDrawStepPartListLayout.viewTransform(forAngle: Tuple3(x: 30, y: 45, z: 0))

        func entryFor(outline: Data?) -> LDrawStepPartListEntry {
            let plain = LDrawStepPartListEntry(partName: "l.ldr", displayTitle: "l.ldr", color: nil, quantity: 1,
                                               modelBounds: box, isMissing: false, isSubmodel: true)
            return outline.map { plain.withOutlinePoints($0) } ?? plain
        }

        func iconWidth(_ entry: LDrawStepPartListEntry) throws -> Double {
            let packed = LDrawStepPartListLayout.layout(forEntries: [entry], constraint: constraint(.area),
                                                        viewTransform: angle, metrics: metrics())
            return try #require(packed.placements.first).iconFrame.size.width / packed.scale
        }

        let boxed = try iconWidth(entryFor(outline: nil))
        let outlined = try iconWidth(entryFor(outline: points(corners(of: alongX) + corners(of: alongZ))))

        #expect(outlined < boxed)

        // The measured middle is the middle of those points, not the box's.
        let center = LDrawStepPartListLayout.projectedCenter(of: entryFor(outline: points(corners(of: alongX))),
                                                             viewTransform: IdentityMatrix4)
        #expect(abs(center.x - 80) < 0.001)
        #expect(abs(center.z - 10) < 0.001)
    }

    /// A single part's box is even about its center, so measuring it by its
    /// corners gives the same center.
    @Test("A plain part is still centered on its box")
    func plainPartsCenterOnTheirBox() {
        let angle = LDrawStepPartListLayout.viewTransform(forAngle: Tuple3(x: 30, y: 45, z: 0))
        let brick = entry("3001.dat", width: 40, height: 24, depth: 80)
        let center = LDrawStepPartListLayout.projectedCenter(of: brick, viewTransform: angle)
        let expected = V3MulPointByProjMatrix(Point3(x: 20, y: 12, z: 40), angle)

        #expect(abs(center.x - expected.x) < 0.001)
        #expect(abs(center.y - expected.y) < 0.001)
    }

    /// A ring of 96 points around the Y axis, 120 LDU across.
    private var ring: [Point3] {
        (0..<96).map { index in
            let angle = Double(index) / 96 * 2 * .pi
            return Point3(x: 100 + 60 * cos(angle), y: 0, z: 100 + 60 * sin(angle))
        }
    }

    /// A submodel measured by the ring, inside a much bigger box.
    private var ringEntry: LDrawStepPartListEntry {
        LDrawStepPartListEntry(partName: "ring.ldr", displayTitle: "ring.ldr", color: nil, quantity: 1,
                               modelBounds: Box3(min: Point3(x: 0, y: 0, z: 0), max: Point3(x: 200, y: 20, z: 200)),
                               isMissing: false, isSubmodel: true)
            .withOutlinePoints(points(ring))
    }

    /// A submodel can have far more corners than a part's box. The extent is
    /// still the points' own.
    @Test("A many-cornered outline still packs, at the points' own extent")
    func manyPointOutlinesPack() throws {
        let packed = layout([ringEntry], constraint(.area))
        let placement = try #require(packed.placements.first)

        // Seen straight on, the ring spans 120 LDU across, not the box's 200.
        #expect(abs(placement.iconFrame.size.width / packed.scale - 120) < 0.5)
    }

    // MARK: - LPub3D's camera angles

    private func expectSameRotation(_ a: Matrix4, _ b: Matrix4, _ comment: Comment? = nil) {
        withUnsafeBytes(of: a.element) { ra in
            withUnsafeBytes(of: b.element) { rb in
                let da = ra.bindMemory(to: Double.self), db = rb.bindMemory(to: Double.self)
                for index in 0..<16 {
                    #expect(abs(da[index] - db[index]) < 0.001, comment)
                }
            }
        }
    }

    /// LPub3D's assembly default, 23 and 45, is the same view Bricksmith has
    /// always used. A sign error in the globe maths would show here.
    @Test("LPub3D's 23, 45 is Bricksmith's 3D view")
    func lpubAssemblyAngleIsTheBricksmithView() {
        let lpub = LDrawStepPartListLayout.viewTransform(latitude: 23, longitude: 45)
        let mlcad = LDrawStepPartListLayout.viewTransform(forAngle: Tuple3(x: 16.707, y: 42.63, z: 16.039))

        expectSameRotation(lpub, mlcad)
    }

    @Test("LPub3D's FRONT view is the identity")
    func frontIsIdentity() {
        expectSameRotation(LDrawStepPartListLayout.viewTransform(latitude: 0, longitude: 0), IdentityMatrix4)
    }

    /// The parts list uses the same tilt from the other side: a part that runs
    /// to the right at 23, 45 runs to the left at 23, -45.
    @Test("The parts list default, 23, -45, mirrors the 3D view")
    func partListDefaultMirrorsTheAssemblyView() {
        let pli = LDrawStepPartListLayout.viewTransform(latitude: 23, longitude: -45)
        let assembly = LDrawStepPartListLayout.viewTransform(latitude: 23, longitude: 45)

        // A 1x2 plate's long axis is x.
        let alongX = Point3(x: 40, y: 0, z: 0)
        let inPli = V3MulPointByProjMatrix(alongX, pli)
        let inAssembly = V3MulPointByProjMatrix(alongX, assembly)

        #expect(abs(inPli.x - inAssembly.x) < 0.001, "same width on screen")
        #expect(abs(inPli.y + inAssembly.y) < 0.001, "opposite slope")
    }

    // MARK: - LPub3D's PLI control file

    private static let controlFile = """
        0 FILE pli.mpd
        0 LPub3D PLI Control Parts
        0 NOFILE
        0 FILE Technic Beams.ldr
        1 0 -179.644 30 -31.7919 0 0 1 1 0 0 0 1 0 32523.dat
        1 4 0 0 0 1 0 0 0 1 0 0 0 1 32523.dat
        1 0 0 0 0 -1 0 0 0 1 0 0 0 -1 3713.DAT
        1 0 0 0 0 1 0 0 0 1 0 0 0 1 part with spaces.dat
        0 NOFILE
        """

    /// The file is read the way LPub3D reads it: type-1 lines of fifteen
    /// tokens, matched by lower-case name, the first line for a part winning,
    /// and only its matrix counting.
    @Test("The control file is read the way LPub3D reads it")
    func controlFileIsReadLikeLPub() {
        let orientations = LDrawPartListOrientations(string: Self.controlFile)

        // 32523 twice, 3713 once; the spaced name is not fifteen tokens.
        #expect(orientations.count == 2)
        let axle = V3MulPointByProjMatrix(Point3(x: 1, y: 0, z: 0), orientations.orientation(forPartName: "3713.dat"))
        #expect(abs(axle.x + 1) < 1e-9, "case does not matter")

        // The first 32523 line holds a matrix that takes x to y, so a point
        // along x lands along y.
        let beam = orientations.orientation(forPartName: "32523.dat")
        let alongX = V3MulPointByProjMatrix(Point3(x: 1, y: 0, z: 0), beam)
        #expect(abs(alongX.x) < 1e-9 && abs(alongX.y - 1) < 1e-9 && abs(alongX.z) < 1e-9)

        // Its position is ignored: no translation.
        let origin = V3MulPointByProjMatrix(Point3(x: 0, y: 0, z: 0), beam)
        #expect(origin.x == 0 && origin.y == 0 && origin.z == 0)

        // Not listed: identity.
        let brick = V3MulPointByProjMatrix(Point3(x: 1, y: 2, z: 3), orientations.orientation(forPartName: "3001.dat"))
        #expect(brick.x == 1 && brick.y == 2 && brick.z == 3)
    }

    /// The orientation turns the part before the list's view, and what is
    /// measured and what is drawn go through the same turn.
    @Test("An entry's orientation is applied before the list's view")
    func entryOrientationComesFirst() {
        let orientations = LDrawPartListOrientations(string: Self.controlFile)
        let turned = entry("32523.dat", width: 60, height: 20, depth: 20)
            .withListOrientation(orientations.orientation(forPartName: "32523.dat"))
        let view = LDrawStepPartListLayout.viewTransform(latitude: 23, longitude: -45)

        let composed = LDrawStepPartListLayout.transform(for: turned, viewTransform: view)
        let point = Point3(x: 1, y: 0, z: 0)
        let byHand = V3MulPointByProjMatrix(V3MulPointByProjMatrix(point, turned.listOrientation), view)
        let viaComposed = V3MulPointByProjMatrix(point, composed)

        #expect(abs(byHand.x - viaComposed.x) < 1e-9 && abs(byHand.y - viaComposed.y) < 1e-9)

        // A long beam turned to stand along y comes out taller than lying down.
        let plain = entry("32523.dat", width: 60, height: 20, depth: 20)
        let lying = layout([plain], constraint(.area))
        let standing = layout([turned], constraint(.area))
        #expect(standing.placements[0].iconFrame.size.height > lying.placements[0].iconFrame.size.height)
    }

    // MARK: - Reading a drag back

    /// A resize drag reads points back into inches at the points per inch the
    /// frame was packed at. On the page that is the page's.
    @Test("A layout carries the points per inch it was packed at")
    func layoutCarriesItsPointsPerInch() {
        var settings = metrics()
        settings.pointsPerInch = 170

        let packed = layout([entry("3001.dat", width: 40, height: 24)], constraint(.width, inches: 2.0), settings)
        #expect(packed.pointsPerInch == 170)
    }

    // MARK: - COLS

    /// A count below one means one column, and a count past the parts adds no
    /// empty columns.
    @Test("A column count decides the row count, whatever the count")
    func columnCountDecidesRowCount() {
        let entries = (0..<7).map { entry("300\($0).dat", width: Double(20 + $0 * 4), height: 24) }

        for (columns, rows) in [(3, 3), (2, 4), (7, 1), (0, 7), (-5, 7), (1_000_000_000, 1)] {
            #expect(layout(entries, constraint(.columns, columns: columns)).rowCount == rows, "COLS \(columns)")
        }
    }

    /// The width follows from the parts rather than the other way round, so
    /// every cell in a column is as wide as that column's widest.
    @Test("Columns line up")
    func columnsAreAligned() {
        let entries = (0..<6).map { entry("300\($0).dat", width: Double(20 + $0 * 20), height: 24) }
        let result = layout(entries, constraint(.columns, columns: 3))

        let firstRow = result.placements.filter { $0.rowIndex == 0 }.sorted { $0.cellFrame.origin.x < $1.cellFrame.origin.x }
        let secondRow = result.placements.filter { $0.rowIndex == 1 }.sorted { $0.cellFrame.origin.x < $1.cellFrame.origin.x }

        #expect(firstRow.count == 3)
        #expect(secondRow.count == 3)

        for (top, bottom) in zip(firstRow, secondRow) {
            #expect(abs(top.cellFrame.origin.x - bottom.cellFrame.origin.x) < 0.001)
            #expect(abs(top.cellFrame.size.width - bottom.cellFrame.size.width) < 0.001)
        }
    }

    // MARK: - SQUARE and AREA

    /// Each searching mode must beat a pinned width on the measure it is named
    /// after. The scale is one where no pinned width caps a cell, since a
    /// capped list has smaller parts and the searching modes never cap.
    @Test("A searching mode beats a pinned width on its own measure",
          arguments: [LPubPliConstrainMode.square, .area])
    func searchingModesBeatAPinnedWidth(mode: LPubPliConstrainMode) {
        var uncapped = metrics()
        uncapped.baseScale = 0.5

        func measure(_ size: Size2) -> Double {
            mode == .square ? abs(size.width - size.height) : size.width * size.height
        }

        let searched = measure(layout(mixedEntries, constraint(mode), uncapped).contentSize)

        for inches: Float in [1.0, 1.5, 2.0, 3.0, 4.0] {
            let pinned = layout(mixedEntries, constraint(.width, inches: inches), uncapped)

            #expect(pinned.placements.allSatisfy { !$0.isScaledDown }, "WIDTH \(inches) caps a cell")
            #expect(searched <= measure(pinned.contentSize) + 0.001, "\(mode) against WIDTH \(inches)")
        }
    }

    @Test("A searching mode reports the width it actually used")
    func searchingModesReportTheUsedWidth() {
        let result = layout(mixedEntries, constraint(.area))

        #expect(abs(result.contentSize.width - (rowWidths(result).max() ?? 0)) < 0.001)
    }

    // MARK: - HEIGHT

    @Test("A pinned height is respected, and the box grows sideways")
    func heightConstraintIsHonored() {
        let settings = metrics()
        let entries = (0..<12).map { entry("300\($0).dat", width: 40, height: 24) }

        let short = layout(entries, constraint(.height, inches: 1.0), settings)
        let tall = layout(entries, constraint(.height, inches: 3.0), settings)

        #expect(short.contentSize.height <= Double(1.0) * settings.pointsPerInch - 2 * settings.framePadding + 0.001)
        // Less vertical room means more horizontal.
        #expect(short.contentSize.width >= tall.contentSize.width)
    }

    /// When no width fits the height, the search takes the shortest layout. The
    /// narrowest would be a single-column tower.
    @Test("An impossible height falls back to the shortest layout, not the narrowest")
    func infeasibleHeightPrefersTheShortestLayout() {
        let entries = mixedEntries
        let impossible = layout(entries, constraint(.height, inches: 0.2))

        let feasible = layout(entries, constraint(.height, inches: 4.0))

        // It cannot meet the budget, but it should not answer with a tower.
        #expect(impossible.contentSize.height <= feasible.contentSize.height + 0.001)
        #expect(impossible.rowCount <= entries.count - 1,
                "one cell per row would be the degenerate answer")
    }

    /// A height shorter than the parts gives each a column of its own at full
    /// size. Shrinking them all to fit would leave a strip of specks.
    @Test("A pinned height shorter than the parts arranges them, it does not shrink them")
    func aTinyPinnedHeightDoesNotShrink() {
        let entries = (0..<4).map { entry("300\($0).dat", width: 40, height: 24) }
        let result = layout(entries, constraint(.height, inches: 0.0823529), metrics(maxHeight: 0))

        #expect(result.scale == LDrawStepPartListLayout.defaultMetrics().baseScale)
        #expect(result.overflowCount == 0)
        #expect(result.placements.count == entries.count)
        #expect(result.rowCount == 1, "one row of columns, each a part tall")
    }

    /// The viewport's own limit still shrinks the list, whatever the step pins.
    @Test("The viewport's height still shrinks a list under a pinned height")
    func theViewportStillShrinksUnderAPinnedHeight() {
        let entries = (0..<10).map { entry("300\($0).dat", width: 40, height: 24) }
        let result = layout(entries, constraint(.height, inches: 0.0823529), metrics(maxHeight: 20))

        #expect(result.scale < LDrawStepPartListLayout.defaultMetrics().baseScale)
    }

    // MARK: - The legibility floor and overflow

    /// The width is narrow enough that the ten cells stack into several
    /// shelves, so the height limit bites. Wider, they would all fit on one
    /// shelf.
    @Test("A tight height shrinks the common scale")
    func aTightHeightShrinksTheScale() {
        let entries = (0..<10).map { entry("300\($0).dat", width: 40, height: 24) }

        let roomy = layout(entries, constraint(.width, inches: 0.5), metrics(maxHeight: 0))
        let cramped = layout(entries, constraint(.width, inches: 0.5), metrics(maxHeight: 80))

        #expect(roomy.scale == LDrawStepPartListLayout.defaultMetrics().baseScale)
        #expect(roomy.contentSize.height > 80, "the fixture has to exceed the limit to test it")
        #expect(cramped.scale < roomy.scale)
        #expect(cramped.contentSize.height <= 80.001)
    }

    /// Shrinking has a floor. Past it an icon is no longer a picture of
    /// anything, so the list overflows instead, and says so.
    @Test("Past the legibility floor the list overflows and reports it")
    func theScaleFloorIsHonoredAndOverflowReported() {
        let settings = metrics(maxHeight: 30)
        let entries = (0..<40).map { entry("part\($0).dat", width: 40, height: 24) }

        let result = layout(entries, constraint(.width, inches: 2.0), settings)

        #expect(result.scale >= settings.minimumScale)
        #expect(result.overflowCount > 0)
        #expect(result.placements.count + Int(result.overflowCount) == entries.count)
        #expect(result.placements.count > 0, "something should still be shown")
    }

    @Test("Nothing is dropped when everything fits")
    func nothingIsDroppedWhenEverythingFits() {
        for maxHeight in [0.0, 1000.0] {
            let result = layout(mixedEntries, constraint(.width, inches: 2.0), metrics(maxHeight: maxHeight))

            #expect(result.placements.count == mixedEntries.count, "max height \(maxHeight)")
            #expect(result.overflowCount == 0, "max height \(maxHeight)")
        }
    }

    // MARK: - Cell geometry

    @Test("A cell is its icon, its padding, and room for the multiplier")
    func cellGeometryAddsUp() throws {
        let settings = metrics()
        let result = layout([entry("3001.dat", width: 40, height: 24)],
                            constraint(.width, inches: 4.0),
                            settings)

        let placement = try #require(result.placements.first)

        #expect(abs(placement.cellFrame.size.width - (40 * result.scale + 2 * settings.cellPadding)) < 0.001)
        #expect(abs(placement.cellFrame.size.height
                    - (24 * result.scale + 2 * settings.cellPadding + settings.labelHeight)) < 0.001)

        // The icon sits inside the padding, above the label strip.
        #expect(abs(placement.iconFrame.size.width - 40 * result.scale) < 0.001)
        #expect(abs(placement.iconFrame.size.height - 24 * result.scale) < 0.001)
        #expect(abs(placement.labelFrame.size.height - settings.labelHeight) < 0.001)
        #expect(abs((placement.labelFrame.origin.y + placement.labelFrame.size.height)
                    - (placement.cellFrame.origin.y + placement.cellFrame.size.height)) < 0.001)
    }

    @Test("The frame is the content plus its padding")
    func frameIsContentPlusPadding() {
        let settings = metrics()
        let result = layout(mixedEntries, constraint(.area), settings)

        #expect(abs(result.frameSize.width - (result.contentSize.width + 2 * settings.framePadding)) < 0.001)
        #expect(abs(result.frameSize.height - (result.contentSize.height + 2 * settings.framePadding)) < 0.001)
    }

    // MARK: - Stud annotations

    /// The number comes from the untransformed bounds, and the longer side
    /// decides. A 1x6 and a 1x8 are the same drawing at different lengths, but
    /// a 1x4 is read off the drawing. A tile has no studs to count, so it needs
    /// the number past two.
    @Test("A part over four studs long is annotated, and a tile over two")
    func longPartsAreAnnotated() throws {
        let cases: [(part: LDrawStepPartListEntry, expected: String?)] = [
            (entry("1x8.dat", width: 20, height: 24, depth: 160), "1×8"),
            (entry("2x6.dat", width: 40, height: 24, depth: 120), "2×6"),
            (entry("1x4.dat", width: 20, height: 24, depth: 80), nil),
            (entry("2x3.dat", width: 40, height: 24, depth: 60), nil),
            (entry("4x4.dat", width: 80, height: 24, depth: 80), nil),
            (entry("3069.dat", title: "Tile  1 x  2", width: 20, height: 8, depth: 40), nil),
            (entry("63864.dat", title: "Tile  1 x  3", width: 20, height: 8, depth: 60), "1×3"),
            (entry("2431.dat", title: "Tile  1 x  4", width: 20, height: 8, depth: 80), "1×4"),
            (entry("3068.dat", title: "Tile  2 x  2", width: 40, height: 8, depth: 40), nil),
            // An alias marker is not part of the name.
            (entry("26603.dat", title: "=Tile  2 x  3", width: 40, height: 8, depth: 60), "2×3"),
            (entry("3070.dat", title: "Tile  1 x  1", width: 20, height: 8, depth: 20), nil),
            (entry("3622.dat", title: "Brick  1 x  3", width: 20, height: 24, depth: 60), nil),
            // Only the first word decides.
            (entry("3004.dat", title: "Brick  1 x  2 with Tile", width: 20, height: 24, depth: 40), nil),
            (entry("tiled.dat", title: "Tiled Slope 2 x 3", width: 40, height: 24, depth: 60), nil),
        ]

        let result = layout(cases.map(\.part), constraint(.area))

        for (part, expected) in cases {
            let placement = try #require(result.placements.first { $0.entry.partName == part.partName })
            #expect(placement.annotationText == expected, "\(part.partName)")
        }
    }

    /// An annotation must not land on the part, whatever angle the projection
    /// leaves it at, so it gets a strip of its own.
    @Test("An annotation gets its own strip, clear of the icon")
    func annotationsDoNotOverlapTheIcon() throws {
        let result = layout([entry("beam.dat", width: 20, height: 24, depth: 160)],
                            constraint(.area))
        let beam = try #require(result.placements.first)

        #expect(beam.annotationFrame.size.height > 0)
        #expect(beam.annotationFrame.size.width > 0)
        #expect(beam.annotationFrame.size.width <= beam.cellFrame.size.width + 0.001)
        #expect(abs(middleX(beam.annotationFrame) - middleX(beam.cellFrame)) < 0.001)

        // Strip on top, icon below it, no overlap. The badge may be let down
        // from the strip toward the part, but no further than the icon's box.
        #expect(beam.annotationFrame.origin.y >= beam.cellFrame.origin.y - 0.001)
        #expect(beam.iconFrame.origin.y
                >= beam.annotationFrame.origin.y + beam.annotationFrame.size.height - 0.001)

        // The icon still clears the label strip at the bottom.
        #expect(beam.iconFrame.origin.y + beam.iconFrame.size.height
                <= beam.labelFrame.origin.y + 0.001)
    }

    /// The host measures the text; the badge is a point taller than it, half
    /// its height wider at each end, centered and held inside its slot.
    @Test("A badge is built around the measured text and stays in its slot")
    func badgeFitsAroundItsText() {
        let slot = Box2(origin: Point2(x: 10, y: 20), size: Size2(width: 40, height: 14))

        let badge = LDrawStepPartListLayout.badgeRect(forTextSize: Size2(width: 17.3, height: 10.2), inSlot: slot)
        #expect(badge.size.height == 12)
        #expect(badge.size.width == 30)
        #expect(badge.origin.x == 15)
        #expect(badge.origin.y == 21)

        let wide = LDrawStepPartListLayout.badgeRect(forTextSize: Size2(width: 50, height: 20), inSlot: slot)
        #expect(wide.size.width == 40)
        #expect(wide.size.height == 14)
    }

    @Test("A cell with no annotation reserves no strip")
    func unannotatedCellsReserveNothing() throws {
        let result = layout([entry("2x3.dat", width: 40, height: 24, depth: 60)],
                            constraint(.area))
        let plate = try #require(result.placements.first)

        #expect(plate.annotationText == nil)
        #expect(plate.annotationFrame.size.height == 0)
        #expect(plate.iconFrame.origin.y > plate.cellFrame.origin.y)
    }

    /// A shrunken icon does not show the part's real size, so it is annotated,
    /// and given a strip, even when it is not long and thin.
    @Test("A shrunken part is annotated even when it is not long and thin")
    func reducedPartsAreAnnotated() throws {
        let plate = try #require(cappedPlateLayout.placements.first)

        #expect(plate.isScaledDown == true)
        #expect(plate.annotationText != nil)
        #expect(plate.annotationFrame.size.height > 0)
    }

    // MARK: - Labels beside the part

    /// The three-quarter view the list is drawn at when it does not follow the
    /// step. The fixtures above use the identity view, where every bounding
    /// box projects to a full rectangle with no empty corners.
    private var threeQuarterView: Matrix4 {
        LDrawStepPartListLayout.viewTransform(forAngle: Tuple3(x: 16.707, y: 42.63, z: 16.039))
    }

    /// AREA unless another constraint is given.
    private func angledLayout(_ entries: [LDrawStepPartListEntry],
                              _ constraint: LDrawStepPartListConstraint? = nil,
                              _ metrics: LDrawStepPartListMetrics? = nil) -> LDrawStepPartListLayout {
        LDrawStepPartListLayout.layout(forEntries: entries,
                                       constraint: constraint ?? self.constraint(.area),
                                       viewTransform: threeQuarterView,
                                       metrics: metrics ?? self.metrics())
    }

    private typealias Point = (x: Double, y: Double)

    /// The shape the labels must stay off: the entry's bounding box projected
    /// at the list's angle and centered in its icon frame. Worked out here on
    /// its own, so the tests check the packer instead of repeating it.
    private func outline(of placement: LDrawStepPartListPlacement) -> [Point] {
        outline(of: placement, points: corners(of: placement.entry.modelBounds), view: threeQuarterView)
    }

    /// The same for the given points, seen through `view`.
    private func outline(of placement: LDrawStepPartListPlacement, points: [Point3], view: Matrix4) -> [Point] {
        let projected: [Point] = points.map { point in
            let seen = V3MulPointByProjMatrix(point, view)
            return (seen.x, seen.y)
        }
        let midX = (projected.map(\.x).min()! + projected.map(\.x).max()!) / 2
        let midY = (projected.map(\.y).min()! + projected.map(\.y).max()!) / 2
        let icon = placement.iconFrame

        return convexHull(projected.map {
            (icon.origin.x + icon.size.width / 2 + ($0.x - midX) * placement.scale,
             icon.origin.y + icon.size.height / 2 + ($0.y - midY) * placement.scale)
        })
    }

    /// The convex hull of the points, by Andrew's monotone chain. Consecutive
    /// corners always turn the same way.
    private func convexHull(_ points: [Point]) -> [Point] {
        func cross(_ o: Point, _ a: Point, _ b: Point) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        let sorted = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        var lower: [Point] = []
        var upper: [Point] = []

        for point in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }
        for point in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    private func hull(_ hull: [Point], contains point: Point) -> Bool {
        guard hull.count >= 3 else { return false }

        for index in 0..<hull.count {
            let a = hull[index]
            let b = hull[(index + 1) % hull.count]
            if (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x) < 0 {
                return false
            }
        }
        return true
    }

    /// Whether a box and an outline share any area. A grid of points across
    /// the box is tested against the outline, and the outline's corners
    /// against the box. The grid is fine enough for text-sized boxes.
    private func overlaps(_ box: Box2, _ outline: [Point]) -> Bool {
        guard box.size.width > 0, box.size.height > 0 else { return false }

        for i in 0...8 {
            for j in 0...8 {
                let point = (box.origin.x + box.size.width * Double(i) / 8,
                             box.origin.y + box.size.height * Double(j) / 8)
                if hull(outline, contains: point) { return true }
            }
        }
        return outline.contains {
            $0.x > box.origin.x && $0.x < box.origin.x + box.size.width
                && $0.y > box.origin.y && $0.y < box.origin.y + box.size.height
        }
    }

    private func intersects(_ a: Box2, _ b: Box2) -> Bool {
        a.origin.x < b.origin.x + b.size.width && b.origin.x < a.origin.x + a.size.width
            && a.origin.y < b.origin.y + b.size.height && b.origin.y < a.origin.y + a.size.height
    }

    /// How far left and right a hull reaches between two heights, or nil when
    /// it does not reach them. Each edge is clipped to that band.
    private func hullSpanX(_ hull: [Point], fromY: Double, toY: Double) -> (lo: Double, hi: Double)? {
        var xs: [Double] = []

        for index in 0..<hull.count {
            let a = hull[index]
            let b = hull[(index + 1) % hull.count]
            var low = 0.0, high = 1.0

            if a.y == b.y {
                if a.y < fromY || a.y > toY { continue }
            } else {
                let t0 = (fromY - a.y) / (b.y - a.y), t1 = (toY - a.y) / (b.y - a.y)
                low = max(low, min(t0, t1))
                high = min(high, max(t0, t1))
                if low > high { continue }
            }
            xs.append(a.x + (b.x - a.x) * low)
            xs.append(a.x + (b.x - a.x) * high)
        }

        guard let lo = xs.min(), let hi = xs.max() else { return nil }
        return (lo, hi)
    }

    /// At three-quarters a 1x8 plate is a diagonal bar in a mostly empty cell,
    /// so its multiplier fits in the empty bottom corner beside the bar and
    /// the cell needs no strip for it.
    @Test("A diagonal part's multiplier sits in an empty corner beside it")
    func diagonalPartsCarryTheirMultiplierBesideThem() throws {
        let settings = metrics()
        let result = angledLayout([entry("3460.dat", width: 20, height: 8, depth: 160)])
        let plate = try #require(result.placements.first)

        // Every annotated cell reserves the badge's strip above the icon.
        let annotationStrip = plate.annotationText != nil ? settings.annotationHeight : 0

        // No strip below the icon...
        #expect(abs(plate.cellFrame.size.height
                    - (plate.iconFrame.size.height + 2 * settings.cellPadding + annotationStrip)) < 0.001)

        // ...because the multiplier is inside the icon's padded box, on its
        // bottom line.
        #expect(plate.labelFrame.size.width < plate.cellFrame.size.width)
        #expect(plate.labelFrame.origin.y >= plate.iconFrame.origin.y - settings.cellPadding - 0.001)
        #expect(abs(maxY(plate.labelFrame) - (maxY(plate.iconFrame) + settings.cellPadding)) < 0.001)
    }

    /// A count starts in a bottom corner and slides toward the middle until it
    /// is `decorationGap` from the part.
    @Test("A count slides in until the part stops it")
    func countsSlideInUntilThePartStopsThem() throws {
        let gap = metrics().decorationGap

        // A 1x8 plate leaves the middle of the bottom line clear.
        let thin = try #require(angledLayout([entry("3460.dat", width: 20, height: 8, depth: 160)]).placements.first)
        let thinLabel = thin.labelFrame

        #expect(thinLabel.size.width < thin.cellFrame.size.width)
        #expect(abs(middleX(thinLabel) - middleX(thin.iconFrame)) < 0.01)
        let thinSpan = try #require(hullSpanX(outline(of: thin), fromY: thinLabel.origin.y - gap, toY: maxY(thinLabel) + gap))
        #expect(thinSpan.hi < thinLabel.origin.x - gap || thinSpan.lo > thinLabel.origin.x + thinLabel.size.width + gap)

        // A 6x8 plate is in the way, so its count stops on the right, a gap
        // short of the part.
        let wide = try #require(angledLayout([entry("6x8.dat", width: 120, height: 8, depth: 160)]).placements.first)
        let wideLabel = wide.labelFrame
        let span = try #require(hullSpanX(outline(of: wide), fromY: wideLabel.origin.y - gap, toY: maxY(wideLabel) + gap))

        #expect(wideLabel.size.width < wide.cellFrame.size.width)
        #expect(middleX(wideLabel) > middleX(wide.iconFrame) + 1)
        #expect(abs(wideLabel.origin.x - (span.hi + gap)) < 0.25)

        // Turned the other way, the plate leaves the left nearer the middle.
        let turned = try #require(angledLayout([entry("8x6.dat", width: 160, height: 8, depth: 120)]).placements.first)
        let turnedLabel = turned.labelFrame
        let turnedSpan = try #require(hullSpanX(outline(of: turned), fromY: turnedLabel.origin.y - gap, toY: maxY(turnedLabel) + gap))

        #expect(middleX(turnedLabel) < middleX(turned.iconFrame) - 1)
        #expect(abs((turnedLabel.origin.x + turnedLabel.size.width) - (turnedSpan.lo - gap)) < 0.25)

        // A turned 1x8 blocks the right corner, so its count comes in from the
        // left.
        let crossing = try #require(angledLayout([entry("1x8.dat", width: 160, height: 8, depth: 20)]).placements.first)

        #expect(crossing.labelFrame.size.width < crossing.cellFrame.size.width)
        #expect(abs(middleX(crossing.labelFrame) - middleX(crossing.iconFrame)) < 0.01)
    }

    /// Face-on, the ring's outline has 96 corners, and the count is still kept
    /// off it.
    @Test("A many-cornered outline keeps its count beside the part")
    func manyCorneredOutlinesKeepTheirCountBeside() throws {
        let faceOn = LDrawStepPartListLayout.viewTransform(forAngle: Tuple3(x: 90, y: 0, z: 0))
        let packed = LDrawStepPartListLayout.layout(forEntries: [ringEntry], constraint: constraint(.area),
                                                    viewTransform: faceOn, metrics: metrics())
        let placement = try #require(packed.placements.first)
        let shape = outline(of: placement, points: ring, view: faceOn)

        #expect(shape.count == 96)
        #expect(placement.labelFrame.size.width < placement.cellFrame.size.width)
        #expect(!overlaps(placement.labelFrame, shape))
    }

    /// The badge is centered across the cell and let down from its strip until
    /// it is just clear of the part. A part drawn at an angle does not reach
    /// the top of its box across the whole width, so a badge left on the
    /// strip's line would hang over an empty corner.
    @Test("A badge is centered over the cell and let down onto the part")
    func badgesAreCenteredAndLetDown() throws {
        let settings = metrics()
        let result = angledLayout([entry("2x16.dat", width: 40, height: 8, depth: 320)])
        let plate = try #require(result.placements.first)

        #expect(plate.annotationText == "2×16")

        // Centered across the cell.
        #expect(abs(middleX(plate.annotationFrame) - middleX(plate.cellFrame)) < 0.001)

        // Let down from the strip's own line, but never past the middle of
        // the icon's box.
        #expect(plate.annotationFrame.origin.y > plate.cellFrame.origin.y + 0.001)
        #expect(plate.annotationFrame.origin.y
                <= plate.iconFrame.origin.y - settings.cellPadding + plate.iconFrame.size.height / 2 + 0.001)

        // The multiplier is beside the part, below the badge.
        #expect(plate.labelFrame.size.width < plate.cellFrame.size.width)
        #expect(plate.labelFrame.origin.y > plate.annotationFrame.origin.y)
    }

    /// On a strip shelf the count is drawn below the icon, so the badge does
    /// not stop where the count would have sat beside the part. A count only
    /// reaches the badge's path when it is tall and narrow and the padding is
    /// wide, so these metrics are unusual.
    @Test("A badge is not held up by a count drawn in the strip")
    func badgesIgnoreACountInTheStrip() throws {
        var settings = metrics()
        settings.baseScale = 0.25
        settings.cellPadding = 15
        settings.labelHeight = 36
        settings.labelCharacterWidth = 2
        settings.annotationCharacterWidth = 12

        var wideCount = settings
        wideCount.labelCharacterWidth = 100

        let plate = entry("3460.dat", width: 20, height: 8, depth: 160)
        let pinned = constraint(.width, inches: 4.0)

        func plateIn(_ packed: LDrawStepPartListLayout) throws -> LDrawStepPartListPlacement {
            try #require(packed.placements.first { $0.entry.partName == "3460.dat" })
        }
        func badgeDrop(_ placement: LDrawStepPartListPlacement) -> Double {
            placement.annotationFrame.origin.y - placement.iconFrame.origin.y
        }

        // Alone, the count sits beside the plate and holds the badge up.
        let beside = try plateIn(angledLayout([plate], pinned, settings))
        // A count too wide to sit beside the plate leaves the badge free.
        let unheld = try plateIn(angledLayout([plate], pinned, wideCount))
        // A tiny part has no room for its count, so the shelf keeps a strip.
        let onShelf = try plateIn(angledLayout([plate, entry("tiny.dat", width: 2, height: 2, depth: 2)], pinned, settings))

        #expect(beside.labelFrame.size.width < beside.cellFrame.size.width)
        #expect(badgeDrop(beside) < badgeDrop(unheld) - 1)

        #expect(abs(onShelf.labelFrame.size.width - onShelf.cellFrame.size.width) < 0.001)
        #expect(abs(badgeDrop(onShelf) - badgeDrop(unheld)) < 0.001)
    }

    /// A 1x1 brick fills its box at any angle, so no corner has room for the
    /// multiplier and it goes in the strip underneath.
    @Test("A compact part keeps its multiplier in the strip below")
    func compactPartsUseTheStrip() throws {
        let settings = metrics()
        let result = angledLayout([entry("3005.dat", width: 20, height: 24, depth: 20)])
        let brick = try #require(result.placements.first)

        #expect(abs(brick.cellFrame.size.height
                    - (brick.iconFrame.size.height + 2 * settings.cellPadding + settings.labelHeight)) < 0.001)
        #expect(abs(brick.labelFrame.size.width - brick.cellFrame.size.width) < 0.001)
        #expect(abs((brick.labelFrame.origin.y + brick.labelFrame.size.height)
                    - (brick.cellFrame.origin.y + brick.cellFrame.size.height)) < 0.001)
    }

    @Test("No label overlaps its part or the other label")
    func labelsStayOffTheirParts() throws {
        let shapes = [entry("1x8.dat", width: 20, height: 8, depth: 160),
                      entry("2x8.dat", width: 40, height: 8, depth: 160),
                      entry("1x4.dat", width: 80, height: 8, depth: 20),
                      entry("1x6brick.dat", width: 20, height: 24, depth: 120),
                      entry("2x2.dat", width: 40, height: 24, depth: 40),
                      entry("6x8.dat", width: 120, height: 8, depth: 160),
                      entry("1x1.dat", width: 20, height: 24, depth: 20),
                      entry("1x15.dat", width: 20, height: 20, depth: 300, quantity: 12)]

        let result = angledLayout(shapes)
        #expect(result.placements.count == shapes.count)

        for placement in result.placements {
            let name = placement.entry.partName
            let shape = outline(of: placement)

            #expect(!overlaps(placement.labelFrame, shape), "\(name): multiplier on the part")
            #expect(!overlaps(placement.annotationFrame, shape), "\(name): annotation on the part")
            #expect(!intersects(placement.labelFrame, placement.annotationFrame), "\(name): labels collide")
        }
    }

    // MARK: - Purity

    /// A caller caches a layout and repacks it when the inputs change, so the
    /// same inputs must always give the same answer.
    @Test("The same inputs always produce the same layout")
    func layoutIsAPureFunctionOfItsInputs() {
        for mode in [LPubPliConstrainMode.area, .square, .width, .height, .columns] {
            let subject = constraint(mode, inches: 2.0, columns: 3)
            let first = layout(mixedEntries, subject)
            let second = layout(mixedEntries, subject)

            #expect(first.scale == second.scale, "\(mode)")
            #expect(first.rowCount == second.rowCount, "\(mode)")
            #expect(first.contentSize.width == second.contentSize.width, "\(mode)")
            #expect(first.contentSize.height == second.contentSize.height, "\(mode)")
            #expect(first.overflowCount == second.overflowCount, "\(mode)")
            #expect(first.placements.count == second.placements.count, "\(mode)")

            for (a, b) in zip(first.placements, second.placements) {
                #expect(a.entry.partName == b.entry.partName, "\(mode)")
                #expect(a.cellFrame.origin.x == b.cellFrame.origin.x, "\(mode)")
                #expect(a.cellFrame.origin.y == b.cellFrame.origin.y, "\(mode)")
                #expect(a.cellFrame.size.width == b.cellFrame.size.width, "\(mode)")
                #expect(a.cellFrame.size.height == b.cellFrame.size.height, "\(mode)")
                #expect(a.scale == b.scale, "\(mode)")
            }
        }
    }

    // MARK: - Stacking

    /// Shelves are filled tallest part first, which packs them tight, then
    /// stacked heaviest at the bottom, the way parts settle on a table.
    @Test("The heaviest shelf sits at the bottom")
    func heaviestShelvesSitAtTheBottom() throws {
        let entries = [entry("small.dat", width: 20, height: 8),
                       entry("tall.dat", width: 20, height: 96),
                       entry("medium.dat", width: 20, height: 24)]

        // One part per shelf, so shelf order is part order.
        let result = layout(entries, constraint(.columns, columns: 1))
        let byRow = result.placements.sorted { $0.rowIndex < $1.rowIndex }

        #expect(byRow.map(\.entry.partName) == ["small.dat", "medium.dat", "tall.dat"])

        // Stacked down the box in that order, not just numbered so.
        #expect(byRow[0].cellFrame.origin.y < byRow[1].cellFrame.origin.y)
        #expect(byRow[1].cellFrame.origin.y < byRow[2].cellFrame.origin.y)
    }

    /// Weight is bounding-box volume, not height, so a big flat plate outweighs
    /// a tall thin part even though the packer places the tall one first.
    @Test("Weight, not height, decides which shelf sinks")
    func weightNotHeightDecidesTheOrder() throws {
        let entries = [entry("antenna.dat", width: 20, height: 96, depth: 20),
                       entry("baseplate.dat", width: 160, height: 8, depth: 160)]

        let result = layout(entries, constraint(.columns, columns: 1))
        let byRow = result.placements.sorted { $0.rowIndex < $1.rowIndex }

        #expect(byRow.map(\.entry.partName) == ["antenna.dat", "baseplate.dat"])
    }

    /// A list that does not fit loses its small parts. The heaviest shelves
    /// are at the bottom, so the losses come off the top.
    @Test("An overflowing list drops its lightest shelves")
    func overflowDropsTheLightestShelves() throws {
        let entries = (0..<5).map { entry("small\($0).dat", width: 20, height: 8) }
                    + [entry("baseplate.dat", width: 160, height: 8, depth: 160)]

        let result = layout(entries, constraint(.columns, columns: 1), metrics(maxHeight: 40))

        #expect(result.overflowCount > 0)
        let bottom = try #require(result.placements.max { $0.rowIndex < $1.rowIndex })
        #expect(bottom.entry.partName == "baseplate.dat")
    }

    /// Parts on a shelf stand on a common line, the way they would on a table,
    /// rather than hanging from the top of the shelf.
    @Test("Parts on a shelf share a bottom edge")
    func partsOnAShelfShareABottomEdge() throws {
        let entries = [entry("tall.dat", width: 20, height: 96),
                       entry("short.dat", width: 20, height: 8),
                       // Long and thin, so it gets an annotation strip.
                       entry("beam.dat", width: 20, height: 24, depth: 160)]

        let result = layout(entries, constraint(.width, inches: 4.0))
        #expect(result.rowCount == 1)

        let bottoms = result.placements.map { $0.iconFrame.origin.y + $0.iconFrame.size.height }
        for bottom in bottoms {
            #expect(abs(bottom - bottoms[0]) < 0.001)
        }
    }

    /// Counts are read across a shelf, so if one part has no room beside it,
    /// every count on that shelf drops into its strip.
    @Test("One count with no room beside its part sends the whole shelf below")
    func oneCrowdedCountSendsTheShelfBelow() throws {
        let entries = [entry("3460.dat", width: 20, height: 8, depth: 160),
                       entry("3005.dat", width: 20, height: 24, depth: 20)]

        let result = angledLayout(entries, constraint(.width, inches: 4.0))
        #expect(result.rowCount == 1)

        let plate = try #require(result.placements.first { $0.entry.partName == "3460.dat" })
        let brick = try #require(result.placements.first { $0.entry.partName == "3005.dat" })

        // The compact brick fills its box and has no corner free. On its own
        // the long plate would have taken its count beside it.
        for placement in [plate, brick] {
            #expect(abs(placement.labelFrame.size.width - placement.cellFrame.size.width) < 0.001)
        }

        #expect(abs(plate.labelFrame.origin.y - brick.labelFrame.origin.y) < 0.001)

        // The line is the bottom of the icons, not of the cells.
        #expect(abs((plate.iconFrame.origin.y + plate.iconFrame.size.height)
                    - (brick.iconFrame.origin.y + brick.iconFrame.size.height)) < 0.001)

        // The shelf is its tallest cell without a count strip, plus one strip.
        let settings = metrics()
        let tallest = [plate, brick].map {
            $0.iconFrame.size.height + 2 * settings.cellPadding + ($0.annotationText != nil ? settings.annotationHeight : 0)
        }.max() ?? 0
        #expect(abs(result.contentSize.height - (tallest + settings.labelHeight)) < 0.001)

        // One shelf, so every cell ends at the bottom of the content.
        for placement in [plate, brick] {
            #expect(abs(maxY(placement.cellFrame) - result.contentSize.height) < 0.001)
        }
    }

    /// Where every part on the shelf has room beside it, each count sits on
    /// the bottom line of its icon's box. The icons stand on one line, so the
    /// counts read across the shelf.
    @Test("Counts beside their parts share one line")
    func countsBesidePartsShareOneLine() throws {
        let settings = metrics()
        // Long thin bars, which project as diagonals and so leave a corner
        // free.
        let entries = [entry("short.dat", width: 20, height: 8, depth: 160),
                       entry("long.dat", width: 20, height: 8, depth: 320),
                       entry("longest.dat", width: 20, height: 24, depth: 400)]

        let result = angledLayout(entries, constraint(.width, inches: 6.0))
        #expect(result.rowCount == 1)

        let line = try #require(result.placements.first.map { maxY($0.labelFrame) })

        for placement in result.placements {
            let name = placement.entry.partName

            // Every count found room, so none spans its cell.
            #expect(placement.labelFrame.size.width < placement.cellFrame.size.width, "\(name)")
            #expect(abs(maxY(placement.labelFrame) - (maxY(placement.iconFrame) + settings.cellPadding)) < 0.001, "\(name)")
            #expect(abs(maxY(placement.labelFrame) - line) < 0.001, "\(name)")
        }
    }

    // MARK: - Room for the labels

    /// A part far smaller than its count still gets a cell as wide as the "12x"
    /// under it, or the counts along a shelf would run together.
    @Test("A cell is at least as wide as its multiplier")
    func cellsAreAsWideAsTheirMultiplier() throws {
        let settings = metrics()
        let result = layout([entry("tiny.dat", width: 2, height: 2, depth: 2, quantity: 12)],
                            constraint(.width, inches: 2.0), settings)
        let tiny = try #require(result.placements.first)

        // "12x": three characters and a point of slack either side.
        #expect(tiny.cellFrame.size.width >= 3 * settings.labelCharacterWidth + 2 - 0.001)
        #expect(abs(tiny.labelFrame.size.width - tiny.cellFrame.size.width) < 0.001)
    }

    /// A 1x6 plate seen from the front is a thin sliver, but its badge must
    /// still read "1x6" without spilling onto the next cell.
    @Test("A cell is at least as wide as its annotation badge")
    func cellsAreAsWideAsTheirBadge() throws {
        let settings = metrics()
        let result = layout([entry("3666.dat", width: 20, height: 8, depth: 120)],
                            constraint(.width, inches: 2.0), settings)
        let plate = try #require(result.placements.first)

        #expect(plate.annotationText == "1×6")

        let badgeWidth = 3 * settings.annotationCharacterWidth + settings.annotationHeight - 2
        #expect(plate.cellFrame.size.width >= badgeWidth - 0.001)
        #expect(plate.annotationFrame.size.width >= badgeWidth - 0.001)
        #expect(plate.annotationFrame.size.width <= plate.cellFrame.size.width + 0.001)
        #expect(abs(middleX(plate.annotationFrame) - middleX(plate.cellFrame)) < 0.001)
    }

    /// Widening a cell for its label does not stretch the icon. The part is
    /// drawn at its own size and centered, which is where the model builder
    /// puts it.
    @Test("A widened cell keeps its icon at its own size, centered")
    func widenedCellsCenterTheirIcon() throws {
        let result = layout([entry("tiny.dat", width: 2, height: 2, depth: 2, quantity: 12)],
                            constraint(.width, inches: 2.0))
        let tiny = try #require(result.placements.first)

        #expect(abs(tiny.iconFrame.size.width - 2 * result.scale) < 0.001)
        #expect(abs(middleX(tiny.iconFrame) - middleX(tiny.cellFrame)) < 0.001)
    }

    /// Primitives a point or two wide each get a cell of their own, so their
    /// counts must not pile up on one another.
    @Test("Counts along a shelf of tiny parts do not run together")
    func tinyPartsCountsDoNotCollide() throws {
        let entries = (0..<8).map { entry("prim\($0).dat", width: 1, height: 1, depth: 1, quantity: UInt(10 + $0)) }
        let result = layout(entries, constraint(.width, inches: 4.0))

        #expect(result.rowCount == 1)

        for a in result.placements {
            for b in result.placements where a !== b {
                #expect(!intersects(a.labelFrame, b.labelFrame), "\(a.entry.partName) / \(b.entry.partName)")
            }
        }
    }

    /// A stud count names a part, and a submodel is not a part.
    @Test("A submodel carries no size annotation")
    func submodelsAreNotAnnotated() throws {
        let submodel = LDrawStepPartListEntry(partName: "boom.ldr",
                                              displayTitle: "boom.ldr",
                                              color: nil,
                                              quantity: 1,
                                              modelBounds: Box3(min: Point3(x: 0, y: 0, z: 0),
                                                                max: Point3(x: 20, y: 24, z: 160)),
                                              isMissing: false,
                                              isSubmodel: true)

        let result = layout([submodel], constraint(.area))
        let placement = try #require(result.placements.first)

        #expect(placement.annotationText == nil)
    }

    // MARK: - Closing up a width

    /// As in LPub3D, a WIDTH from the view, the document or a drag only
    /// sets where the shelves wrap. The box never keeps blank space past them.
    @Test("A width wider than the parts closes up to them")
    func aWideWidthClosesUp() throws {
        let settings = metrics()
        let entries = [entry("3001.dat", width: 40, height: 24), entry("3003.dat", width: 20, height: 24)]

        for inches: Float in [2.5, 6.0] {
            let result = layout(entries, constraint(.width, inches: inches), settings)

            #expect(result.rowCount == 1, "\(inches)")
            #expect(abs(result.contentSize.width - 72) < 0.001, "\(inches)")
            #expect(abs(result.contentSize.width - (rowWidths(result).max() ?? 0)) < 0.001, "\(inches)")
        }
    }

    /// When the parts need more room, the shelves wrap at the width and the
    /// box grows no wider than it.
    @Test("A width still wraps the shelves")
    func widthStillWraps() throws {
        let settings = metrics()
        let entries = (0..<12).map { entry("part\($0).dat", width: 40, height: 24) }
        let result = layout(entries, constraint(.width, inches: 1.0), settings)

        #expect(result.rowCount > 1)
        #expect(result.contentSize.width <= 1.0 * settings.pointsPerInch - 2 * settings.framePadding + 0.001)
    }

    /// The first shelf is six 46 point cells, 276 points. The beam is drawn
    /// 172.8 points wide below it, so 51.6 points of blank space on each side.
    @Test("A capped part stays centered in a box that closed up")
    func cappedPartCenteredInClosedBox() throws {
        let entries = beamEntries + (0..<5).map { entry("brick\($0).dat", width: 40, height: 24) }
        let result = layout(entries, constraint(.width, inches: 2.0))
        let beam = try #require(result.placements.first { $0.entry.partName == "beam.dat" })

        let leftGap = beam.cellFrame.origin.x
        let rightGap = result.contentSize.width - (beam.cellFrame.origin.x + beam.cellFrame.size.width)

        #expect(beam.isScaledDown)
        #expect(abs(result.contentSize.width - 276) < 0.001)
        #expect(abs(leftGap - 51.6) < 0.001)
        #expect(abs(leftGap - rightGap) < 0.001)
    }

    // MARK: - Where a resize drag stops

    /// A size in inches as CONSTRAIN writes it, rounded up the way a drag
    /// rounds its stops.
    private func writtenInches(_ points: Double) -> Float {
        Float(ceil(points / 150 / 0.0001 + 0.5) * 0.0001)
    }

    /// The cells are 126, 86, 46, 46, 26 and 26 points wide: 356 in all, and
    /// 368 with the frame padding.
    @Test("The one-row width holds every part on one shelf, and a little less does not")
    func oneRowWidthHoldsEveryPart() {
        let packed = layout(mixedEntries, constraint(.area))

        #expect(abs(packed.oneRowFrameWidth - 368) < 0.001)

        let oneRow = layout(mixedEntries, constraint(.width, inches: writtenInches(packed.oneRowFrameWidth)))
        #expect(oneRow.rowCount == 1)
        #expect(oneRow.placements.allSatisfy { !$0.isScaledDown })

        let less = layout(mixedEntries, constraint(.width, inches: Float((packed.oneRowFrameWidth - 2) / 150)))
        #expect(less.rowCount > 1)
    }

    /// The beam's padded icon is 646 points. Any narrower than 646 / 0.6 and
    /// it would be drawn smaller on a shelf of its own. The box still closes up
    /// to the 718 points the one shelf uses.
    @Test("A part too wide for its share sets the one-row width, so it is not drawn smaller")
    func aWidePartSetsTheOneRowWidth() {
        let packed = layout(beamEntries, constraint(.area))

        #expect(abs(packed.oneRowFrameWidth - (646 / 0.6 + 12)) < 0.001)

        let oneRow = layout(beamEntries, constraint(.width, inches: writtenInches(packed.oneRowFrameWidth)))
        #expect(oneRow.rowCount == 1)
        #expect(oneRow.placements.allSatisfy { !$0.isScaledDown })
        #expect(abs(oneRow.frameSize.width - (718 + 12)) < 0.001)
    }

    /// One shelf is the 3009 with its badge, 43 points, and a 12 point count
    /// strip. At the widest cell, 126 points, the shelves are 55, 42, 42 and
    /// 26 points with three gaps.
    @Test("A height packs one shelf below the one-row height, and the same packing above the tallest")
    func heightLimitsBracketWhatAHeightChanges() {
        let packed = layout(mixedEntries, constraint(.area))

        #expect(abs(packed.oneRowFrameHeight - 67) < 0.001)
        #expect(abs(packed.tallestFrameHeight - 195) < 0.001)

        for inches in [writtenInches(packed.oneRowFrameHeight), 0.25] {
            let short = layout(mixedEntries, constraint(.height, inches: inches))

            #expect(short.rowCount == 1, "\(inches)")
            #expect(abs(short.frameSize.height - packed.oneRowFrameHeight) < 0.001, "\(inches)")
        }

        for inches in [writtenInches(packed.tallestFrameHeight), 6.0] {
            let tall = layout(mixedEntries, constraint(.height, inches: inches))

            #expect(abs(tall.frameSize.height - packed.tallestFrameHeight) < 0.001, "\(inches)")
            #expect(abs(tall.frameSize.width - 138) < 0.001, "\(inches)")
        }
    }

    /// Measured from the parts at the base scale, so every drag event reads the
    /// same stops, whatever the step's constraint or the room on screen.
    @Test("The resize stops do not depend on the constraint or the height budget")
    func resizeStopsIgnoreTheConstraint() {
        let reference = layout(mixedEntries, constraint(.area))
        let others = [layout(mixedEntries, constraint(.square)),
                      layout(mixedEntries, constraint(.height, inches: 1.0)),
                      layout(mixedEntries, constraint(.width, inches: 1.0)),
                      layout(mixedEntries, constraint(.width, inches: 5.0)),
                      layout(mixedEntries, constraint(.columns, columns: 2)),
                      layout(mixedEntries, constraint(.width, inches: 1.0), metrics(maxHeight: 40))]

        for (index, other) in others.enumerated() {
            #expect(other.oneRowFrameWidth == reference.oneRowFrameWidth, "\(index)")
            #expect(other.oneRowFrameHeight == reference.oneRowFrameHeight, "\(index)")
            #expect(other.tallestFrameHeight == reference.tallestFrameHeight, "\(index)")
        }
    }
}
