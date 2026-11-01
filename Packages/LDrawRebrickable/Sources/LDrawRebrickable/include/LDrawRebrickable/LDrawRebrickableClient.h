//==============================================================================
//
//  File:       LDrawRebrickableClient.h
//  Package:    LDrawRebrickable
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawRebrickableClient
///
/// @abstract   Calls Rebrickable's API v3 with the user's own key.
///
/// @discussion Calls go out one at a time, a second apart, as Rebrickable
///             asks. A 429 is retried after the wait the server names, a few
///             times. The key goes in the Authorization header only. The
///             spacing holds within one client, so a host keeps one.
///
///             Rebrickable's docs ask apps to read full lists from the
///             downloads, not page through the API, so this is meant for a
///             few calls at a time: one set, or the colors.
///
//------------------------------------------------------------------------------
@interface LDrawRebrickableClient : NSObject

@property (nonatomic, readonly, copy) NSString *apiKey;

/// Default https://rebrickable.com/api/v3/
@property (nonatomic, copy) NSURL *baseURL;

/// The session's configuration. Tests give one with a stub protocol.
@property (nonatomic, copy) NSURLSessionConfiguration *sessionConfiguration;

/// The least time between two calls. Default one second.
@property (nonatomic) NSTimeInterval minimumInterval;

/// How many times a 429 is retried. Default 3.
@property (nonatomic) NSUInteger maximumRetries;

/// Where completions run. Main when nil, the default.
@property (nonatomic, nullable) dispatch_queue_t completionQueue;

- (instancetype) initWithAPIKey:(NSString *)apiKey NS_DESIGNATED_INITIALIZER;
- (instancetype) init NS_UNAVAILABLE;

/// GETs one object, e.g. `lego/sets/42115-1/`.
- (void) fetchObjectAtPath:(NSString *)path
				parameters:(nullable NSDictionary<NSString *, NSString *> *)parameters
				completion:(void (^)(NSDictionary * _Nullable object, NSError * _Nullable error))completion;

/// GETs a list, following its `next` pages, and gives every result.
- (void) fetchAllResultsAtPath:(NSString *)path
					parameters:(nullable NSDictionary<NSString *, NSString *> *)parameters
					completion:(void (^)(NSArray<NSDictionary *> * _Nullable results,
										 NSError * _Nullable error))completion;

/// Stops every call; their completions get a cancelled error.
- (void) cancelAll;

@end

NS_ASSUME_NONNULL_END
