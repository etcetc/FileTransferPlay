//
//  OBFileTransferTaskManager.h
//  FileTransferPlay
//
//  Created by Farhad on 7/28/14.
//  Copyright (c) 2014 NoPlanBees. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "OBFileTransferTask.h"

@interface OBFileTransferTaskManager : NSObject

-(OBFileTransferTask *) trackUploadTo: (NSString *)remoteUrl fromFilePath:(NSString *)filePath withMarker:(NSString *)marker withParams: (NSDictionary *)params;
-(OBFileTransferTask *) trackDownloadFrom: (NSString *)remoteUrl toFilePath:(NSString *)filePath withMarker: (NSString *)marker withParams: (NSDictionary *)params;

-(NSString *) markerForNSTask:(NSURLSessionTask *)task;
-(OBFileTransferTask *) transferTaskForNSTask: (NSURLSessionTask *)task;
-(OBFileTransferTask *) transferTaskWithMarker:(NSString *)marker;
-(void) removeTransferTaskForNsTask:(NSURLSessionTask *)nsTask;

-(void) queueForRetry: (OBFileTransferTask *) obTask;
-(void) processing: (OBFileTransferTask *) obTask withNsTask: (NSURLSessionTask *) nsTask;

-(void) reset;
-(void) restoreState;

-(NSArray *) currentState;
-(NSArray *) pendingTasks;

@end
