//
//  TBMLogger.m
//  FileTransferPlay
//
//  Created by Farhad on 6/23/14.
//  Copyright (c) 2014 NoPlanBees. All rights reserved.
//

#import "TBMLogger.h"

// Why a separate class for logger?
// So we can conigure and implement its functionality  - for example, we could write to a log file that we download ourselves, or
// we can pop up the error message as a main thread Alert, or any of a number of other things
@implementation TBMLogger

+(instancetype) instance
{
    static TBMLogger * instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TBMLogger alloc] init];
    });
    return instance;
}

-(void) error: (NSString *) error
{
    NSLog(@"**** ERROR: %@",error);
}

-(void) warn: (NSString *) message
{
    NSLog(@"## WARN: %@",message);
}


-(void) info: (NSString *) message
{
    NSLog(@"INFO: %@",message);
}

-(void) debug: (NSString *) message
{
    NSLog(@"DEBUG: %@",message);
}

@end
