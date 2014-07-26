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
        _fileTransferManager.remoteUrlBase = @"s3://tbm_videos/";
//        _fileTransferManager.remoteUrlBase = @"http://localhost:3000/api/upload/";
//        _fileTransferManager.remoteUrlBase = @"http://localhost:3000/videos/create";
    }
    return _fileTransferManager;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    OB_INFO(@"START");
    
//    This is a short one
//    [self downloadFile:@"test6451.jpg"];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


-(void) uploadFile: (NSString *)filename
{
    static NSString * uploadBase;
//    uploadBase = @"http://localhost:3000/api/upload/";
//    uploadBase = @"http://localhost:3000/videos/create";
    NSString * imagePath = [[NSBundle mainBundle] pathForResource:filename ofType:nil];
    NSString *targetFilename = [NSString stringWithFormat:@"test%d.jpg", arc4random_uniform(10000)];
    [self.fileTransferManager uploadFile:imagePath to:uploadBase withMarker:targetFilename withParams:@{FilenameParamKey: targetFilename, @"p1":@"test"}];
    [self addTransferView:targetFilename isUpload:YES];

}

-(void) downloadFile: (NSString *)filePathOnS3
{
    [self.fileTransferManager downloadFile:filePathOnS3 to:filePathOnS3 withMarker:filePathOnS3];
    [self addTransferView:filePathOnS3 isUpload:NO];
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

-(void) start
{
    [self clearTransferViews];
    [self.fileTransferManager reset];
    [self uploadFile: @"uploadtest.jpg"];
//    [self downloadFile:@"test4128.jpg"];
//    [self downloadFile:@"test9062.jpg"];
//    [self uploadFile: @"uploadtest.jpg"];
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

@end
