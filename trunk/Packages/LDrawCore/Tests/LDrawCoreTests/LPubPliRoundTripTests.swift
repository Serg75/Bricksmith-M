//
//  LPubPliRoundTripTests.swift
//  UnitTests
//
//  Opening and saving a file written by LPub3D must not change its metas.
//  CONSTRAIN is written back in LPub3D's own spelling, and the other metas keep
//  their text as it was, so a file already in that form comes out unchanged.
//
//  The fixture uses type-2 lines in place of parts. Parsing a type-1 line loads
//  the referenced file through LDrawPartLibrary, which needs a renderer the
//  UnitTests target does not have. The geometry itself does not matter here.
//
//  Created by Sergey Slobodenyuk on 2026-09-09.
//

import Testing
import Foundation
import LDrawCore

@Suite("LPub PLI metas survive open/save")
struct LPubPliRoundTripTests {

    /// Real LPub3D PLI metas: the ones we parse, in every scope, and a few
    /// that we do not parse.
    private static let fixture = """
        0 Parts List Fixture
        0 Name: main.ldr
        0 Author: Bricksmith
        0 !LPUB PLI CONSTRAIN GLOBAL AREA
        0 !LPUB PLI SHOW GLOBAL TRUE
        0 !LPUB PLI MODEL_SCALE GLOBAL 1.0000
        0 !LPUB PLI VIEW_ANGLE GLOBAL 23 -45
        0 !LPUB PLI INCLUDE_SUBMODELS GLOBAL FALSE
        0 !LPUB PLI SORT GLOBAL TRUE
        0 !LPUB PLI MARGINS GLOBAL 0.05 0.03
        0 !LPUB PLI CONSTRAIN LOCAL WIDTH 3.2400
        2 24 0 0 0 20 0 0
        2 24 20 0 0 20 20 0
        0 STEP
        0 !LPUB PLI CONSTRAIN LOCAL COLS 2
        0 !LPUB PLI BEGIN IGN
        2 24 0 0 0 0 20 0
        0 !LPUB PLI END
        2 24 0 20 0 20 20 0
        0 STEP
        0 !LPUB PLI SHOW LOCAL FALSE
        0 !LPUB PLI BEGIN SUB 3070b.dat 4
        2 24 0 0 0 0 0 20
        0 !LPUB PLI END
        0 STEP
        """

    /// Splits on any newline. The file is written with CRLF, and Swift reads a
    /// CRLF pair as one character, so a split on "\n" would match nothing.
    private static func lines(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map(String.init)
    }

    private static func lpubLines(in text: String) -> [String] {
        lines(in: text).filter { $0.hasPrefix("0 !LPUB") }
    }

    @Test("Every PLI meta comes back out exactly as it went in")
    func pliMetasRoundTrip() throws {
        let file = try #require(LDrawFile.parse(fromFileContents: Self.fixture))

        let output = file.write()

        #expect(Self.lpubLines(in: output) == Self.lpubLines(in: Self.fixture))
    }

    /// Compared line by line, because the writer changes the line endings and
    /// that is not what this test checks.
    @Test("The whole file comes back unchanged")
    func wholeFileRoundTrips() throws {
        let file = try #require(LDrawFile.parse(fromFileContents: Self.fixture))

        let output = file.write()

        #expect(Self.lines(in: output) == Self.lines(in: Self.fixture))
    }

    @Test("The metas we model become their own directives, the rest stay generic")
    func modeledMetasGetTheirOwnClass() throws {
        let file = try #require(LDrawFile.parse(fromFileContents: Self.fixture))
        let model = try #require(file.submodels().first as? LDrawModel)

        var constrains = 0
        var shows = 0
        var brackets = 0
        var scales = 0
        var substitutes = 0
        var angles = 0
        var generics = 0

        for case let step as LDrawStep in model.steps() {
            for case let directive as LDrawDirective in step.subdirectives() {
                switch directive {
                    case is LPubPliConstrain:	constrains += 1
                    case is LPubPliShow:		shows += 1
                    case is LPubPliIgnore:		brackets += 1
                    case is LPubModelScale:		scales += 1
                    case is LPubPliSubstitute:	substitutes += 1
                    case is LPubPliCameraAngles:	angles += 1
                    case let command as LPubCommand where command.isMember(of: LPubCommand.self):
                                                generics += 1
                    default:					break
                }
            }
        }

        // The header metas land in the model's first step with the rest.
        #expect(constrains == 3)
        #expect(shows == 2)
        // BEGIN IGN, its END, and the END that closes the SUB range. An END on
        // its own reads as an IGN terminator.
        #expect(brackets == 3)
        #expect(scales == 1)
        #expect(substitutes == 1)
        #expect(angles == 1)
        // INCLUDE_SUBMODELS, SORT, MARGINS.
        #expect(generics == 3)
    }
}
