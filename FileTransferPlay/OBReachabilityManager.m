//
//  OBReachability.m
//  FileTransferPlay
//
//  Created by Farhad on 7/25/14.
//  Copyright (c) 2014 NoPlanBees. All rights reserved.
//

#import "OBReachabilityManager.h"

// This is just a simple wrapper around Tony Million's Reachability class, per tutsplus tutorial
@implementation OBReachabilityManager

#pragma mark -
#pragma mark Default Manager

+ (instancetype)instance {
    static OBReachabilityManager *_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[self alloc] init];
    });
    
    return _instance;
}

#pragma mark -
#pragma mark Memory Management
- (void)dealloc {
    // Stop Notifier
    if (_reachability) {
        [_reachability stopNotifier];
    }
}

#pragma mark -
#pragma mark Class Methods
+ (BOOL)isReachable {
    return [[[OBReachabilityManager instance] reachability] isReachable];
}

+ (BOOL)isUnreachable {
    return ![[[OBReachabilityManager instance] reachability] isReachable];
}

+ (BOOL)isReachableViaWWAN {
    return [[[OBReachabilityManager instance] reachability] isReachableViaWWAN];
}

+ (BOOL)isReachableViaWiFi {
    return [[[OBReachabilityManager instance] reachability] isReachableViaWiFi];
}

#pragma mark -
#pragma mark Private Initialization
- (id)init {
    self = [super init];
    
    if (self) {
//        // Initialize Reachability with a site that is always available
//        Since the reachability API doesn't actually reach that site, just checks to see if it reachable
//        this should be good enough
        self.reachability = [Reachability reachabilityWithHostname:@"www.google.com"];
        
        // Start Monitoring
//         this will generate a notification that you can subscribe to via:
//        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachability handling name) name:kReachabilityChangedNotification object:nil];

        [self.reachability startNotifier];
    }
    
    return self;
}

@end
