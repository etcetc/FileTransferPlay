//
//  TBMViewController.h
//  FileTransferPlay
//
//  Created by Farhad on 6/20/14.
//  Copyright (c) 2014 NoPlanBees. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "TBMFileTransferManager.h"

@interface TBMViewController : UIViewController <TBMFileTransferDelegate>

@property (nonatomic,weak) IBOutlet UIImageView * image;
@property (nonatomic,weak) IBOutlet UIView * transferViewArea;

@end
