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

#import "PTDownloadManager.h"

#import "ASINetworkQueue.h"
#import "ASIHTTPRequest.h"

#define kPTLibraryInfoFileName                  @"libraryInfo.plist"
#define kPTLibraryInfoFilesKey                  @"files"
#define kPTLibraryInfoRequestURLStringsKey      @"urls"

////////////////////////////////////////////////////////////////////////////////
// Internal APIs
////////////////////////////////////////////////////////////////////////////////

@interface PTFile ()

@property (nonatomic) NSString *name;

- (id)initWithName:(NSString *)name date:(NSDate *)date;

@end

////////////////////////////////////////////////////////////////////////////////
// Private
////////////////////////////////////////////////////////////////////////////////

@interface PTDownloadManager () {
    NSMutableDictionary *_libraryInfo;
    ASINetworkQueue *_downloadQueue;
}

@property (nonatomic, retain) NSString *diskCachePath;
@property (nonatomic, retain) NSString *fileDownloadPath;

@property (nonatomic, readonly) NSMutableDictionary *libraryInfo;
@property (nonatomic, readonly) ASINetworkQueue *downloadQueue;

@property (nonatomic, assign) BOOL scanningFileInDirectory;

- (void)saveLibraryInfo;
- (void)createDirectoryAtPath:(NSString *)path;
- (ASIHTTPRequest *)requestForFile:(PTFile *)file;

@end

@implementation PTDownloadManager

@synthesize diskCachePath = _diskCachePath;
@synthesize fileDownloadPath = _fileDownloadPath;
@synthesize downloadQueue = _downloadQueue;
@synthesize scanningFileInDirectory = _scanningFileInDirectory;

+ (PTDownloadManager *)sharedManager
{
    static PTDownloadManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[PTDownloadManager alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        NSString *defaultPath = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0]
                                 stringByAppendingPathComponent:@"PTDownloadManager"];
        _diskCachePath = defaultPath;
        _fileDownloadPath = defaultPath;
        _scanningFileInDirectory = NO;

        _downloadQueue = [ASINetworkQueue queue];
        _downloadQueue.delegate = self;
        _downloadQueue.requestDidFinishSelector = @selector(queueDidFinishRequest);
        _downloadQueue.requestDidFailSelector = @selector(queueDidFailRequest);
        _downloadQueue.showAccurateProgress = YES;
        _downloadQueue.shouldCancelAllRequestsOnFailure = NO;
        [_downloadQueue go];
    }
    return self;
}

- (NSArray *)files
{
    NSMutableArray *result = [NSMutableArray array];
    
    NSArray *fileNames = [[self.libraryInfo objectForKey:kPTLibraryInfoFilesKey] allKeys];
    for (NSString *name in fileNames) {
        [result addObject:[self fileWithName:name]];
    }
    
    return result;
}

- (void)changeDiskCapacity:(NSUInteger)diskCapacity andFileDownloadPath:(NSString *)path
{
    // TODO missing implementation
    NSAssert(diskCapacity == 0, @"disk capacity is currently unused and should be set to 0.");
    
    self.fileDownloadPath = path;
}

- (void)changeDefaultDownloadPath:(NSString *)path
{
    if (path) {
        
        // stop pending operations
        [self.downloadQueue cancelAllOperations];
        
        // clean library info
        _libraryInfo = nil;
        
        // set new path
        self.diskCachePath = path;
        self.fileDownloadPath = path;
    }
}

- (PTFile *)addFileWithName:(NSString *)name date:(NSDate *)date request:(NSURLRequest *)request
{
    [self createDirectoryAtPath:self.fileDownloadPath];
    
    // TODO missing implementation
    // - if exceeded 'diskCapacity', do periodic maintenance to save up some disk space, deleting oldest files in the library by their 'date'

    NSMutableDictionary *files = [self.libraryInfo objectForKey:kPTLibraryInfoFilesKey];
    NSAssert(![files objectForKey:name], @"file name is used by another file, name must be unique across all files in the library.");
    [files setObject:date forKey:name];

    NSMutableDictionary *urls = [self.libraryInfo objectForKey:kPTLibraryInfoRequestURLStringsKey];
    [urls setObject:[[request URL] absoluteString] forKey:name];

    [self saveLibraryInfo];
    
    return [self fileWithName:name];
}

- (void)startFileDownloads
{
    [self startFileDownloadsForced:YES];
}

- (void)startFileDownloadsForced:(BOOL)force
{
    if (force == NO) {
         _scanningFileInDirectory = YES;
    }
    
    for (PTFile *file in self.files) {
        if (force == YES || file.status != PTFileContentStatusAvailable) {
            [file download];
        }
        else {
            [[NSNotificationCenter defaultCenter] postNotificationName:kPTDownloadManagerNotificationLoadFileComplete object:file userInfo:nil];
        }
    }
    
    if (force == NO) {
        _scanningFileInDirectory = NO;
        [self performSelectorOnMainThread:@selector(checkIfDownloadIsComplete) withObject:nil waitUntilDone:YES];
    }
}

- (void)removeFile:(PTFile *)file
{
    ASIHTTPRequest *request = [self requestForFile:file];
    if (request) {
        [request cancel];
        [request removeTemporaryDownloadFile];
    }
    
    [[self.libraryInfo objectForKey:kPTLibraryInfoFilesKey] removeObjectForKey:file.name];
    [[self.libraryInfo objectForKey:kPTLibraryInfoRequestURLStringsKey] removeObjectForKey:file.name];
    
    [self saveLibraryInfo];

    NSFileManager *fileManager = [[NSFileManager alloc] init];
    [fileManager removeItemAtURL:file.contentURL error:NULL];
}

- (void)removeAllFiles
{
    // stop pending operations
    [self.downloadQueue cancelAllOperations];
    
    // clean library info and remove directory
    _libraryInfo = nil;
    [self removeDirectoryAtPath:self.diskCachePath];

}

- (PTFile *)fileWithName:(NSString *)name
{
    NSDictionary *files = [self.libraryInfo objectForKey:kPTLibraryInfoFilesKey];
    return [files objectForKey:name] ? [[PTFile alloc] initWithName:name date:[files objectForKey:name]] : nil;
}

- (NSMutableDictionary *)libraryInfo
{
    if (!_libraryInfo) {
        _libraryInfo = [[NSMutableDictionary alloc] initWithContentsOfFile:[self.diskCachePath stringByAppendingPathComponent:kPTLibraryInfoFileName]];
        if (!_libraryInfo) {
            _libraryInfo = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                            [NSMutableDictionary dictionary], kPTLibraryInfoFilesKey,
                            [NSMutableDictionary dictionary], kPTLibraryInfoRequestURLStringsKey,
                            nil];
        }
    }
    
    return _libraryInfo;
}

- (void)saveLibraryInfo
{
    [self createDirectoryAtPath:self.diskCachePath];
    
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:self.libraryInfo format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    if (data) {
        [data writeToFile:[self.diskCachePath stringByAppendingPathComponent:kPTLibraryInfoFileName] atomically:YES];
    }
}

- (void)createDirectoryAtPath:(NSString *)path
{
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    if (![fileManager fileExistsAtPath:path]) {
        [fileManager createDirectoryAtPath:path
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:NULL];
    }
}

- (void)removeDirectoryAtPath:(NSString *)path
{
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    if ([fileManager fileExistsAtPath:path]) {
        [fileManager removeItemAtPath:path error:NULL];
    }
}

- (ASIHTTPRequest *)requestForFile:(PTFile *)file
{
    NSString *urlString = [[self.libraryInfo objectForKey:kPTLibraryInfoRequestURLStringsKey] objectForKey:file.name];
    for (ASIHTTPRequest *request in self.downloadQueue.operations) {
        if ([request.originalURL.absoluteString isEqualToString:urlString]) {
            return request;
        }
    }
    
    ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:urlString]];
    request.userInfo = [NSDictionary dictionaryWithObject:self.downloadQueue forKey:@"queue"];
    request.temporaryFileDownloadPath = [[NSTemporaryDirectory() stringByAppendingPathComponent:file.name] stringByAppendingPathExtension:@"download"];
    request.downloadDestinationPath = [self.fileDownloadPath stringByAppendingPathComponent:file.name];
    request.allowResumeForFileDownloads = YES;
    request.shouldContinueWhenAppEntersBackground = YES;
    return request;
}

- (void)queueDidFinishRequest
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kPTDownloadManagerNotificationLoadFileComplete object:nil userInfo:nil];
    
    [self checkIfDownloadIsComplete];
}

- (void)queueDidFailRequest
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kPTDownloadManagerNotificationLoadFileComplete object:nil userInfo:nil];
    
    [self checkIfDownloadIsComplete];
}

- (void)checkIfDownloadIsComplete
{
    if (_downloadQueue.requestsCount == 0 && _scanningFileInDirectory == NO) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kPTDownloadManagerNotificationDownloadComplete object:nil userInfo:nil];
    }
}

@end
