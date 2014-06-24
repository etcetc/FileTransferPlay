//
//  TBMViewController.m
//  FileTransferPlay
//
//  Created by Farhad on 6/20/14.
//  Copyright (c) 2014 NoPlanBees. All rights reserved.
//

#import "TBMViewController.h"
#import "TBMFileTransferManager.h"
#import "TBMLogger.h"
#import "TBMTransferView.h"

@interface TBMViewController ()
@property (nonatomic) NSMutableDictionary * transferViews;
@property (nonatomic) TBMFileTransferManager * fileTransferManager;

@end

@implementation TBMViewController

// --------------
// Lazy instantiations
// --------------
-(NSMutableDictionary *) transferViews
{
    if ( _transferViews == nil )
        _transferViews =  [NSMutableDictionary new];
    return _transferViews;
}

-(TBMFileTransferManager *) fileTransferManager
{
    if ( _fileTransferManager == nil ) {
        _fileTransferManager =[TBMFileTransferManager instance];
        _fileTransferManager.delegate = self;
        _fileTransferManager.downloadDirectory = [self documentDirectory];
    }
    return _fileTransferManager;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    TBM_INFO(@"START");
    
    
//    [self uploadFile: @"uploadtest.jpg"];
//    [self downloadFile:@"test4128.jpg"];
//    [self downloadFile:@"test9062.jpg"];
//    [self uploadFile: @"uploadtest.jpg"];
    [self downloadFile:@"test6451.jpg"];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


-(void) uploadFile: (NSString *)filename
{
    NSString * imagePath = [[NSBundle mainBundle] pathForResource:filename ofType:nil];
    NSString *targetFilename = [NSString stringWithFormat:@"test%d.jpg", arc4random_uniform(10000)];
    [self.fileTransferManager uploadFile:imagePath as:targetFilename withMarker:targetFilename];
    [self addTransferView:targetFilename isUpload:YES];

}

-(void) downloadFile: (NSString *)filePathOnS3
{
    [self.fileTransferManager downloadFile:filePathOnS3 to:filePathOnS3 withMarker:filePathOnS3];
    [self addTransferView:filePathOnS3 isUpload:NO];
}


-(void) addTransferView: (NSString *) fileName isUpload: (BOOL) isUpload
{
    TBMTransferView *transferView = [[TBMTransferView alloc] initInRow: self.transferViews.count];
    [transferView startTransfer:fileName upload:isUpload ? Upload : Download];
    [self.transferViewArea addSubview:transferView];
    self.transferViews[fileName] = transferView;
}

#pragma mark - FileTransferDelegate Protocol

-(void)fileTransferCompleted:(NSString *)markerId withError:(NSError *)error
{
    TBM_INFO(@"Completed file transfer with marker %@ and error %@",markerId,error.localizedDescription);
    [[NSOperationQueue mainQueue] addOperationWithBlock:^ {
        [(TBMTransferView *)self.transferViews[markerId] updateStatus:error == nil ? Success : Error];
    }];
    
}

-(void)fileTransferRetrying:(NSString *)markerId withError:(NSError *)error
{
    TBM_WARN(@"Retrying file transfer with marker %@",markerId);
}

-(void) fileTransferProgress: (NSString *)markerId percent: (NSUInteger) progress
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^ {
        [(TBMTransferView *)self.transferViews[markerId] updateProgress:progress];
    }];
}

-(NSString *) documentDirectory
{
    NSArray * urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                           inDomains:NSUserDomainMask];
    if ( urls.count > 0 ) {
        return [(NSURL *)urls[0] URLByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]].path;
    } else
        return nil;
}

@end
