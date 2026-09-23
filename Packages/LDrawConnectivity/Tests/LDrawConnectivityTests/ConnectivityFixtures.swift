//
//  ConnectivityFixtures.swift
//  LDrawConnectivityTests
//
//  Loads the fixture LDraw and shadow libraries through their own paths,
//  leaving the shared paths alone.
//
//  Created by Sergey Slobodenyuk on 2026-09-19.
//

import Foundation
import LDrawCore
import LDrawConnectivity

enum ConnectivityFixtures {

    static let root = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    static let ldraw = root.appendingPathComponent("ldraw")
    static let shadow = root.appendingPathComponent("shadow")

    /// New paths pointed at the fixture. The shared paths are not changed,
    /// because the rest of the process uses them.
    static func fixturePaths() -> LDrawPaths {
        let paths = LDrawPaths()

        paths.setPreferredLDrawPath(ldraw.path)

        return paths
    }

    /// Without the shadow library, so only studs from stud primitives are found.
    static let primitivesOnly = LDrawConnectorLibrary(paths: fixturePaths(), shadowLibraryPath: nil)

    /// With the shadow library, as the app reads it.
    static let withShadow = LDrawConnectorLibrary(paths: fixturePaths(), shadowLibraryPath: shadow.path)

    static func connectorSet(_ partName: String) -> LDrawConnectorSet? {
        primitivesOnly.connectorSet(forPartNamed: partName)
    }

    static func shadowConnectorSet(_ partName: String) -> LDrawConnectorSet? {
        withShadow.connectorSet(forPartNamed: partName)
    }
}


/// A connector reduced to what the tests compare, rounded so that -0.0 and
/// float noise do not matter.
struct ConnectorPoint: Hashable, CustomStringConvertible {
    let x, y, z: Double
    let axisX, axisY, axisZ: Double

    init(_ x: Double, _ y: Double, _ z: Double, axis: (Double, Double, Double)) {
        func round3(_ value: Double) -> Double {
            let rounded = (value * 1000).rounded() / 1000
            return rounded == 0 ? 0 : rounded
        }
        self.x = round3(x)
        self.y = round3(y)
        self.z = round3(z)
        axisX = round3(axis.0)
        axisY = round3(axis.1)
        axisZ = round3(axis.2)
    }

    init(_ connector: LDrawConnector) {
        self.init(connector.position.x, connector.position.y, connector.position.z,
                  axis: (connector.axis.x, connector.axis.y, connector.axis.z))
    }

    var description: String {
        "(\(x), \(y), \(z)) axis (\(axisX), \(axisY), \(axisZ))"
    }
}


extension LDrawConnectorSet {
    var connectors: [LDrawConnector] {
        (0..<connectorCount).map { connector(at: $0) }
    }
}
