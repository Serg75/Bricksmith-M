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

/// Where the sets, inventories and parts data come from.
@property (nonatomic, readonly) LDrawInventoryStore *store;

/// The limit the host chose. Setting it builds the table again and posts the
/// notification, unless it is the same limit.
@property (nonatomic, copy) LDrawPartLimit *limit;

/// The limit in force: `limit`, or no limit when it names an inventory the
/// store does not have.
@property (nonatomic, readonly) LDrawPartLimit *effectiveLimit;

/// What `effectiveLimit` allows.
@property (nonatomic, readonly) LDrawPartLimitTable *table;

/// How LDraw parts and colors match Rebrickable's.
@property (nonatomic, readonly) LDrawPartIdentity *identity;

/// The table when its limit restricts and it has the data it needs, else nil.
/// Only such a table narrows what the editor offers.
@property (nonatomic, readonly, nullable) LDrawPartLimitTable *restrictingTable;

/// The year Available now counts back from. Default the current year.
@property (nonatomic) NSInteger currentYear;

/// The limits a menu offers: All Parts and Available Now, then each set and
/// combined inventory in the store. Each keeps the current limit's options.
- (NSArray<LDrawPartLimit *> *) choosableLimits;

/// A table for one set or combined inventory, with the limit's options, for
/// browsing it whatever the limit is. Nil when the store does not have it.
/// Kept until the session builds its table again.
- (nullable LDrawPartLimitTable *) tableForInventoryIdentifier:(NSString *)identifier
	NS_SWIFT_NAME(table(forInventoryIdentifier:));

/// The part library's records, for the keywords that name Rebrickable parts
/// and for moved parts, and the LDraw colors that are rubber, such as rubber
/// black, which only rubber parts are offered. Setting them builds everything
/// again; records equal to the last ones change nothing.
///
/// Once the parts data is needed, the session reads which of the records'
/// parts are shortcuts and then sets shortcuts. The read opens every part
/// file, so it runs on a background queue, and never for a user who never
/// limits parts.
- (void) setCatalogRecords:(nullable NSArray<NSDictionary *> *)catalogRecords
		  rubberColorCodes:(nullable NSSet<NSNumber *> *)rubberColorCodes;

/// Whether anything uses the parts data: a limit, a set or an inventory.
@property (nonatomic, readonly) BOOL needsPartsData;

/// The part library's shortcuts, so assemblies and their pieces count alike.
/// When the read of them ends, the tables are built again and the notification
/// posts.
@property (nonatomic, readonly, nullable) LDrawShortcutMap *shortcuts;

@end

NS_ASSUME_NONNULL_END
