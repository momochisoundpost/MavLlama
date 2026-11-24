#import "ServerController.h"
#import "HardwareInspector.h"
#import <signal.h>

static NSString * const kPrefModelsDir = @"MavModelsDirectory";
static NSString * const kPrefPort = @"MavServerPort";
static NSString * const kPrefAllowLAN = @"MavAllowLAN";
static NSString * const kPrefThreads = @"MavThreads";
static NSString * const kPrefCtxSize = @"MavCtxSize";
static NSString * const kPrefAutoStart = @"MavAutoStart";
static NSString * const kPrefCustomEngine = @"MavCustomEnginePath";

@interface ServerController ()
@property (nonatomic, strong) EngineManager *engineManager;
@property (nonatomic, strong) NSTask *serverTask;
@property (nonatomic, strong) NSFileHandle *logHandle;
@property (nonatomic, strong) dispatch_queue_t workerQueue;
@property (nonatomic, assign, readwrite) BOOL isRunning;
@property (nonatomic, assign, readwrite) BOOL isHealthy;
@property (nonatomic, assign, readwrite) BOOL isBusy;
@property (nonatomic, assign, readwrite) double serverRSSMB;
@property (nonatomic, copy, readwrite) NSString *activePIDsText;
@property (nonatomic, copy, readwrite) NSArray *loadedModels;
@property (nonatomic, copy, readwrite) NSArray *availableModels;
@property (nonatomic, copy, readwrite) NSString *lastError;
@property (nonatomic, copy) NSString *launchedBinaryPath;
@end

@implementation ServerController

+ (NSString *)defaultModelsDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = paths.count > 0 ? paths[0] : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    return [[base stringByAppendingPathComponent:@"MavLlama"] stringByAppendingPathComponent:@"models"];
}

+ (NSString *)logFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *lib = paths.count > 0 ? paths[0] : [NSHomeDirectory() stringByAppendingPathComponent:@"Library"];
    return [[lib stringByAppendingPathComponent:@"Logs/MavLlama"] stringByAppendingPathComponent:@"llama-server.log"];
}

- (instancetype)initWithEngineManager:(EngineManager *)engineManager {
    self = [super init];
    if (self) {
        _engineManager = engineManager;
        _workerQueue = dispatch_queue_create("com.momochisoundpost.MavLlama.server", DISPATCH_QUEUE_SERIAL);
        _loadedModels = @[];
        _availableModels = @[];
        _activePIDsText = @"";
        [self ensureDirectoriesExist];
    }
    return self;
}

- (void)ensureDirectoriesExist {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:[self modelsDirectory] withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:[[ServerController logFilePath] stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
}

- (NSString *)modelsDirectory {
    NSString *val = [[NSUserDefaults standardUserDefaults] stringForKey:kPrefModelsDir];
    if (val && val.length > 0) return val;
    return [ServerController defaultModelsDirectory];
}

- (void)setModelsDirectory:(NSString *)modelsDirectory {
    if (!modelsDirectory || modelsDirectory.length == 0) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPrefModelsDir];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:modelsDirectory forKey:kPrefModelsDir];
        [[NSFileManager defaultManager] createDirectoryAtPath:modelsDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (NSInteger)port {
    NSInteger p = [[NSUserDefaults standardUserDefaults] integerForKey:kPrefPort];
    return (p > 0 && p <= 65535) ? p : 8080;
}

- (void)setPort:(NSInteger)port {
    if (port <= 0 || port > 65535) port = 8080;
    [[NSUserDefaults standardUserDefaults] setInteger:port forKey:kPrefPort];
}

- (BOOL)allowLAN {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:kPrefAllowLAN] == nil) return YES;
    return [[NSUserDefaults standardUserDefaults] boolForKey:kPrefAllowLAN];
}

- (void)setAllowLAN:(BOOL)allowLAN {
    [[NSUserDefaults standardUserDefaults] setBool:allowLAN forKey:kPrefAllowLAN];
}

- (NSInteger)threads {
    return [[NSUserDefaults standardUserDefaults] integerForKey:kPrefThreads];
}

- (void)setThreads:(NSInteger)threads {
    [[NSUserDefaults standardUserDefaults] setInteger:threads forKey:kPrefThreads];
}

- (NSInteger)ctxSize {
    return [[NSUserDefaults standardUserDefaults] integerForKey:kPrefCtxSize];
}

- (void)setCtxSize:(NSInteger)ctxSize {
    [[NSUserDefaults standardUserDefaults] setInteger:ctxSize forKey:kPrefCtxSize];
}

- (BOOL)autoStart {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kPrefAutoStart];
}

- (void)setAutoStart:(BOOL)autoStart {
    [[NSUserDefaults standardUserDefaults] setBool:autoStart forKey:kPrefAutoStart];
}

- (NSString *)customEnginePath {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kPrefCustomEngine] ?: @"";
}

- (void)setCustomEnginePath:(NSString *)customEnginePath {
    if (!customEnginePath || customEnginePath.length == 0) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPrefCustomEngine];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:customEnginePath forKey:kPrefCustomEngine];
    }
}

- (NSArray *)managedProcessPIDsWithTotalRSSMB:(double *)outRSSMB {
    NSTask *ps = [[NSTask alloc] init];
    [ps setLaunchPath:@"/bin/ps"];
    [ps setArguments:@[@"-axo", @"pid=,rss=,command="]];
    NSPipe *pipe = [NSPipe pipe];
    [ps setStandardOutput:pipe];
    [ps setStandardError:[NSFileHandle fileHandleWithNullDevice]];

    NSMutableArray *pids = [NSMutableArray array];
    double rssKB = 0.0;

    @try {
        [ps launch];
        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        [ps waitUntilExit];
        NSString *out = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";

        NSString *managedPath = [self.engineManager managedServerBinaryPath];
        NSString *customPath = self.customEnginePath;

        for (NSString *line in [out componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
            BOOL matchManaged = (managedPath.length > 0 && [line rangeOfString:managedPath].location != NSNotFound);
            BOOL matchCustom = (customPath.length > 0 && [line rangeOfString:customPath].location != NSNotFound);
            BOOL matchLaunched = (self.launchedBinaryPath.length > 0 && [line rangeOfString:self.launchedBinaryPath].location != NSNotFound);
            if (!(matchManaged || matchCustom || matchLaunched)) continue;

            NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSScanner *scanner = [NSScanner scannerWithString:trimmed];
            long long pid = 0, rss = 0;
            if ([scanner scanLongLong:&pid] && [scanner scanLongLong:&rss] && pid > 0) {
                [pids addObject:@((pid_t)pid)];
                rssKB += (double)rss;
            }
        }
    } @catch (NSException *ex) {
        (void)ex;
    }

    if (outRSSMB) *outRSSMB = rssKB / 1024.0;
    return pids;
}

- (void)terminateManagedProcessesSync {
    if (self.serverTask && [self.serverTask isRunning]) {
        [self.serverTask terminate];
    }

    NSArray *pids = [self managedProcessPIDsWithTotalRSSMB:NULL];
    for (NSNumber *num in pids) {
        kill((pid_t)[num intValue], SIGTERM);
    }

    for (int i = 0; i < 15; i++) {
        NSArray *left = [self managedProcessPIDsWithTotalRSSMB:NULL];
        if (left.count == 0) break;
        [NSThread sleepForTimeInterval:0.1];
    }

    NSArray *stubborn = [self managedProcessPIDsWithTotalRSSMB:NULL];
    for (NSNumber *num in stubborn) {
        kill((pid_t)[num intValue], SIGKILL);
    }

    self.serverTask = nil;
    if (self.logHandle) {
        [self.logHandle closeFile];
        self.logHandle = nil;
    }
}

- (void)stopSynchronouslyForTermination {
    [self terminateManagedProcessesSync];
}

- (void)startServerWithHardwareRAMGB:(NSInteger)ramGB logicalCPUs:(NSInteger)cpus completion:(void (^)(BOOL success, NSString *error))completion {
    if (self.isBusy) {
        if (completion) completion(NO, @"Server is busy.");
        return;
    }

    NSString *binPath = [self.engineManager activeServerBinaryPathWithCustomPath:self.customEnginePath];
    if (!binPath) {
        if (completion) completion(NO, @"No llama-server engine installed. Download one in System Check & Engine.");
        return;
    }

    NSString *modelsDir = self.modelsDirectory;
    [[NSFileManager defaultManager] createDirectoryAtPath:modelsDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSInteger effectiveThreads = self.threads > 0 ? self.threads : (cpus > 0 ? cpus : 2);
    NSInteger effectiveCtx = self.ctxSize > 0 ? self.ctxSize : [HardwareInspector recommendedContextSizeForRAMGB:ramGB];
    NSInteger listenPort = self.port;
    NSString *listenHost = self.allowLAN ? @"0.0.0.0" : @"127.0.0.1";

    self.isBusy = YES;
    self.lastError = nil;

    dispatch_async(self.workerQueue, ^{
        [self terminateManagedProcessesSync];

        NSString *logPath = [ServerController logFilePath];
        [[NSFileManager defaultManager] createDirectoryAtPath:[logPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        [[NSFileManager defaultManager] createFileAtPath:logPath contents:[NSData data] attributes:nil];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];

        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:binPath];
        [task setArguments:@[
            @"--models-dir", modelsDir,
            @"--models-max", @"1",
            @"--host", listenHost,
            @"--port", [NSString stringWithFormat:@"%ld", (long)listenPort],
            @"-t", [NSString stringWithFormat:@"%ld", (long)effectiveThreads],
            @"-c", [NSString stringWithFormat:@"%ld", (long)effectiveCtx],
            @"-fa", @"on",
            @"-ctk", @"q8_0",
            @"-ctv", @"q8_0"
        ]];
        if (fh) {
            [task setStandardOutput:fh];
            [task setStandardError:fh];
        } else {
            [task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
            [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
        }

        self.launchedBinaryPath = binPath;
        self.logHandle = fh;
        self.serverTask = task;

        BOOL launched = NO;
        NSString *errMsg = nil;

        @try {
            [task launch];
            launched = YES;
        } @catch (NSException *ex) {
            errMsg = [ex reason] ?: @"Failed to launch llama-server.";
        }

        BOOL healthy = NO;
        if (launched) {
            NSString *healthURL = [NSString stringWithFormat:@"http://127.0.0.1:%ld/health", (long)listenPort];
            for (int i = 0; i < 20; i++) {
                if (![task isRunning]) {
                    errMsg = [NSString stringWithFormat:@"llama-server exited early (code %d). Check View Server Log.", [task terminationStatus]];
                    break;
                }
                NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:healthURL]
                                                     cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                 timeoutInterval:1.0];
                NSHTTPURLResponse *resp = nil;
                [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:nil];
                if (resp && [resp statusCode] == 200) {
                    healthy = YES;
                    break;
                }
                [NSThread sleepForTimeInterval:0.5];
            }
            if (!healthy && !errMsg) {
                errMsg = @"Server started, waiting for health endpoint...";
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.isBusy = NO;
            self.lastError = errMsg;
            [self refreshStatusWithCompletion:^{
                if (completion) {
                    completion(launched && (healthy || self.isRunning), errMsg);
                }
            }];
        });
    });
}

- (void)stopServerWithCompletion:(void (^)(void))completion {
    if (self.isBusy) {
        if (completion) completion();
        return;
    }
    self.isBusy = YES;
    dispatch_async(self.workerQueue, ^{
        [self terminateManagedProcessesSync];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isBusy = NO;
            self.isRunning = NO;
            self.isHealthy = NO;
            self.serverRSSMB = 0.0;
            self.activePIDsText = @"";
            self.loadedModels = @[];
            if (completion) completion();
        });
    });
}

- (void)restartServerWithHardwareRAMGB:(NSInteger)ramGB logicalCPUs:(NSInteger)cpus completion:(void (^)(BOOL success, NSString *error))completion {
    [self stopServerWithCompletion:^{
        [self startServerWithHardwareRAMGB:ramGB logicalCPUs:cpus completion:completion];
    }];
}

- (void)refreshStatusWithCompletion:(void (^)(void))completion {
    NSInteger listenPort = self.port;
    dispatch_async(self.workerQueue, ^{
        double rssMB = 0.0;
        NSArray *pids = [self managedProcessPIDsWithTotalRSSMB:&rssMB];
        NSMutableArray *pidStrs = [NSMutableArray arrayWithCapacity:pids.count];
        for (NSNumber *n in pids) [pidStrs addObject:[n stringValue]];

        BOOL taskRunning = (self.serverTask && [self.serverTask isRunning]);
        BOOL healthy = NO;
        NSMutableArray *loaded = [NSMutableArray array];
        NSMutableArray *avail = [NSMutableArray array];

        NSString *healthURL = [NSString stringWithFormat:@"http://127.0.0.1:%ld/health", (long)listenPort];
        NSURLRequest *healthReq = [NSURLRequest requestWithURL:[NSURL URLWithString:healthURL]
                                                 cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                             timeoutInterval:1.2];
        NSHTTPURLResponse *healthResp = nil;
        [NSURLConnection sendSynchronousRequest:healthReq returningResponse:&healthResp error:nil];
        if (healthResp && [healthResp statusCode] == 200) {
            healthy = YES;
            NSString *modelsURL = [NSString stringWithFormat:@"http://127.0.0.1:%ld/v1/models", (long)listenPort];
            NSURLRequest *modelsReq = [NSURLRequest requestWithURL:[NSURL URLWithString:modelsURL]
                                                     cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                 timeoutInterval:1.2];
            NSHTTPURLResponse *modelsResp = nil;
            NSData *modelsData = [NSURLConnection sendSynchronousRequest:modelsReq returningResponse:&modelsResp error:nil];
            if (modelsData && modelsResp && [modelsResp statusCode] == 200) {
                id json = [NSJSONSerialization JSONObjectWithData:modelsData options:0 error:nil];
                if ([json isKindOfClass:[NSDictionary class]]) {
                    NSArray *dataArr = json[@"data"];
                    if ([dataArr isKindOfClass:[NSArray class]]) {
                        for (NSDictionary *item in dataArr) {
                            NSString *mid = item[@"id"];
                            if (!mid) continue;
                            [avail addObject:mid];
                            NSString *st = item[@"status"][@"value"];
                            if ([st isKindOfClass:[NSString class]] && [st isEqualToString:@"loaded"]) {
                                [loaded addObject:mid];
                            }
                        }
                    }
                }
            }
        }

        BOOL running = healthy || taskRunning || (pids.count > 0);

        dispatch_async(dispatch_get_main_queue(), ^{
            self.isRunning = running;
            self.isHealthy = healthy;
            self.serverRSSMB = rssMB;
            self.activePIDsText = [pidStrs componentsJoinedByString:@","];
            self.loadedModels = loaded;
            self.availableModels = avail;
            if (completion) completion();
        });
    });
}

@end
