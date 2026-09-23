//
//  SnapPerformanceTests.swift
//  LDrawConnectivityTests
//
//  Timing of the index and the solver in a model of 10,000 parts. Times are
//  always printed. The time limits are checked only when asked, because a
//  busy machine can miss them:
//
//      LDRAW_TIMING_TESTS=1 swift test --filter SnapPerformance
//
//  Created by Sergey Slobodenyuk on 2026-09-20.
//

import Testing
import Foundation
import LDrawCore
import LDrawConnectivity

@Suite("Answering fast enough to drag with", .timeLimit(.minutes(1)))
struct SnapPerformanceTests {

    /// Whether the time limits are checked, or only printed.
    static let budgetsAreKept = (ProcessInfo.processInfo.environment["LDRAW_TIMING_TESTS"] != nil)

    /// The Y of the top of the wall.
    private static let topOfWall = -24.0 * 100

    /// A wall of 10,000 bricks in rows of 100.
    private func largeModel() throws -> (index: LDrawConnectorIndex, seconds: Double) {
        let index = LDrawConnectorIndex()
        var bricks: [(UInt32, Data)] = []

        for owner in 0..<10_000 {
            let x = Double(owner % 100) * 80
            let y = Double(owner / 100) * -24
            bricks.append((UInt32(owner), try SnapScene.connectors("3001.dat", at: (x, y, 0),
                                                                   owner: UInt32(owner))))
        }

        let start = Date()

        for (owner, connectors) in bricks {
            index.setConnectors(connectors, forOwner: owner)
        }
        return (index, -start.timeIntervalSinceNow)
    }

    @Test("A model of 10,000 parts goes into the index in a few seconds")
    func indexBuild() throws {
        let (index, seconds) = try largeModel()

        #expect(index.connectorCount == 160_000)        // 16 connectors a brick
        print("index build: \(String(format: "%.2f", seconds)) s for \(index.connectorCount) connectors")

        if Self.budgetsAreKept {
            #expect(seconds < 10.0)
        }
    }

    @Test("A thousand drag steps each answer in well under a frame")
    func dragQueries() throws {
        let (index, _) = try largeModel()
        let solver = LDrawSnapSolver(connectorIndex: index)
        let steps = 1_000

        solver.pointsPerUnit = 1

        // Drag a brick along the top of the wall, one step per frame.
        let path = try (0..<steps).map { step in
            try SnapScene.connectors("3001.dat", at: (Double(step) * 0.08, Self.topOfWall, 0),
                                     owner: 99_999)
        }

        var snapped = 0
        let start = Date()

        for moving in path {
            if solver.solution(forConnectors: moving, dragDirection: V3Make(1, 0, 0)).snapped {
                snapped += 1
            }
        }

        let each = -start.timeIntervalSinceNow / Double(steps) * 1000

        print("drag step: \(String(format: "%.3f", each)) ms each, over \(steps) steps")
        #expect(snapped == steps)                       // the whole path is over the wall

        if Self.budgetsAreKept {
            #expect(each < 2.0)
        }
    }
}
