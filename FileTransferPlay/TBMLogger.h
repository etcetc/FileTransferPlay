//
//  TBMLogger.h
//  FileTransferPlay
//
//  Created by Farhad on 6/23/14.
//  Copyright (c) 2014 NoPlanBees. All rights reserved.
//


#import <Foundation/Foundation.h>

// Define some macros

#ifndef TBM_ERROR
#define TBM_ERROR(message,...) [[TBMLogger instance] error:[NSString stringWithFormat:(message),##__VA_ARGS__]]
#endif

#ifndef TBM_WARN
#define TBM_WARN(message,...) [[TBMLogger instance] warn:[NSString stringWithFormat:(message),##__VA_ARGS__]]
#endif

#ifndef TBM_INFO
#define TBM_INFO(message,...) [[TBMLogger instance] info:[NSString stringWithFormat:(message),##__VA_ARGS__]]
#endif

#ifndef TBM_DEBUG
#define TBM_DEBUG(message,...) [[TBMLogger instance] debug:[NSString stringWithFormat:(message),##__VA_ARGS__]]
#endif

@interface TBMLogger : NSObject

+(instancetype) instance;

-(void) error: (NSString *) error;
-(void) warn: (NSString *) error;
-(void) info: (NSString *) error;
-(void) debug: (NSString *) error;

@end

