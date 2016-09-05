//
//  ViewController.m
//  BOSiOS
//
//  Created by kkwong on 16/7/23.
//  Copyright © 2016年 kkwong. All rights reserved.
//

#import "ViewController.h"
#import "BOSService.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


+ (BOSClient *)getBOSClientWithSTSToken:(id )stsToken{
    //    NSString *bucket = [BaoQuanClientConfig sharedInstance].BOS_BUKET_NAME;
    NSString *endpoint = @"http://gz.bcebos.com/";
    id<BOSCredentialProvider> credential = [[BOSFederationCredentialProvider alloc] initWithFederationTokenGetter:^BOSFederationToken * {
        BOSFederationToken * token = [BOSFederationToken new];
        token.tAccessKey = @"kdb39495501c64688be2350f61e335c5ck";
        token.tSecretKey = @"k69baa55ff18f42f68917d6421a27c1e9k";
        token.tToken = @"";
        token.expirationTimeInGMTFormat = @"";
        return token;
    }];
    
    
    BOSClientConfiguration *conf = [BOSClientConfiguration new];
    conf.maxRetryCount = 2;
    conf.timeoutIntervalForRequest = 30;
    conf.timeoutIntervalForResource = 24 * 60 * 60;
    BOSClient *client = [[BOSClient alloc] initWithEndpoint:endpoint credentialProvider:credential clientConfiguration:conf];
    return client;
}


- (IBAction)onclicked:(id)sender {
    
    return;
    
    BOSClient *client = [[self class] getBOSClientWithSTSToken:nil];
        BOSPutObjectRequest * put = [BOSPutObjectRequest new];
        // required fields
        NSString *bucket = @"ancun-bps-test";
        put.bucketName = bucket;
        
        //在上传文件时，如果把ObjectKey写为"folder/subfolder/file"，即是模拟了把文件上传到folder/subfolder/下的file文件。注意，路径默认是"根目录"，不需要以'/'开头
        
//        if ([_fileCloudPathKey rangeOfString:@"/"].location == 0) {
//            _fileCloudPathKey = [_fileCloudPathKey substringFromIndex:1];
//        }po
        put.objectKey = @"test11111.jpg";
        NSString *filePath1 = [[NSBundle mainBundle] pathForResource:@"baoquan" ofType:@".jpg"];
//        NSURL *filePath = [NSURL fileURLWithPath:filePath1];
        put.uploadingFileURL = [NSURL fileURLWithPath:filePath1];

//        if (_fileData) {
//            put.uploadingData = _fileData;
//        } else {
//            //        put.uploadingFileURL = [NSURL fileURLWithPath:filePath];
//        }
    
        put.uploadProgress = ^(int64_t bytesSent, int64_t totalByteSent, int64_t totalBytesExpectedToSend) {
            //        NSLog(@"%lld, %lld, %lld", bytesSent, totalByteSent, totalBytesExpectedToSend);
            dispatch_async(dispatch_get_main_queue(), ^(){
//                if (_progressBlock) {
//                    _progressBlock(1.0*totalByteSent/totalBytesExpectedToSend, _fileUploaName,_token.securityToken);
//                }
            });
        };
        // 可选参数
        //    put.contentType = @"";
        //    put.contentMd5 = @"";
        //    put.contentEncoding = @"";
        //    put.contentDisposition = @"";
        //    // 设置回调参数
        //    put.callbackParam = @{@"callbackUrl": @"<your server callback address>",
        //                          @"callbackBody": @"<your callback body>"};
        //    // 设置自定义变量
        //    put.callbackVar = @{@"<var1>": @"<value1>",
        //                        @"<var2>": @"<value2>"};
        BOSTask * putTask = [client putObject:put];
        
        [putTask continueWithBlock:^id(BOSTask *task) {
            NSLog(@"objectKey: %@", put.objectKey);
            NSString *string = @"";
            if (!task.error) {
                string = @"upload object success!";
                NSLog(@"upload object success!");
            } else {
                NSLog(@"upload object failed, error: %@", task.error);
            }
            BOSPutObjectResult * result = task.result;
            NSHTTPURLResponse * response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@.BOS.aliyuncs.com/", bucket]] statusCode:result.httpResponseCode HTTPVersion:@"1.1" headerFields:result.httpResponseHeaderFields];
            
            NSDictionary *dic = @{@"response":response, @"responseData":string};
            dispatch_async(dispatch_get_main_queue(), ^(){
//                if (_completionBlock) {
//                    _completionBlock(task.error, dic, task.error==nil);
//                }
            });
            return nil;
        }];
        
        
    

}

@end
