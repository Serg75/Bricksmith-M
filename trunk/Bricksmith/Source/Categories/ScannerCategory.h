//
//  ScannerCategory.h
//  Bricksmith
//
//  Extends functionality for NSScanner.
//
//  Created by Sergey Slobodenyuk on 2023-02-28.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSScanner (ScannerCategory)

- (NSArray<NSString *> *)scanSubstringsWithQuotations;

@end

NS_ASSUME_NONNULL_END
