//
//  LDrawDocumentTree.h
//  Bricksmith
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//

#import <Foundation/Foundation.h>

#import "LDrawStep.h"

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class		LDrawDocumentTree
///
/// @abstract	Methods to examine document structure.
///
//------------------------------------------------------------------------------
@interface LDrawDocumentTree : NSObject

+ (NSArray *)mostInnerDirectives:(NSArray *)objects;
+ (NSSet<NSString *> *) groupsBeforeStep:(LDrawStep *)step;

@end

NS_ASSUME_NONNULL_END
