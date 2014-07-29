//
//  OBViewController.h
//  FileTransferPlay
//
//  Created by Farhad on 6/20/14.
//  Copyright (c) 2014 NoPlanBees. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "OBFileTransferManager.h"

@interface OBViewController : UIViewController <OBFileTransferDelegate>

@property (nonatomic,weak) IBOutlet UIImageView * image;
@property (nonatomic,weak) IBOutlet UIView * transferViewArea;
@property (weak, nonatomic) IBOutlet UISwitch *useS3Switch;
@property (weak, nonatomic) IBOutlet UITextField *baseUrlInput;
- (IBAction)changedFileStore:(id)sender;
- (IBAction)changedFileStoreUrl:(id)sender;
- (IBAction)retryPending:(id)sender;

@property (weak, nonatomic) IBOutlet UILabel *pendingInfo;

@end
