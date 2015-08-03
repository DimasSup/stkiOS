//
//  STKStickersEntityService.m
//  StickerPipe
//
//  Created by Vadim Degterev on 27.07.15.
//  Copyright (c) 2015 908 Inc. All rights reserved.
//

#import "STKStickersEntityService.h"
#import "STKStickersCache.h"
#import "STKStickersApiService.h"
#import "STKStickersSerializer.h"
#import "STKStickerPackObject.h"
#import "STKUtility.h"

static NSString *const kLastModifiedDateKey = @"kLastModifiedDateKey";
static NSString *const kLastUpdateIntervalKey = @"kLastUpdateIntervalKey";
static const NSTimeInterval kUpdatesDelay = 900.0; //15 min

@interface STKStickersEntityService()

@property (strong, nonatomic) STKStickersApiService *apiService;
@property (strong, nonatomic) STKStickersCache *cacheEntity;
@property (strong, nonatomic) STKStickersSerializer *serializer;
@property (strong, nonatomic) dispatch_queue_t queue;

@end

@implementation STKStickersEntityService

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.apiService = [[STKStickersApiService alloc] init];
        self.cacheEntity = [[STKStickersCache alloc] init];
        self.serializer = [[STKStickersSerializer alloc] init];
        self.queue = dispatch_queue_create("com.stickers.service", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)getStickerPacksWithType:(NSString *)type
                 completion:(void (^)(NSArray *))completion
                    failure:(void (^)(NSError *))failure
{
    
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.queue, ^{
        NSTimeInterval lastUpdate = [self lastUpdateDate];
        NSTimeInterval timeSinceLastUpdate = [[NSDate date] timeIntervalSince1970] - lastUpdate;
        if (timeSinceLastUpdate > kUpdatesDelay) {
            [weakSelf updateStickerPacksWithType:type completion:nil];
        }
        
        [self.cacheEntity getStickerPacks:^(NSArray *stickerPacks) {
            if (stickerPacks.count == 0) {
                [weakSelf updateStickerPacksWithType:type completion:^(NSArray *stickerPacks) {
                    if (completion) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(stickerPacks);
                        });
                    }
                }];
            } else {
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(stickerPacks);
                    });
                }
            }

        }];
    });
}

- (void)updateStickerPacksWithType:(NSString*)type completion:(void(^)(NSArray *stickerPacks))completion {
    
    __weak typeof(self) weakSelf = self;
    
    [self.apiService getStickersPackWithType:type success:^(id response, NSTimeInterval lastModifiedDate) {
        
        NSArray* serializedObjects = [weakSelf.serializer serializeStickerPacks:response[@"data"]];
        if (lastModifiedDate != [weakSelf lastModifiedDate]) {
            [weakSelf.cacheEntity saveStickerPacks:serializedObjects];
            [weakSelf setLastModifiedDate:lastModifiedDate];
        }
//        STKStickerPackObject *recentPack = weakSelf.cacheEntity.recentStickerPack;
//        NSArray *packsWithRecent = nil;
//        if (recentPack) {
//            NSArray *recentPackArray = @[recentPack];
//            packsWithRecent = [recentPackArray arrayByAddingObjectsFromArray:serializedObjects];
//        } else {
//            packsWithRecent = serializedObjects;
//        }
        //TODO:Refactoring
        [weakSelf.cacheEntity getStickerPacks:^(NSArray *stickerPacks) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(stickerPacks);
                });
            }
        }];
        [weakSelf setLastUpdateDate:[[NSDate date] timeIntervalSince1970]];

        
    } failure:^(NSError *error) {
        if (completion) {
            //TODO:REfactoring
            completion(nil);
        }
    }];

}

- (void)incrementStickerUsedCountWithID:(NSNumber *)stickerID {
    [self.cacheEntity incrementUsedCountWithStickerID:stickerID];
}

-(void)getPackWithMessage:(NSString *)message completion:(void (^)(STKStickerPackObject *, BOOL))completion {
    
    NSArray *separaredStickerNames = [STKUtility trimmedPackNameAndStickerNameWithMessage:message];
    NSString *packName = [[separaredStickerNames firstObject] lowercaseString];
    
    STKStickerPackObject *stickerPackObject =  [self.cacheEntity getStickerPackWithPackName:packName];
    if (!stickerPackObject) {
        
        __weak typeof(self) weakSelf = self;
        
        [self.apiService getStickerPackWithName:packName success:^(id response) {
            
            NSDictionary *serverPack = response[@"data"];
            STKStickerPackObject *object = [weakSelf.serializer serializeStickerPack:serverPack];
            //TODO:Refactoring
            if (![self isPackSaved:object]) {
                [weakSelf.cacheEntity saveDisabledStickerPack:object];
            }
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(object, NO);
                });
            }
        } failure:^(NSError *error) {
            
        }];
    } else {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(stickerPackObject, YES);
            });
        }
    }

}

- (void)togglePackDisabling:(STKStickerPackObject *)pack {
    BOOL status = pack.disabled.boolValue;
    pack.disabled = @(!status);
    
    [self.cacheEntity markStickerPack:pack disabled:!status];
    
}

#pragma mark Check save delete

- (BOOL)isPackSaved:(STKStickerPackObject *)stickerPack {
    //TODO: Optimize
    STKStickerPackObject *object = [self.cacheEntity getStickerPackWithPackName:stickerPack.packName];
    if (object) {
        return YES;
    } else {
        return NO;
    }
}

- (void)saveStickerPack:(STKStickerPackObject *)stickerPack {
    [self.cacheEntity saveStickerPacks:@[stickerPack]];
}
- (void)deleteStickerPack:(STKStickerPackObject *)stickerPack {
    [self.cacheEntity deleteStickerPacks:@[stickerPack]];
}

#pragma mark - LastUpdateTime

- (NSTimeInterval)lastUpdateDate {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSTimeInterval lastUpdateDate = [defaults doubleForKey:kLastUpdateIntervalKey];
    return lastUpdateDate;
}

- (void)setLastUpdateDate:(NSTimeInterval) lastUpdateInterval {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:lastUpdateInterval forKey:kLastUpdateIntervalKey];
}

#pragma mark - LastModifiedDate

- (NSTimeInterval)lastModifiedDate {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSTimeInterval timeInterval = [defaults doubleForKey:kLastModifiedDateKey];
    return timeInterval;
}

- (void)setLastModifiedDate:(NSTimeInterval)lastModifiedDate {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:lastModifiedDate forKey:kLastModifiedDateKey];
}

@end
