//
//  OBLogger.h
//  FileTransferPlay
//
//  Created by Farhad on 6/23/14.
//  Copyright (c) 2014 NoPlanBees. All rights reserved.
//


#import <Foundation/Foundation.h>

// Define some macros

#ifndef OB_ERROR
#define OB_ERROR(message,...) [[OBLogger instance] error:[NSString stringWithFormat:(message),##__VA_ARGS__]]
#endif

#ifndef OB_WARN
#define OB_WARN(message,...) [[OBLogger instance] warn:[NSString stringWithFormat:(message),##__VA_ARGS__]]
#endif

#ifndef OB_INFO
#define OB_INFO(message,...) [[OBLogger instance] info:[NSString stringWithFormat:(message),##__VA_ARGS__]]
#endif

#ifndef OB_DEBUG
#define OB_DEBUG(message,...) [[OBLogger instance] debug:[NSString stringWithFormat:(message),##__VA_ARGS__]]
#endif

@interface OBLogger : NSObject

+(instancetype) instance;

-(void) error: (NSString *) error;
-(void) warn: (NSString *) error;
-(void) info: (NSString *) error;
-(void) debug: (NSString *) error;

@end

