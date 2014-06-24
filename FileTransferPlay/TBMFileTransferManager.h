//
//  TBMFileTransferManager.h
//  FileTransferPlay
//
//  Created by Farhad on 6/20/14.
//  Copyright (c) 2014 NoPlanBees. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol TBMFileTransferDelegate <NSObject>

-(void) fileTransferCompleted: (NSString *)markerId withError: (NSError *)error;
-(void) fileTransferProgress: (NSString *)markerId percent: (NSUInteger) progress;
-(void) fileTransferRetrying: (NSString *)markerId withError: (NSError *)error;

@optional
-(void) transferProgress: (float) progress withMarker:(NSString *)markerId;

@end

@interface TBMFileTransferManager : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate>

@property (nonatomic,strong) NSString * uploadDirectory;
@property (nonatomic,strong) NSString * downloadDirectory;
@property (nonatomic,strong) id<TBMFileTransferDelegate> delegate;

+(TBMFileTransferManager *) instance;

- (void) uploadFile:(NSString *)filePath as:(NSString *)filePathOnS3 withMarker: (NSString *)markerId;
- (void) downloadFile:(NSString *)filePathOnS3 to:(NSString *)filePath withMarker: (NSString *)markerId;


@end
