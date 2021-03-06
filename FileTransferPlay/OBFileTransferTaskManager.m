//
//  OBFileTransferTaskManager.m
//  FileTransferPlay
//
//  Created by Farhad on 7/28/14.
//  Copyright (c) 2014 NoPlanBees. All rights reserved.
//

#import "OBFileTransferTaskManager.h"
#import "OBLogger.h"

@interface OBFileTransferTaskManager()
@property (nonatomic,strong) NSString * statePlistFile;
@property (nonatomic,strong) NSMutableArray *  tasks;
@end

@implementation OBFileTransferTaskManager

// Stop tracking all tasks
-(void) reset
{
    [self.tasks removeAllObjects];
}

// Warning: do not provide the same nsTask with a different marker, or vice versa
-(OBFileTransferTask *) trackUploadTo: (NSString *)remoteUrl fromFilePath:(NSString *)filePath withMarker:(NSString *)marker withParams: (NSDictionary *)params
{
    OBFileTransferTask * obTask = [[OBFileTransferTask alloc] init];
    if ( obTask != nil ) {
        obTask.marker = marker;
        obTask.typeUpload = YES;
        obTask.localFilePath = filePath;
        obTask.remoteUrl = remoteUrl;
        obTask.status = FileTransferInProgress;
        obTask.params = params;
    }
    [self removeTaskWithMarker:marker];
    [self addTask: obTask];
    return obTask;
}

-(OBFileTransferTask *) trackDownloadFrom: (NSString *)remoteUrl toFilePath:(NSString *)filePath withMarker: (NSString *)marker withParams: (NSDictionary *)params
{
    OBFileTransferTask * obTask = [[OBFileTransferTask alloc] init];
    if ( obTask != nil ) {
        obTask.marker = marker;
        obTask.typeUpload = NO;
        obTask.localFilePath = filePath;
        obTask.remoteUrl = remoteUrl;
        obTask.status = FileTransferInProgress;
        obTask.params = params;
    }
    [self removeTaskWithMarker:marker];
    [self addTask: obTask];
    return obTask;
}

-(NSArray *) currentState
{
    NSMutableArray *taskStates = [NSMutableArray new];
    for ( OBFileTransferTask * task in [self tasks] ) {
        [taskStates addObject:task.stateSummary];
    }
    return taskStates;
}

-(NSArray *)pendingTasks
{
    NSMutableArray *pending = [NSMutableArray new];
    for ( OBFileTransferTask * task in [self tasks] ) {
        if ( task.status == FileTransferPendingRetry )
            [pending addObject:task];
    }
    return pending;
}

-(void) queueForRetry: (OBFileTransferTask *) obTask
{
    obTask.status = FileTransferPendingRetry;
    [self saveState];
}

-(void) processing: (OBFileTransferTask *) obTask withNsTask: (NSURLSessionTask *) nsTask
{
    obTask.status = FileTransferInProgress;
    obTask.attemptCount++;
    obTask.nsTaskIdentifier = nsTask.taskIdentifier;
    OB_INFO(@"Started %@",obTask.description);
    [self saveState];
}

// Finds a task whichhas the nsTask provided in the argument and returns its marker
-(NSString *)markerForNSTask:(NSURLSessionTask *)nsTask
{
    return [[self transferTaskForNSTask: nsTask] marker];
}

// We can remove a given task form the list of tasks that are being tracked
-(void) removeTransferTaskForNsTask:(NSURLSessionTask *)nsTask
{
    [self removeTask:[self transferTaskForNSTask:nsTask]];
}

// Removes a task with the indicated marker value
-(void) removeTaskWithMarker: (NSString *)marker
{
    [self removeTask: [self transferTaskWithMarker:marker]];
}

// Private

-(NSMutableArray *)tasks
{
    if ( _tasks == nil )
        _tasks = [[NSMutableArray alloc] init];
    return _tasks;
}


-(OBFileTransferTask *) transferTaskForNSTask:(NSURLSessionTask *)nsTask
{
    for ( OBFileTransferTask * task in [self tasks] ) {
        if ( task.nsTaskIdentifier == nsTask.taskIdentifier )
            return task;
    }
    return nil;
}

-(OBFileTransferTask *) transferTaskWithMarker:(NSString *)marker
{
    for ( OBFileTransferTask * task in [self tasks] ) {
        if ( [task.marker isEqualToString:marker] )
            return task;
    }
    return nil;
}

-(void) addTask: (OBFileTransferTask *) task
{
    [[self tasks] addObject:task];
    [self saveState];
}

-(void) removeTask: (OBFileTransferTask *) task
{
    if ( task != nil ) {
        [[self tasks] removeObject:task];
        [self saveState];
    }
}

// Save and restore the current state of the tasks
-(void) saveState
{
    NSMutableArray *tasksToSave = [[NSMutableArray alloc] init];
    for ( OBFileTransferTask *task in self.tasks ) {
        [tasksToSave addObject:[task asDictionary]];
    }
    NSDictionary *stateDictionary = @{@"tasks": tasksToSave};
    BOOL wroteToFile = [stateDictionary writeToFile:self.statePlistFile atomically:YES];
    if ( !wroteToFile ) {
        OB_ERROR(@"Could not write save tasks to %@",self.statePlistFile);
    }
}

-(void) restoreState
{
    NSDictionary *stateDictionary;
    [self.tasks removeAllObjects];
    if ( ![[NSFileManager defaultManager] fileExistsAtPath:self.statePlistFile] ) {
        [self saveState];
    } else {
        stateDictionary = [[NSMutableDictionary alloc] initWithContentsOfFile:self.statePlistFile];
    }
    for ( NSDictionary *taskInfo in stateDictionary[@"tasks"] ) {
        [self.tasks addObject:[[OBFileTransferTask alloc] initFromDictionary:taskInfo]];
    }
}

-(NSString *) statePlistFile
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory ,NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        _statePlistFile = [documentsDirectory stringByAppendingPathComponent:@"FileTransferTaskManager.plist"];
        NSLog(@"FileTransferTaskManager Plist File = %@", _statePlistFile);
    });
    return _statePlistFile;
}

@end

