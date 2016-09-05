//
//  BOSDefine.h
//  baiduyunBOSiOS
//
//  Created by zhouzhuo on 5/1/16.
//  Copyright © 2016 zhouzhuo. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifndef BOSDefine_h
#define BOSDefine_h

#define BOSUAPrefix                             @"baiduyun-sdk-ios"
#define BOSSDKVersion                           @"2.5.0"

#define BOSListBucketResultXMLTOKEN             @"ListBucketResult"
#define BOSNameXMLTOKEN                         @"Name"
#define BOSDelimiterXMLTOKEN                    @"Delimiter"
#define BOSMarkerXMLTOKEN                       @"Marker"
#define BOSNextMarkerXMLTOKEN                   @"NextMarker"
#define BOSMaxKeysXMLTOKEN                      @"MaxKeys"
#define BOSIsTruncatedXMLTOKEN                  @"IsTruncated"
#define BOSContentsXMLTOKEN                     @"Contents"
#define BOSKeyXMLTOKEN                          @"Key"
#define BOSLastModifiedXMLTOKEN                 @"LastModified"
#define BOSETagXMLTOKEN                         @"ETag"
#define BOSTypeXMLTOKEN                         @"Type"
#define BOSSizeXMLTOKEN                         @"Size"
#define BOSStorageClassXMLTOKEN                 @"StorageClass"
#define BOSCommonPrefixesXMLTOKEN               @"CommonPrefixes"
#define BOSOwnerXMLTOKEN                        @"Owner"
#define BOSAccessControlListXMLTOKEN            @"AccessControlList"
#define BOSGrantXMLTOKEN                        @"Grant"
#define BOSIDXMLTOKEN                           @"ID"
#define BOSDisplayNameXMLTOKEN                  @"DisplayName"
#define BOSBucketsXMLTOKEN                      @"Buckets"
#define BOSBucketXMLTOKEN                       @"Bucket"
#define BOSCreationDate                         @"CreationDate"
#define BOSPrefixXMLTOKEN                       @"Prefix"
#define BOSUploadIdXMLTOKEN                     @"UploadId"
#define BOSLocationXMLTOKEN                     @"Location"
#define BOSNextPartNumberMarkerXMLTOKEN         @"NextPartNumberMarker"
#define BOSMaxPartsXMLTOKEN                     @"MaxParts"
#define BOSPartXMLTOKEN                         @"Part"
#define BOSPartNumberXMLTOKEN                   @"PartNumber"

#define BOSClientErrorDomain                    @"com.baiduyun.BOS.clientError"
#define BOSServerErrorDomain                    @"com.baiduyun.BOS.serverError"

#define BOSErrorMessageTOKEN                    @"ErrorMessage"

#define BOSHttpHeaderContentDisposition         @"Content-Disposition"
#define BOSHttpHeaderXBOSCallback               @"x-BOS-callback"
#define BOSHttpHeaderXBOSCallbackVar            @"x-BOS-callback-var"
#define BOSHttpHeaderContentEncoding            @"Content-Encoding"
#define BOSHttpHeaderContentType                @"Content-Type"
#define BOSHttpHeaderContentMD5                 @"Content-MD5"
#define BOSHttpHeaderCacheControl               @"Cache-Control"
#define BOSHttpHeaderExpires                    @"Expires"

#define BOSDefaultRetryCount                    3
#define BOSDefaultMaxConcurrentNum              5
#define BOSDefaultTimeoutForRequestInSecond     15
#define BOSDefaultTimeoutForResourceInSecond    7 * 24 * 60 * 60

#endif /* BOSDefine_h */
