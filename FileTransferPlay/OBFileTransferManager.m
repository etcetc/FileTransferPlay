//
//  OBFileTransferManager.m
//  How to use this framework
//
//  The FileTransferManager can be handed the responsibility of sending a file.  It will attempt to do so in the background.  If there is no connectivity
//  or the transfer doesn't complete, it will queue it for retry and test again when there is connectivity.
//  The File TransferManager can support multiple targets (currently 2: standard upload to a server, or Amazon S3 using the Token Vending Machine model).
//
//  TODO: AmazonClientManager should really be passed along to this - right now it's hardcoded
//  Usage:
//    OBFileTransferManager ftm = [OBFileTransferManager instance]
//    [ftm uploadFile: someFilePathString to:remoteUrlString withMarker:markerString
//
//  Created by Farhad on 6/20/14.
//  Copyright (c) 2014 No Plan B. All rights reserved.
//

#import "OBFileTransferManager.h"
#import "OBAppDelegate.h"
#import "OBLogger.h"
#import "OBServerFileTransferAgent.h"
#import "OBFileTransferTaskManager.h"

// *********************************
// The File Transfer Manager
// *********************************

@interface OBFileTransferManager()
@property (nonatomic) UIBackgroundTaskIdentifier backgroundTaskIdentifier;
@property (nonatomic,strong) OBFileTransferTaskManager * transferTaskManager;

@end

@implementation OBFileTransferManager

static NSString * const OBFileTransferSessionIdentifier = @"com.onebeat.fileTransferSession";

OBFileTransferTaskManager * _transferTaskManager = nil;

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
// GARF - deprecate - not using a singleton pattern
+(instancetype) instance
{
    static OBFileTransferManager * instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}


//--------------
// Configure
//--------------

// You can set a default uploadDirectory, downloadDirectory, and remoteUrlBase
// Then when you pass any parameter in the upload and download messages, they will be made into fully formed paths.  For the
// directories, if the path for the passed param starts with '/', it is assumed to already be a fully formed path

// Set the download directory, but they may be renamed...
-(void) setDownloadDirectory:(NSString *)downloadDirectory
{
    NSError * error;
    _downloadDirectory = downloadDirectory;
    [[NSFileManager defaultManager] createDirectoryAtPath:downloadDirectory withIntermediateDirectories:YES attributes:nil error:&error];
    if ( error != nil ) {
        OB_ERROR(@"create download directory failed: %@",error.localizedDescription);
    }
}

-(void) setRemoteUrlBase:(NSString *)remoteUrlBase
{
    _remoteUrlBase = remoteUrlBase;
    if ( ![_remoteUrlBase hasSuffix:@"/"] ) {
        _remoteUrlBase = [_remoteUrlBase stringByAppendingString:@"/"];
    }
}

// Initialize the instance. Don't want to call it initialize
-(void) initSession
{
    [self session];
}

// ---------------
// Lazy Instantiators for key helper objects
// ---------------

// The transfer task manager keeps track of ongoing transfers
-(OBFileTransferTaskManager *)transferTaskManager
{
    if ( _transferTaskManager == nil )
        @synchronized(self) {
            _transferTaskManager = [[OBFileTransferTaskManager alloc] init];
            [_transferTaskManager restoreState];
        }
    return _transferTaskManager;
}

// ---------------
// Session methods
// ---------------

/*
 Singleton with unique identifier so our session is matched when our app is relaunched either in foreground or background. From: apple docuementation :: Note: You must create exactly one session per identifier (specified when you create the configuration object). The behavior of multiple sessions sharing the same identifier is undefined.
 */

- (NSURLSession *) session{
    static NSURLSession *backgroundSession = nil;
    static dispatch_once_t once;
    //    Create a single session and make it be thread-safe
    dispatch_once(&once, ^{
        OB_INFO(@"Creating a %@ URLSession",self.foregroundTransferOnly ? @"foreground" : @"background");
        NSURLSessionConfiguration *configuration = self.foregroundTransferOnly ? [NSURLSessionConfiguration defaultSessionConfiguration] :
            [NSURLSessionConfiguration backgroundSessionConfiguration:OBFileTransferSessionIdentifier];
        configuration.HTTPMaximumConnectionsPerHost = 10;
        backgroundSession = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
        [backgroundSession resetWithCompletionHandler:^{
            OB_DEBUG(@"Reset the session cache");
        }];
        
    });
    return backgroundSession;
}

-(void) printSessionTasks
{
    [[self session] getTasksWithCompletionHandler: ^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        if ( uploadTasks.count == 0 ) {
            OB_DEBUG(@"No Upload tasks");
        } else {
            OB_DEBUG(@"CURRENT UPLOAD TASKS");
            for ( NSURLSessionTask * task in uploadTasks ) {
                OB_DEBUG(@"%@",[[self.transferTaskManager transferTaskForNSTask:task] description]);
            }
        }
        if ( downloadTasks.count == 0 ) {
            OB_DEBUG(@"No Download tasks");
        } else {
            OB_DEBUG(@"CURRENT DOWNLOAD TASKS");
            for ( NSURLSessionTask * task in downloadTasks ) {
                OB_DEBUG(@"%@",[[self.transferTaskManager transferTaskForNSTask:task] description]);
            }
        }
    }];
}

-(void) cancelSessionTasks
{
    OB_DEBUG(@"Canceling session tasks");
    [[self session] getTasksWithCompletionHandler: ^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        if ( uploadTasks.count != 0 ) {
            for ( NSURLSessionTask * task in uploadTasks ) {
                OB_DEBUG(@"Canceling upload task %@",[[self.transferTaskManager transferTaskForNSTask:task] description]);
                [task cancel];
            }
        }
        if ( downloadTasks.count != 0 ) {
            for ( NSURLSessionTask * task in downloadTasks ) {
                OB_DEBUG(@"Canceling download task %@",[[self.transferTaskManager transferTaskForNSTask:task] description]);
                [task cancel];
            }
            
        }
    }];
}

#pragma mark - Main API
// --------------
// Main API
// --------------

// This resets everything by cancelling all tasks and removing them from our task Manager
-(void) reset
{
    [self cancelSessionTasks];
    [self.transferTaskManager reset];
}

// Upload the file at the indicated filePath to the remoteFileUrl (do not include target filename here!).
// Note that the params dictionary contains both parmetesr interpreted by the local transfer agent and those
// that are sent along with the file for uploading.  Local params start with the underscore.  Specifically:
//  FilenameParamKey: contains the uploaded filename. Default: it is pulled from the input filename
//  ContentTypeParamKey: contains the content type to use.  Default: it is extracted from the filename extension.
//  FormFileFieldNameParamKey: contains the field name containing the file. Default: file.
// Note that in some file stores some of these parameters may be meaningless.  For example, for S3, the Amazon API uses its
// own thing - we don't really care about the field name.

- (void) uploadFile:(NSString *)filePath to:(NSString *)remoteFileUrl withMarker:(NSString *)markerId withParams:(NSDictionary *) params
{
    if ( NO ) {
        NSString *fullRemoteUrl = [self fullRemotePath:remoteFileUrl];
        NSString *fullPath =[self normalizeLocalUploadPath:filePath];
        OBFileTransferAgent * fileTransferAgent = [OBFileTransferAgentFactory fileTransferAgentInstance:fullRemoteUrl];
        
        NSMutableURLRequest *request = [fileTransferAgent uploadFileRequest:fullPath to:fullRemoteUrl withParams:params];
        
        //    Now write the request body to a temporary file that we can upload because the background task manager ignores
        //    the request body
        NSError *error;
        NSString * tmpFile = [self temporaryFile:markerId];
        if ( fileTransferAgent.hasEncodedBody )
            [[request HTTPBody] writeToFile:tmpFile atomically:NO];
        else
            [[NSFileManager defaultManager] copyItemAtPath:fullPath toPath:tmpFile error:&error];
        
        if ( error != nil )
            OB_ERROR(@"Unable to copy file to temporary file");
        
        NSURLSessionTask *task = [[self session] uploadTaskWithRequest:request fromFile:[NSURL fileURLWithPath:tmpFile]];
        
        OBFileTransferTask *obTask =[self.transferTaskManager  trackUploadTo:fullRemoteUrl fromFilePath:fullPath withMarker:markerId withParams:params];
        [self.transferTaskManager processing:obTask withNsTask:task];
        [task resume];
    } else {
        [self processTransfer:markerId remote:remoteFileUrl local:filePath params:params upload:YES];
    }


}

// Download the file from the remote URL to the provided filePath.
//
- (void) downloadFile:(NSString *)remoteFileUrl to:(NSString *)filePath withMarker: (NSString *)markerId withParams:(NSDictionary *) params
{
    if ( NO ) {
        NSString *fullRemoteUrl = [self fullRemotePath:remoteFileUrl];
        NSString *fullDownloadPath =[self normalizeLocalDownloadPath:filePath];
        
        OBFileTransferAgent * fileTransferAgent = [OBFileTransferAgentFactory fileTransferAgentInstance:fullRemoteUrl];
        
        NSMutableURLRequest *request = [fileTransferAgent downloadFileRequest:fullRemoteUrl withParams:params];
        NSURLSessionTask *task = [[self session] downloadTaskWithRequest:request];
        
        OBFileTransferTask *obTask = [self.transferTaskManager  trackDownloadFrom:remoteFileUrl toFilePath:fullDownloadPath withMarker:markerId withParams:params];
        [self.transferTaskManager processing:obTask withNsTask:task];
        [task resume];
    } else {
        [self processTransfer:markerId remote:remoteFileUrl local:filePath params:params upload:NO];
    }
    
}

-(NSArray *) currentState
{
    return [self.transferTaskManager currentState];
}

-(NSString *) pendingSummary
{
    NSInteger uploads=0,downloads=0;
    for ( OBFileTransferTask * task in [self.transferTaskManager pendingTasks] ) {
        if ( task.typeUpload) uploads++; else downloads++;
    }
    return [NSString stringWithFormat:@"%d up, %d down",uploads,downloads];
}

// Return the state for the indicated marker
-(NSDictionary *) stateForMarker: (NSString *)marker
{
    return [[self.transferTaskManager transferTaskWithMarker:marker] stateSummary];
}

// Retry all pending transfers
-(void) retryPending
{
    for ( OBFileTransferTask * obTask in [self.transferTaskManager pendingTasks] ) {
        NSURLSessionTask * task = [self createNsTaskFromObTask: obTask];
        [self.transferTaskManager processing:obTask withNsTask:task];
        [task resume];
    }
}


-(void) processTransfer: (NSString *)marker remote: (NSString *)remoteFileUrl local:(NSString *)filePath params:(NSDictionary *)params upload:(BOOL) upload
{
    NSString *fullRemoteUrl = [self fullRemotePath:remoteFileUrl];
    NSString *localFilePath;

    OBFileTransferTask *obTask;
    if ( upload ) {
        localFilePath = [self normalizeLocalUploadPath:filePath];
        obTask = [self.transferTaskManager trackUploadTo:fullRemoteUrl fromFilePath:localFilePath withMarker:marker withParams:params];
    } else {
        localFilePath = [self normalizeLocalDownloadPath:filePath];
        obTask = [self.transferTaskManager trackDownloadFrom:fullRemoteUrl toFilePath:localFilePath withMarker:marker withParams:params];
    }
    
    NSURLSessionTask *task = [self createNsTaskFromObTask:obTask];
    [self.transferTaskManager processing:obTask withNsTask:task];
    [task resume];
}

#pragma mark - Delegates

// --------------
// Delegate Functions
// --------------

// ------
// Security for Testing w/ Charles (to track info going up and down)
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
// Upload & Download Completion Handling
// ------

// TODO: make max attempts a configuration parameter
#define MAX_ATTEMPTS 5

// NOTE::: This gets called for upload and download when the task is complete, possibly w/ framework or server error (server error has bad response code)
- (void) URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    OBFileTransferTask * obtask = [[self transferTaskManager] transferTaskForNSTask:task];
    NSString *marker = obtask.marker;
    NSHTTPURLResponse *response =   (NSHTTPURLResponse *)task.response;
    //    OB_DEBUG(@"File transfer %@ response = %@",marker, response);
    if ( task.state == NSURLSessionTaskStateCompleted ) {
        //        We'll consider any of the 200 codes to be a success
        if ( response.statusCode/100 == 2  ) {
            //            We actually get this one when the internet is shut off in the middle of a download
            if ( obtask.typeUpload ) {
                NSError * error;
                [[NSFileManager defaultManager] removeItemAtPath:[self temporaryFile:marker] error:&error];
                if ( error != nil ) {
                    OB_ERROR(@"Unable to delete file %@: %@",[self temporaryFile:marker],error.localizedDescription);
                }
                OB_INFO(@"%@ File transfer for %@ done and tmp file deleted",obtask.typeUpload ? @"Upload" : @"Download", marker);
            }
        } else {
            //            We get this when internet is shut off in middle of upload
            error = [self createErrorFromBadHttpResponse:response.statusCode];
            OB_ERROR(@"%@ File Transfer for %@ received status code %ld and error %@",obtask.typeUpload ? @"Upload" : @"Download", marker,(long)response.statusCode, error.localizedDescription);
        }
        if ( error == nil || obtask.attemptCount >= MAX_ATTEMPTS ) {
            [[self transferTaskManager] removeTransferTaskForNsTask:task];
            [self.delegate fileTransferCompleted:marker withError:error];
        } else {
            [[self transferTaskManager] queueForRetry:obtask];
            [self.delegate fileTransferRetrying:marker withError:error];
        }
    } else {
        OB_WARN(@"Indicated that task completed but state = %d", (int) task.state );
    }
}


// ------
// Upload
// ------

- (void) URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
    NSString *marker = [[self transferTaskManager] markerForNSTask:task];
    NSUInteger percentDone = (NSUInteger)(100*totalBytesSent/totalBytesExpectedToSend);
    OB_DEBUG(@"Upload progress %@: %lu%% [sent:%llu, of:%llu]", marker, (unsigned long)percentDone, totalBytesSent, totalBytesExpectedToSend);
    if ( [self.delegate respondsToSelector:@selector(fileTransferProgress:percent:)] ) {
        NSString *marker = [[self transferTaskManager] markerForNSTask:task];
        [self.delegate fileTransferProgress: marker percent:percentDone];
    }
}

// --------
// Download
// --------

// Download progress
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    NSString *marker = [[self transferTaskManager] markerForNSTask:task];
    NSUInteger percentDone = (NSUInteger)(100*totalBytesWritten/totalBytesExpectedToWrite);
    OB_DEBUG(@"Download progress %@: %lu%% [sent:%llu, of:%llu]", marker, (unsigned long)percentDone, totalBytesWritten, totalBytesExpectedToWrite);
    if ( [self.delegate respondsToSelector:@selector(fileTransferProgress:percent:)] ) {
        NSString *marker = [[self transferTaskManager] markerForNSTask:task];
        [self.delegate fileTransferProgress: marker percent:percentDone];
    }
}

// Completed the download
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location
{
    NSString *marker = [[self transferTaskManager] markerForNSTask:downloadTask];
    OB_INFO(@"Download of %@ completed",marker);
    NSHTTPURLResponse *response =   (NSHTTPURLResponse *)downloadTask.response;
    if ( response.statusCode/100 == 2   ) {
        //        Now we need to copy the file to our downloads location...
        NSError * error;
        NSString *localFilePath = [[[self transferTaskManager] transferTaskForNSTask: downloadTask] localFilePath];
        
//        If the file already exists, remove it and overwrite it
        if ( [[NSFileManager defaultManager] fileExistsAtPath:localFilePath] ) {
            [[NSFileManager defaultManager] removeItemAtPath:localFilePath error:&error];
        }
        
        [[NSFileManager defaultManager] copyItemAtPath:location.path toPath:localFilePath  error:&error];
        if ( error != nil )
            OB_ERROR(@"Unable to copy downloaded file to %@ with error: %@",localFilePath,error.localizedDescription);
    } else {
        OB_ERROR(@"Download for %@ received status code %ld",marker,(long)response.statusCode);
    }
}

// Resumed the download
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didResumeAtOffset:(int64_t)fileOffset expectedTotalBytes:(int64_t)expectedTotalBytes
{
    OB_WARN(@" Got download resume but haven't implemented it yet!");
}


// -------
// Session
// -------
/*
 If an application has received an -application:handleEventsForBackgroundURLSession:completionHandler: message, the session delegate will receive this message to indicate that all messages previously enqueued for this session have been delivered. We need to process all the completed tasks update the ui accordingly and invoke the completion handler so the os can take a picture of our app.
 */
- (void) URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session{
    if ([session.configuration.identifier isEqualToString:OBFileTransferSessionIdentifier]){
        
        OBAppDelegate *appDelegate = [[UIApplication sharedApplication] delegate];
        appDelegate.backgroundSessionCompletionHandler();
        appDelegate.backgroundSessionCompletionHandler = nil;
        DebugLog(@"Flushing session %@.", [self session].configuration.identifier);
        [[self session] flushWithCompletionHandler:^{
            DebugLog(@"Flushed session should be using new socket.");
        }];
    }
}

#pragma mark - Private utility 

// -------
// Private
// -------

-(NSString* )normalizeLocalDownloadPath: (NSString * )filePath
{
    if ( _downloadDirectory == nil || [filePath characterAtIndex:0] == '/')
        return filePath;
    else
        return [NSString pathWithComponents:@[_downloadDirectory,filePath ]];
}

-(NSString *) normalizeLocalUploadPath: (NSString *)filePath
{
    if ( _uploadDirectory == nil || [filePath characterAtIndex:0] == '/' )
        return filePath;
    else
        return [NSString pathWithComponents:@[_uploadDirectory,filePath ]];
}

-(NSString *) fullRemotePath: (NSString *)remotePath
{
    if ( remotePath == nil ) remotePath = @"";
    if ( self.remoteUrlBase == nil || [remotePath rangeOfString:@"://"].location != NSNotFound )
        return remotePath;
    else {
        if ( [remotePath hasPrefix:@"/"] )
            remotePath = [remotePath substringFromIndex:1];
    }
    return [self.remoteUrlBase stringByAppendingString:remotePath];
}

-(NSString *) tempDirectory
{
    static NSString * _tempDirectory;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        //    Get a temporary directory
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        if ([paths count]) {
            NSString *bundleName =[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
            _tempDirectory = [[paths objectAtIndex:0] stringByAppendingPathComponent:bundleName];
        }
    });
    return _tempDirectory;
}

-(NSString *) temporaryFile: (NSString *)marker
{
    return [[self tempDirectory] stringByAppendingPathComponent:marker];
}

-(NSError *) createErrorFromBadHttpResponse:(NSInteger) responseCode
{
    NSString *description  = [NSHTTPURLResponse localizedStringForStatusCode:responseCode];
    NSString *bundleName =  [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
    return [NSError errorWithDomain:bundleName code:FileManageErrorBadHttpResponse userInfo:@{NSLocalizedDescriptionKey: description}];
}

-(NSURLSessionTask *) createNsTaskFromObTask: (OBFileTransferTask *) obTask
{
    NSURLSessionTask *task;
    OBFileTransferAgent * fileTransferAgent = [OBFileTransferAgentFactory fileTransferAgentInstance:obTask.remoteUrl];
    
    if ( obTask.typeUpload ) {
        
        NSMutableURLRequest *request = [fileTransferAgent uploadFileRequest:obTask.localFilePath to:obTask.remoteUrl withParams:obTask.params];
        NSError *error;
        NSString * tmpFile = [self temporaryFile:obTask.marker];
        if ( fileTransferAgent.hasEncodedBody )
            [[request HTTPBody] writeToFile:tmpFile atomically:NO];
        else
            [[NSFileManager defaultManager] copyItemAtPath:obTask.localFilePath toPath:tmpFile error:&error];
        
        if ( error != nil )
            OB_ERROR(@"Unable to copy file to temporary file");
        
        task = [[self session] uploadTaskWithRequest:request fromFile:[NSURL fileURLWithPath:tmpFile]];
        
    } else {
        NSMutableURLRequest *request = [fileTransferAgent downloadFileRequest:obTask.remoteUrl withParams:obTask.params];
        task = [[self session] downloadTaskWithRequest:request];
    }
    return task;
}

@end
