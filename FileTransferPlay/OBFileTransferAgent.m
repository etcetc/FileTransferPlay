//
//  OBFileTransferAgentBase.m
//  FileTransferPlay
//
//  Created by Farhad on 6/27/14.
//  Copyright (c) 2014 NoPlanBees. All rights reserved.
//

#import "OBFileTransferAgent.h"

@implementation OBFileTransferAgent

NSString * const FilenameParamKey = @"_filename";
NSString * const ContentTypeParamKey = @"_contentType";
NSString * const FormFileFieldNameParamKey = @"_fileFieldName";

-(NSMutableURLRequest *) downloadFileRequest:(NSString *)sourcefileUrl
{
    [NSException raise:NSInternalInconsistencyException format:@"Please override method %@ in your subclass",NSStringFromSelector(_cmd)];
    return nil;
}

-(NSMutableURLRequest *) uploadFileRequest:(NSString *)filePath to:(NSString *)targetFileUrl withParams:(NSDictionary *)params
{
    [NSException raise:NSInternalInconsistencyException format:@"Please override method %@ in your subclass",NSStringFromSelector(_cmd)];
    return nil;
}

// By default the transfer agent is not encoding a body - the file is what it is
-(BOOL) hasEncodedBody
{
    return NO;
}


-(NSDictionary *)removeSpecialParams: (NSDictionary *)params
{
    NSMutableDictionary * p = [NSMutableDictionary dictionaryWithDictionary:params];
    [p removeObjectForKey:FilenameParamKey];
    [p removeObjectForKey:FormFileFieldNameParamKey];
    [p removeObjectForKey:ContentTypeParamKey];
    return p;
}

-(NSString *)mimeTypeFromFilename: (NSString *)filename
{
    NSString * extension = [[filename componentsSeparatedByString:@"."] lastObject];
    return [self mimeTypes][extension];
}

-(NSDictionary *) mimeTypes
{
    static NSDictionary * mimeTypes;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError *error;
        NSString * mimeTypesPath = [[NSBundle mainBundle] pathForResource:@"mimeTypes" ofType:@"txt"];
        // read everything from text
        NSString* fileContents =   [NSString stringWithContentsOfFile:mimeTypesPath encoding:NSUTF8StringEncoding error:&error];
        
        if ( error != nil ) {
            [NSException raise:@"Unable to read file mimeTypes.txt" format:nil];
        }
        
        NSArray* lines = [fileContents componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet]];

        NSMutableDictionary * types = [NSMutableDictionary new];
        for ( NSString * line in lines ) {
            NSArray * split = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ( split.count == 2 ) {
                types[split[0]] = split[1];
            } else {
                OB_WARN(@"Noncomformat line in mimeTypes.txt: %@",line);
            }
        }
        mimeTypes = [NSDictionary dictionaryWithDictionary:types];
    });
    return mimeTypes;
}

@end
