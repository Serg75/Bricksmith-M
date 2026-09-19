//
//  LPubPliMetaTests.swift
//  UnitTests
//
//  Grammar tests for the LPub metas that get their own directive class:
//  PLI CONSTRAIN, PLI SHOW, the PLI and PART BEGIN IGN / END brackets,
//  PLI BEGIN SUB, PLI CAMERA_ANGLES, PLI PART_ROTATION, MODEL_SCALE on each
//  of its three branches, RESOLUTION, and PAGE SIZE / ORIENTATION.
//
//  A line we do not understand, including a bad spelling of one we do, stays
//  a generic LPubCommand and is written back unchanged. CONSTRAIN, which we
//  write, is written back in the form LPub3D writes. The other metas we
//  understand keep their text as typed.
//
//  The fixtures use no type-1 lines. Parsing one loads the referenced file
//  through LDrawPartLibrary, which needs a renderer the UnitTests target does
//  not have.
//
//  Created by Sergey Slobodenyuk on 2026-09-09.
//

import Testing
import Foundation
import LDrawCore

@Suite("LPub metas")
struct LPubPliMetaTests {

    // MARK: - Helpers

    /// Parses one line the way opening a document does and returns the
    /// directive it made.
    private func parse(_ line: String) throws -> LDrawDirective {
        let lines = [line, "0 STEP"]
        let step = try #require(LDrawStep(lines: lines,
                                          in: NSRange(location: 0, length: lines.count),
                                          parentGroup: nil))
        let directives = try #require(step.subdirectives() as? [LDrawDirective])
        return try #require(directives.first)
    }

    private func written(_ line: String) throws -> String {
        try parse(line).write()
    }

    /// Checks that a line stays a generic command and is written back
    /// unchanged.
    private func expectGenericAndVerbatim(_ line: String,
                                          sourceLocation: SourceLocation = #_sourceLocation) throws {
        let directive = try parse(line)

        #expect(directive.isMember(of: LPubCommand.self),
                "\(line) should stay a generic LPub command",
                sourceLocation: sourceLocation)
        #expect(directive.write() == line, sourceLocation: sourceLocation)
    }

    // MARK: - CONSTRAIN

    @Test("CONSTRAIN AREA and SQUARE parse without a value")
    func constrainValuelessModes() throws {
        let area = try #require(parse("0 !LPUB PLI CONSTRAIN AREA") as? LPubPliConstrain)
        #expect(area.scope == .unspecified)
        #expect(area.mode == .area)

        let square = try #require(parse("0 !LPUB PLI CONSTRAIN SQUARE") as? LPubPliConstrain)
        #expect(square.mode == .square)
    }

    @Test("CONSTRAIN WIDTH and HEIGHT carry an inch value")
    func constrainDimensionModes() throws {
        let width = try #require(parse("0 !LPUB PLI CONSTRAIN WIDTH 3.2400") as? LPubPliConstrain)
        #expect(width.mode == .width)
        #expect(width.inches == 3.24)

        let height = try #require(parse("0 !LPUB PLI CONSTRAIN HEIGHT 1.5") as? LPubPliConstrain)
        #expect(height.mode == .height)
        #expect(height.inches == 1.5)
    }

    @Test("CONSTRAIN COLS carries a column count")
    func constrainColumnMode() throws {
        let columns = try #require(parse("0 !LPUB PLI CONSTRAIN COLS 4") as? LPubPliConstrain)
        #expect(columns.mode == .columns)
        #expect(columns.columns == 4)
    }

    @Test("The scope keyword is optional, and both spellings are read")
    func constrainScopeKeyword() throws {
        let none = try #require(parse("0 !LPUB PLI CONSTRAIN WIDTH 2.5") as? LPubPliConstrain)
        #expect(none.scope == .unspecified)

        let local = try #require(parse("0 !LPUB PLI CONSTRAIN LOCAL WIDTH 2.5") as? LPubPliConstrain)
        #expect(local.scope == .local)
        #expect(local.inches == 2.5)

        let global = try #require(parse("0 !LPUB PLI CONSTRAIN GLOBAL AREA") as? LPubPliConstrain)
        #expect(global.scope == .global)
        #expect(global.mode == .area)
    }

    @Test("A parsed CONSTRAIN writes back the line it came from")
    func constrainRoundTrips() throws {
        for line in ["0 !LPUB PLI CONSTRAIN AREA",
                     "0 !LPUB PLI CONSTRAIN SQUARE",
                     "0 !LPUB PLI CONSTRAIN LOCAL WIDTH 3.2400",
                     "0 !LPUB PLI CONSTRAIN GLOBAL HEIGHT 11.0000",
                     "0 !LPUB PLI CONSTRAIN LOCAL COLS 3"] {
            let output = try written(line)
            #expect(output == line)
        }
    }

    /// We write the canonical spelling, not the one we read. Four decimals is
    /// the precision LPub3D uses.
    @Test("A loosely written value is canonicalized on write")
    func constrainCanonicalizesTheValue() throws {
        var output = try written("0 !LPUB PLI CONSTRAIN WIDTH 2")
        #expect(output == "0 !LPUB PLI CONSTRAIN WIDTH 2.0000")

        output = try written("0 !LPUB PLI CONSTRAIN LOCAL HEIGHT .5")
        #expect(output == "0 !LPUB PLI CONSTRAIN LOCAL HEIGHT 0.5000")
    }

    @Test("Editing a property rewrites the line")
    func constrainSettersRewriteTheLine() throws {
        let constrain = try #require(parse("0 !LPUB PLI CONSTRAIN AREA") as? LPubPliConstrain)

        constrain.scope = .local
        constrain.mode = .width
        constrain.inches = 2.5

        #expect(constrain.write() == "0 !LPUB PLI CONSTRAIN LOCAL WIDTH 2.5000")
    }

    @Test("A constraint built from scratch is AREA with no scope")
    func constrainDefaults() {
        let constrain = LPubPliConstrain()

        #expect(constrain.scope == .unspecified)
        #expect(constrain.mode == .area)
        #expect(constrain.write() == "0 !LPUB PLI CONSTRAIN AREA")
    }

    @Test("A copied constraint keeps its own values")
    func constrainCopiesIndependently() throws {
        let original = try #require(parse("0 !LPUB PLI CONSTRAIN LOCAL WIDTH 2.5") as? LPubPliConstrain)
        let duplicate = try #require(original.copy() as? LPubPliConstrain)

        original.inches = 4

        #expect(duplicate.inches == 2.5)
        #expect(duplicate.scope == .local)
        #expect(duplicate.write() == "0 !LPUB PLI CONSTRAIN LOCAL WIDTH 2.5000")
    }

    // MARK: - SHOW

    @Test("SHOW reads both booleans, with or without a scope")
    func showParses() throws {
        let plain = try #require(parse("0 !LPUB PLI SHOW TRUE") as? LPubPliShow)
        #expect(plain.scope == .unspecified)
        #expect(plain.isShown == true)

        let local = try #require(parse("0 !LPUB PLI SHOW LOCAL FALSE") as? LPubPliShow)
        #expect(local.scope == .local)
        #expect(local.isShown == false)

        let global = try #require(parse("0 !LPUB PLI SHOW GLOBAL TRUE") as? LPubPliShow)
        #expect(global.scope == .global)
        #expect(global.isShown == true)
    }

    @Test("A parsed SHOW writes back the line it came from")
    func showRoundTrips() throws {
        for line in ["0 !LPUB PLI SHOW TRUE",
                     "0 !LPUB PLI SHOW LOCAL FALSE",
                     "0 !LPUB PLI SHOW GLOBAL TRUE"] {
            let output = try written(line)
            #expect(output == line)
        }
    }

    // MARK: - BEGIN IGN / END

    @Test("The ignore bracket parses both ends")
    func ignoreBracketParses() throws {
        let begin = try #require(parse("0 !LPUB PLI BEGIN IGN") as? LPubPliIgnore)
        #expect(begin.beginsRange == true)

        let end = try #require(parse("0 !LPUB PLI END") as? LPubPliIgnore)
        #expect(end.beginsRange == false)
    }

    @Test("A parsed ignore bracket writes back the line it came from")
    func ignoreBracketRoundTrips() throws {
        for line in ["0 !LPUB PLI BEGIN IGN", "0 !LPUB PLI END"] {
            let output = try written(line)
            #expect(output == line)
        }
    }

    /// The PART bracket uses the same class as the PLI one. The branch tells
    /// them apart, so the two ranges stay separate.
    @Test("The PART ignore bracket parses both ends and writes them back")
    func partIgnoreBracketParsesAndRoundTrips() throws {
        let begin = try #require(parse("0 !LPUB PART BEGIN IGN") as? LPubPliIgnore)
        #expect(begin.beginsRange == true)
        #expect(begin.branch == .part)

        let end = try #require(parse("0 !LPUB PART END") as? LPubPliIgnore)
        #expect(end.beginsRange == false)
        #expect(end.branch == .part)

        let pli = try #require(parse("0 !LPUB PLI BEGIN IGN") as? LPubPliIgnore)
        #expect(pli.branch == .pli)

        for line in ["0 !LPUB PART BEGIN IGN", "0 !LPUB PART END"] {
            #expect(try written(line) == line)
        }

        try expectGenericAndVerbatim("0 !LPUB PART BEGIN IGN EXTRA")
        try expectGenericAndVerbatim("0 !LPUB PART BEGIN SUB 3001.dat")
    }

    /// -1 is the color an uncolored substitute holds. A real color code is
    /// never negative, so -1 stays with the tokens after it.
    @Test("A negative color on a substitute is not a color, and survives")
    func substituteNegativeColorIsKeptAsTyped() throws {
        let line = "0 !LPUB PLI BEGIN SUB 3001.dat -1 REL"
        let substitute = try #require(parse(line) as? LPubPliSubstitute)

        #expect(substitute.partColorCode == -1)
        #expect(substitute.trailingTokens == ["-1", "REL"])
        #expect(substitute.write() == line)
    }

    @Test("BEGIN SUB is a substitute, not an ignore bracket")
    func beginSubIsASubstitute() throws {
        let hinge = try #require(parse("0 !LPUB PLI BEGIN SUB 2429c01.ldr 15") as? LPubPliSubstitute)
        #expect(hinge.partName == "2429c01.ldr")
        #expect(hinge.partColorCode == 15)
        #expect(hinge.trailingTokens.isEmpty)

        // The color is optional. Without it the list uses the part's own.
        let uncolored = try #require(parse("0 !LPUB PLI BEGIN SUB 3001.dat") as? LPubPliSubstitute)
        #expect(uncolored.partColorCode == Int(LDrawColorT.colorBogus.rawValue))

        // Whatever LPub3D writes after the color is kept as it was.
        let rotated = try #require(parse("0 !LPUB PLI BEGIN SUB 3070b.dat 4 0 90 0 REL") as? LPubPliSubstitute)
        #expect(rotated.trailingTokens == ["0", "90", "0", "REL"])

        for line in ["0 !LPUB PLI BEGIN SUB 2429c01.ldr 15",
                     "0 !LPUB PLI BEGIN SUB 3001.dat",
                     "0 !LPUB PLI BEGIN SUB 3070b.dat 4 0 90 0 REL"] {
            #expect(try written(line) == line)
        }

        // No part named: nothing to substitute, so it stays generic.
        try expectGenericAndVerbatim("0 !LPUB PLI BEGIN SUB")
    }


    // MARK: - CAMERA_ANGLES

    @Test("CAMERA_ANGLES reads numbers, named views and the legacy VIEW_ANGLE")
    func cameraAnglesParse() throws {
        let plain = try #require(parse("0 !LPUB PLI CAMERA_ANGLES LOCAL 30 -60") as? LPubPliCameraAngles)
        #expect(plain.scope == .local)
        #expect(plain.latitude == 30)
        #expect(plain.longitude == -60)

        let legacy = try #require(parse("0 !LPUB PLI VIEW_ANGLE GLOBAL 23 -45") as? LPubPliCameraAngles)
        #expect(legacy.scope == .global)
        #expect(legacy.longitude == -45)

        let front = try #require(parse("0 !LPUB PLI CAMERA_ANGLES FRONT") as? LPubPliCameraAngles)
        #expect(front.latitude == 0)
        #expect(front.longitude == 0)

        let right = try #require(parse("0 !LPUB PLI CAMERA_ANGLES RIGHT") as? LPubPliCameraAngles)
        #expect(right.longitude == -90)

        // After HOME or LAT_LON the numbers win, and the viewpoint counts as
        // custom. Plain numbers do not.
        let custom = try #require(parse("0 !LPUB PLI CAMERA_ANGLES HOME 10.0 20.0") as? LPubPliCameraAngles)
        #expect(custom.latitude == 10)
        #expect(custom.longitude == 20)
        #expect(custom.isCustomViewpoint)
        #expect(plain.isCustomViewpoint == false)

        for line in ["0 !LPUB PLI CAMERA_ANGLES LOCAL 30 -60",
                     "0 !LPUB PLI VIEW_ANGLE GLOBAL 23 -45",
                     "0 !LPUB PLI CAMERA_ANGLES FRONT",
                     "0 !LPUB PLI CAMERA_ANGLES HOME 10.0 20.0"] {
            #expect(try written(line) == line)
        }

        try expectGenericAndVerbatim("0 !LPUB PLI CAMERA_ANGLES SIDEWAYS")
        // LPub3D takes numbers after HOME and LAT_LON only.
        try expectGenericAndVerbatim("0 !LPUB PLI CAMERA_ANGLES FRONT 10 20")
        try expectGenericAndVerbatim("0 !LPUB PLI CAMERA_ANGLES 23")
        try expectGenericAndVerbatim("0 !LPUB ASSEM CAMERA_ANGLES 23 45")
    }

    // MARK: - PART_ROTATION

    @Test("PART_ROTATION reads three angles and an optional type")
    func partRotationParses() throws {
        let abs = try #require(parse("0 !LPUB PLI PART_ROTATION LOCAL 0 90 0 ABS") as? LPubPliPartRotation)
        #expect(abs.scope == .local)
        #expect(abs.angles.y == 90)
        #expect(abs.type == .absolute)

        let rel = try #require(parse("0 !LPUB PLI PART_ROTATION GLOBAL -15.5 30 45 REL") as? LPubPliPartRotation)
        #expect(rel.angles.x == -15.5)
        #expect(rel.type == .relative)

        #expect(try #require(parse("0 !LPUB PLI PART_ROTATION 1 2 3 ADD") as? LPubPliPartRotation).type == .additive)

        // With no type the line parses, but LPub3D applies no rotation.
        let untyped = try #require(parse("0 !LPUB PLI PART_ROTATION 0 90 0") as? LPubPliPartRotation)
        #expect(untyped.type == .none)

        for line in ["0 !LPUB PLI PART_ROTATION LOCAL 0 90 0 ABS",
                     "0 !LPUB PLI PART_ROTATION GLOBAL -15.5 30 45 REL",
                     "0 !LPUB PLI PART_ROTATION 0 90 0"] {
            #expect(try written(line) == line)
        }

        try expectGenericAndVerbatim("0 !LPUB PLI PART_ROTATION 0 90")
        try expectGenericAndVerbatim("0 !LPUB PLI PART_ROTATION 0 90 0 SIDEWAYS")
        try expectGenericAndVerbatim("0 !LPUB PLI PART_ROTATION 0 90 0 ABS EXTRA")
    }

    /// The matrix is the LDraw ROTSTEP rotation that LPub3D uses, transposed
    /// for Bricksmith's row vectors.
    @Test("PART_ROTATION turns a part the way LPub3D's matrixMakeRot does")
    func partRotationMatchesLPub() throws {
        func turned(_ line: String, _ point: Point3) throws -> Point3 {
            let rotation = try #require(parse(line) as? LPubPliPartRotation)
            return V3MulPointByProjMatrix(point, rotation.rotationMatrix)
        }

        // A 90 degree turn about Y sends x to -z.
        let aboutY = try turned("0 !LPUB PLI PART_ROTATION 0 90 0 ABS", Point3(x: 1, y: 0, z: 0))
        #expect(abs(aboutY.x) < 1e-9 && abs(aboutY.y) < 1e-9 && abs(aboutY.z + 1) < 1e-9)

        // A 90 degree turn about X sends y to z.
        let aboutX = try turned("0 !LPUB PLI PART_ROTATION 90 0 0 REL", Point3(x: 0, y: 1, z: 0))
        #expect(abs(aboutX.x) < 1e-9 && abs(aboutX.y) < 1e-9 && abs(aboutX.z - 1) < 1e-9)

        // No type, no rotation.
        let untyped = try turned("0 !LPUB PLI PART_ROTATION 0 90 0", Point3(x: 1, y: 0, z: 0))
        #expect(untyped.x == 1 && untyped.z == 0)
    }

    @Test("The PLI metas we do not model stay generic and verbatim")
    func unmodeledPliMetasFallThrough() throws {
        try expectGenericAndVerbatim("0 !LPUB PLI SORT TRUE")
        try expectGenericAndVerbatim("0 !LPUB PLI INCLUDE_SUBMODELS FALSE")
        try expectGenericAndVerbatim("0 !LPUB PLI PLACEMENT TOP_LEFT PAGE INSIDE")
        try expectGenericAndVerbatim("0 !LPUB PLI INSTANCE_COUNT FONT Arial,24,-1,5,50,0,0,0,0,0")
        try expectGenericAndVerbatim("0 !LPUB BOM CONSTRAIN LOCAL WIDTH 11")
    }

    /// An argument we cannot read is someone else's syntax, so the line is
    /// kept as it is.
    @Test("A malformed CONSTRAIN falls through rather than being repaired")
    func malformedConstrainFallsThrough() throws {
        try expectGenericAndVerbatim("0 !LPUB PLI CONSTRAIN")
        try expectGenericAndVerbatim("0 !LPUB PLI CONSTRAIN LOCAL")
        try expectGenericAndVerbatim("0 !LPUB PLI CONSTRAIN WIDTH")
        try expectGenericAndVerbatim("0 !LPUB PLI CONSTRAIN WIDTH wide")
        try expectGenericAndVerbatim("0 !LPUB PLI CONSTRAIN WIDTH 2.5in")
        try expectGenericAndVerbatim("0 !LPUB PLI CONSTRAIN WIDTH -2.5")
        try expectGenericAndVerbatim("0 !LPUB PLI CONSTRAIN COLS 0")
        try expectGenericAndVerbatim("0 !LPUB PLI CONSTRAIN COLS 2.5")
        try expectGenericAndVerbatim("0 !LPUB PLI CONSTRAIN AREA 3")
        try expectGenericAndVerbatim("0 !LPUB PLI CONSTRAIN LOCAL WIDTH 2.5 EXTRA")
        try expectGenericAndVerbatim("0 !LPUB PLI CONSTRAIN SIDEWAYS 2.5")
    }

    @Test("A malformed SHOW or ignore bracket falls through")
    func malformedShowAndIgnoreFallThrough() throws {
        try expectGenericAndVerbatim("0 !LPUB PLI SHOW")
        try expectGenericAndVerbatim("0 !LPUB PLI SHOW MAYBE")
        try expectGenericAndVerbatim("0 !LPUB PLI SHOW LOCAL")
        try expectGenericAndVerbatim("0 !LPUB PLI SHOW TRUE FALSE")
        try expectGenericAndVerbatim("0 !LPUB PLI BEGIN")
        try expectGenericAndVerbatim("0 !LPUB PLI BEGIN IGN EXTRA")
        try expectGenericAndVerbatim("0 !LPUB PLI END NOW")
    }

    /// Keywords are matched exactly, like the rest of the LPub parsing.
    @Test("Keyword matching is case-sensitive")
    func keywordMatchingIsCaseSensitive() throws {
        try expectGenericAndVerbatim("0 !LPUB pli constrain width 2.5")
        try expectGenericAndVerbatim("0 !LPUB PLI CONSTRAIN local WIDTH 2.5")
    }

    /// The parser hands over the tokens already split, so a line that runs out
    /// of them early must not read past the end.
    @Test("A truncated PLI line does not crash the parser")
    func truncatedLinesDoNotCrash() throws {
        for line in ["0 !LPUB", "0 !LPUB PLI", "0 !LPUB PLI ", "0 !LPUB  PLI  CONSTRAIN"] {
            let directive = try parse(line)
            #expect(directive is LPubCommand)
        }
    }

    // MARK: - Editing the line as raw text
    //
    // The inspector sets lPubCommandString when the new text keeps the class,
    // and swaps in replacement(forText:) when it does not. The parts-list code
    // reads the parsed properties, so the two must not disagree.

    @Test("Retyping the line re-derives the properties")
    func rawTextEditReDerivesProperties() throws {
        let constrain = try #require(parse("0 !LPUB PLI CONSTRAIN LOCAL WIDTH 2.5") as? LPubPliConstrain)

        constrain.lPubCommandString = "PLI CONSTRAIN GLOBAL COLS 3"

        #expect(constrain.scope == .global)
        #expect(constrain.mode == .columns)
        #expect(constrain.columns == 3)
        #expect(constrain.write() == "0 !LPUB PLI CONSTRAIN GLOBAL COLS 3")
    }

    /// A read-only meta keeps the text as typed.
    @Test("Retyping a SHOW or ignore bracket re-derives too")
    func rawTextEditReDerivesTheOtherMetas() throws {
        let show = try #require(parse("0 !LPUB PLI SHOW TRUE") as? LPubPliShow)
        show.lPubCommandString = "PLI SHOW  LOCAL FALSE"
        #expect(show.scope == .local)
        #expect(show.isShown == false)
        #expect(show.write() == "0 !LPUB PLI SHOW  LOCAL FALSE")

        let bracket = try #require(parse("0 !LPUB PLI BEGIN IGN") as? LPubPliIgnore)
        bracket.lPubCommandString = "PLI END"
        #expect(bracket.beginsRange == false)
    }

    /// Undo only sets the old text back, so the properties come from parsing
    /// it again.
    @Test("Undoing a retyped read-only meta brings its properties back")
    func undoRestoresAReadOnlyMeta() throws {
        let line = "0 !LPUB PAGE SIZE GLOBAL 8.5 11 Letter"
        let page = try #require(parse(line) as? LPubPageSize)
        let undoManager = UndoManager()

        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        page.registerUndoActions(undoManager)
        undoManager.endUndoGrouping()

        page.lPubCommandString = "PAGE SIZE LOCAL 21 29.7"
        #expect(page.scope == .local)

        undoManager.undo()

        #expect(page.scope == .global)
        #expect(page.width == 8.5)
        #expect(page.pageName == "Letter")
        #expect(page.write() == line)
    }

    /// The read-only metas archive only their text.
    @Test("An archived meta gets its properties back from its text")
    func archivedMetaReparsesItsText() throws {
        func roundTrip<T: LPubCommand>(_ command: T, _ text: String) throws -> T {
            command.lPubCommandString = text

            let data = try NSKeyedArchiver.archivedData(withRootObject: command, requiringSecureCoding: false)
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            let decoded = try #require(unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? T)

            #expect(decoded.write() == command.write())
            return decoded
        }

        #expect(try roundTrip(LPubPliShow(), "PLI SHOW LOCAL TRUE").isShown)
        #expect(try roundTrip(LPubPliIgnore(), "PART BEGIN IGN").branch == .part)
        #expect(try roundTrip(LPubPliSubstitute(), "PLI BEGIN SUB 3001.dat 4 REL").partColorCode == 4)
        #expect(try roundTrip(LPubModelScale(), "ASSEM MODEL_SCALE 1.2").scale == 1.2)
        #expect(try roundTrip(LPubResolution(), "RESOLUTION 72.5 DPCM").unit == .dotsPerCentimeter)
        #expect(try roundTrip(LPubPageSize(), "PAGE SIZE 8.5 11 Letter").pageName == "Letter")
        #expect(try roundTrip(LPubPageOrientation(), "PAGE ORIENTATION LANDSCAPE").isLandscape)
    }

    @Test("A copied PAGE SIZE keeps its values")
    func pageSizeCopyKeepsItsValues() throws {
        let original = try #require(parse("0 !LPUB PAGE SIZE GLOBAL 8.5 11 Letter") as? LPubPageSize)
        let duplicate = try #require(original.copy() as? LPubPageSize)

        #expect(duplicate.scope == .global)
        #expect(duplicate.width == 8.5)
        #expect(duplicate.height == 11)
        #expect(duplicate.pageName == "Letter")
        #expect(duplicate.write() == "0 !LPUB PAGE SIZE GLOBAL 8.5 11 Letter")
    }

    /// The setter keeps the class, so text that no longer matches the grammar
    /// stands as typed and the properties keep their last valid values. The
    /// inspector asks replacement(forText:) first. A copy must hold both.
    @Test("A copy of a line that no longer parses keeps the text as typed")
    func copyKeepsUnparsedTextAsTyped() throws {
        let original = try #require(parse("0 !LPUB PLI CONSTRAIN LOCAL WIDTH 2.5") as? LPubPliConstrain)
        original.lPubCommandString = "PLI MODEL_SCALE 0.6"

        let copy = try #require(original.copy() as? LPubPliConstrain)

        #expect(copy.write() == original.write())
        #expect(copy.write() == "0 !LPUB PLI MODEL_SCALE 0.6")
        #expect(copy.mode == .width)
        #expect(copy.inches == 2.5)
        #expect(copy.scope == .local)
    }

    @Test("Text that no longer parses is left as typed")
    func rawTextEditThatNoLongerParsesIsLeftAlone() throws {
        let constrain = try #require(parse("0 !LPUB PLI CONSTRAIN LOCAL WIDTH 2.5") as? LPubPliConstrain)

        constrain.lPubCommandString = "PLI MODEL_SCALE 0.6"

        #expect(constrain.write() == "0 !LPUB PLI MODEL_SCALE 0.6")
        #expect(constrain.mode == .width)
        #expect(constrain.inches == 2.5)
    }

    @Test("A plain command retyped as CONSTRAIN is replaced by one")
    func plainCommandRetypedAsConstrainIsReplaced() throws {
        let replacement = try #require(LPubCommand().replacement(forText: "PLI CONSTRAIN LOCAL WIDTH 3") as? LPubPliConstrain)

        #expect(replacement.mode == .width)
        #expect(replacement.inches == 3)
        #expect(replacement.scope == .local)
        #expect(replacement.write() == "0 !LPUB PLI CONSTRAIN LOCAL WIDTH 3.0000")
    }

    @Test("A CONSTRAIN retyped into text it does not parse becomes a plain command, word for word")
    func constrainRetypedOutOfTheGrammarBecomesPlain() throws {
        let constrain = try #require(parse("0 !LPUB PLI CONSTRAIN LOCAL WIDTH 2.5") as? LPubPliConstrain)

        for text in ["PLI CONSTRAIN LOCAL WIDTH", "PLI CONSTRAIN LOCAL WIDTH 0"] {
            let replacement = try #require(constrain.replacement(forText: text), "\(text)")

            #expect(replacement.isMember(of: LPubCommand.self), "\(text)")
            #expect(replacement.write() == "0 !LPUB " + text)
        }
    }

    @Test("A CONSTRAIN retyped as another meta becomes that meta")
    func constrainRetypedAsAnotherMeta() throws {
        let constrain = try #require(parse("0 !LPUB PLI CONSTRAIN LOCAL WIDTH 2.5") as? LPubPliConstrain)

        let scale = try #require(constrain.replacement(forText: "PLI MODEL_SCALE 0.6") as? LPubModelScale)

        #expect(scale.branch == .pli)
        #expect(scale.scale == 0.6)
    }

    @Test("Text the command's own class parses needs no replacement")
    func sameClassTextNeedsNoReplacement() throws {
        let constrain = try #require(parse("0 !LPUB PLI CONSTRAIN LOCAL WIDTH 2.5") as? LPubPliConstrain)

        #expect(constrain.replacement(forText: "PLI CONSTRAIN GLOBAL COLS 3") == nil)
        #expect(LPubCommand().replacement(forText: "PLI SORT GLOBAL TRUE") == nil)
    }

    /// With no replacement, the inspector sets the text on the command itself.
    @Test("A replacement is what opening the file makes",
          arguments: ["REMOVE GROUP \"Two Words\"",
                      "PLI CAMERA_ANGLES FRONT",
                      "PLI BEGIN IGN",
                      "PLI END",
                      "RESOLUTION 150 DPI",
                      "PLI SORT TRUE",
                      "",
                      "PLI  CONSTRAIN   WIDTH 2"])
    func replacementMatchesOpeningTheFile(text: String) throws {
        let receiver = LPubCommand()
        let result = receiver.replacement(forText: text) ?? {
            receiver.lPubCommandString = text
            return receiver
        }()
        let opened = try parse("0 !LPUB " + text)

        #expect(type(of: result) == type(of: opened))
        #expect(result.write() == opened.write())
    }

    /// Opening the file drops the spaces after !LPUB. This is the one place
    /// the setter differs.
    @Test("A plain command keeps leading spaces as typed")
    func plainCommandKeepsLeadingSpaces() {
        let command = LPubCommand()

        #expect(command.replacement(forText: "  PLI SORT TRUE") == nil)

        command.lPubCommandString = "  PLI SORT TRUE"
        #expect(command.write() == "0 !LPUB   PLI SORT TRUE")
    }

    // MARK: - MODEL_SCALE

    /// The same leaf sits under three branches, and the scale means the same
    /// under each: a multiplier on life size.
    @Test("MODEL_SCALE parses under each of its branches")
    func modelScaleBranches() throws {
        let pli = try #require(parse("0 !LPUB PLI MODEL_SCALE 0.6") as? LPubModelScale)
        #expect(pli.branch == .pli)
        #expect(pli.scale == 0.6)
        #expect(pli.scope == .unspecified)

        let assem = try #require(parse("0 !LPUB ASSEM MODEL_SCALE GLOBAL  1.1500") as? LPubModelScale)
        #expect(assem.branch == .assembly)
        #expect(assem.scope == .global)
        #expect(assem.scale == 1.15)

        let bom = try #require(parse("0 !LPUB BOM MODEL_SCALE LOCAL 1.0000") as? LPubModelScale)
        #expect(bom.branch == .bom)
        #expect(bom.scope == .local)
    }

    /// LPub3D writes four decimals when it sets a scale, but we only read it,
    /// so the number stays as written.
    @Test("MODEL_SCALE keeps its text")
    func modelScaleKeepsItsText() throws {
        #expect(try written("0 !LPUB ASSEM MODEL_SCALE LOCAL  1.2") == "0 !LPUB ASSEM MODEL_SCALE LOCAL  1.2")
        #expect(try written("0 !LPUB PLI MODEL_SCALE 1") == "0 !LPUB PLI MODEL_SCALE 1")
    }

    /// A scale is a multiplier, so zero and negative values are not scales.
    @Test("A MODEL_SCALE we cannot make sense of stays generic")
    func malformedModelScaleFallsThrough() throws {
        try expectGenericAndVerbatim("0 !LPUB PLI MODEL_SCALE")
        try expectGenericAndVerbatim("0 !LPUB PLI MODEL_SCALE 0")
        try expectGenericAndVerbatim("0 !LPUB PLI MODEL_SCALE -1.5")
        try expectGenericAndVerbatim("0 !LPUB PLI MODEL_SCALE 1.5x")
        try expectGenericAndVerbatim("0 !LPUB PLI MODEL_SCALE 1.5 2.0")
        try expectGenericAndVerbatim("0 !LPUB CALLOUT MODEL_SCALE 1.5")
    }

    /// One LDU is 1/64 inch at scale 1.0, which is LPub3D's rounding of the
    /// 0.4 mm LDU. A stud is 20 LDU, so just under 8 mm on the page.
    @Test("A scale of 1.0 is life size")
    func lifeSizeConstant() throws {
        #expect(LPubModelScale.inchesPerLDU() == 1.0 / 64.0)
        #expect(abs(20 * LPubModelScale.inchesPerLDU() * 25.4 - 7.9375) < 0.0001)
    }

    // MARK: - RESOLUTION

    @Test("RESOLUTION carries a value and its unit")
    func resolutionParses() throws {
        let dpi = try #require(parse("0 !LPUB RESOLUTION GLOBAL 170 DPI") as? LPubResolution)
        #expect(dpi.scope == .global)
        #expect(dpi.dotsPerUnit == 170)
        #expect(dpi.unit == .dotsPerInch)
        #expect(dpi.inchesPerUnit == 1)

        let dpcm = try #require(parse("0 !LPUB RESOLUTION 100 DPCM") as? LPubResolution)
        #expect(dpcm.dotsPerUnit == 100)
        #expect(dpcm.unit == .dotsPerCentimeter)
        #expect(abs(dpcm.inchesPerUnit - 1 / 2.54) < 0.0001)
    }

    @Test("RESOLUTION keeps its text")
    func resolutionKeepsItsText() throws {
        #expect(try written("0 !LPUB RESOLUTION GLOBAL  150  DPI") == "0 !LPUB RESOLUTION GLOBAL  150  DPI")
        #expect(try written("0 !LPUB RESOLUTION 72.5 DPCM") == "0 !LPUB RESOLUTION 72.5 DPCM")
    }

    @Test("A RESOLUTION we cannot make sense of stays generic")
    func malformedResolutionFallsThrough() throws {
        try expectGenericAndVerbatim("0 !LPUB RESOLUTION 150")
        try expectGenericAndVerbatim("0 !LPUB RESOLUTION DPI")
        try expectGenericAndVerbatim("0 !LPUB RESOLUTION 150 PIXELS")
        try expectGenericAndVerbatim("0 !LPUB RESOLUTION -150 DPI")
    }

    // MARK: - PAGE

    @Test("PAGE SIZE carries two measurements and an optional name")
    func pageSizeParses() throws {
        let measured = try #require(parse("0 !LPUB PAGE SIZE GLOBAL 12.0480 8.0000") as? LPubPageSize)
        #expect(measured.scope == .global)
        #expect(measured.width == 12.048)
        #expect(measured.height == 8.0)
        #expect(measured.pageName == nil)

        let named = try #require(parse("0 !LPUB PAGE SIZE 8.5 11 Letter") as? LPubPageSize)
        #expect(named.pageName == "Letter")
        #expect(try written("0 !LPUB PAGE SIZE 8.5 11 Letter") == "0 !LPUB PAGE SIZE 8.5 11 Letter")
    }

    /// Reading a named page would need our own table of page sizes, which
    /// could disagree with LPub3D's.
    @Test("A page named rather than measured stays generic")
    func namedPageFallsThrough() throws {
        try expectGenericAndVerbatim("0 !LPUB PAGE SIZE A4")
        try expectGenericAndVerbatim("0 !LPUB PAGE SIZE GLOBAL Letter")
        try expectGenericAndVerbatim("0 !LPUB PAGE SIZE 8.5")
        try expectGenericAndVerbatim("0 !LPUB PAGE SIZE 0 11")
    }

    @Test("PAGE ORIENTATION reads both ways up")
    func pageOrientationParses() throws {
        let landscape = try #require(parse("0 !LPUB PAGE ORIENTATION GLOBAL LANDSCAPE") as? LPubPageOrientation)
        #expect(landscape.isLandscape == true)
        #expect(landscape.scope == .global)

        let portrait = try #require(parse("0 !LPUB PAGE ORIENTATION PORTRAIT") as? LPubPageOrientation)
        #expect(portrait.isLandscape == false)
    }

    /// PAGE has about a dozen other leaves, and we model two of them.
    @Test("The other PAGE metas stay generic")
    func otherPageMetasFallThrough() throws {
        try expectGenericAndVerbatim("0 !LPUB PAGE MARGINS GLOBAL 0.3000 0.1500")
        try expectGenericAndVerbatim("0 !LPUB PAGE DISPLAY_PAGE_NUMBER GLOBAL TRUE")
        try expectGenericAndVerbatim("0 !LPUB PAGE ORIENTATION SIDEWAYS")
    }

    // MARK: - Raw text edits

    /// A run of spaces counts as one delimiter, so the line still parses.
    /// CONSTRAIN is then written back in its canonical form.
    @Test("Extra spaces between tokens still parse")
    func extraSpacesStillParse() throws {
        let constrain = try #require(parse("0 !LPUB PLI   CONSTRAIN   LOCAL   WIDTH   2.5") as? LPubPliConstrain)

        #expect(constrain.mode == .width)
        #expect(constrain.write() == "0 !LPUB PLI CONSTRAIN LOCAL WIDTH 2.5000")
    }

    /// LPub3D rewrites a line only when its user changes the setting.
    @Test("A meta Bricksmith only reads keeps its text as written",
          arguments: [("0 !LPUB PLI SHOW LOCAL FALSE", LPubPliShow.self),
                      ("0 !LPUB PART END", LPubPliIgnore.self),
                      ("0 !LPUB PLI BEGIN SUB 3001.dat 04 REL", LPubPliSubstitute.self),
                      ("0 !LPUB PLI MODEL_SCALE 1", LPubModelScale.self),
                      ("0 !LPUB ASSEM MODEL_SCALE GLOBAL  1.1500", LPubModelScale.self),
                      ("0 !LPUB RESOLUTION 72.5 DPCM", LPubResolution.self),
                      ("0 !LPUB PAGE SIZE 8.5 11 Letter", LPubPageSize.self),
                      ("0 !LPUB PAGE ORIENTATION GLOBAL LANDSCAPE", LPubPageOrientation.self)]
          as [(String, LPubCommand.Type)])
    func readOnlyMetaKeepsItsText(line: String, type: LPubCommand.Type) throws {
        let directive = try parse(line)

        #expect(Swift.type(of: directive) == type)
        #expect(directive.write() == line)
    }
}
