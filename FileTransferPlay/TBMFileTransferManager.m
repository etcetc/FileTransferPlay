//
//  TBMFileTransferManager.m
//  tbm
//
//  Created by Farhad on 6/20/14.
//  Copyright (c) 2014 No Plan B. All rights reserved.
//

#import "TBMFileTransferManager.h"
#import "AmazonClientManager.h"
#import "TBMAppDelegate.h"
#import "TBMLogger.h"

static NSString * const TBMFileTransferSessionIdentifier = @"com.noplanbees.tbm.fileTransferSession";

@interface TBMFileTransferTask : NSObject
@property (nonatomic) BOOL typeUpload;
@property (nonatomic) BOOL retrying;
@property (nonatomic,strong) NSURLSessionTask *nsTask;
@property (nonatomic,strong) NSString *marker;
@property (nonatomic,strong) NSString *filePath;

@end

@implementation TBMFileTransferTask

@end

@interface TBMFileTransferTaskTracker: NSObject

-(void) trackUploadNSTask: (NSURLSessionTask *) task withMarker: (NSString *)marker;
-(void) trackDownloadNSTask: (NSURLSessionTask *) task withMarker: (NSString *)marker toFilePath: (NSString *)filePath;
-(NSString *) markerForNSTask:(NSURLSessionTask *)task;
-(NSString *) filePathForNSTask:(NSURLSessionTask *)task;

@end

@implementation TBMFileTransferTaskTracker

static NSMutableArray * _tasks;

// Warning: do not provide the same nsTask with a different marker, or vice versa
-(void) trackUploadNSTask: (NSURLSessionTask *) nsTask withMarker: (NSString *)marker
{
    TBMFileTransferTask * instance = [[TBMFileTransferTask alloc] init];
    if ( instance != nil ) {
        instance.marker = marker;
        instance.nsTask = nsTask;
        instance.typeUpload = YES;
    }
    [self removeTaskWithMarker:marker];
    [self addTask: instance];
}

-(void) trackDownloadNSTask: (NSURLSessionTask *) nsTask withMarker: (NSString *)marker toFilePath:(NSString *)filePath
{
    TBMFileTransferTask * instance = [[TBMFileTransferTask alloc] init];
    if ( instance != nil ) {
        instance.marker = marker;
        instance.nsTask = nsTask;
        instance.typeUpload = NO;
        instance.filePath = filePath;
    }
    [self removeTaskWithMarker:marker];
    
    [self addTask: instance];
}

// Finds a task whichhas the nsTask provided in the argument and returns its marker
-(NSString *)markerForNSTask:(NSURLSessionTask *)nsTask
{
    TBMFileTransferTask * task = [self findNSTask: nsTask];
    if ( task != nil )
        return task.marker;
    else
        return nil;
}

-(NSString *)filePathForNSTask:(NSURLSessionTask *)nsTask
{
    return [[self findNSTask: nsTask] filePath];
}

// We can remove a given task form the list of tasks that are being tracked
-(void) removeNsTask:(NSURLSessionTask *)nsTask
{
    [self removeTask:[self findNSTask:nsTask]];
}

// Removes a task with the indicated marker value
-(void) removeTaskWithMarker: (NSString *)marker
{
    [self removeTask: [self findNSTaskWithMarker:marker]];
}

// Private

-(NSMutableArray *)tasks
{
    if ( _tasks == nil )
        _tasks = [[NSMutableArray alloc] init];
    return _tasks;
}


-(TBMFileTransferTask *) findNSTask:(NSURLSessionTask *)nsTask
{
    for ( TBMFileTransferTask * task in [self tasks] ) {
        if ( task.nsTask.taskIdentifier == nsTask.taskIdentifier )
            return task;
    }
    return nil;
}

-(TBMFileTransferTask *) findNSTaskWithMarker:(NSString *)marker
{
    for ( TBMFileTransferTask * task in [self tasks] ) {
        if ( [task.marker isEqualToString:marker] )
            return task;
    }
    return nil;
}

-(void) addTask: (TBMFileTransferTask *) task
{
    [[self tasks] addObject:task];
}

-(void) removeTask: (TBMFileTransferTask *) task
{
    [[self tasks] removeObject:task];
}
@end

@interface TBMFileTransferManager()
@property (nonatomic) UIBackgroundTaskIdentifier backgroundTaskIdentifier;
@end

@implementation TBMFileTransferManager

TBMFileTransferTaskTracker * _transferTaskTracker = nil;

static NSString * _uploadDirectory ;
static NSString * _downloadDirectory ;

//--------------
// Configure
//--------------

// Set the download directory.  Files are downloaded to this directory
-(void) setDownloadDirectory:(NSString *)downloadDirectory
{
    NSError * error;
    _downloadDirectory = downloadDirectory;
    [[NSFileManager defaultManager] createDirectoryAtPath:downloadDirectory withIntermediateDirectories:YES attributes:nil error:&error];
    if ( error != nil ) {
        TBM_ERROR(@"create download directory failed: %@",error.localizedDescription);
    }
}

//--------------
// Instantiation
//--------------

- (instancetype)init{
    self = [super init];
    if (self){
        _backgroundTaskIdentifier = UIBackgroundTaskInvalid;
    }
    return self;
}


// Right now we just return a single instance but in the future I could return multiple instances
// if I want to have different delegates for each
+(instancetype) instance
{
    static TBMFileTransferManager * instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

// ---------------
// Task Tracker
// ---------------

-(TBMFileTransferTaskTracker *)transferTaskTracker
{
    if ( _transferTaskTracker == nil )
        _transferTaskTracker = [[TBMFileTransferTaskTracker alloc] init];
    return _transferTaskTracker;
}

// ---------------
// Session methods
// ---------------

#define FOREGROUND_TRANSFER_ONLY 0
/*
 Singleton with unique identifier so our session is matched when our app is relaunched either in foreground or background. From: apple docuementation :: Note: You must create exactly one session per identifier (specified when you create the configuration object). The behavior of multiple sessions sharing the same identifier is undefined.
 */

- (NSURLSession *) session{
    static NSURLSession *backgroundSession = nil;
    static dispatch_once_t once;
    //    Create a single session and make it be thread-safe
    dispatch_once(&once, ^{
#if FOREGROUND_TRANSFER_ONLY
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
#else
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration backgroundSessionConfiguration:TBMFileTransferSessionIdentifier];
#endif
        configuration.HTTPMaximumConnectionsPerHost = 10;
        backgroundSession = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
        [backgroundSession resetWithCompletionHandler:^{
            TBM_INFO(@"Reset the session cache");
        }];
        
    });
    return backgroundSession;
}

- (void) uploadFile:(NSString *)filePath as:(NSString *)filePathOnS3 withMarker: (NSString *)markerId
{
    S3PutObjectRequest * putRequest = [[S3PutObjectRequest alloc] initWithKey:filePathOnS3 inBucket:@"tbm_videos"];
    if ( NO ) {
        putRequest.contentType = @"image/jpeg";
        putRequest.data = [NSData dataWithContentsOfFile:filePath];
        TBM_INFO(@"Native S3 SDK uploading %@ file %@ to %@",markerId, filePath,filePathOnS3);
        @try {
            [[AmazonClientManager s3] putObject:putRequest];
        }
        @catch (AmazonClientException *exception) {
            TBM_ERROR(@"Received Amazon exception: %@",exception);
        }
    } else {
        TBM_INFO(@"Standard Session Task uploading %@ file %@ to %@ ",markerId, filePath,filePathOnS3);
        putRequest.filename = filePath;
        putRequest.endpoint =[AmazonClientManager s3].endpoint;
        [putRequest setSecurityToken:[AmazonClientManager securityToken]];
        putRequest.contentType = @"image/jpeg";
        NSMutableURLRequest *request = [[AmazonClientManager s3] signS3Request:putRequest];
        
        //    We have to copy over because request is actually a sublass of NSMutableREquest and can cause problems
        NSMutableURLRequest* request2 = [[NSMutableURLRequest alloc]initWithURL:request.URL];
        [request2 setHTTPMethod:request.HTTPMethod];
        [request2 setAllHTTPHeaderFields:[request allHTTPHeaderFields]];
        
        NSURLSessionTask *task = [[self session] uploadTaskWithRequest:request2 fromFile:[NSURL fileURLWithPath:[self normalizeUploadPath:filePath]]];
        [self.transferTaskTracker trackUploadNSTask:task withMarker:markerId];
        [task resume];
    }

}

- (void) downloadFile:(NSString *)filePathOnS3 to:(NSString *)filePath withMarker: (NSString *)markerId
{
    S3GetObjectRequest * getRequest = [[S3GetObjectRequest alloc] initWithKey:filePathOnS3 withBucket:@"tbm_videos"];
    if ( NO ) {
        TBM_INFO(@"Native S3 SDK downloading %@ file %@ from %@",markerId, filePath,filePathOnS3);
        @try {
            S3GetObjectResponse * response = [[AmazonClientManager s3] getObject:getRequest];
            if ( response.error == nil ) {
                if ( response.body != nil ) {
                    NSData * data = response.body;
                    [[NSFileManager defaultManager]createFileAtPath:[[self class ]normalizeDownloadPath: filePath] contents:data attributes:nil];
                } else {
                    TBM_ERROR(@"Downloaded file body for %@ was null", markerId);
                }
            } else {
                TBM_ERROR(@"Error downloading file with marker %@: %@", markerId, response.error.localizedDescription);
            }
        }
        @catch (AmazonClientException *exception) {
            NSLog(@"Received Amazon exception: %@",exception);
        }
    } else {
        TBM_INFO(@"Standard Session Task downloading %@ file %@ from %@ ",markerId, filePath,filePathOnS3);
        getRequest.endpoint =[AmazonClientManager s3].endpoint;
        [getRequest setSecurityToken:[AmazonClientManager securityToken]];
        NSMutableURLRequest *request = [[AmazonClientManager s3] signS3Request:getRequest];
        
        //    We have to copy over because request is actually a sublass of NSMutableREquest and can cause problems
        NSMutableURLRequest* request2 = [[NSMutableURLRequest alloc]initWithURL:request.URL];
        [request2 setHTTPMethod:request.HTTPMethod];
        [request2 setAllHTTPHeaderFields:[request allHTTPHeaderFields]];
        
        NSURLSessionTask *task = [[self session] downloadTaskWithRequest:request2];
                                
        [self.transferTaskTracker trackDownloadNSTask:task withMarker:markerId toFilePath: [self normalizeDownloadPath:filePath]];
        [task resume];
    }
    
}



// --------------
// Delegate Functions
// --------------

// ------
// Security for Testing w/ Charles
// ------

// TODO : Remove these
-(void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler
{
    
    NSLog(@">>>>>Received authentication challenge");
    completionHandler(NSURLSessionAuthChallengeUseCredential,nil);
}

-(void) URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler
{
    
    NSLog(@">>>>>Received task-level authentication challenge");
    completionHandler(NSURLSessionAuthChallengeUseCredential,nil);
    
}

// ------
// Upload
// ------

- (void) URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
    NSString *marker = [[self transferTaskTracker] markerForNSTask:task];
    NSUInteger percentDone = 100*totalBytesSent/totalBytesExpectedToSend;
    TBM_DEBUG(@"Upload progress %@: %lu%% [sent:%llu, of:%llu]", marker, (unsigned long)percentDone, totalBytesSent, totalBytesExpectedToSend);
    if ( [self.delegate respondsToSelector:@selector(fileTransferProgress:percent:)] ) {
        NSString *marker = [[self transferTaskTracker] markerForNSTask:task];
        [self.delegate fileTransferProgress: marker percent:percentDone];
    }
}

- (void) URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    NSString *marker = [[self transferTaskTracker] markerForNSTask:task];
    NSHTTPURLResponse *response =   (NSHTTPURLResponse *)task.response;
//    TBM_DEBUG(@"File transfer %@ response = %@",marker, response);
    if ( task.state == NSURLSessionTaskStateCompleted ) {
        if ( response.statusCode != 200  ) {
            TBM_ERROR(@"File Transfer for %@ received status code %ld",marker,(long)response.statusCode);
        } else {
            [self.delegate fileTransferCompleted:marker withError:error];
        }
    } else {
        TBM_WARN(@"Indicated that task completed but state = %d", task.state );
    }
}

// --------
// Download
// --------
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    NSString *marker = [[self transferTaskTracker] markerForNSTask:task];
    NSUInteger percentDone = 100*totalBytesWritten/totalBytesExpectedToWrite;
    TBM_DEBUG(@"Download progress %@: %lu%% [sent:%llu, of:%llu]", marker, (unsigned long)percentDone, totalBytesWritten, totalBytesExpectedToWrite);
    if ( [self.delegate respondsToSelector:@selector(fileTransferProgress:percent:)] ) {
        NSString *marker = [[self transferTaskTracker] markerForNSTask:task];
        [self.delegate fileTransferProgress: marker percent:percentDone];
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didResumeAtOffset:(int64_t)fileOffset expectedTotalBytes:(int64_t)expectedTotalBytes
{
    //    NOT YET USPPORTED
    DebugLog(@"ERROR: downloadTask didResumeAtOffset. We should not be getting this callback.");
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location
{
    NSString *marker = [[self transferTaskTracker] markerForNSTask:downloadTask];
    TBM_INFO(@"Download of %@ completed",marker);
    NSHTTPURLResponse *response =   (NSHTTPURLResponse *)downloadTask.response;
//    TBM_DEBUG(@"File transfer for %@ response = %@",marker, response);
    if ( response.statusCode != 200  ) {
        TBM_ERROR(@"Download for %@ received status code %ld",marker,(long)response.statusCode);
    } else {
//        Now we need to copy the file to our downloads location...
        NSError * error;
        [[NSFileManager defaultManager] copyItemAtPath:location.path toPath: [[self transferTaskTracker] filePathForNSTask:downloadTask] error:&error];
        
//        This is already called by the method URLSession:task:didCompletewithError: 
//        [self.delegate fileTransferCompleted:marker withError:nil];
    }
}


// -------
// Session
// -------
/*
 If an application has received an -application:handleEventsForBackgroundURLSession:completionHandler: message, the session delegate will receive this message to indicate that all messages previously enqueued for this session have been delivered. We need to process all the completed tasks update the ui accordingly and invoke the completion handler so the os can take a picture of our app.
 */
- (void) URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session{
    if ([session.configuration.identifier isEqualToString:TBMFileTransferSessionIdentifier]){
        
        TBMAppDelegate *appDelegate = [[UIApplication sharedApplication] delegate];
        appDelegate.backgroundSessionCompletionHandler();
        appDelegate.backgroundSessionCompletionHandler = nil;
        DebugLog(@"Flusing session %@.", [self session].configuration.identifier);
        [[self session] flushWithCompletionHandler:^{
            DebugLog(@"Flushed session should be using new socket.");
        }];
    }
}

// -------
// Private
// -------

-(NSString* )normalizeDownloadPath: (NSString * )filePath
{
    return [NSString pathWithComponents:@[_downloadDirectory,filePath ]];
}

-(NSString *) normalizeUploadPath: (NSString *)filePath
{
    if ( [filePath rangeOfString:_uploadDirectory].location != NSNotFound ) {
        return [NSString pathWithComponents:@[_uploadDirectory,filePath ]];
    }
    return filePath;
}

@end
