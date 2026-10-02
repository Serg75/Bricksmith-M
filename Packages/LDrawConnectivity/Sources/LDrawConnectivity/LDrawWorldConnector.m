//==============================================================================
//
//  File:       LDrawWorldConnector.m
//  Package:    LDrawConnectivity
//
//  Purpose:    Places a part's connectors in the model, and says which of
//              them could hold each other.
//
//  Created by Sergey Slobodenyuk on 2026-09-20.
//
//==============================================================================

#import <LDrawConnectivity/LDrawWorldConnector.h>

#import "LDrawConnectivityMath.h"

// Studs are radius 6 and pins radius 4, so half an LDU tells them apart.
static const double RadiusTolerance = 0.5;

// How far two fingers may reach into each other's width: float noise only.
static const double FingerOverlap = 0.25;


//---------- ShapesAccept ----------------------------------------------[static]--
//
// Purpose:		Whether a male section fits a female one. An axle hole takes
//				only an axle, and an axle turns in a round hole as well. Round
//				and square fit each other, so a stud fits a plate's square
//				hole.
//
//------------------------------------------------------------------------------
static BOOL ShapesAccept(LDrawSectionShape male, LDrawSectionShape female)
{
	if (female == LDrawSectionShapeAxle)
	{
		return (male == LDrawSectionShapeAxle);
	}
	if (male == LDrawSectionShapeAxle)
	{
		return (female == LDrawSectionShapeRound);
	}
	return (male == LDrawSectionShapeRound || male == LDrawSectionShapeSquare)
		&& (female == LDrawSectionShapeRound || female == LDrawSectionShapeSquare);
}


//---------- KindsAccept -----------------------------------------------[static]--
//
// Purpose:		Whether two connector kinds can mate. A clip takes a cylinder,
//				fingers take fingers, and generic shapes take each other.
//
//------------------------------------------------------------------------------
static BOOL KindsAccept(LDrawConnectorKind one, LDrawConnectorKind other)
{
	switch (one)
	{
		case LDrawConnectorKindCylinder:
			return (other == LDrawConnectorKindCylinder) || (other == LDrawConnectorKindClip);

		case LDrawConnectorKindClip:
			return (other == LDrawConnectorKindCylinder);

		case LDrawConnectorKindFinger:
			return (other == LDrawConnectorKindFinger);

		case LDrawConnectorKindGeneric:
			return (other == LDrawConnectorKindGeneric);
	}
	return NO;
}


//---------- FingersInterleave -----------------------------------------[static]--
//
// Purpose:		Whether two rows of fingers fit into each other with the second
//				starting at the given depth along the first: no finger of one
//				stands where the other has one.
//
// Notes:		Each section is one finger's width, and the genders alternate
//				from the row's gender.
//
//------------------------------------------------------------------------------
static BOOL FingersInterleave(LDrawWorldConnector row, LDrawWorldConnector other, double depth)
{
	double start = 0.0;

	for (NSUInteger mine = 0; mine < row.sectionCount; mine++)
	{
		double	finish		= start + row.sections[mine].length;
		BOOL	male		= ((mine % 2 == 0) == (row.gender == LDrawConnectorGenderMale));
		double	theirStart	= depth;

		for (NSUInteger theirs = 0; male && theirs < other.sectionCount; theirs++)
		{
			double	theirFinish	= theirStart + other.sections[theirs].length;
			BOOL	theirMale	= ((theirs % 2 == 0) == (other.gender == LDrawConnectorGenderMale));

			if (theirMale && MIN(finish, theirFinish) - MAX(start, theirStart) > FingerOverlap)
			{
				return NO;
			}
			theirStart = theirFinish;
		}
		start = finish;
	}
	return YES;
}


//---------- PositionAlong ---------------------------------------------[static]--
//
// Purpose:		How far along a connector its position is from its mouth.
//
//------------------------------------------------------------------------------
static double PositionAlong(LDrawWorldConnector connector)
{
	return connector.centered ? (connector.length / 2.0) : 0.0;
}


//---------- SectionStart ----------------------------------------------[static]--
//
// Purpose:		How far along the axis a section begins, measured from the
//				connector's mouth.
//
//------------------------------------------------------------------------------
static double SectionStart(LDrawWorldConnector connector, NSUInteger section)
{
	double start = 0.0;

	for (NSUInteger index = 0; index < section && index < connector.sectionCount; index++)
	{
		start += connector.sections[index].length;
	}
	return start;
}


//---------- SectionsMeet ----------------------------------------------[static]--
//
// Purpose:		Whether a section of one connector fits a section of the other:
//				the shapes accept each other and the radii agree.
//
//------------------------------------------------------------------------------
static BOOL SectionsMeet(LDrawWorldConnector one, NSUInteger mine, LDrawWorldConnector other, NSUInteger theirs)
{
	BOOL				oneIsMale	= (one.gender == LDrawConnectorGenderMale);
	LDrawSectionShape	male		= oneIsMale ? one.sections[mine].shape : other.sections[theirs].shape;
	LDrawSectionShape	female		= oneIsMale ? other.sections[theirs].shape : one.sections[mine].shape;

	return ShapesAccept(male, female)
		&& fabs(one.sections[mine].radius - other.sections[theirs].radius) <= RadiusTolerance;
}


//---------- LDrawWorldConnectorsMate ------------------------------------------
//------------------------------------------------------------------------------
BOOL LDrawWorldConnectorsMate(LDrawWorldConnector one, LDrawWorldConnector other,
							  double axisTolerance, double * _Nullable depth)
{
	BOOL	found	= NO;
	double	nearest	= 0.0;

	if (KindsAccept(one.kind, other.kind) == NO || one.match != other.match)
	{
		return NO;
	}
	if (one.anyDirection == false && other.anyDirection == false
		&& V3Dot(one.axis, other.axis) < cos(axisTolerance))
	{
		return NO;
	}

	// Rows of fingers meet at their positions, and fit when no finger of one
	// stands in a finger of the other.
	if (one.kind == LDrawConnectorKindFinger)
	{
		double reach = PositionAlong(other) - PositionAlong(one);

		if (FingersInterleave(other, one, reach) == NO)
		{
			return NO;
		}
		if (depth != NULL)
		{
			*depth = reach;
		}
		return YES;
	}
	if (one.gender == other.gender)
	{
		return NO;
	}

	// A generic shape has nothing more to match, apart from its size when it
	// asks for that. It meets at its position.
	if (one.kind == LDrawConnectorKindGeneric)
	{
		if ((one.matchesSize || other.matchesSize)
			&& fabs(one.sections[0].radius - other.sections[0].radius) > RadiusTolerance)
		{
			return NO;
		}
		if (depth != NULL)
		{
			*depth = 0.0;
		}
		return YES;
	}

	// Any section may meet any section, so a bar can reach the narrow part of
	// a tube. The shallowest match wins.
	for (NSUInteger mine = 0; mine < one.sectionCount; mine++)
	{
		for (NSUInteger theirs = 0; theirs < other.sectionCount; theirs++)
		{
			double reach = SectionStart(other, theirs) - SectionStart(one, mine);

			if (SectionsMeet(one, mine, other, theirs) == NO)
			{
				continue;
			}
			if (found == NO || fabs(reach) < fabs(nearest))
			{
				nearest	= reach;
				found	= YES;
			}
		}
	}
	if (found && depth != NULL)
	{
		*depth = nearest;
	}
	return found;
}


//---------- LDrawWorldConnectorsSlideRange ------------------------------------
//------------------------------------------------------------------------------
void LDrawWorldConnectorsSlideRange(LDrawWorldConnector moving, LDrawWorldConnector met, double depth,
									double *lowest, double *highest)
{
	double	shared	= met.length - moving.length;
	double	low		= INFINITY;
	double	high	= -INFINITY;

	// The sections that met at this depth stay within each other.
	for (NSUInteger mine = 0; mine < moving.sectionCount; mine++)
	{
		for (NSUInteger theirs = 0; theirs < met.sectionCount; theirs++)
		{
			double reach	= SectionStart(met, theirs) - SectionStart(moving, mine);
			double spare	= met.sections[theirs].length - moving.sections[mine].length;

			if (fabs(reach - depth) > 1e-6 || SectionsMeet(moving, mine, met, theirs) == NO)
			{
				continue;
			}
			low		= MIN(low, reach + MIN(spare, 0.0));
			high	= MAX(high, reach + MAX(spare, 0.0));
		}
	}
	if (low > high)
	{
		low		= depth + MIN(shared, 0.0);
		high	= depth + MAX(shared, 0.0);
	}

	// So does the shorter connector within the longer, when that leaves room.
	if (MAX(low, MIN(shared, 0.0)) <= MIN(high, MAX(shared, 0.0)))
	{
		low		= MAX(low, MIN(shared, 0.0));
		high	= MIN(high, MAX(shared, 0.0));
	}
	*lowest		= low - depth;
	*highest	= high - depth;
}
