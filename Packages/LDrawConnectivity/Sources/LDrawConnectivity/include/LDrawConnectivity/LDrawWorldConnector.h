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
//              have the same axis, not opposite ones. A connector open at both
//              ends, such as an axle or a beam hole, can also be met from its
//              far end.
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
	bool					bothEndsOpen;	// may be met from either end

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


//---------- LDrawWorldConnectorReversed ---------------------------------------
///
/// The same connector described from its far end: the axis turned round and
/// the sections in the opposite order.
///
//------------------------------------------------------------------------------
static inline LDrawWorldConnector LDrawWorldConnectorReversed(LDrawWorldConnector connector)
{
	LDrawWorldConnector	reversed	= connector;
	NSUInteger			count		= connector.sectionCount;

	if (connector.centered == false)
	{
		reversed.position = V3Add(connector.position, V3MulScalar(connector.axis, connector.length));
	}
	reversed.axis = V3MulScalar(connector.axis, -1.0);

	for (NSUInteger index = 0; index < count; index++)
	{
		LDrawConnectorSection section = connector.sections[count - 1 - index];

		// A flexible end joins the section on its other side once reversed.
		if (section.shape == LDrawSectionShapeFlexToPrevious)
		{
			section.shape = LDrawSectionShapeFlexToNext;
		}
		else if (section.shape == LDrawSectionShapeFlexToNext)
		{
			section.shape = LDrawSectionShapeFlexToPrevious;
		}
		reversed.sections[index] = section;
	}
	return reversed;
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


//---------- LDrawBoxByMatrix --------------------------------------------------
///
/// The space a box fills once it is moved: the box around its eight moved
/// corners. A turned box grows, which is what an upright box around a turned
/// part is.
///
//------------------------------------------------------------------------------
static inline Box3 LDrawBoxByMatrix(Box3 box, Matrix4 matrix)
{
	Box3 moved = InvalidBox;

	for (NSUInteger at = 0; at < 8; at++)
	{
		Point3 corner = {
			.x = (at & 1) ? box.max.x : box.min.x,
			.y = (at & 2) ? box.max.y : box.min.y,
			.z = (at & 4) ? box.max.z : box.min.z,
		};
		moved = V3UnionBoxAndPoint(moved, V3MulPointByProjMatrix(corner, matrix));
	}
	return moved;
}


NS_ASSUME_NONNULL_END
