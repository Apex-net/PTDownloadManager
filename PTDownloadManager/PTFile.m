//
// Copyright (C) 2012 Ali Servet Donmez. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "PTFile.h"

#import "ASIHTTPRequest.h"
#import "ASINetworkQueue.h"
#import "PTDownloadManager.h"

////////////////////////////////////////////////////////////////////////////////
// Internal APIs
////////////////////////////////////////////////////////////////////////////////

@interface PTDownloadManager ()

- (ASIHTTPRequest *)requestForFile:(PTFile *)file;

@end

////////////////////////////////////////////////////////////////////////////////
// Private
////////////////////////////////////////////////////////////////////////////////

@interface PTFile ()

@property (nonatomic, strong) PTDownloadManager *downloadManager;


- (id)initWithName:(NSString *)name contentURL:(NSURL *)contentURL date:(NSDate *)date;
- (id)initWithName:(NSString *)name contentURL:(NSURL *)contentURL date:(NSDate *)date downloadManager:(PTDownloadManager *)downloadManager;

@end

@implementation PTFile

@synthesize name = _name;
@synthesize contentURL = _contentURL;
@synthesize date = _date;

- (id)initWithName:(NSString *)name contentURL:(NSURL *)contentURL date:(NSDate *)date
{
    self = [super init];
    if (self) {
        _name = name;
        _contentURL = contentURL;
        _date = date;
        
        _downloadManager = [PTDownloadManager sharedManager];
    }
    return self;
}

- (id)initWithName:(NSString *)name contentURL:(NSURL *)contentURL date:(NSDate *)date downloadManager:(PTDownloadManager *)downloadManager
{
    self = [super init];
    if (self) {
        _name = name;
        _contentURL = contentURL;
        _date = date;

        _downloadManager = downloadManager;
    }
    return self;
}

- (PTFileContentStatus)status
{
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    if ([fileManager fileExistsAtPath:[self.contentURL path]]) {
        return PTFileContentStatusAvailable;
    }
    else {
        ASIHTTPRequest *request = [self.downloadManager requestForFile:self];
        if (request && request.isExecuting) {
            return PTFileContentStatusDownloading;
        }
    }
    
    return PTFileContentStatusNone;
}

@end
