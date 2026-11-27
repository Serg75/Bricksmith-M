//
//  LDrawObserverSetTests.swift
//  LDrawCoreTests
//
//  Tests for the observers a directive tells when its cache goes stale or it
//  is freed.
//
//  Created by Sergey Slobodenyuk on 2026-11-27.
//

import Testing
import Foundation
import LDrawCore

/// Counts what it is told. When told the cache is stale, it can stop another
/// observer from observing.
final class CountingObserver: NSObject, LDrawObserver {
    var invalidated = 0
    var goodbyes = 0
    weak var removes: CountingObserver?

    func observableSaysGoodbyeCruelWorld(_ doomedObservable: LDrawObservable) {
        goodbyes += 1
    }

    func statusInvalidated(_ flags: CacheFlagsT, who observable: LDrawObservable) {
        invalidated += 1
        if let removes {
            observable.remove(removes)
        }
    }

    func receive(_ msg: LDrawObserverMessage, who observable: LDrawObservable) {}
}

@Suite("The observers of a directive")
struct LDrawObserverSetTests {

    @Test("Each observer is told once, however often it was added")
    func toldOnce() {
        let first = CountingObserver()
        let second = CountingObserver()
        let directive = LDrawDirective()

        directive.add(first)
        directive.add(second)
        directive.add(first)
        directive.invalCache(CacheFlagsT(rawValue: 1))

        #expect(first.invalidated == 1)
        #expect(second.invalidated == 1)
    }

    @Test("An observer that was removed is not told")
    func removedNotTold() {
        let first = CountingObserver()
        let second = CountingObserver()
        let directive = LDrawDirective()

        directive.add(first)
        directive.add(second)
        directive.remove(first)
        directive.invalCache(CacheFlagsT(rawValue: 1))

        #expect(first.invalidated == 0)
        #expect(second.invalidated == 1)
    }

    @Test("An observer removed by another while they are told is skipped")
    func removedWhileTold() {
        let first = CountingObserver()
        let second = CountingObserver()
        let directive = LDrawDirective()

        first.removes = second
        second.removes = first
        directive.add(first)
        directive.add(second)
        directive.invalCache(CacheFlagsT(rawValue: 1))

        #expect(first.invalidated + second.invalidated == 1)
    }

    @Test("Every observer is told when the directive is freed")
    func toldWhenFreed() {
        let first = CountingObserver()
        let second = CountingObserver()

        autoreleasepool {
            let directive = LDrawDirective()

            directive.add(first)
            directive.add(second)
        }
        #expect(first.goodbyes == 1)
        #expect(second.goodbyes == 1)
    }
}
