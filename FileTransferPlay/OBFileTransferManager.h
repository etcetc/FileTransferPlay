//
//  OBFileTransferManager.h
//  FileTransferPlay
//
//  Created by Farhad on 6/20/14.
//  Copyright (c) 2014 NoPlanBees. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "OBFileTransferAgentFactory.h"

typedef NS_ENUM(NSUInteger, FileManagerErrorCode) {
    FileManageErrorUnknown = -1,
    FileManageErrorBadHttpResponse = 1000,
};

@interface OBFileTransferManager : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate>

@property (nonatomic,strong) NSString * uploadDirectory;
@property (nonatomic,strong) NSString * downloadDirectory;
@property (nonatomic,strong) NSString * remoteUrlBase;
@property (nonatomic,strong) id<OBFileTransferDelegate> delegate;
@property (nonatomic) BOOL foregroundTransferOnly;

@property (nonatomic) OBFileStore fileStore;


+(OBFileTransferManager *) instance;

-(void) initSession;

// Reset the state of all the tasks
-(void) reset;

// Main API
- (void) uploadFile:(NSString *)localFilePath to:(NSString *)remoteUrl withMarker: (NSString *)markerId withParams:(NSDictionary *)params;
- (void) downloadFile:(NSString *)remoteUrl to:(NSString *)localFilePath withMarker: (NSString *)markerId withParams:(NSDictionary *)params;

@end
