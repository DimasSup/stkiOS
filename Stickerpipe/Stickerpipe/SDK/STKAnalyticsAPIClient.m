//
//  STKAnalyticsAPIClient.m
//  StickerFactory
//
//  Created by Vadim Degterev on 30.06.15.
//  Copyright (c) 2015 908 Inc. All rights reserved.
//

#import "STKAnalyticsAPIClient.h"
#import <AFNetworking/AFNetworking.h>
#import "STKStatistic.h"
#import "STKUtility.h"
#import "STKUUIDManager.h"
#import "STKApiKeyManager.h"

static NSString * const statisticUrl = @"statistics";

@implementation STKAnalyticsAPIClient

- (instancetype)init {
    
    self = [super init];
    if (self) {
        [self.sessionManager.requestSerializer setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    return self;
}

- (void)sendStatistics:(NSArray *)statisticsArray success:(void (^)(id))success failure:(void (^)(NSError *))failure {
    
    NSMutableArray *array = [NSMutableArray array];
    
    for (STKStatistic *statistic in statisticsArray) {
        [array addObject:[statistic dictionary]];
    }
    
    if (array.count > 0) {
        [self.sessionManager POST:statisticUrl parameters:array success:^(NSURLSessionDataTask *task, id responseObject) {
            if (success) {
                success(responseObject);
            }
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            //                    NSData *errorData = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
            //                    NSDictionary *serializedData = [NSJSONSerialization JSONObjectWithData: errorData options:kNilOptions error:nil];
            
            if (failure) {
                failure(error);
            }
        }];
    }
}

@end
