//
//  LDrawPartLimitPresentationTests.swift
//  LDrawFeaturesTests
//
//  Tests for how parts limit problems are shown, and the nearest color a
//  part is made in.
//
//  Created by Sergey Slobodenyuk on 2026-10-28.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures

@Suite("Parts limit presentation")
struct LDrawPartLimitPresentationTests {

    private func color(_ code: Int32, _ red: Float, _ green: Float, _ blue: Float, alpha: Float = 1) -> LDrawColor {
        let color = LDrawColor()
        color.setColorCode(LDrawColorT(rawValue: code)!)
        var rgba: [Float] = [red, green, blue, alpha]
        color.setColorRGBA(&rgba)
        return color
    }

    @Test("Each problem has its badge and color; an allowed part has none")
    func badges() {
        #expect(LDrawPartLimitPresentation.badgeSymbolName(for: .notAvailable) == "nosign")
        #expect(LDrawPartLimitPresentation.badgeSymbolName(for: .notInColor) == "exclamationmark.circle.fill")
        #expect(LDrawPartLimitPresentation.badgeSymbolName(for: .tooMany) == "plus.circle.fill")
        #expect(LDrawPartLimitPresentation.badgeSymbolName(for: .noData) == "questionmark.circle")
        #expect(LDrawPartLimitPresentation.badgeSymbolName(for: .allowed) == nil)

        #expect(LDrawPartLimitPresentation.badgeTint(for: .notInColor) == .notAvailable)
        #expect(LDrawPartLimitPresentation.badgeTint(for: .tooMany) == .tooMany)
        #expect(LDrawPartLimitPresentation.badgeTint(for: .noData) == .gray)
        #expect(LDrawPartLimitPresentation.badgeTint(for: .allowed) == .none)
    }

    @Test("The nearest color goes by red, green and blue, not alpha; none without choices")
    func nearestColor() {
        let sandBlue = color(379, 0.42, 0.50, 0.63)
        let blue = color(1, 0.0, 0.33, 0.75)
        let gray = color(71, 0.63, 0.65, 0.65)
        let clearGray = color(40, 0.40, 0.48, 0.60, alpha: 0.5)

        #expect(LDrawPartLimitPresentation.nearestColor(to: sandBlue, among: [blue, gray])?.colorCode().rawValue == 71)
        #expect(LDrawPartLimitPresentation.nearestColor(to: sandBlue, among: [blue, clearGray])?.colorCode().rawValue
                == 40)
        #expect(LDrawPartLimitPresentation.nearestColor(to: blue, among: [gray, blue])?.colorCode().rawValue == 1)
        #expect(LDrawPartLimitPresentation.nearestColor(to: sandBlue, among: []) == nil)
    }
}
