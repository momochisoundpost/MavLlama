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

+ (NSString *)sha256ForString:(NSString *)str {
    NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([data bytes], (CC_LONG)[data length], digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

+ (NSData *)fetchDataFromURL:(NSString *)urlString error:(NSError **)outError {
    return [self fetchDataFromURL:urlString headers:nil error:outError];
}

+ (NSData *)fetchDataFromURL:(NSString *)urlString headers:(NSDictionary *)headers error:(NSError **)outError {
    if (!urlString || urlString.length == 0) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"MavLlamaDownload"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"Empty URL"}];
        }
        return nil;
    }
    NSString *lower = [[urlString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (![lower hasPrefix:@"http://"] && ![lower hasPrefix:@"https://"]) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"MavLlamaDownload"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"Only http and https URLs are supported."}];
        }
        return nil;
    }

    NSString *curl = [self resolvedCurlPath];
    NSString *ca = [self resolvedCABundlePath];

    NSMutableArray *args = [NSMutableArray array];
    if (ca) {
        [args addObject:@"--cacert"];
        [args addObject:ca];
    }
    [args addObjectsFromArray:@[@"-A", @"MavLlama/1.1", @"--proto", @"=http,https", @"--proto-redir", @"=http,https", @"-g"]];
    if (headers) {
        for (NSString *key in headers) {
            id val = headers[key];
            if ([key isKindOfClass:[NSString class]] && [val isKindOfClass:[NSString class]]) {
                [args addObject:@"-H"];
                [args addObject:[NSString stringWithFormat:@"%@: %@", key, val]];
            }
        }
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

+ (BOOL)classifyMediaData:(NSData *)headerBytes
              contentType:(NSString *)contentType
                urlString:(NSString *)urlString
                extension:(NSString **)outExt
                  isVideo:(BOOL *)outIsVideo {
    NSString *ext = nil;
    BOOL isVideo = NO;

    NSString *mime = @"";
    if (contentType && contentType.length > 0) {
        NSArray *parts = [[contentType lowercaseString] componentsSeparatedByString:@";"];
        mime = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }

    if ([mime hasPrefix:@"text/html"] || [mime isEqualToString:@"application/xhtml+xml"]) {
        return NO;
    }

    if ([mime isEqualToString:@"video/mp4"]) {
        ext = @"mp4"; isVideo = YES;
    } else if ([mime isEqualToString:@"video/x-m4v"]) {
        ext = @"m4v"; isVideo = YES;
    } else if ([mime isEqualToString:@"video/quicktime"]) {
        ext = @"mov"; isVideo = YES;
    } else if ([mime isEqualToString:@"image/gif"]) {
        ext = @"gif"; isVideo = NO;
    } else if ([mime isEqualToString:@"image/svg+xml"]) {
        ext = @"svg"; isVideo = NO;
    } else if ([mime isEqualToString:@"image/png"]) {
        ext = @"png"; isVideo = NO;
    } else if ([mime isEqualToString:@"image/jpeg"] || [mime isEqualToString:@"image/jpg"]) {
        ext = @"jpg"; isVideo = NO;
    } else if ([mime isEqualToString:@"image/webp"]) {
        ext = @"webp"; isVideo = NO;
    }

    if (!ext && headerBytes && headerBytes.length > 0) {
        const uint8_t *b = (const uint8_t *)[headerBytes bytes];
        NSUInteger len = [headerBytes length];
        if (len >= 8 && b[4] == 'f' && b[5] == 't' && b[6] == 'y' && b[7] == 'p') {
            ext = @"mp4"; isVideo = YES;
        } else if (len >= 6 && (memcmp(b, "GIF87a", 6) == 0 || memcmp(b, "GIF89a", 6) == 0)) {
            ext = @"gif"; isVideo = NO;
        } else if (len >= 4 && b[0] == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G') {
            ext = @"png"; isVideo = NO;
        } else if (len >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
            ext = @"jpg"; isVideo = NO;
        } else if (len >= 12 && memcmp(b, "RIFF", 4) == 0 && memcmp(b + 8, "WEBP", 4) == 0) {
            ext = @"webp"; isVideo = NO;
        } else {
            NSUInteger prefixLen = MIN(len, (NSUInteger)256);
            NSString *prefix = [[NSString alloc] initWithBytes:b length:prefixLen encoding:NSISOLatin1StringEncoding];
            NSString *low = [[prefix lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (low) {
                if ([low rangeOfString:@"<html"].location != NSNotFound || [low rangeOfString:@"<!doctype html"].location != NSNotFound) {
                    return NO;
                }
                if ([low rangeOfString:@"<svg"].location != NSNotFound) {
                    ext = @"svg"; isVideo = NO;
                }
            }
        }
    }

    if (!ext && urlString && urlString.length > 0) {
        NSURL *u = [NSURL URLWithString:urlString];
        NSString *pathExt = [[u pathExtension] lowercaseString];
        if ([pathExt isEqualToString:@"mp4"]) {
            ext = @"mp4"; isVideo = YES;
        } else if ([pathExt isEqualToString:@"m4v"]) {
            ext = @"m4v"; isVideo = YES;
        } else if ([pathExt isEqualToString:@"mov"]) {
            ext = @"mov"; isVideo = YES;
        } else if ([pathExt isEqualToString:@"gif"] || [pathExt isEqualToString:@"png"] ||
                   [pathExt isEqualToString:@"jpg"] || [pathExt isEqualToString:@"svg"] ||
                   [pathExt isEqualToString:@"webp"]) {
            ext = pathExt; isVideo = NO;
        } else if ([pathExt isEqualToString:@"jpeg"]) {
            ext = @"jpg"; isVideo = NO;
        }
    }

    if (!ext) return NO;
    if (outExt) *outExt = ext;
    if (outIsVideo) *outIsVideo = isVideo;
    return YES;
}

+ (NSString *)lastContentTypeFromHeaderData:(NSData *)headerData {
    if (!headerData || headerData.length == 0) return @"";
    NSString *raw = [[NSString alloc] initWithData:headerData encoding:NSISOLatin1StringEncoding];
    if (!raw) return @"";
    NSString *lastCT = @"";
    NSArray *lines = [raw componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([[trimmed lowercaseString] hasPrefix:@"content-type:"]) {
            lastCT = [[trimmed substringFromIndex:13] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
    }
    return lastCT;
}

+ (BOOL)cacheMediaURL:(NSString *)urlString
          inDirectory:(NSString *)cacheDir
             maxBytes:(uint64_t)maxBytes
              fileURL:(NSURL **)outFileURL
              isVideo:(BOOL *)outIsVideo
                error:(NSError **)outError {
    if (!urlString || urlString.length == 0 || !cacheDir || cacheDir.length == 0) {
        return NO;
    }
    NSString *lowerURL = [urlString lowercaseString];
    if (![lowerURL hasPrefix:@"http://"] && ![lowerURL hasPrefix:@"https://"]) {
        return NO;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:cacheDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *hash = [self sha256ForString:urlString];
    NSArray *knownExts = @[@"mp4", @"m4v", @"mov", @"gif", @"png", @"jpg", @"webp", @"svg"];
    for (NSString *e in knownExts) {
        NSString *cand = [cacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", hash, e]];
        NSDictionary *attrs = [fm attributesOfItemAtPath:cand error:nil];
        if (attrs && [attrs fileSize] > 0) {
            if (outFileURL) *outFileURL = [NSURL fileURLWithPath:cand];
            if (outIsVideo) *outIsVideo = ([e isEqualToString:@"mp4"] || [e isEqualToString:@"m4v"] || [e isEqualToString:@"mov"]);
            return YES;
        }
    }

    NSString *nonce = [[NSUUID UUID] UUIDString];
    NSString *tmpHdr = [cacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.hdr", hash, nonce]];
    NSString *tmpPart = [cacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.part", hash, nonce]];

    NSString *curl = [self resolvedCurlPath];
    NSString *ca = [self resolvedCABundlePath];
    NSMutableArray *args = [NSMutableArray array];
    if (ca) {
        [args addObject:@"--cacert"];
        [args addObject:ca];
    }
    [args addObjectsFromArray:@[
        @"-A", @"MavLlama/1.1",
        @"--proto", @"=http,https",
        @"--proto-redir", @"=http,https",
        @"-g",
        @"-fsSL",
        @"--max-time", @"30",
        @"--retry", @"1",
        @"--max-filesize", [NSString stringWithFormat:@"%llu", (unsigned long long)(maxBytes > 0 ? maxBytes : (50ULL * 1024ULL * 1024ULL))],
        @"-D", tmpHdr,
        @"-o", tmpPart,
        urlString
    ]];

    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:curl];
    [task setArguments:args];
    [task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
    [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];

    BOOL launched = NO;
    @try {
        [task launch];
        [task waitUntilExit];
        launched = YES;
    } @catch (NSException *ex) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"MavLlamaMediaCache"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: [ex reason] ?: @"Failed to run curl"}];
        }
    }

    if (!launched || [task terminationStatus] != 0) {
        [fm removeItemAtPath:tmpHdr error:nil];
        [fm removeItemAtPath:tmpPart error:nil];
        return NO;
    }

    NSData *hdrData = [NSData dataWithContentsOfFile:tmpHdr];
    NSString *ct = [self lastContentTypeFromHeaderData:hdrData];
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:tmpPart];
    NSData *magic = fh ? [fh readDataOfLength:256] : nil;
    [fh closeFile];

    NSString *ext = nil;
    BOOL isVideo = NO;
    NSDictionary *partAttrs = [fm attributesOfItemAtPath:tmpPart error:nil];
    if (!partAttrs || [partAttrs fileSize] == 0 ||
        ![self classifyMediaData:magic contentType:ct urlString:urlString extension:&ext isVideo:&isVideo]) {
        [fm removeItemAtPath:tmpHdr error:nil];
        [fm removeItemAtPath:tmpPart error:nil];
        return NO;
    }

    NSString *destPath = [cacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", hash, ext]];
    [fm removeItemAtPath:destPath error:nil];
    NSError *moveErr = nil;
    BOOL moved = [fm moveItemAtPath:tmpPart toPath:destPath error:&moveErr];
    [fm removeItemAtPath:tmpHdr error:nil];
    if (!moved) {
        [fm removeItemAtPath:tmpPart error:nil];
        if (outError) *outError = moveErr;
        return NO;
    }

    if (outFileURL) *outFileURL = [NSURL fileURLWithPath:destPath];
    if (outIsVideo) *outIsVideo = isVideo;
    return YES;
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
    if (!urlString || urlString.length == 0 || !partPath || !destPath) {
        if (completionBlock) {
            completionBlock(NO, @"Invalid download URL or destination path.");
        }
        return;
    }
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
