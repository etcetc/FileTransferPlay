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

// *********************************
// The File Transfer Tracking Object - ONLY USED INTERNALLY
// *********************************


@interface OBFileTransferTask : NSObject
@property (nonatomic,strong) NSDate * createdOn;
@property (nonatomic) BOOL typeUpload;
@property (nonatomic) NSInteger retryCount;
@property (nonatomic,strong) NSString *marker;
@property (nonatomic,strong) NSString *remoteUrl;
@property (nonatomic,strong) NSString *localFilePath;
@property (nonatomic) NSUInteger nsTaskIdentifier;
@property (nonatomic,strong) NSDictionary *params;

-(NSString *) description;

@end

@interface OBFileTransferTask()
@property (nonatomic,strong) OBFileTransferAgent * transferAgent;
@end

@implementation OBFileTransferTask


-(NSString *) description {
    return [NSString stringWithFormat:@"%@ task '%@' remote %@ local %@", (self.typeUpload ? @"Upload" : @"Download"), self.marker, self.remoteUrl, self.localFilePath];
}


-(OBFileTransferAgent *) transferAgent
{
    if ( _transferAgent == nil ) {
        _transferAgent = [OBFileTransferAgentFactory fileTransferAgentInstance:self.remoteUrl];
        if ( _transferAgent == nil )
            [NSException raise:@"Transfer Agent not found" format:@"Could not find transfer agent for protocol in %@",self.remoteUrl];
    }
    return _transferAgent;
}

-(NSMutableURLRequest *) request
{
    if ( self.typeUpload )
        return [self.transferAgent uploadFileRequest:self.localFilePath to:self.remoteUrl withParams:self.params];
    else
        return [self.transferAgent downloadFileRequest:self.remoteUrl withParams:self.params];
}


@end

// *********************************
// The File Transfer Tracking Manager - ONLY USED INTERNALLY
// *********************************


@interface OBFileTransferTaskManager: NSObject

-(void) trackUploadNSTask: (NSURLSessionTask *)task fromFilePath:(NSString *)filePath withMarker: (NSString *)marker;
-(void) trackDownloadNSTask: (NSURLSessionTask *)task toFilePath: (NSString *)filePath withMarker: (NSString *)marker;
-(NSString *) markerForNSTask:(NSURLSessionTask *)task;
-(OBFileTransferTask *) transferTaskForNSTask: (NSURLSessionTask *)task;
-(void) reset;

@end

@implementation OBFileTransferTaskManager

static NSMutableArray * _tasks;

// Stop tracking all tasks
-(void) reset
{
    [self.tasks removeAllObjects];
}

// Warning: do not provide the same nsTask with a different marker, or vice versa
-(void) trackUploadNSTask: (NSURLSessionTask *)nsTask fromFilePath:(NSString *)filePath withMarker:(NSString *)marker
{
    OBFileTransferTask * instance = [[OBFileTransferTask alloc] init];
    if ( instance != nil ) {
        instance.marker = marker;
        instance.nsTaskIdentifier = nsTask.taskIdentifier;
        instance.typeUpload = YES;
        instance.localFilePath = filePath;
        instance.remoteUrl = nsTask.originalRequest.URL.absoluteString;
    }
    [self removeTaskWithMarker:marker];
    [self addTask: instance];
}

-(void) trackDownloadNSTask: (NSURLSessionTask *)nsTask toFilePath:(NSString *)filePath withMarker: (NSString *)marker
{
    OBFileTransferTask * instance = [[OBFileTransferTask alloc] init];
    if ( instance != nil ) {
        instance.marker = marker;
        instance.nsTaskIdentifier = nsTask.taskIdentifier;
        instance.typeUpload = NO;
        instance.localFilePath = filePath;
        instance.remoteUrl = nsTask.originalRequest.URL.absoluteString;
    }
    [self removeTaskWithMarker:marker];
    [self addTask: instance];
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
}

-(void) removeTask: (OBFileTransferTask *) task
{
    [[self tasks] removeObject:task];
}
@end



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

// I think the goal is to reset all the tasks
-(void) reset
{
    OB_DEBUG(@"Canceling session tasks");
    [self cancelSessionTasks];
    [self.transferTaskManager reset];
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
    [[self session] getTasksWithCompletionHandler: ^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        if ( uploadTasks.count != 0 ) {
            for ( NSURLSessionTask * task in uploadTasks ) {
                OB_DEBUG(@"Canceling task %@",[[self.transferTaskManager transferTaskForNSTask:task] description]);
                [task cancel];
            }
        }
        if ( downloadTasks.count != 0 ) {
            for ( NSURLSessionTask * task in downloadTasks ) {
                OB_DEBUG(@"Canceling task %@",[[self.transferTaskManager transferTaskForNSTask:task] description]);
                [task cancel];
            }
            
        }
    }];
}

// --------------
// Main API
// --------------


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
    
    [self.transferTaskManager trackUploadNSTask:task fromFilePath:filePath  withMarker:markerId];
    OB_INFO(@"Started upload of file %@ to %@",filePath,fullRemoteUrl);
    [task resume];

}

// Download the file from the remote URL to the provided filePath.
//
- (void) downloadFile:(NSString *)remoteFileUrl to:(NSString *)filePath withMarker: (NSString *)markerId withParams:(NSDictionary *) params
{
    NSString *fullRemoteUrl = [self fullRemotePath:remoteFileUrl];
    NSString *fullDownloadPath =[self normalizeLocalDownloadPath:filePath];

    OBFileTransferAgent * fileTransferAgent = [OBFileTransferAgentFactory fileTransferAgentInstance:fullRemoteUrl];

    NSMutableURLRequest *request = [fileTransferAgent downloadFileRequest:fullRemoteUrl withParams:params];
    NSURLSessionTask *task = [[self session] downloadTaskWithRequest:request];
                            
    [self.transferTaskManager trackDownloadNSTask:task toFilePath:fullDownloadPath withMarker:markerId ];
    OB_INFO(@"Started download of file %@ from %@",filePath,fullRemoteUrl);
    [task resume];
    
}



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
                OB_INFO(@"File transfer for %@ done and tmp file deleted",marker);
            }
        } else {
            //            We get this when internet is shut off in middle of upload
            error = [self createErrorFromBadHttpResponse:response.statusCode];
            OB_ERROR(@"%@ File Transfer for %@ received status code %ld and error %@",obtask.typeUpload ? @"Upload" : @"Download", marker,(long)response.statusCode, error.localizedDescription);
        }
        //        TODO - If not successfully completed put it retry queue??
        [self.delegate fileTransferCompleted:marker withError:error];
        [[self transferTaskManager] removeTransferTaskForNsTask:task];
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
        [[NSFileManager defaultManager] copyItemAtPath:location.path toPath: [[[self transferTaskManager] transferTaskForNSTask: downloadTask] localFilePath] error:&error];
    } else {
        OB_ERROR(@"Download for %@ received status code %ld",marker,(long)response.statusCode);
    }
}

// Resumed
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didResumeAtOffset:(int64_t)fileOffset expectedTotalBytes:(int64_t)expectedTotalBytes
{
    //    NOT YET USPPORTED
    DebugLog(@"ERROR: downloadTask didResumeAtOffset. We should not be getting this callback.");
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

// -------
// Private
// -------

-(NSString* )normalizeLocalDownloadPath: (NSString * )filePath
{
    if ( _downloadDirectory == nil || [filePath characterAtIndex:0] != '/')
        return filePath;
    else
        return [NSString pathWithComponents:@[_downloadDirectory,filePath ]];
}

-(NSString *) normalizeLocalUploadPath: (NSString *)filePath
{
    if ( _uploadDirectory == nil || [filePath characterAtIndex:0] != '/' )
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

@end
