//
//  StepSettingsTrait.swift
//  LDrawTestSupport
//
//  A trait for the suites that change or read the LDrawStepPartList settings.
//
//  Created by Sergey Slobodenyuk on 2026-10-15.
//

import Testing

/// Lets one holder in at a time. A waiter does not block a thread.
private actor Gate {

    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        if isHeld {
            await withCheckedContinuation { waiters.append($0) }
        }
        else {
            isHeld = true
        }
    }

    /// Hands the gate to the next waiter, who then holds it.
    func leave() {
        if waiters.isEmpty {
            isHeld = false
        }
        else {
            waiters.removeFirst().resume()
        }
    }
}

/// One gate for the whole test process. The test targets share this target, so
/// their suites wait for each other too.
private let settingsGate = Gate()

/// Runs a suite while no other suite with this trait runs. The parts list's
/// settings are process-wide, and every test target runs in one process.
/// Give it only to a top suite: a suite inside another one with it would wait
/// for itself.
public struct StepSettingsTrait: SuiteTrait, TestTrait, TestScoping {

    public func provideScope(for test: Test,
                             testCase: Test.Case?,
                             performing function: @Sendable () async throws -> Void) async throws {
        await settingsGate.enter()

        do {
            try await function()
        }
        catch {
            await settingsGate.leave()
            throw error
        }

        await settingsGate.leave()
    }
}

extension Trait where Self == StepSettingsTrait {

    /// Runs the suite apart from every other suite that has this trait.
    public static var usesStepSettings: Self { Self() }
}
