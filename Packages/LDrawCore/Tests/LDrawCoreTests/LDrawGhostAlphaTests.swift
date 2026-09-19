//
//  LDrawGhostAlphaTests.swift
//  UnitTests
//
//  Covers how faint a ghost draws -- one host-injected value shared by both
//  kinds of ghost, a removed MLCAD group and a step already built.
//
//  What matters here is the clamp. The renderers scale a ghost's alpha by this
//  value, so 0 would leave nothing on screen at all and 1 would draw a solid
//  part through the ghost pass; neither is something a stored preference, a
//  typed-in number or a hand-edited defaults plist should be able to produce.
//
//  Created by Sergey Slobodenyuk on 2026-09-08.
//

import Testing
import Foundation
import LDrawCore

@Suite("How faint a ghost draws", .serialized)
final class LDrawGhostAlphaTests {

    /// The value is a process-wide C static, so put the documented default back
    /// afterwards -- Swift Testing releases the suite instance after each test,
    /// so this runs even when one fails partway through.
    deinit {
        LDrawModel.setGhostAlpha(LDRAW_DEFAULT_GHOST_ALPHA)
    }

    // MARK: - The default

    @Test("The default is translucent rather than absent or solid")
    func theDefaultIsTranslucent() {
        #expect(LDRAW_DEFAULT_GHOST_ALPHA > 0)
        #expect(LDRAW_DEFAULT_GHOST_ALPHA < 1)
        #expect(LDrawModel.ghostAlpha() == LDRAW_DEFAULT_GHOST_ALPHA)
    }

    @Test("The allowed band is inside 0 and 1, and the default is in it")
    func theBandIsSane() {
        #expect(LDRAW_MIN_GHOST_ALPHA > 0)
        #expect(LDRAW_MAX_GHOST_ALPHA < 1)
        #expect(LDRAW_MIN_GHOST_ALPHA < LDRAW_MAX_GHOST_ALPHA)
        #expect(LDRAW_DEFAULT_GHOST_ALPHA >= LDRAW_MIN_GHOST_ALPHA)
        #expect(LDRAW_DEFAULT_GHOST_ALPHA <= LDRAW_MAX_GHOST_ALPHA)
    }

    // MARK: - Setting it

    @Test("A value inside the band is taken as given")
    func aValueInsideTheBandIsKept() {
        LDrawModel.setGhostAlpha(0.5)

        #expect(LDrawModel.ghostAlpha() == 0.5)
    }

    @Test("A ghost can never be dialed all the way out of sight")
    func fullyTransparentIsClamped() {
        LDrawModel.setGhostAlpha(0)

        #expect(LDrawModel.ghostAlpha() == LDRAW_MIN_GHOST_ALPHA)
    }

    @Test("A ghost can never be dialed solid")
    func fullyOpaqueIsClamped() {
        LDrawModel.setGhostAlpha(1)

        #expect(LDrawModel.ghostAlpha() == LDRAW_MAX_GHOST_ALPHA)
    }

    @Test("Nonsense from a hand-edited preference is clamped, not honored")
    func outOfRangeIsClamped() {
        LDrawModel.setGhostAlpha(-5)
        #expect(LDrawModel.ghostAlpha() == LDRAW_MIN_GHOST_ALPHA)

        LDrawModel.setGhostAlpha(42)
        #expect(LDrawModel.ghostAlpha() == LDRAW_MAX_GHOST_ALPHA)
    }

    @Test("Setting it notifies only when the value actually changes")
    func settingItPostsANotificationOnlyOnChange() {
        LDrawModel.setGhostAlpha(0.5)

        var postCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(LDrawGhostAlphaDidChangeNotification),
            object: nil,
            queue: nil) { _ in postCount += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        LDrawModel.setGhostAlpha(0.5)   // already 0.5
        #expect(postCount == 0)

        LDrawModel.setGhostAlpha(0.4)
        #expect(postCount == 1)

        // Two different requests that clamp to the same value are one change,
        // so a slider pinned at the end of its travel does not spam redraws.
        LDrawModel.setGhostAlpha(0)
        #expect(postCount == 2)

        LDrawModel.setGhostAlpha(-1)
        #expect(postCount == 2)
    }

    // MARK: - The stored preference

    @Test("The stored percent transparent converts to the alpha the renderers want")
    func percentConvertsToAlpha() {
        // Solid at one end, invisible at the other; the conversion itself does
        // not clamp -- that is the setter's job.
        #expect(LDrawGhostAlphaForTransparencyPercent(0) == 1)
        #expect(LDrawGhostAlphaForTransparencyPercent(100) == 0)

        // The seeded default, 60% transparent, is the documented default alpha.
        #expect(abs(LDrawGhostAlphaForTransparencyPercent(60) - LDRAW_DEFAULT_GHOST_ALPHA) < 0.0001)
    }
}
