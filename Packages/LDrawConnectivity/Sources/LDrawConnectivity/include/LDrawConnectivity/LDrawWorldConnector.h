//==============================================================================
//
//  File:       LDrawWorldConnector.h
//  Package:    LDrawConnectivity
//
//  Purpose:    A connector of a placed part, in model coordinates, with its
//              grid expanded to one record per point.
//
//  Notes:      The position is where two parts meet, and the axis points the
//              way the shape runs from there. A stud and the hole it enters
//              have the same axis, not opposite ones.
//
//  Created by Sergey Slobodenyuk on 2026-09-20.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawConnectivity/LDrawConnector.h>

NS_ASSUME_NONNULL_BEGIN

/// The most sections kept per connector. The shadow library uses at most
/// three.
#define LDrawWorldConnectorSectionLimit 4

typedef struct
{
	Point3					position;
	Vector3					axis;			// unit length
	double					length;			// the whole profile
	LDrawConnectorSection	sections[LDrawWorldConnectorSectionLimit];
	uint32_t				owner;			// which placed part this belongs to
	uint8_t					sectionCount;
	LDrawConnectorKind		kind;
	LDrawConnectorGender	gender;
	bool					centered;		// position is the middle of the run
	bool					slide;			// may sit anywhere along the axis

} LDrawWorldConnector;


//---------- LDrawWorldConnectorMouth ------------------------------------------
///
/// The open end of the shape, where another part enters it. This is the
/// position unless the connector is centered.
///
//------------------------------------------------------------------------------
static inline Point3 LDrawWorldConnectorMouth(LDrawWorldConnector connector)
{
	Point3	mouth	= connector.position;
	double	back	= connector.centered ? (connector.length / 2.0) : 0.0;

	mouth.x -= connector.axis.x * back;
	mouth.y -= connector.axis.y * back;
	mouth.z -= connector.axis.z * back;

	return mouth;
}


/// Whether the two can mate: opposite genders, matching shapes and radii, and
/// axes within the tolerance. Position is not tested, and neither is the
/// owner: a part's own connectors mate with each other inside it.
///
/// `depth` is how far the first connector's mouth sits along the second's
/// axis, from its mouth. It is zero for a stud in a stud hole, and the depth
/// of the narrow part for a bar inside a tube.
extern BOOL LDrawWorldConnectorsMate(LDrawWorldConnector one, LDrawWorldConnector other,
									 double axisTolerance, double * _Nullable depth);


NS_ASSUME_NONNULL_END
