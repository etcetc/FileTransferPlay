//
//  OBServerFileTransferAgent.m
//  FileTransferPlay
//
//  Created by Farhad on 6/26/14.
//  Copyright (c) 2014 NoPlanBees. All rights reserved.
//

#import "OBServerFileTransferAgent.h"

@implementation OBServerFileTransferAgent

NSString * const OBHttpFormBoundary = @"--------sdfllkjkjkli98ijj";

// Create a download request to a standard URL
- (NSMutableURLRequest *) downloadFileRequest:(NSString *)sourcefileUrl
{
    NSMutableURLRequest* request = [[NSMutableURLRequest alloc]initWithURL:[NSURL URLWithString:sourcefileUrl]];
    [request setHTTPMethod:@"GET"];
    return request;
}

-(NSMutableURLRequest *) uploadFileRequest:(NSString *)filePath to:(NSString *)targetFileUrl withParams:(NSDictionary *)params
{
    NSMutableURLRequest* request = [[NSMutableURLRequest alloc]initWithURL:[NSURL URLWithString:targetFileUrl]];

    NSString *formFileInputName = params[FormFileFieldNameParamKey] == nil ? @"file" : params[FormFileFieldNameParamKey];
    NSString *filename = params[FilenameParamKey] == nil ? [[filePath pathComponents] lastObject] : params[FilenameParamKey];
    NSString *contentType =params[ContentTypeParamKey] ? params[ContentTypeParamKey] : [self mimeTypeFromFilename:filePath];
    
    params = [self removeSpecialParams:params];

    [request setHTTPMethod:@"POST"];
    
    [request setValue:@"Keep-Alive" forHTTPHeaderField:@"Connection"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    [request setValue:[NSString stringWithFormat:@"multipart/form-data;boundary=%@", OBHttpFormBoundary ] forHTTPHeaderField:@"Content-Type"];
    
    
    NSMutableData *body = [[NSMutableData alloc] init];

    NSMutableString *preString =  [[NSMutableString alloc] init];
    [preString appendString:[NSString stringWithFormat:@"--%@\r\n", OBHttpFormBoundary]];
    [preString appendString:[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n",formFileInputName,filename]];
    [preString appendString:[NSString stringWithFormat:@"Content-Type: %@\r\n",contentType]];
    [preString appendString:@"Content-Transfer-Encoding: binary\r\n"];
    [preString appendString:@"\r\n"];


    [body appendData:[preString dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[NSData dataWithContentsOfFile:filePath]];
    [body appendData:[@"\r\n"dataUsingEncoding:NSUTF8StringEncoding]];

    
    if ( params.count > 0 ) {
        NSMutableString *paramsString = [NSMutableString new];
        
        // add params (all params are strings)
        for (NSString *param in [params allKeys]) {
            [paramsString appendString:[NSString stringWithFormat:@"--%@\r\n", OBHttpFormBoundary]];
            [paramsString appendString:[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", param]];
            [paramsString appendString:[NSString stringWithFormat:@"%@\r\n", params[param]]];
        }
        
        [body appendData:[paramsString dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    NSString *postString =  [NSString stringWithFormat:@"\r\n--%@--\r\n", OBHttpFormBoundary];
    
    [body appendData:[postString dataUsingEncoding:NSUTF8StringEncoding]];
    
    [request setHTTPBody:body];
    
    return request;
}

-(BOOL) hasEncodedBody
{
    return YES;
}

@end
