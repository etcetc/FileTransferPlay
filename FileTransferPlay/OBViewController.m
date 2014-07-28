//
//  OBViewController.m
//  FileTransferPlay
//
//  Created by Farhad on 6/20/14.
//  Copyright (c) 2014 NoPlanBees. All rights reserved.
//

#import "OBViewController.h"
#import "OBFileTransferManager.h"
#import "OBLogger.h"
#import "OBTransferView.h"

@interface OBViewController ()
@property (nonatomic) NSMutableDictionary * transferViews;
@property (nonatomic) OBFileTransferManager * fileTransferManager;
@property (nonatomic) BOOL useS3;
@property (nonatomic,strong) NSString * baseUrl;
@end

@implementation OBViewController

// --------------
// Lazy instantiations
// --------------
-(NSMutableDictionary *) transferViews
{
    if ( _transferViews == nil )
        _transferViews =  [NSMutableDictionary new];
    return _transferViews;
}

-(OBFileTransferManager *) fileTransferManager
{
    if ( _fileTransferManager == nil ) {
        _fileTransferManager =[OBFileTransferManager instance];
        _fileTransferManager.delegate = self;
        _fileTransferManager.downloadDirectory = [self documentDirectory];
        
        _fileTransferManager.remoteUrlBase = self.baseUrl;
        
//        _fileTransferManager.remoteUrlBase = @"http://localhost:3000/api/upload/";
//        _fileTransferManager.remoteUrlBase = @"http://localhost:3000/videos/create";
    }
    return _fileTransferManager;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setup];
    OB_INFO(@"START");
}

-(void) setup
{
    self.useS3 = YES;
    self.useS3Switch.on = self.useS3;
    [self setDefaultURLs];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


-(void) uploadFile: (NSString *)filename
{
    NSString * uploadBase =@"";
    if ( !self.useS3 )
        uploadBase = @"upload/";
    
    NSString * localFilePath = [[NSBundle mainBundle] pathForResource:filename ofType:nil];
    NSString *targetFilename = [NSString stringWithFormat:@"test%d.jpg", arc4random_uniform(10000)];
    [self.fileTransferManager uploadFile:localFilePath to:uploadBase withMarker:targetFilename withParams:@{FilenameParamKey: targetFilename, @"p1":@"test"}];
    [self addTransferView:targetFilename isUpload:YES];

}

-(void) downloadFile: (NSString *)filename
{
    static NSString * base=@"";
    if ( !self.useS3 )
        base = @"files/";

    [self.fileTransferManager downloadFile:[base  stringByAppendingString:filename] to:filename withMarker:filename withParams:nil];
    [self addTransferView:filename isUpload:NO];
}


-(void) addTransferView: (NSString *) fileName isUpload: (BOOL) isUpload
{
    OBTransferView *transferView = [[OBTransferView alloc] initInRow: self.transferViews.count];
    [transferView startTransfer:fileName upload:isUpload ? Upload : Download];
    [self.transferViewArea addSubview:transferView];
    self.transferViews[fileName] = transferView;
}

-(void) clearTransferViews
{
    for ( UIView * view in self.transferViewArea.subviews )
        [view removeFromSuperview];
    [self.transferViews removeAllObjects];
}

#pragma mark - FileTransferDelegate Protocol

-(void)fileTransferCompleted:(NSString *)markerId withError:(NSError *)error
{
    OB_INFO(@"Completed file transfer with marker %@ and error %@",markerId,error.localizedDescription);
    [[NSOperationQueue mainQueue] addOperationWithBlock:^ {
        [(OBTransferView *)self.transferViews[markerId] updateStatus:error == nil ? Success : Error];
    }];
    
}

-(void)fileTransferRetrying:(NSString *)markerId withError:(NSError *)error
{
    OB_WARN(@"Retrying file transfer with marker %@",markerId);
}

-(void) fileTransferProgress: (NSString *)markerId percent: (NSUInteger) progress
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^ {
        [(OBTransferView *)self.transferViews[markerId] updateProgress:progress];
    }];
}

//NOTE: these are files that we know are there!
-(void) start
{
    [self clearTransferViews];
    [self.fileTransferManager reset];
    [self uploadFile: @"uploadtest.jpg"];
    [self downloadFile:@"test4128.jpg"];
    [self downloadFile:@"test9062.jpg"];
    [self uploadFile: @"uploadtest.jpg"];
}

-(IBAction)start:(id)sender
{
    [self start];
}

// Put files in document directory
-(NSString *) documentDirectory
{
    NSArray * urls = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                           inDomains:NSUserDomainMask];
    if ( urls.count > 0 ) {
        return [(NSURL *)urls[0] URLByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]].path;
    } else
        return nil;
}

// Change the file store and appropriate URL
- (IBAction)changedFileStore:(id)sender {
    self.useS3 = self.useS3Switch.on;
    [self setDefaultURLs];
}

- (IBAction)changedFileStoreUrl:(id)sender {
    self.baseUrl = self.baseUrlInput.text;
    self.fileTransferManager.remoteUrlBase = self.baseUrl;
}

-(void) setDefaultURLs
{
    if ( self.useS3 )
        self.baseUrl = @"s3://tbm_videos/";
    else
        self.baseUrl = @"http://192.168.1.9:3000/";
    self.baseUrlInput.text = self.baseUrl;
}

@end
