#import "EngineManager.h"

@implementation MavEngineTierInfo
@end

@interface EngineManager ()
@property (nonatomic, copy, readwrite) NSString *releaseTag;
@property (nonatomic, copy, readwrite) NSString *llamaCppCommit;
@property (nonatomic, strong, readwrite) NSDictionary *tiersByName;
@end

@implementation EngineManager

- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadEmbeddedManifest];
    }
    return self;
}

+ (NSString *)appSupportBase {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = paths.count > 0 ? paths[0] : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    return [base stringByAppendingPathComponent:@"MavLlama"];
}

+ (NSString *)defaultEngineDirectory {
    return [[self appSupportBase] stringByAppendingPathComponent:@"engine"];
}

+ (NSString *)defaultDownloadsDirectory {
    return [[self appSupportBase] stringByAppendingPathComponent:@"downloads"];
}

- (void)loadEmbeddedManifest {
    _releaseTag = @"v1.0.0";
    _llamaCppCommit = @"66a3b01";
    _tiersByName = @{};

    NSString *path = [[NSBundle mainBundle] pathForResource:@"engine-manifest" ofType:@"json"];
    if (!path) return;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return;

    if (json[@"releaseTag"]) _releaseTag = [json[@"releaseTag"] description];
    if (json[@"llamaCppCommit"]) _llamaCppCommit = [json[@"llamaCppCommit"] description];

    NSDictionary *tiers = json[@"tiers"];
    if (![tiers isKindOfClass:[NSDictionary class]]) return;

    NSMutableDictionary *parsed = [NSMutableDictionary dictionary];
    for (NSString *key in tiers) {
        NSDictionary *d = tiers[key];
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        MavEngineTierInfo *info = [[MavEngineTierInfo alloc] init];
        info.tier = key;
        info.url = [d[@"url"] description] ?: @"";
        info.sha256 = [d[@"sha256"] description] ?: @"";
        info.sizeBytes = [d[@"sizeBytes"] unsignedLongLongValue];
        parsed[key] = info;
    }
    _tiersByName = parsed;
}

- (NSString *)managedServerBinaryPath {
    return [[EngineManager defaultEngineDirectory] stringByAppendingPathComponent:@"llama-server"];
}

- (NSString *)activeServerBinaryPathWithCustomPath:(NSString *)customPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (customPath && customPath.length > 0 && [fm isExecutableFileAtPath:customPath]) {
        return customPath;
    }
    NSString *managed = [self managedServerBinaryPath];
    if ([fm isExecutableFileAtPath:managed]) {
        return managed;
    }
    return nil;
}

- (BOOL)isEngineInstalledWithCustomPath:(NSString *)customPath {
    return [self activeServerBinaryPathWithCustomPath:customPath] != nil;
}

- (NSDictionary *)installedMetadata {
    NSString *metaPath = [[EngineManager defaultEngineDirectory] stringByAppendingPathComponent:@"engine-meta.json"];
    NSData *data = [NSData dataWithContentsOfFile:metaPath];
    if (!data) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

- (MavEngineTierInfo *)infoForTier:(NSString *)tier {
    return self.tiersByName[tier];
}

- (BOOL)extractArchive:(NSString *)archivePath tierLabel:(NSString *)tierLabel error:(NSError **)outError {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *engineDir = [EngineManager defaultEngineDirectory];
    NSString *stagingDir = [[EngineManager appSupportBase] stringByAppendingPathComponent:@"engine-staging"];

    [fm removeItemAtPath:stagingDir error:nil];
    [fm createDirectoryAtPath:stagingDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSTask *tar = [[NSTask alloc] init];
    [tar setLaunchPath:@"/usr/bin/tar"];
    [tar setArguments:@[@"-xzf", archivePath, @"-C", stagingDir]];
    NSPipe *errPipe = [NSPipe pipe];
    [tar setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
    [tar setStandardError:errPipe];
    [tar launch];
    NSData *errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
    [tar waitUntilExit];

    if ([tar terminationStatus] != 0) {
        NSString *msg = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?: @"tar extraction failed";
        if (outError) {
            *outError = [NSError errorWithDomain:@"MavLlamaEngine" code:2 userInfo:@{NSLocalizedDescriptionKey: msg}];
        }
        [fm removeItemAtPath:stagingDir error:nil];
        return NO;
    }

    // Handle either flat archive (llama-server at root) or single top-level directory
    NSString *sourceRoot = stagingDir;
    NSString *directBin = [stagingDir stringByAppendingPathComponent:@"llama-server"];
    if (![fm fileExistsAtPath:directBin]) {
        NSArray *entries = [fm contentsOfDirectoryAtPath:stagingDir error:nil] ?: @[];
        for (NSString *entry in entries) {
            NSString *candidate = [[stagingDir stringByAppendingPathComponent:entry] stringByAppendingPathComponent:@"llama-server"];
            if ([fm fileExistsAtPath:candidate]) {
                sourceRoot = [stagingDir stringByAppendingPathComponent:entry];
                break;
            }
        }
    }

    NSString *stagedBin = [sourceRoot stringByAppendingPathComponent:@"llama-server"];
    if (![fm fileExistsAtPath:stagedBin]) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"MavLlamaEngine"
                                            code:3
                                        userInfo:@{NSLocalizedDescriptionKey: @"Engine archive does not contain llama-server."}];
        }
        [fm removeItemAtPath:stagingDir error:nil];
        return NO;
    }

    [fm removeItemAtPath:engineDir error:nil];
    NSError *moveErr = nil;
    if (![fm moveItemAtPath:sourceRoot toPath:engineDir error:&moveErr]) {
        if (outError) *outError = moveErr;
        [fm removeItemAtPath:stagingDir error:nil];
        return NO;
    }
    [fm removeItemAtPath:stagingDir error:nil];

    NSString *finalBin = [engineDir stringByAppendingPathComponent:@"llama-server"];
    [fm setAttributes:@{NSFilePosixPermissions: @(0755)} ofItemAtPath:finalBin error:nil];

    NSDictionary *meta = @{
        @"tier": tierLabel ?: @"unknown",
        @"releaseTag": self.releaseTag ?: @"v1.0.0",
        @"llamaCppCommit": self.llamaCppCommit ?: @"unknown"
    };
    NSData *metaData = [NSJSONSerialization dataWithJSONObject:meta options:NSJSONWritingPrettyPrinted error:nil];
    if (metaData) {
        [metaData writeToFile:[engineDir stringByAppendingPathComponent:@"engine-meta.json"] atomically:YES];
    }
    return YES;
}

- (BOOL)installLocalArchiveAtPath:(NSString *)archivePath
                        tierLabel:(NSString *)tierLabel
                            error:(NSError **)outError {
    return [self extractArchive:archivePath tierLabel:tierLabel error:outError];
}

- (void)installEngineForTier:(NSString *)tier
             downloadManager:(DownloadManager *)downloadManager
                    progress:(MavDownloadProgressBlock)progressBlock
                  completion:(void (^)(BOOL success, NSString *message))completion {
    MavEngineTierInfo *info = [self infoForTier:tier];
    if (!info || info.url.length == 0 || info.sha256.length == 0) {
        if (completion) {
            completion(NO, [NSString stringWithFormat:@"No pinned release URL/SHA-256 found for CPU tier '%@'. You can install a local engine archive instead.", tier]);
        }
        return;
    }

    NSString *dlDir = [EngineManager defaultDownloadsDirectory];
    NSString *tarName = [NSString stringWithFormat:@"mavllama-engine-%@.tar.gz", tier];
    NSString *partPath = [dlDir stringByAppendingPathComponent:[tarName stringByAppendingString:@".part"]];
    NSString *destPath = [dlDir stringByAppendingPathComponent:tarName];

    [downloadManager downloadURL:info.url
                   expectedBytes:info.sizeBytes
                  expectedSHA256:info.sha256
                        partPath:partPath
                        destPath:destPath
                           label:[NSString stringWithFormat:@"Engine (%@)", tier]
                        progress:progressBlock
                      completion:^(BOOL ok, NSString *errMsg) {
        if (!ok) {
            if (completion) completion(NO, errMsg ?: @"Engine download failed.");
            return;
        }
        NSError *extractErr = nil;
        BOOL extracted = [self extractArchive:destPath tierLabel:tier error:&extractErr];
        [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
        if (!extracted) {
            if (completion) completion(NO, [extractErr localizedDescription] ?: @"Failed to unpack engine.");
            return;
        }
        if (completion) {
            completion(YES, [NSString stringWithFormat:@"Installed tailored '%@' engine (%@).", tier, self.releaseTag]);
        }
    }];
}

@end
