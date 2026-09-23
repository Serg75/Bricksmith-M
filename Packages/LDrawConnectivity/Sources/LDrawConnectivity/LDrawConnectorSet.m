//==============================================================================
//
//  File:       LDrawConnectorSet.m
//  Package:    LDrawConnectivity
//
//  Purpose:    The connectors of one part, in the part's own coordinates.
//
//  Created by Sergey Slobodenyuk on 2026-09-19.
//
//==============================================================================

#import <LDrawConnectivity/LDrawConnectorSet.h>

@implementation LDrawConnectorSet
{
	NSData	*_connectors;
	NSData	*_sections;
}

//========== initWithConnectors:connectorCount:sections:sectionCount: =========
//
// Purpose:		Copies the given records; the caller keeps its buffers.
//
//==============================================================================
- (instancetype)initWithConnectors:(const LDrawConnector *)connectors
					connectorCount:(NSUInteger)connectorCount
						  sections:(const LDrawConnectorSection *)sections
					  sectionCount:(NSUInteger)sectionCount
{
	self = [super init];
	if (self != nil)
	{
		_connectors	= [NSData dataWithBytes:connectors length:connectorCount * sizeof(LDrawConnector)];
		_sections	= [NSData dataWithBytes:sections length:sectionCount * sizeof(LDrawConnectorSection)];
	}
	return self;
}


//========== connectorCount ====================================================
//==============================================================================
- (NSUInteger)connectorCount
{
	return _connectors.length / sizeof(LDrawConnector);
}


//========== connectorAtIndex: =================================================
//
// Purpose:		The record at the index, or an empty one when the index is out
//				of range.
//
// Notes:		Asserts in debug builds. Release builds return an empty record
//				rather than read past the buffer.
//
//==============================================================================
- (LDrawConnector)connectorAtIndex:(NSUInteger)index
{
	NSParameterAssert(index < self.connectorCount);

	if (index >= self.connectorCount)
	{
		return (LDrawConnector){};
	}
	return ((const LDrawConnector *)_connectors.bytes)[index];
}


//========== sectionAtIndex: ===================================================
//==============================================================================
- (LDrawConnectorSection)sectionAtIndex:(NSUInteger)index
{
	NSUInteger count = _sections.length / sizeof(LDrawConnectorSection);

	NSParameterAssert(index < count);

	if (index >= count)
	{
		return (LDrawConnectorSection){};
	}
	return ((const LDrawConnectorSection *)_sections.bytes)[index];
}

@end
