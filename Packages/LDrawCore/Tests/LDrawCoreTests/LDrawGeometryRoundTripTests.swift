//
//  LDrawGeometryRoundTripTests.swift
//  UnitTests
//
//  Parse -> write round-trip fidelity for the geometry directives. Opening a
//  file and saving it without editing anything must not alter its coordinates.
//
//  Created by Sergey Slobodenyuk on 2026-09-01.
//

import Testing
import LDrawCore

@Suite("Geometry parse/write round-trip")
struct LDrawGeometryRoundTripTests {

    // MARK: - Helpers

    private static let firstLine = NSRange(location: 0, length: 1)

    private static func writtenLine(_ source: String) -> String? {
        LDrawLine(lines: [source], in: firstLine, parentGroup: nil)?.write()
    }

    private static func writtenTriangle(_ source: String) -> String? {
        LDrawTriangle(lines: [source], in: firstLine, parentGroup: nil)?.write()
    }

    private static func writtenQuadrilateral(_ source: String) -> String? {
        LDrawQuadrilateral(lines: [source], in: firstLine, parentGroup: nil)?.write()
    }

    // MARK: - Coordinates a float can hold

    /// Integer coordinates are exactly representable in float32, so these have
    /// always round-tripped. They guard the parse and write changes against
    /// regression.
    @Test("Integer coordinates round-trip unchanged")
    func integerCoordinatesRoundTrip() {
        let line = "2 24 0 0 0 20 0 0"
        #expect(Self.writtenLine(line) == line)

        let triangle = "3 16 1024 0 0 20 0 0 0 20 0"
        #expect(Self.writtenTriangle(triangle) == triangle)

        // Quad vertices must wind around the perimeter -- a bow-tie ordering
        // gets legitimately reordered on parse and would fail this comparison
        // for reasons that have nothing to do with precision.
        let quad = "4 16 0 0 0 20 0 0 20 0 20 0 0 20"
        #expect(Self.writtenQuadrilateral(quad) == quad)
    }

    /// Fractions that happen to be exact binary values (halves, quarters,
    /// eighths) survive float32 too.
    @Test("Binary-exact fractions round-trip unchanged")
    func binaryExactFractionsRoundTrip() {
        let line = "2 24 0.5 -0.25 1024.125 20 0 0"
        #expect(Self.writtenLine(line) == line)
    }

    // MARK: - Coordinates a float cannot hold

    /// The real-world case: a decimal coordinate large enough that float32
    /// spacing (~1.2e-4 at 1024) exceeds the six decimal places `%f` prints.
    /// This is the `1024.150024` symptom, and the reason the geometry types are
    /// double precision -- with float32 storage these two lines could not
    /// survive being read and written back.
    @Test("Decimal coordinates round-trip unchanged")
    func decimalCoordinatesRoundTrip() {
        let triangle = "3 16 1024.15 0 0 20 0 0 0 20 0"
        let quad = "4 16 1024.15 0 -820.35 1044.15 0 -820.35 1044.15 0 -800.35 1024.15 0 -800.35"

        #expect(Self.writtenTriangle(triangle) == triangle)
        #expect(Self.writtenQuadrilateral(quad) == quad)
    }

    /// Splits the check above in half, so a future regression points at the
    /// guilty side. This covers the *parse* end specifically: the coordinate as
    /// stored on the directive, before any formatting is involved.
    @Test("Parsed coordinates match the text they came from")
    func parsedCoordinateMatchesSourceText() throws {
        let triangle = try #require(LDrawTriangle(lines: ["3 16 1024.15 0 0 20 0 0 0 20 0"],
                                                  in: Self.firstLine,
                                                  parentGroup: nil))

        #expect(Double(triangle.vertex1().x) == 1024.15)
    }

    // MARK: - Part transforms

    /// A part keeps its own copy of the transform, so widening Point3/Matrix4
    /// alone would not have been enough -- LDrawPart's storage had to widen too
    /// or -write would narrow the position back to float on the way out. This
    /// is the drift users actually see in the inspector.
    @Test("A part's position survives being written out")
    func partPositionSurvivesWrite() {
        let part = LDrawPart()
        part.setDisplayName("3001.dat", parse: false, in: nil)

        var transform = IdentityMatrix4
        transform.element.3.0 = 1024.15
        transform.element.3.1 = -820.35
        transform.element.3.2 = 2048.05
        part.setTransformationMatrix(&transform)

        #expect(part.write().contains("1024.15 -820.35 2048.05"))
    }
}
