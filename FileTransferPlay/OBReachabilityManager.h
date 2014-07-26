//
//  OBReachability.h
//  FileTransferPlay
//
//  Created by Farhad on 7/25/14.
//  Copyright (c) 2014 NoPlanBees. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Reachability.h"

@interface OBReachabilityManager : NSObject

@property (strong, nonatomic) Reachability *reachability;

#pragma mark -
#pragma mark Shared Manager

+ (OBReachabilityManager *)instance;

#pragma mark -
#pragma mark Class Methods
+ (BOOL)isReachable;
+ (BOOL)isUnreachable;
+ (BOOL)isReachableViaWWAN;
+ (BOOL)isReachableViaWiFi;

@end
