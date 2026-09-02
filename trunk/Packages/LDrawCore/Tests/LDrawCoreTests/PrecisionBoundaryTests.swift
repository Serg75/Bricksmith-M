//
//  PrecisionBoundaryTests.swift
//  UnitTests
//
//  Guards the places where float-only APIs meet double-precision geometry.
//  Getting these wrong is silent: C passes a double* to a float* parameter with
//  only a warning, so the callee reads garbage and nothing crashes. That is how
//  3D selection broke after the geometry types were widened.
//
//  Created by Sergey Slobodenyuk on 2026-09-02.
//

import Testing
import LDrawCore

@Suite("Float boundaries in double-precision geometry")
struct PrecisionBoundaryTests {

    // MARK: - Hit-test culling

    /// `VolumeCanIntersectBox` narrows the transform into a `float[16]` for the
    /// clipbox helpers. When those buffers were mistyped as double, it received
    /// nonsense NDC bounds and culled everything -- marquee selection in the 3D
    /// view stopped picking anything.
    ///
    /// With an identity transform, model coordinates pass through to NDC
    /// unchanged (w stays 1), so the expected answers are easy to reason about.
    @Test("Screen box overlapping the volume is not culled")
    func overlappingBoxIsNotCulled() {
        let bounds = V3BoundsFromPoints(V3Make(-10, -10, -10), V3Make(10, 10, 10))

        #expect(VolumeCanIntersectBox(bounds, IdentityMatrix4, V2MakeBox(0, 0, 1, 1)))
    }

    @Test("Screen box well outside the volume is culled")
    func distantBoxIsCulled() {
        let bounds = V3BoundsFromPoints(V3Make(-10, -10, -10), V3Make(10, 10, 10))

        #expect(!VolumeCanIntersectBox(bounds, IdentityMatrix4, V2MakeBox(100, 100, 1, 1)))
    }

    /// The point variant additionally culls anything behind a depth already
    /// found. Both answers have to be right, or clicking either selects nothing
    /// or always hits the frontmost object.
    @Test("Point culling respects screen position and depth")
    func pointCullingHonoursPositionAndDepth() {
        let bounds = V3BoundsFromPoints(V3Make(-10, -10, -10), V3Make(10, 10, 10))
        let overlapping = V2MakeBox(0, 0, 1, 1)

        #expect(VolumeCanIntersectPoint(bounds, IdentityMatrix4, overlapping, 1000))
        #expect(!VolumeCanIntersectPoint(bounds, IdentityMatrix4, V2MakeBox(100, 100, 1, 1), 1000))

        // A depth limit nearer than the volume's minimum Z culls it entirely.
        #expect(!VolumeCanIntersectPoint(bounds, IdentityMatrix4, overlapping, -1000))
    }

    // MARK: - Scanned values

    /// ROTSTEP angles are scanned straight into a `Tuple3`. While those fields
    /// were double and the scan was still `-scanFloat:`, four bytes landed in an
    /// eight-byte slot and the angles came out as garbage.
    ///
    /// The step stores them in its internal XYZ convention, so reading them back
    /// as ZYX runs a full matrix compose/decompose round-trip -- which also
    /// covers the double-precision trig in `Matrix4DecomposeZYXRotation`.
    @Test("ROTSTEP angles survive scanning and the ZYX round-trip")
    func rotationStepAnglesParse() throws {
        let step = try #require(LDrawStep(lines: ["0 ROTSTEP 45 30 -60 ABS"],
                                         in: NSRange(location: 0, length: 1),
                                         parentGroup: nil))
        let angle = step.rotationAngleZYX()

        #expect(abs(angle.x - 45) < 1e-9)
        #expect(abs(angle.y - 30) < 1e-9)
        #expect(abs(angle.z - -60) < 1e-9)
    }
}
