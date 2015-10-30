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

#import <Foundation/Foundation.h>

#import "PTFile.h"

static NSString *const kPTDownloadManagerNotificationDownloadComplete = @"PTDownloadManagerNotificationDownloadComplete";
static NSString *const kPTDownloadManagerNotificationLoadFileComplete = @"PTDownloadManagerNotificationLoadFileComplete";
static NSString *const kPTDownloadManagerNotificationLoadFileFail = @"PTDownloadManagerNotificationLoadFileFail";

@interface PTDownloadManager : NSObject

@property (nonatomic, readonly) NSArray *files;

@property (readonly, nonatomic, strong) NSString *fileDownloadPath;

+ (PTDownloadManager *)sharedManager;

- (id)initWithLibraryInfoFileName:(NSString *)libraryInfoFileName;

- (void)changeDiskCapacity:(NSUInteger)diskCapacity andFileDownloadPath:(NSString *)path;

- (PTFile *)addFileWithName:(NSString *)name date:(NSDate *)date request:(NSURLRequest *)request;
- (PTFile *)fileWithName:(NSString *)name;

- (void)startFileDownloads __deprecated_msg("Method deprecated. Use `startFileDownloadsForced:");

/* 'force' value:
    - YES, all files will be downloaded
    - NO, all files that are already downloaded, will not be re-downloaded
*/

- (void)startFileDownloadsForced:(BOOL)force;

- (void)removeFile:(PTFile *)file;
- (void)removeAllFiles;

- (void)changeDefaultDownloadPath:(NSString *)path;

@end
