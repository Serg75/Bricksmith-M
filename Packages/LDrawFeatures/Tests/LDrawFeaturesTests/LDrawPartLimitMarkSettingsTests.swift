//
//  LDrawPartLimitMarkSettingsTests.swift
//  LDrawFeaturesTests
//
//  Tests for reading the parts limit's mark settings.
//
//  Created by Sergey Slobodenyuk on 2026-11-03.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures

@Suite("Parts limit mark settings")
struct LDrawPartLimitMarkSettingsTests {

    private func defaults() -> UserDefaults {
        let name = "LDrawPartLimitMarkSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func color(_ key: String, in defaults: UserDefaults) -> [Float] {
        var rgb: [Float] = [0, 0, 0]
        LDrawPreferences.getPartsLimitMarkColor(&rgb, forKey: key, in: defaults)
        return rgb
    }

    @Test("A style the settings do not offer reads as stripes")
    func style() {
        let defaults = defaults()

        defaults.set(LDrawRenderMarkStyle.outline.rawValue, forKey: PARTS_LIMIT_MARK_STYLE_KEY)
        #expect(LDrawPreferences.partsLimitMarkStyle(in: defaults) == .outline)
        defaults.set(LDrawRenderMarkStyle.stripesBack.rawValue, forKey: PARTS_LIMIT_MARK_STYLE_KEY)
        #expect(LDrawPreferences.partsLimitMarkStyle(in: defaults) == .stripes)
    }

    @Test("A stored color is three numbers; anything else reads as the factory color")
    func colors() {
        let defaults = defaults()

        defaults.set([0.0, 0.5, 1.0], forKey: PARTS_LIMIT_NOT_AVAILABLE_COLOR_KEY)
        #expect(color(PARTS_LIMIT_NOT_AVAILABLE_COLOR_KEY, in: defaults) == [0.0, 0.5, 1.0])

        defaults.set(["red"], forKey: PARTS_LIMIT_TOO_MANY_COLOR_KEY)
        #expect(color(PARTS_LIMIT_TOO_MANY_COLOR_KEY, in: defaults) == [1.0, 0.55, 0.0])

        defaults.set([1, 2], forKey: PARTS_LIMIT_NOT_AVAILABLE_COLOR_KEY)
        #expect(color(PARTS_LIMIT_NOT_AVAILABLE_COLOR_KEY, in: defaults) == [0.9, 0.1, 0.1])
    }
}
