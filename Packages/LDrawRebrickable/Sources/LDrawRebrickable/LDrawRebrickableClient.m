//==============================================================================
//
//  File:       LDrawRebrickableClient.m
//  Package:    LDrawRebrickable
//
//  Purpose:    Calls Rebrickable's API v3 with the user's own key.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawRebrickable/LDrawRebrickableClient.h>

#import <LDrawInventory/LDrawInventoryJSON.h>
#import <LDrawRebrickable/LDrawRebrickableCSVReader.h>

static NSString * const DefaultBaseURL = @"https://rebrickable.com/api/v3/";

/// The longest wait a 429 may ask for before the call gives up instead.
static const NSTimeInterval MaximumRetryWait = 60;


//========== ClientError =======================================================
//==============================================================================
static NSError *ClientError(LDrawRebrickableError code, NSString *reason)
{
	NSDictionary *userInfo = (reason != nil) ? @{ NSLocalizedDescriptionKey : reason } : nil;
	return [NSError errorWithDomain:LDrawRebrickableErrorDomain code:code userInfo:userInfo];
}


@implementation LDrawRebrickableClient
{
	NSURLSession		*session;		// made on the first call, from sessionConfiguration
	dispatch_queue_t	 scheduleQueue;	// keeps the calls apart
	CFAbsoluteTime		 nextSlot;		// the earliest time the next call may go out
	NSUInteger			 generation;	// cancelAll counts up, so waiting calls know
}


// MARK: - INITIALIZATION -


//========== initWithAPIKey: ===================================================
//==============================================================================
- (instancetype) initWithAPIKey:(NSString *)apiKey
{
	self = [super init];
	if (self) {
		self->_apiKey				= [apiKey copy];
		self->_baseURL				= [NSURL URLWithString:DefaultBaseURL];
		self->_sessionConfiguration	= [NSURLSessionConfiguration ephemeralSessionConfiguration];
		self->_minimumInterval		= 1.0;
		self->_maximumRetries		= 3;
		self->scheduleQueue			= dispatch_queue_create("LDrawRebrickableClient", DISPATCH_QUEUE_SERIAL);
	}
	return self;
}


//========== dealloc ===========================================================
//==============================================================================
- (void) dealloc
{
	[self->session invalidateAndCancel];
}


// MARK: - CALLS -


//========== fetchObjectAtPath:parameters:completion: ==========================
//==============================================================================
- (void) fetchObjectAtPath:(NSString *)path
				parameters:(NSDictionary<NSString *, NSString *> *)parameters
				completion:(void (^)(NSDictionary *object, NSError *error))completion
{
	NSURL				*url	= [self urlForPath:path parameters:parameters];
	dispatch_queue_t	 queue	= self.completionQueue ?: dispatch_get_main_queue();

	[self sendRequestForURL:url attempt:0 completion:^(NSDictionary *object, NSError *error) {
		dispatch_async(queue, ^{
			completion(object, error);
		});
	}];

}//end fetchObjectAtPath:parameters:completion:


//========== fetchAllResultsAtPath:parameters:completion: ======================
///
/// @abstract	GETs a list and its next pages. A thousand results come to a
/// 			page unless the parameters say otherwise.
///
//==============================================================================
- (void) fetchAllResultsAtPath:(NSString *)path
					parameters:(NSDictionary<NSString *, NSString *> *)parameters
					completion:(void (^)(NSArray<NSDictionary *> *results, NSError *error))completion
{
	NSMutableDictionary		*query		= [NSMutableDictionary dictionaryWithDictionary:parameters ?: @{}];
	NSMutableArray			*results	= [NSMutableArray array];
	dispatch_queue_t		 queue		= self.completionQueue ?: dispatch_get_main_queue();
	__weak typeof(self)		 weakSelf	= self;

	// The next page's step holds itself weakly. A call on its way holds it
	// strongly, so it lives until the last page is in.
	__block __weak void		(^weakFetchPage)(NSURL *url) = nil;
	void					(^fetchPage)(NSURL *url) = nil;

	if (query[@"page_size"] == nil)
		query[@"page_size"] = @"1000";

	void (^finish)(NSArray *, NSError *) = ^(NSArray *finalResults, NSError *error) {
		dispatch_async(queue, ^{
			completion(finalResults, error);
		});
	};

	weakFetchPage = fetchPage = ^(NSURL *url) {
		LDrawRebrickableClient	*client	= weakSelf;
		void					(^next)(NSURL *) = weakFetchPage;

		if (client == nil)
		{
			finish(nil, ClientError(LDrawRebrickableErrorCancelled, nil));
			return;
		}
		[client sendRequestForURL:url attempt:0 completion:^(NSDictionary *page, NSError *error) {
			NSString	*nextText	= LDrawJSONString(page[@"next"]);
			NSURL		*nextURL	= (nextText != nil) ? [NSURL URLWithString:nextText] : nil;

			if (error != nil)
			{
				finish(nil, error);
				return;
			}
			for (id result in LDrawJSONArray(page[@"results"]))
			{
				if (LDrawJSONDictionary(result) != nil)
					[results addObject:result];
			}

			if (nextURL == nil)
				finish(results, nil);
			else if ([nextURL.host isEqualToString:weakSelf.baseURL.host] == NO)
				// The key must not go anywhere but Rebrickable.
				finish(nil, ClientError(LDrawRebrickableErrorBadResponse, @"The next page is on another server."));
			else
				next(nextURL);
		}];
	};

	fetchPage([self urlForPath:path parameters:query]);

}//end fetchAllResultsAtPath:parameters:completion:


//========== cancelAll =========================================================
//==============================================================================
- (void) cancelAll
{
	dispatch_sync(self->scheduleQueue, ^{
		self->generation += 1;
	});
	[self->session getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> *tasks) {
		for (NSURLSessionTask *task in tasks)
			[task cancel];
	}];
}


// MARK: - UTILITIES -


//========== urlForPath:parameters: ============================================
///
/// @abstract	The path below the base URL, with the parameters in key order.
///
//==============================================================================
- (NSURL *) urlForPath:(NSString *)path parameters:(NSDictionary<NSString *, NSString *> *)parameters
{
	NSURL			*url		= [NSURL URLWithString:path relativeToURL:self.baseURL];
	NSURLComponents	*components	= [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:YES];
	NSMutableArray	*items		= [NSMutableArray array];

	for (NSString *key in [[parameters allKeys] sortedArrayUsingSelector:@selector(compare:)])
		[items addObject:[NSURLQueryItem queryItemWithName:key value:parameters[key]]];

	if ([items count] > 0)
		components.queryItems = items;

	return components.URL;

}//end urlForPath:parameters:


//========== urlSession ========================================================
//==============================================================================
- (NSURLSession *) urlSession
{
	@synchronized (self) {
		if (self->session == nil)
			self->session = [NSURLSession sessionWithConfiguration:self.sessionConfiguration];
		return self->session;
	}
}


//========== sendRequestForURL:attempt:completion: =============================
///
/// @abstract	Waits for the call's turn, sends it, and reads the answer. The
/// 			completion runs on the session's queue.
///
//==============================================================================
- (void) sendRequestForURL:(NSURL *)url
				   attempt:(NSUInteger)attempt
				completion:(void (^)(NSDictionary *object, NSError *error))completion
{
	dispatch_async(self->scheduleQueue, ^{
		CFAbsoluteTime	now			= CFAbsoluteTimeGetCurrent();
		CFAbsoluteTime	start		= MAX(now, self->nextSlot);
		NSUInteger		calledIn	= self->generation;

		self->nextSlot = start + self.minimumInterval;

		dispatch_time_t	when		= dispatch_time(DISPATCH_TIME_NOW, (int64_t)((start - now) * NSEC_PER_SEC));

		dispatch_after(when, self->scheduleQueue, ^{
			if (calledIn != self->generation)
			{
				completion(nil, ClientError(LDrawRebrickableErrorCancelled, nil));
				return;
			}

			NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
			[request setValue:[@"key " stringByAppendingString:self.apiKey] forHTTPHeaderField:@"Authorization"];
			[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

			void (^handler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response,
																	  NSError *error) {
				[self handleData:data response:response error:error url:url attempt:attempt completion:completion];
			};
			[[[self urlSession] dataTaskWithRequest:request completionHandler:handler] resume];
		});
	});

}//end sendRequestForURL:attempt:completion:


//========== handleData:response:error:url:attempt:completion: =================
///
/// @abstract	Reads an answer: the JSON object, a retry after a 429, or an
/// 			error that says what went wrong.
///
//==============================================================================
- (void) handleData:(NSData *)data
		   response:(NSURLResponse *)response
			  error:(NSError *)error
				url:(NSURL *)url
			attempt:(NSUInteger)attempt
		 completion:(void (^)(NSDictionary *object, NSError *error))completion
{
	NSHTTPURLResponse	*http		= (NSHTTPURLResponse *)response;
	NSInteger			 status		= [http isKindOfClass:[NSHTTPURLResponse class]] ? http.statusCode : 0;
	NSDictionary		*object		= nil;

	if (error != nil)
	{
		BOOL isCancelled = [error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled;
		completion(nil, isCancelled ? ClientError(LDrawRebrickableErrorCancelled, nil) : error);
		return;
	}

	if (status == 429)
	{
		NSTimeInterval wait = [[http valueForHTTPHeaderField:@"Retry-After"] doubleValue];

		if (wait <= 0)
			wait = pow(2.0, (double)attempt) * MAX(self.minimumInterval, 0.01);

		if (attempt >= self.maximumRetries || wait > MaximumRetryWait)
		{
			completion(nil, ClientError(LDrawRebrickableErrorTooManyRequests,
										@"Rebrickable asks to slow down. Try again in a minute."));
			return;
		}

		dispatch_async(self->scheduleQueue, ^{
			self->nextSlot = MAX(self->nextSlot, CFAbsoluteTimeGetCurrent() + wait);
		});
		[self sendRequestForURL:url attempt:attempt + 1 completion:completion];
		return;
	}

	if (status == 401 || status == 403)
	{
		completion(nil, ClientError(LDrawRebrickableErrorBadKey, @"Rebrickable did not accept the API key."));
		return;
	}
	if (status == 404)
	{
		completion(nil, ClientError(LDrawRebrickableErrorNotFound, @"Rebrickable has no such item."));
		return;
	}

	object = LDrawJSONDictionary([NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:NULL]);
	if (status != 200 || object == nil)
	{
		completion(nil, ClientError(LDrawRebrickableErrorBadResponse,
									[NSString stringWithFormat:@"Rebrickable answered %ld.", (long)status]));
		return;
	}
	completion(object, nil);

}//end handleData:response:error:url:attempt:completion:

@end
