//
//  LDrawUtilitiesOutputStringTests.swift
//  UnitTests
//
//  Tests for +[LDrawUtilities outputStringForFloat:], the formatter every
//  directive uses to turn a coordinate into LDraw file text.
//
//  Created by Sergey Slobodenyuk on 2026-09-01.
//

import Testing
import LDrawCore

@Suite("Numeric output for LDraw files")
struct LDrawUtilitiesOutputStringTests {

    // MARK: - Precision

    /// The formatter takes a double so that a caller holding a double-precision
    /// coordinate can write it out faithfully.
    ///
    /// Every one of these values is unrepresentable in float32, so when the
    /// parameter was a `float` each of them picked up error at the sixth
    /// decimal place -- which is exactly where `%f` prints. 1024.15 came out as
    /// "1024.150024", 2048.05 as "2048.050049", and so on.
    @Test("Double-precision coordinates survive formatting", arguments: [
        (1024.15, "1024.15"),
        (2048.05, "2048.05"),
        (-820.35, "-820.35"),
        (0.1, "0.1"),
        (-0.7, "-0.7"),
    ])
    func preservesDoublePrecision(value: Double, expected: String) {
        #expect(LDrawUtilities.outputString(forFloat: value) == expected)
    }

    /// A value a hair under an integer must not print as the integer minus a
    /// smear of nines. This is the `479.999878` symptom, expressed at the
    /// formatter level.
    @Test("Values just below an integer collapse onto it")
    func collapsesOntoIntegers() {
        #expect(LDrawUtilities.outputString(forFloat: 479.99999999999994) == "480")
        #expect(LDrawUtilities.outputString(forFloat: 1024.0000000000001) == "1024")
    }

    // MARK: - Trailing zero trimming

    @Test("Trailing zeroes and bare decimal points are trimmed", arguments: [
        (480.0, "480"),
        (0.0, "0"),
        (20.0, "20"),
        (0.5, "0.5"),
        (-0.25, "-0.25"),
        (-1.0, "-1"),
    ])
    func trimsTrailingZeroes(value: Double, expected: String) {
        #expect(LDrawUtilities.outputString(forFloat: value) == expected)
    }

    /// The format carries six decimal places; anything finer rounds away.
    /// Documenting the resolution matters because it is the bar the storage
    /// type has to clear -- float32 error at coordinate 1024 is ~1.2e-4, which
    /// lands *above* this threshold and is therefore visible in saved files.
    @Test("Magnitudes below the format's resolution round to zero")
    func roundsAwayNoiseBelowSixDecimals() {
        #expect(LDrawUtilities.outputString(forFloat: 1e-8) == "0")
        #expect(LDrawUtilities.outputString(forFloat: 0.000002) == "0.000002")
    }

    // MARK: - Large magnitudes

    /// Regression test for a silent truncation bug: the formatter used a
    /// 16-byte stack buffer, so any value needing more characters than that was
    /// cut short and *then* had its trailing zeroes trimmed -- turning 1e20
    /// into "1". Nothing in a real model is this big, but the failure mode was
    /// silent corruption of file output, and widening the parameter to double
    /// widened the range of values that can reach it.
    @Test("Large magnitudes are not truncated into a wrong number")
    func doesNotMangleLargeMagnitudes() {
        #expect(LDrawUtilities.outputString(forFloat: 1e20) == "100000000000000000000")
        #expect(LDrawUtilities.outputString(forFloat: 123456789.0) == "123456789")
    }

    /// Beyond what any buffer can hold the formatter gives up on trimming, but
    /// it must still emit a number that reads back as the same value rather
    /// than a mangled one.
    @Test("Absurd magnitudes still round-trip through the text")
    func pathologicalMagnitudesRemainParseable() {
        let written = LDrawUtilities.outputString(forFloat: 1e300)
        #expect(Double(written) == 1e300)
    }
}
