#import "DownloadManager.h"
#import <CommonCrypto/CommonDigest.h>

@interface DownloadManager ()
@property (nonatomic, assign, readwrite) BOOL isDownloading;
@property (nonatomic, copy, readwrite) NSString *activeLabel;
@property (nonatomic, assign, readwrite) uint64_t downloadedBytes;
@property (nonatomic, assign, readwrite) uint64_t expectedBytes;
@property (nonatomic, strong) NSTask *activeTask;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, copy) NSString *activePartPath;
@property (nonatomic, copy) MavDownloadProgressBlock progressHandler;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL deletePartOnCancel;
@property (nonatomic, strong) dispatch_queue_t workerQueue;
@end

@implementation DownloadManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _workerQueue = dispatch_queue_create("com.momochisoundpost.MavLlama.download", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

+ (NSString *)resolvedCurlPath {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundled = [bundle pathForResource:@"curl" ofType:nil inDirectory:@"bin"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (bundled && [fm isExecutableFileAtPath:bundled]) {
        return bundled;
    }
    if ([fm isExecutableFileAtPath:@"/opt/local/bin/curl"]) {
        return @"/opt/local/bin/curl";
    }
    return @"/usr/bin/curl";
}

+ (NSString *)resolvedCABundlePath {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundled = [bundle pathForResource:@"ca-bundle" ofType:@"crt"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (bundled && [fm fileExistsAtPath:bundled]) {
        return bundled;
    }
    if ([fm fileExistsAtPath:@"/opt/local/share/curl/curl-ca-bundle.crt"]) {
        return @"/opt/local/share/curl/curl-ca-bundle.crt";
    }
    return nil;
}

+ (NSString *)sha256ForFileAtPath:(NSString *)path {
    NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:path];
    if (!stream) return nil;
    [stream open];
    if ([stream streamStatus] == NSStreamStatusError) {
        [stream close];
        return nil;
    }

    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    uint8_t buf[65536];
    while ([stream hasBytesAvailable]) {
        NSInteger n = [stream read:buf maxLength:sizeof(buf)];
        if (n < 0) {
            [stream close];
            return nil;
        }
        if (n == 0) break;
        CC_SHA256_Update(&ctx, buf, (CC_LONG)n);
    }
    [stream close];

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

+ (NSData *)fetchDataFromURL:(NSString *)urlString error:(NSError **)outError {
    NSString *curl = [self resolvedCurlPath];
    NSString *ca = [self resolvedCABundlePath];

    NSMutableArray *args = [NSMutableArray array];
    if (ca) {
        [args addObject:@"--cacert"];
        [args addObject:ca];
    }
    [args addObjectsFromArray:@[@"-fsSL", @"--max-time", @"15", @"--retry", @"2", urlString]];

    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:curl];
    [task setArguments:args];
    NSPipe *outPipe = [NSPipe pipe];
    NSPipe *errPipe = [NSPipe pipe];
    [task setStandardOutput:outPipe];
    [task setStandardError:errPipe];

    @try {
        [task launch];
    } @catch (NSException *ex) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"MavLlamaDownload"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: [ex reason] ?: @"Failed to launch curl"}];
        }
        return nil;
    }

    NSData *outData = [[outPipe fileHandleForReading] readDataToEndOfFile];
    NSData *errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];

    if ([task terminationStatus] != 0) {
        NSString *errStr = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?: @"curl failed";
        if (outError) {
            *outError = [NSError errorWithDomain:@"MavLlamaDownload"
                                            code:[task terminationStatus]
                                        userInfo:@{NSLocalizedDescriptionKey: [errStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]}];
        }
        return nil;
    }
    return outData;
}

- (void)pollPartProgress:(NSTimer *)timer {
    (void)timer;
    if (!self.isDownloading || !self.activePartPath) return;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.activePartPath error:nil];
    uint64_t bytes = attrs ? [attrs fileSize] : 0;
    self.downloadedBytes = bytes;
    if (self.progressHandler) {
        self.progressHandler(bytes, self.expectedBytes);
    }
}

- (void)downloadURL:(NSString *)urlString
       expectedBytes:(uint64_t)expectedBytes
      expectedSHA256:(NSString *)expectedSHA256
            partPath:(NSString *)partPath
            destPath:(NSString *)destPath
               label:(NSString *)label
            progress:(MavDownloadProgressBlock)progressBlock
          completion:(MavDownloadCompletionBlock)completionBlock {
    if (self.isDownloading) {
        if (completionBlock) {
            completionBlock(NO, @"Another download is already running.");
        }
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:[partPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:[destPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];

    self.isDownloading = YES;
    self.cancelled = NO;
    self.deletePartOnCancel = NO;
    self.activeLabel = label ?: [destPath lastPathComponent];
    self.activePartPath = partPath;
    self.expectedBytes = expectedBytes;
    self.progressHandler = progressBlock;

    NSDictionary *initAttrs = [fm attributesOfItemAtPath:partPath error:nil];
    self.downloadedBytes = initAttrs ? [initAttrs fileSize] : 0;

    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.35
                                                      target:self
                                                    selector:@selector(pollPartProgress:)
                                                    userInfo:nil
                                                     repeats:YES];

    NSString *curl = [DownloadManager resolvedCurlPath];
    NSString *ca = [DownloadManager resolvedCABundlePath];

    dispatch_async(self.workerQueue, ^{
        NSMutableArray *args = [NSMutableArray array];
        if (ca) {
            [args addObject:@"--cacert"];
            [args addObject:ca];
        }
        [args addObjectsFromArray:@[@"-fL", @"--retry", @"4", @"--retry-delay", @"2", @"-C", @"-", @"-o", partPath, urlString]];

        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:curl];
        [task setArguments:args];
        NSPipe *errPipe = [NSPipe pipe];
        [task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
        [task setStandardError:errPipe];

        self.activeTask = task;

        NSString *errMsg = nil;
        BOOL ok = NO;

        @try {
            [task launch];
            NSData *errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
            [task waitUntilExit];

            if (self.cancelled) {
                errMsg = @"Download cancelled.";
            } else if ([task terminationStatus] != 0) {
                NSString *rawErr = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?: @"";
                NSString *trimmed = [rawErr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmed.length > 260) {
                    trimmed = [trimmed substringFromIndex:trimmed.length - 260];
                }
                errMsg = trimmed.length > 0 ? trimmed : [NSString stringWithFormat:@"curl exited with code %d", [task terminationStatus]];
            } else {
                if (expectedSHA256 && expectedSHA256.length > 0) {
                    NSString *actual = [DownloadManager sha256ForFileAtPath:partPath];
                    if (!actual || ![[actual lowercaseString] isEqualToString:[expectedSHA256 lowercaseString]]) {
                        errMsg = [NSString stringWithFormat:@"SHA-256 verification failed (expected %@, got %@).",
                                  expectedSHA256, actual ?: @"nil"];
                        [fm removeItemAtPath:partPath error:nil];
                    } else {
                        ok = YES;
                    }
                } else {
                    ok = YES;
                }
            }
        } @catch (NSException *ex) {
            errMsg = [ex reason] ?: @"Failed to run curl.";
        }

        if (ok) {
            [fm removeItemAtPath:destPath error:nil];
            NSError *moveErr = nil;
            if (![fm moveItemAtPath:partPath toPath:destPath error:&moveErr]) {
                ok = NO;
                errMsg = [moveErr localizedDescription] ?: @"Failed to move completed download.";
            }
        } else if (self.cancelled && self.deletePartOnCancel) {
            [fm removeItemAtPath:partPath error:nil];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.pollTimer invalidate];
            self.pollTimer = nil;
            self.activeTask = nil;
            self.isDownloading = NO;
            self.progressHandler = nil;
            if (ok) {
                NSDictionary *doneAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:destPath error:nil];
                self.downloadedBytes = doneAttrs ? [doneAttrs fileSize] : self.expectedBytes;
            }
            if (completionBlock) {
                completionBlock(ok, errMsg);
            }
        });
    });
}

- (void)cancelAndDeletePart:(BOOL)deletePart {
    if (!self.isDownloading) return;
    self.cancelled = YES;
    self.deletePartOnCancel = deletePart;
    if (self.activeTask && [self.activeTask isRunning]) {
        [self.activeTask terminate];
    }
}

@end
