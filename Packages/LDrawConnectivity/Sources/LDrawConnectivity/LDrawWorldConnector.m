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


//---------- ShapesAccept ----------------------------------------------[static]--
//
// Purpose:		Whether one section shape fits another. Axle fits only axle.
//				Round and square fit each other, so a stud fits a plate's
//				square hole.
//
//------------------------------------------------------------------------------
static BOOL ShapesAccept(LDrawSectionShape one, LDrawSectionShape other)
{
	if (one == LDrawSectionShapeAxle || other == LDrawSectionShapeAxle)
	{
		return (one == other);
	}
	return (one == LDrawSectionShapeRound || one == LDrawSectionShapeSquare)
		&& (other == LDrawSectionShapeRound || other == LDrawSectionShapeSquare);
}


//---------- KindsAccept -----------------------------------------------[static]--
//
// Purpose:		Whether two connector kinds can mate. A clip takes a cylinder,
//				fingers take fingers. Generic never matches, because groups
//				are not read yet.
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
			return NO;
	}
	return NO;
}


//---------- LDrawWorldConnectorsFromSet ---------------------------------------
//------------------------------------------------------------------------------
NSData *LDrawWorldConnectorsFromSet(LDrawConnectorSet *set, Matrix4 placement, uint32_t owner)
{
	NSMutableData *placed = [NSMutableData data];

	for (NSUInteger index = 0; index < set.connectorCount; index++)
	{
		LDrawConnector			connector	= [set connectorAtIndex:index];
		LDrawConnectorSection	profile[LDrawWorldConnectorSectionLimit] = {};
		NSUInteger				kept		= 0;
		double					length		= 0.0;

		for (NSUInteger section = 0; section < connector.sectionCount; section++)
		{
			LDrawConnectorSection run = [set sectionAtIndex:connector.sectionOffset + section];

			if (kept < LDrawWorldConnectorSectionLimit)
			{
				profile[kept] = run;
				kept++;
				length += run.length;
			}
		}

		for (NSUInteger point = 0; point < LDrawConnectorPointCount(connector); point++)
		{
			LDrawWorldConnector world = {
				.position		= V3MulPointByProjMatrix(LDrawConnectorPointAtIndex(connector, point), placement),
				.axis			= V3Normalize(LDrawDirectionByMatrix(connector.axis, placement)),
				.length			= length,
				.owner			= owner,
				.sectionCount	= (uint8_t)kept,
				.kind			= connector.kind,
				.gender			= connector.gender,
				.centered		= connector.centered,
				.slide			= connector.slide,
			};
			memcpy(world.sections, profile, sizeof(profile));
			[placed appendBytes:&world length:sizeof(world)];
		}
	}
	return placed;
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


//---------- LDrawWorldConnectorsMate ------------------------------------------
//------------------------------------------------------------------------------
BOOL LDrawWorldConnectorsMate(LDrawWorldConnector one, LDrawWorldConnector other,
							  double axisTolerance, double * _Nullable depth)
{
	BOOL	found	= NO;
	double	nearest	= 0.0;

	if (one.owner == other.owner)
	{
		return NO;
	}
	if (one.gender == other.gender)
	{
		return NO;
	}
	if (KindsAccept(one.kind, other.kind) == NO)
	{
		return NO;
	}
	if (V3Dot(one.axis, other.axis) < cos(axisTolerance))
	{
		return NO;
	}

	// Any section may meet any section, so a bar can reach the narrow part of
	// a tube. The shallowest match wins.
	for (NSUInteger mine = 0; mine < one.sectionCount; mine++)
	{
		for (NSUInteger theirs = 0; theirs < other.sectionCount; theirs++)
		{
			double reach = SectionStart(other, theirs) - SectionStart(one, mine);

			if (ShapesAccept(one.sections[mine].shape, other.sections[theirs].shape) == NO)
			{
				continue;
			}
			if (fabs(one.sections[mine].radius - other.sections[theirs].radius) > RadiusTolerance)
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
