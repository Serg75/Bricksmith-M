//==============================================================================
//
//  File:       LDrawPartLimitSession.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawInventoryStore;
@class LDrawPartIdentity;
@class LDrawPartLimit;
@class LDrawPartLimitTable;
@class LDrawShortcutMap;

NS_ASSUME_NONNULL_BEGIN

/// The limit, or what it allows, changed: a new limit, new data in the store,
/// or a reloaded part library. Object is the session. No userInfo.
extern NSString * const LDrawPartLimitDidChangeNotification;


//------------------------------------------------------------------------------
///
/// @class      LDrawPartLimitSession
///
/// @abstract   The editor's one parts limit, and the table built for it.
///
/// @discussion A host makes one, gives it the store and the part library's
///             records, and sets the limit it keeps in its own settings. The
///             session builds the table again whenever one of them changes,
///             and posts `LDrawPartLimitDidChangeNotification`; every
///             document checks itself again then. The identity map is built
///             when first needed. Used on the main thread.
///
//------------------------------------------------------------------------------
@interface LDrawPartLimitSession : NSObject

- (instancetype) initWithStore:(LDrawInventoryStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype) init NS_UNAVAILABLE;

@property (nonatomic, readonly) LDrawInventoryStore *store;

/// The limit the host chose. Setting it builds the table again and posts the
/// notification, unless it is the same limit.
@property (nonatomic, copy) LDrawPartLimit *limit;

/// The limit in force: `limit`, or no limit when it names an inventory the
/// store does not have.
@property (nonatomic, readonly) LDrawPartLimit *effectiveLimit;

@property (nonatomic, readonly) LDrawPartLimitTable *table;
@property (nonatomic, readonly) LDrawPartIdentity *identity;

/// The table when its limit restricts and it has the data it needs, else nil.
/// Only such a table narrows what the editor offers.
@property (nonatomic, readonly, nullable) LDrawPartLimitTable *restrictingTable;

/// The year Available now counts back from. Default the current year.
@property (nonatomic) NSInteger currentYear;

/// A table for one set or combined inventory, with the limit's options, for
/// browsing it whatever the limit is. Nil when the store does not have it.
/// Kept until the session builds its table again.
- (nullable LDrawPartLimitTable *) tableForInventoryIdentifier:(NSString *)identifier
	NS_SWIFT_NAME(table(forInventoryIdentifier:));

/// The part library's records, for the keywords that name Rebrickable parts
/// and for moved parts. Setting them builds everything again.
- (void) setCatalogRecords:(nullable NSArray<NSDictionary *> *)catalogRecords;

/// The part library's shortcuts, so assemblies and their pieces count alike.
/// Setting it builds the tables again and posts the notification.
@property (nonatomic, nullable) LDrawShortcutMap *shortcuts;

@end

NS_ASSUME_NONNULL_END
