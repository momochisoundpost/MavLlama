#import "UpdateManager.h"
#import "MarkdownRenderer.h"
#import "ServerController.h"
#import <Cocoa/Cocoa.h>
#import <sys/stat.h>
#import <unistd.h>

static NSString * const kReleasesAPIURL = @"https://api.github.com/repos/momochisoundpost/MavLlama/releases";
static NSTimeInterval const kReleaseCacheTTLSeconds = 6.0 * 3600.0;
static uint64_t const kMaxCachedMediaBytes = 50ULL * 1024ULL * 1024ULL;

@implementation MavReleaseInfo
@end

static BOOL MavIsAllDigits(NSString *s) {
    if (!s || s.length == 0) return NO;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c < '0' || c > '9') return NO;
    }
    return YES;
}

static void MavSplitVersionString(NSString *v, NSString **outBase, NSString **outPre) {
    NSString *s = [(v ?: @"0") stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([s hasPrefix:@"v"] || [s hasPrefix:@"V"]) {
        s = [s substringFromIndex:1];
    }
    NSRange dash = [s rangeOfString:@"-"];
    if (dash.location != NSNotFound) {
        *outBase = [s substringToIndex:dash.location];
        *outPre = [s substringFromIndex:dash.location + 1];
    } else {
        *outBase = s;
        *outPre = nil;
    }
}

@interface UpdateManager ()
@property (nonatomic, strong) dispatch_queue_t workerQueue;
@property (nonatomic, copy) NSString *activeRenderToken;
@end

@implementation UpdateManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _workerQueue = dispatch_queue_create("com.momochisoundpost.MavLlama.updater", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

+ (NSString *)cacheDirectory {
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject]
                       ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"];
    return [caches stringByAppendingPathComponent:@"MavLlama"];
}

+ (NSString *)mediaCacheDirectory {
    return [[self cacheDirectory] stringByAppendingPathComponent:@"release-media"];
}

+ (NSString *)updatesSupportDirectory {
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject]
                           ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    return [[appSupport stringByAppendingPathComponent:@"MavLlama"] stringByAppendingPathComponent:@"updates"];
}

+ (NSComparisonResult)compareVersion:(NSString *)v1 toVersion:(NSString *)v2 {
    NSString *b1 = nil, *p1 = nil;
    NSString *b2 = nil, *p2 = nil;
    MavSplitVersionString(v1, &b1, &p1);
    MavSplitVersionString(v2, &b2, &p2);

    NSArray *c1 = [b1 componentsSeparatedByString:@"."];
    NSArray *c2 = [b2 componentsSeparatedByString:@"."];
    NSUInteger maxCount = MAX(c1.count, c2.count);

    for (NSUInteger i = 0; i < maxCount; i++) {
        NSInteger n1 = (i < c1.count) ? [c1[i] integerValue] : 0;
        NSInteger n2 = (i < c2.count) ? [c2[i] integerValue] : 0;
        if (n1 < n2) return NSOrderedAscending;
        if (n1 > n2) return NSOrderedDescending;
    }

    BOOL hasPre1 = (p1 && p1.length > 0);
    BOOL hasPre2 = (p2 && p2.length > 0);
    if (!hasPre1 && !hasPre2) return NSOrderedSame;
    if (!hasPre1 && hasPre2) return NSOrderedDescending;
    if (hasPre1 && !hasPre2) return NSOrderedAscending;

    NSArray *pc1 = [p1 componentsSeparatedByString:@"."];
    NSArray *pc2 = [p2 componentsSeparatedByString:@"."];
    NSUInteger pMax = MAX(pc1.count, pc2.count);
    for (NSUInteger i = 0; i < pMax; i++) {
        if (i >= pc1.count) return NSOrderedAscending;
        if (i >= pc2.count) return NSOrderedDescending;
        NSString *s1 = pc1[i];
        NSString *s2 = pc2[i];
        if (MavIsAllDigits(s1) && MavIsAllDigits(s2)) {
            NSInteger i1 = [s1 integerValue];
            NSInteger i2 = [s2 integerValue];
            if (i1 < i2) return NSOrderedAscending;
            if (i1 > i2) return NSOrderedDescending;
        } else {
            NSComparisonResult cr = [s1 compare:s2 options:NSCaseInsensitiveSearch];
            if (cr != NSOrderedSame) return cr;
        }
    }
    return NSOrderedSame;
}

+ (NSArray *)parseReleasesFromData:(NSData *)jsonData error:(NSError **)outError {
    if (!jsonData) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"MavLlamaUpdate" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Empty releases payload."}];
        }
        return nil;
    }
    NSError *parseErr = nil;
    id root = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&parseErr];
    if (!root || ![root isKindOfClass:[NSArray class]]) {
        if (outError) {
            *outError = parseErr ?: [NSError errorWithDomain:@"MavLlamaUpdate" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid GitHub Releases JSON array."}];
        }
        return nil;
    }

    NSMutableArray *result = [NSMutableArray array];
    for (id obj in (NSArray *)root) {
        if (![obj isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *dict = (NSDictionary *)obj;
        if ([dict[@"draft"] boolValue]) continue;

        MavReleaseInfo *info = [[MavReleaseInfo alloc] init];
        info.tagName = [dict[@"tag_name"] isKindOfClass:[NSString class]] ? dict[@"tag_name"] : @"";
        info.name = [dict[@"name"] isKindOfClass:[NSString class]] ? dict[@"name"] : info.tagName;
        if (info.name.length == 0) info.name = info.tagName;
        info.body = [dict[@"body"] isKindOfClass:[NSString class]] ? dict[@"body"] : @"";
        info.htmlURL = [dict[@"html_url"] isKindOfClass:[NSString class]] ? dict[@"html_url"] : @"https://github.com/momochisoundpost/MavLlama/releases";
        info.publishedAt = [dict[@"published_at"] isKindOfClass:[NSString class]] ? dict[@"published_at"] : @"";
        info.prerelease = [dict[@"prerelease"] boolValue];
        info.draft = NO;

        NSArray *assets = [dict[@"assets"] isKindOfClass:[NSArray class]] ? dict[@"assets"] : @[];
        NSString *fallbackZipName = nil;
        NSString *fallbackZipURL = nil;
        uint64_t fallbackZipSize = 0;

        for (id aObj in assets) {
            if (![aObj isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *asset = (NSDictionary *)aObj;
            NSString *aName = [asset[@"name"] isKindOfClass:[NSString class]] ? asset[@"name"] : @"";
            NSString *aURL = [asset[@"browser_download_url"] isKindOfClass:[NSString class]] ? asset[@"browser_download_url"] : @"";
            uint64_t aSize = [asset[@"size"] respondsToSelector:@selector(unsignedLongLongValue)] ? [asset[@"size"] unsignedLongLongValue] : 0;

            if ([[aName lowercaseString] isEqualToString:@"checksums.txt"] && aURL.length > 0) {
                info.checksumsDownloadURL = aURL;
            }
            NSString *lowName = [aName lowercaseString];
            if ([lowName hasPrefix:@"mavllama"] && [lowName hasSuffix:@".zip"] && aURL.length > 0) {
                if ([lowName rangeOfString:@"mavericks"].location != NSNotFound && !info.appZipDownloadURL) {
                    info.appZipAssetName = aName;
                    info.appZipDownloadURL = aURL;
                    info.appZipSizeBytes = aSize;
                } else if (!fallbackZipURL) {
                    fallbackZipName = aName;
                    fallbackZipURL = aURL;
                    fallbackZipSize = aSize;
                }
            }
        }
        if (!info.appZipDownloadURL && fallbackZipURL) {
            info.appZipAssetName = fallbackZipName;
            info.appZipDownloadURL = fallbackZipURL;
            info.appZipSizeBytes = fallbackZipSize;
        }
        if (info.tagName.length > 0) {
            [result addObject:info];
        }
    }
    return result;
}

+ (MavReleaseInfo *)latestStableReleaseFromReleases:(NSArray *)releases {
    MavReleaseInfo *best = nil;
    for (MavReleaseInfo *r in releases) {
        if (r.draft || r.prerelease) continue;
        if (!r.appZipDownloadURL || r.appZipDownloadURL.length == 0) continue;
        if (!best || [self compareVersion:r.tagName toVersion:best.tagName] == NSOrderedDescending) {
            best = r;
        }
    }
    return best;
}

+ (NSString *)parseSHA256ForFilename:(NSString *)filename fromChecksumsText:(NSString *)text {
    if (!filename || filename.length == 0 || !text || text.length == 0) return nil;
    NSArray *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length < 66) continue;
        NSArray *parts = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSMutableArray *nonEmpty = [NSMutableArray array];
        for (NSString *p in parts) {
            if (p.length > 0) [nonEmpty addObject:p];
        }
        if (nonEmpty.count >= 2) {
            NSString *candHash = [nonEmpty[0] lowercaseString];
            NSString *candName = nonEmpty[nonEmpty.count - 1];
            if ([candName isEqualToString:filename] && candHash.length == 64) {
                return candHash;
            }
        }
    }
    return nil;
}

+ (NSString *)updaterShellScriptContents {
    return
        @"#!/bin/sh\n"
        @"OLD_PID=\"$1\"\n"
        @"STAGED_APP=\"$2\"\n"
        @"TARGET_APP=\"$3\"\n"
        @"STAGING_DIR=\"$4\"\n"
        @"BACKUP_APP=\"${TARGET_APP}.old-$$\"\n"
        @"\n"
        @"echo \"[MavLlama Updater] Waiting for PID $OLD_PID to exit...\"\n"
        @"i=0\n"
        @"while kill -0 \"$OLD_PID\" 2>/dev/null && [ $i -lt 50 ]; do\n"
        @"  sleep 0.2\n"
        @"  i=$((i + 1))\n"
        @"done\n"
        @"\n"
        @"if mv \"$TARGET_APP\" \"$BACKUP_APP\"; then\n"
        @"  if mv \"$STAGED_APP\" \"$TARGET_APP\"; then\n"
        @"    rm -rf \"$BACKUP_APP\" \"$STAGING_DIR\"\n"
        @"    echo \"[MavLlama Updater] Replaced $TARGET_APP successfully; launching...\"\n"
        @"    /usr/bin/open \"$TARGET_APP\"\n"
        @"    exit 0\n"
        @"  else\n"
        @"    echo \"[MavLlama Updater] Failed moving staged app; restoring backup...\"\n"
        @"    mv \"$BACKUP_APP\" \"$TARGET_APP\"\n"
        @"  fi\n"
        @"fi\n"
        @"echo \"[MavLlama Updater] Update replacement failed.\"\n"
        @"exit 1\n";
}

- (NSString *)currentAppVersion {
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return (ver && ver.length > 0) ? ver : @"1.0.0";
}

- (void)checkForUpdatesForceRefresh:(BOOL)force
                         completion:(void (^)(NSArray *releases,
                                              MavReleaseInfo *latestStable,
                                              BOOL updateAvailable,
                                              NSError *error))completion {
    dispatch_async(self.workerQueue, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *cacheDir = [UpdateManager cacheDirectory];
        [fm createDirectoryAtPath:cacheDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *cachePath = [cacheDir stringByAppendingPathComponent:@"releases-cache.json"];

        if (!force && [fm fileExistsAtPath:cachePath]) {
            NSData *cachedRaw = [NSData dataWithContentsOfFile:cachePath];
            id wrapper = cachedRaw ? [NSJSONSerialization JSONObjectWithData:cachedRaw options:0 error:nil] : nil;
            if ([wrapper isKindOfClass:[NSDictionary class]]) {
                double fetchedAt = [wrapper[@"fetchedAt"] doubleValue];
                id rawArray = wrapper[@"releases"];
                double age = [[NSDate date] timeIntervalSince1970] - fetchedAt;
                if (age >= 0 && age < kReleaseCacheTTLSeconds && [rawArray isKindOfClass:[NSArray class]]) {
                    NSData *arrData = [NSJSONSerialization dataWithJSONObject:rawArray options:0 error:nil];
                    NSArray *parsed = [UpdateManager parseReleasesFromData:arrData error:nil];
                    if (parsed) {
                        MavReleaseInfo *latest = [UpdateManager latestStableReleaseFromReleases:parsed];
                        BOOL avail = (latest && [UpdateManager compareVersion:latest.tagName toVersion:[self currentAppVersion]] == NSOrderedDescending);
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (completion) completion(parsed, latest, avail, nil);
                        });
                        return;
                    }
                }
            }
        }

        NSError *fetchErr = nil;
        NSData *data = [DownloadManager fetchDataFromURL:kReleasesAPIURL
                                                 headers:@{@"Accept": @"application/vnd.github+json"}
                                                   error:&fetchErr];
        if (!data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, nil, NO, fetchErr);
            });
            return;
        }

        NSError *parseErr = nil;
        NSArray *parsed = [UpdateManager parseReleasesFromData:data error:&parseErr];
        if (!parsed) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, nil, NO, parseErr);
            });
            return;
        }

        id rawJSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([rawJSON isKindOfClass:[NSArray class]]) {
            NSDictionary *wrapper = @{
                @"fetchedAt": @([[NSDate date] timeIntervalSince1970]),
                @"releases": rawJSON
            };
            NSData *wrapData = [NSJSONSerialization dataWithJSONObject:wrapper options:0 error:nil];
            if (wrapData) {
                [wrapData writeToFile:cachePath atomically:YES];
            }
        }

        MavReleaseInfo *latest = [UpdateManager latestStableReleaseFromReleases:parsed];
        BOOL avail = (latest && [UpdateManager compareVersion:latest.tagName toVersion:[self currentAppVersion]] == NSOrderedDescending);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(parsed, latest, avail, nil);
        });
    });
}

- (void)renderRelease:(MavReleaseInfo *)release
          initialHTML:(void (^)(NSString *html, NSURL *baseURL))initialBlock
          updatedHTML:(void (^)(NSString *html, NSURL *baseURL))updatedBlock {
    if (!release) return;
    NSString *token = [[NSUUID UUID] UUIDString];
    self.activeRenderToken = token;

    NSString *mediaDir = [UpdateManager mediaCacheDirectory];
    NSURL *baseURL = [NSURL fileURLWithPath:mediaDir];
    NSArray *mediaURLs = [MarkdownRenderer extractRemoteMediaURLsFromMarkdown:release.body ?: @""];
    [[NSFileManager defaultManager] createDirectoryAtPath:mediaDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *initHTML = [MarkdownRenderer renderHTMLFromMarkdown:release.body ?: @""
                                                     releaseTitle:release.name
                                                       releaseTag:release.tagName
                                                    resolvedMedia:@{}];
    if (initialBlock) {
        initialBlock(initHTML, baseURL);
    }

    if (mediaURLs.count == 0) return;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableDictionary *fetchedMap = [NSMutableDictionary dictionary];
        BOOL anyResolved = NO;
        for (NSString *u in mediaURLs) {
            if (![self.activeRenderToken isEqualToString:token]) return;
            NSURL *localURL = nil;
            BOOL isVid = NO;
            if ([DownloadManager cacheMediaURL:u
                                   inDirectory:mediaDir
                                      maxBytes:kMaxCachedMediaBytes
                                       fileURL:&localURL
                                       isVideo:&isVid
                                         error:nil] && localURL) {
                MavResolvedMedia *m = [[MavResolvedMedia alloc] init];
                m.fileURLString = [localURL absoluteString];
                m.isVideo = isVid;
                fetchedMap[u] = m;
                anyResolved = YES;
            }
        }
        if (anyResolved && [self.activeRenderToken isEqualToString:token]) {
            NSString *finalHTML = [MarkdownRenderer renderHTMLFromMarkdown:release.body ?: @""
                                                              releaseTitle:release.name
                                                                releaseTag:release.tagName
                                                             resolvedMedia:fetchedMap];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.activeRenderToken isEqualToString:token] && updatedBlock) {
                    updatedBlock(finalHTML, baseURL);
                }
            });
        }
    });
}

+ (NSString *)locateStagedAppInDirectory:(NSString *)stagingDir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *direct = [stagingDir stringByAppendingPathComponent:@"MavLlama.app"];
    if ([fm fileExistsAtPath:[direct stringByAppendingPathComponent:@"Contents/Info.plist"]]) {
        return direct;
    }
    NSArray *items = [fm contentsOfDirectoryAtPath:stagingDir error:nil];
    for (NSString *item in items) {
        if ([[item lowercaseString] hasSuffix:@".app"]) {
            NSString *cand = [stagingDir stringByAppendingPathComponent:item];
            NSString *plistPath = [cand stringByAppendingPathComponent:@"Contents/Info.plist"];
            NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
            if (plist && [plist[@"CFBundleIdentifier"] isEqualToString:@"com.momochisoundpost.MavLlama"]) {
                return cand;
            }
        }
    }
    return nil;
}

- (void)installRelease:(MavReleaseInfo *)release
       downloadManager:(DownloadManager *)downloadManager
      serverController:(ServerController *)serverController
              progress:(MavDownloadProgressBlock)progressBlock
            completion:(void (^)(BOOL launchedUpdater, NSString *errorMessage))completion {
    if (!release || !release.appZipDownloadURL || release.appZipDownloadURL.length == 0) {
        if (completion) completion(NO, @"Selected release does not contain a MavLlama .zip app bundle.");
        return;
    }
    if (downloadManager.isDownloading) {
        if (completion) completion(NO, @"Another download is currently running. Please wait or cancel it first.");
        return;
    }

    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *targetAppPath = [mainBundle bundlePath];
    NSString *targetParentDir = [targetAppPath stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![targetAppPath hasSuffix:@".app"] ||
        ![fm fileExistsAtPath:[targetAppPath stringByAppendingPathComponent:@"Contents/Info.plist"]]) {
        if (completion) {
            completion(NO, [NSString stringWithFormat:@"Cannot auto-update non-bundle binary at %@", targetAppPath]);
        }
        return;
    }
    if (![fm isWritableFileAtPath:targetParentDir] || ![fm isWritableFileAtPath:targetAppPath]) {
        if (completion) {
            completion(NO, [NSString stringWithFormat:
                            @"MavLlama does not have write permission to replace %@. Move MavLlama.app to /Applications or a user-writable folder and try again.",
                            targetAppPath]);
        }
        return;
    }

    dispatch_async(self.workerQueue, ^{
        NSString *expectedSHA = nil;
        if (release.checksumsDownloadURL && release.checksumsDownloadURL.length > 0) {
            NSData *chkData = [DownloadManager fetchDataFromURL:release.checksumsDownloadURL headers:nil error:nil];
            if (chkData) {
                NSString *chkText = [[NSString alloc] initWithData:chkData encoding:NSUTF8StringEncoding];
                expectedSHA = [UpdateManager parseSHA256ForFilename:release.appZipAssetName fromChecksumsText:chkText];
            }
        }

        NSString *updatesDir = [UpdateManager updatesSupportDirectory];
        [fm createDirectoryAtPath:updatesDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *zipName = release.appZipAssetName.length > 0 ? release.appZipAssetName : @"MavLlama-update.zip";
        NSString *destZip = [updatesDir stringByAppendingPathComponent:zipName];
        NSString *partZip = [destZip stringByAppendingString:@".part"];
        [fm removeItemAtPath:partZip error:nil];
        [fm removeItemAtPath:destZip error:nil];

        dispatch_async(dispatch_get_main_queue(), ^{
            [downloadManager downloadURL:release.appZipDownloadURL
                           expectedBytes:release.appZipSizeBytes
                          expectedSHA256:expectedSHA
                                partPath:partZip
                                destPath:destZip
                                   label:zipName
                                progress:progressBlock
                              completion:^(BOOL ok, NSString *errMsg) {
                if (!ok) {
                    if (completion) completion(NO, errMsg ?: @"Failed to download update zip.");
                    return;
                }

                dispatch_async(self.workerQueue, ^{
                    NSString *stagingDir = [updatesDir stringByAppendingPathComponent:[NSString stringWithFormat:@"staging-%@", [[NSUUID UUID] UUIDString]]];
                    [fm createDirectoryAtPath:stagingDir withIntermediateDirectories:YES attributes:nil error:nil];

                    NSTask *ditto = [[NSTask alloc] init];
                    [ditto setLaunchPath:@"/usr/bin/ditto"];
                    [ditto setArguments:@[@"-x", @"-k", destZip, stagingDir]];
                    [ditto setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
                    [ditto setStandardError:[NSFileHandle fileHandleWithNullDevice]];
                    BOOL dittoOK = NO;
                    @try {
                        [ditto launch];
                        [ditto waitUntilExit];
                        dittoOK = ([ditto terminationStatus] == 0);
                    } @catch (NSException *ex) {
                        (void)ex;
                    }

                    [fm removeItemAtPath:destZip error:nil];

                    if (!dittoOK) {
                        [fm removeItemAtPath:stagingDir error:nil];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (completion) completion(NO, @"Failed to extract update archive with ditto.");
                        });
                        return;
                    }

                    NSString *stagedApp = [UpdateManager locateStagedAppInDirectory:stagingDir];
                    NSString *stagedExe = stagedApp ? [stagedApp stringByAppendingPathComponent:@"Contents/MacOS/MavLlama"] : nil;
                    NSDictionary *stagedPlist = stagedApp ? [NSDictionary dictionaryWithContentsOfFile:[stagedApp stringByAppendingPathComponent:@"Contents/Info.plist"]] : nil;

                    if (!stagedApp || !stagedPlist || ![fm isExecutableFileAtPath:stagedExe]) {
                        [fm removeItemAtPath:stagingDir error:nil];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (completion) completion(NO, @"Extracted archive does not contain a valid MavLlama.app bundle.");
                        });
                        return;
                    }

                    // Strip quarantine extended attributes so OS X 10.9 Gatekeeper won't block relaunch
                    NSTask *xattr = [[NSTask alloc] init];
                    [xattr setLaunchPath:@"/usr/bin/xattr"];
                    [xattr setArguments:@[@"-dr", @"com.apple.quarantine", stagedApp]];
                    [xattr setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
                    [xattr setStandardError:[NSFileHandle fileHandleWithNullDevice]];
                    @try {
                        [xattr launch];
                        [xattr waitUntilExit];
                    } @catch (NSException *ex) {
                        (void)ex;
                    }

                    NSString *scriptPath = [updatesDir stringByAppendingPathComponent:@"apply-update.sh"];
                    NSError *writeErr = nil;
                    BOOL wroteScript = [[UpdateManager updaterShellScriptContents] writeToFile:scriptPath
                                                                                     atomically:YES
                                                                                       encoding:NSUTF8StringEncoding
                                                                                          error:&writeErr];
                    if (!wroteScript) {
                        [fm removeItemAtPath:stagingDir error:nil];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (completion) completion(NO, [writeErr localizedDescription] ?: @"Failed to write updater helper script.");
                        });
                        return;
                    }
                    chmod([scriptPath fileSystemRepresentation], 0755);

                    dispatch_async(dispatch_get_main_queue(), ^{
                        [serverController stopSynchronouslyForTermination];

                        NSString *logsDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs"];
                        [fm createDirectoryAtPath:logsDir withIntermediateDirectories:YES attributes:nil error:nil];
                        NSString *updaterLog = [logsDir stringByAppendingPathComponent:@"MavLlama-updater.log"];

                        NSString *pidStr = [NSString stringWithFormat:@"%d", (int)getpid()];
                        NSTask *launcher = [[NSTask alloc] init];
                        [launcher setLaunchPath:@"/bin/sh"];
                        [launcher setArguments:@[
                            @"-c",
                            @"nohup /bin/sh \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" </dev/null >>\"$6\" 2>&1 &",
                            @"_",
                            scriptPath,
                            pidStr,
                            stagedApp,
                            targetAppPath,
                            stagingDir,
                            updaterLog
                        ]];
                        @try {
                            [launcher launch];
                        } @catch (NSException *ex) {
                            if (completion) completion(NO, [ex reason] ?: @"Failed to launch updater helper.");
                            return;
                        }

                        if (completion) completion(YES, nil);
                        [NSApp terminate:nil];
                    });
                });
            }];
        });
    });
}

@end
