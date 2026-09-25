//==============================================================================
//
//  File:       LDrawWorldConnectors.m
//  Package:    LDrawConnectivity
//
//  Purpose:    The connectors of one or more placed parts.
//
//  Created by Sergey Slobodenyuk on 2026-09-25.
//
//==============================================================================

#import <LDrawConnectivity/LDrawWorldConnectors.h>

#import "LDrawConnectivityMath.h"
#import "LDrawConnectorNeighborhood.h"

// Two connectors at the same point, allowing for the library's rounding.
static const double MouthMargin = 0.25;

// The stud pitch: as close as two connectors of one part sit.
static const double CellPitch = 20.0;


//---------- RunCovers -------------------------------------------------[static]--
//
// Purpose:		Whether a point lies on a connector's run, between its ends.
//
//------------------------------------------------------------------------------
static BOOL RunCovers(LDrawWorldConnector connector, Point3 point, double margin)
{
	Point3	mouth	= LDrawWorldConnectorMouth(connector);
	Vector3	apart	= V3Sub(point, mouth);
	double	along	= V3Dot(apart, connector.axis);
	Vector3	aside	= V3Sub(apart, V3MulScalar(connector.axis, along));

	return (V3Length(aside) <= margin)
		&& (along >= -margin) && (along <= connector.length + margin);
}


@implementation LDrawWorldConnectors
{
	NSMutableData *_connectors;
}

//---------- connectors ------------------------------------------------[static]--
//------------------------------------------------------------------------------
+ (instancetype)connectors
{
	return [[self alloc] init];
}


//---------- connectorsFromSet:placement:owner: ------------------------[static]--
//------------------------------------------------------------------------------
+ (instancetype)connectorsFromSet:(LDrawConnectorSet *)set
						placement:(Matrix4)placement
							owner:(uint32_t)owner
{
	LDrawWorldConnectors *placed = [self connectors];

	[placed addConnectorsFromSet:set placement:placement owner:owner];

	return placed;
}


//========== init ==============================================================
//==============================================================================
- (instancetype)init
{
	self = [super init];
	if (self != nil)
	{
		_connectors = [NSMutableData data];
	}
	return self;
}


#pragma mark - Building


//========== addConnectorsFromSet:placement:owner: =============================
//
// Purpose:		Places every connector of a part, grids unpacked.
//
//==============================================================================
- (void)addConnectorsFromSet:(LDrawConnectorSet *)set
				   placement:(Matrix4)placement
					   owner:(uint32_t)owner
{

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
			[self addConnector:world];
		}
	}
}


//========== addConnectors: ====================================================
//==============================================================================
- (void)addConnectors:(LDrawWorldConnectors *)connectors
{
	[_connectors appendBytes:connectors.all length:connectors.count * sizeof(LDrawWorldConnector)];
}


//========== addConnector: =====================================================
//==============================================================================
- (void)addConnector:(LDrawWorldConnector)connector
{
	[_connectors appendBytes:&connector length:sizeof(connector)];
}


//========== copyWithZone: =====================================================
//
// Purpose:		The same connectors in a set of their own, for a holder that
//				must not see the caller add more.
//
//==============================================================================
- (id)copyWithZone:(nullable NSZone *)zone
{
	LDrawWorldConnectors *copy = [[LDrawWorldConnectors alloc] init];

	[copy addConnectors:self];

	return copy;
}


#pragma mark - Reading


//========== count =============================================================
//==============================================================================
- (NSUInteger)count
{
	return _connectors.length / sizeof(LDrawWorldConnector);
}


//========== all ===============================================================
//==============================================================================
- (const LDrawWorldConnector *)all
{
	return _connectors.bytes;
}


//========== connectorAtIndex: =================================================
//==============================================================================
- (LDrawWorldConnector)connectorAtIndex:(NSUInteger)index
{
	NSParameterAssert(index < self.count);

	if (index >= self.count)
	{
		return (LDrawWorldConnector){};
	}
	return self.all[index];
}


#pragma mark - Making others


//========== connectorsPlacedBy: ===============================================
//==============================================================================
- (LDrawWorldConnectors *)connectorsPlacedBy:(Matrix4)placement
{
	LDrawWorldConnectors	*placed	= [LDrawWorldConnectors connectors];
	const LDrawWorldConnector *all	= self.all;
	NSUInteger				count	= self.count;

	for (NSUInteger index = 0; index < count; index++)
	{
		LDrawWorldConnector moved = all[index];

		moved.position	= V3MulPointByProjMatrix(moved.position, placement);
		moved.axis		= V3Normalize(LDrawDirectionByMatrix(moved.axis, placement));

		[placed addConnector:moved];
	}
	return placed;
}


//========== connectorsStillFree: ==============================================
//==============================================================================
- (LDrawWorldConnectors *)connectorsStillFree:(double)axisTolerance
{
	const LDrawWorldConnector	*all	= self.all;
	NSUInteger					count	= self.count;
	LDrawWorldConnectors		*free	= [LDrawWorldConnectors connectors];
	LDrawConnectorNeighborhood	*nearby	= [[LDrawConnectorNeighborhood alloc]
										   initWithConnectors:self cellSize:CellPitch];

	for (NSUInteger index = 0; index < count; index++)
	{
		Point3		mouth	= LDrawWorldConnectorMouth(all[index]);
		Box3		around	= V3BoundsFromPoints(mouth, mouth);
		NSUInteger	found	= 0;
		BOOL		blocked	= NO;

		if (all[index].slide)
		{
			[free addConnector:all[index]];
			continue;
		}
		around.min.x -= MouthMargin;	around.min.y -= MouthMargin;	around.min.z -= MouthMargin;
		around.max.x += MouthMargin;	around.max.y += MouthMargin;	around.max.z += MouthMargin;

		const uint32_t *close = [nearby indicesNearBox:around count:&found];

		for (NSUInteger other = 0; other < found && blocked == NO; other++)
		{
			if (close[other] == index)
			{
				continue;
			}
			blocked = LDrawWorldConnectorsMate(all[index], all[close[other]], axisTolerance, NULL)
				   && RunCovers(all[close[other]], mouth, MouthMargin);
		}
		if (blocked == NO)
		{
			[free addConnector:all[index]];
		}
	}
	return free;
}

@end
