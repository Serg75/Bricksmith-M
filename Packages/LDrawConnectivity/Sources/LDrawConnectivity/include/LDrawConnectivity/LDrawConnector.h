//==============================================================================
//
//  File:       LDrawConnector.h
//  Package:    LDrawConnectivity
//
//  Purpose:    Value types for one place where a part connects to another,
//              such as a stud, a stud hole, a pin or a hole, in the part's
//              own coordinates.
//
//  Notes:      The kinds match LDCad's SNAP metas. Only cylinders are read
//              from the shadow library for now.
//
//  Created by Sergey Slobodenyuk on 2026-09-19.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(uint8_t, LDrawConnectorKind)
{
	LDrawConnectorKindCylinder	= 0,	// studs, stud holes, pins, axles, holes
	LDrawConnectorKindClip		= 1,	// always female; takes a male cylinder
	LDrawConnectorKindFinger	= 2,	// matches only other fingers
	LDrawConnectorKindGeneric	= 3,	// matches only by group name
};

typedef NS_ENUM(uint8_t, LDrawConnectorGender)
{
	LDrawConnectorGenderMale	= 0,
	LDrawConnectorGenderFemale	= 1,
};

/// Cross-section of one length of a cylinder.
typedef NS_ENUM(uint8_t, LDrawSectionShape)
{
	LDrawSectionShapeRound			= 0,	// R
	LDrawSectionShapeAxle			= 1,	// A: a cross; does not take round pins
	LDrawSectionShapeSquare			= 2,	// S
	LDrawSectionShapeFlexToPrevious	= 3,	// _L
	LDrawSectionShapeFlexToNext		= 4,	// L_
};

/// Which ends of a cylinder are closed.
typedef NS_ENUM(uint8_t, LDrawConnectorCaps)
{
	LDrawConnectorCapsNone	= 0,
	LDrawConnectorCapsOne	= 1,
	LDrawConnectorCapsTwo	= 2,
	LDrawConnectorCapsA		= 3,
	LDrawConnectorCapsB		= 4,
};

/// Which measurements follow a scaled reference. A stud keeps its size, but a
/// stretched tube primitive makes a longer hole.
typedef NS_ENUM(uint8_t, LDrawConnectorScaleRule)
{
	LDrawConnectorScaleRuleNone		= 0,	// the default: neither measurement follows
	LDrawConnectorScaleRuleLength	= 1,	// YOnly
	LDrawConnectorScaleRuleRadius	= 2,	// ROnly
	LDrawConnectorScaleRuleBoth		= 3,	// YandR
};

/// What a mirrored reference does to a connector. Read from the shadow file
/// but not used yet.
typedef NS_ENUM(uint8_t, LDrawConnectorMirrorRule)
{
	LDrawConnectorMirrorRuleNone	= 0,
	LDrawConnectorMirrorRuleCorrect	= 1,
};

/// Where a connector came from. When two sources describe the same connector,
/// the one kept is, from best: override, shadow, inherited, primitive, lattice.
typedef NS_ENUM(uint8_t, LDrawConnectorProvenance)
{
	LDrawConnectorProvenanceShadow		= 0,	// LDCad shadow file for the part itself
	LDrawConnectorProvenanceInherited	= 1,	// shadow file of a subpart or primitive
	LDrawConnectorProvenancePrimitive	= 2,	// a stud primitive in the part's geometry
	LDrawConnectorProvenanceLattice		= 3,	// stud holes inferred from the underside
	LDrawConnectorProvenanceOverride	= 4,	// a correction file
};

/// One length of a cylinder profile. "secs=R 6 20" is one of these.
typedef struct
{
	double				radius;
	double				length;
	LDrawSectionShape	shape;

} LDrawConnectorSection;

/// A rectangle of identical connectors, such as the eight stud holes of a
/// 2 x 4 brick. The steps are vectors in the part's coordinates, so a grid on
/// a sideways or mirrored face needs no special case.
typedef struct
{
	uint8_t	countX;			// 1 means no grid along X
	uint8_t	countZ;
	bool	centeredX;		// the grid is centered on the position, rather
	bool	centeredZ;		// than starting at it
	Vector3	stepX;
	Vector3	stepZ;

} LDrawConnectorGrid;

/// A connector in its part's coordinates. A cylinder runs from position along
/// axis, or starts half its length back when it is centered. Studs rise along
/// -Y, so a stud's axis is (0, -1, 0).
typedef struct
{
	Point3						position;
	Vector3						axis;			// unit length
	Vector3						reference;		// unit length, across the axis; sets the
												// turn of axle and square sections
	LDrawConnectorGrid			grid;
	uint16_t					sectionOffset;	// into the owning set's sections
	uint8_t						sectionCount;
	LDrawConnectorKind			kind;
	LDrawConnectorGender		gender;
	LDrawConnectorCaps			caps;
	LDrawConnectorProvenance	provenance;
	bool						centered;		// position is the middle, not an end
	bool						slide;			// may slide along the axis, as an axle does

} LDrawConnector;


//---------- LDrawConnectorPointCount ------------------------------------------
///
/// How many connectors the record holds, counting every grid point.
///
//------------------------------------------------------------------------------
static inline NSUInteger LDrawConnectorPointCount(LDrawConnector connector)
{
	NSUInteger	countX	= MAX(connector.grid.countX, (uint8_t)1);
	NSUInteger	countZ	= MAX(connector.grid.countZ, (uint8_t)1);

	return countX * countZ;
}


//---------- LDrawConnectorPointAtIndex ----------------------------------------
///
/// The position of one connector of the grid, counting along X first.
///
//------------------------------------------------------------------------------
static inline Point3 LDrawConnectorPointAtIndex(LDrawConnector connector, NSUInteger index)
{
	NSUInteger	countX	= MAX(connector.grid.countX, (uint8_t)1);
	NSUInteger	countZ	= MAX(connector.grid.countZ, (uint8_t)1);
	double		stepsX	= (double)(index % countX);
	double		stepsZ	= (double)((index / countX) % countZ);
	Point3		point	= connector.position;

	if (connector.grid.centeredX)
	{
		stepsX -= (double)(countX - 1) / 2.0;
	}
	if (connector.grid.centeredZ)
	{
		stepsZ -= (double)(countZ - 1) / 2.0;
	}
	point.x += connector.grid.stepX.x * stepsX + connector.grid.stepZ.x * stepsZ;
	point.y += connector.grid.stepX.y * stepsX + connector.grid.stepZ.y * stepsZ;
	point.z += connector.grid.stepX.z * stepsX + connector.grid.stepZ.z * stepsZ;

	return point;
}

NS_ASSUME_NONNULL_END
