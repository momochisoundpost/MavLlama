#import <Foundation/Foundation.h>
#import "EngineManager.h"

@interface ServerController : NSObject
@property (nonatomic, assign, readonly) BOOL isRunning;
@property (nonatomic, assign, readonly) BOOL isHealthy;
@property (nonatomic, assign, readonly) BOOL isBusy;
@property (nonatomic, assign, readonly) double serverRSSMB;
@property (nonatomic, copy, readonly) NSString *activePIDsText;
@property (nonatomic, copy, readonly) NSArray *loadedModels;
@property (nonatomic, copy, readonly) NSArray *availableModels;
@property (nonatomic, copy, readonly) NSString *lastError;

@property (nonatomic, copy) NSString *modelsDirectory;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, assign) BOOL allowLAN;
@property (nonatomic, assign) NSInteger threads; // 0 = Auto
@property (nonatomic, assign) NSInteger ctxSize; // 0 = Auto
@property (nonatomic, assign) BOOL autoStart;
@property (nonatomic, copy) NSString *customEnginePath;

- (instancetype)initWithEngineManager:(EngineManager *)engineManager;
+ (NSString *)defaultModelsDirectory;
+ (NSString *)logFilePath;

- (void)startServerWithHardwareRAMGB:(NSInteger)ramGB logicalCPUs:(NSInteger)cpus completion:(void (^)(BOOL success, NSString *error))completion;
- (void)stopServerWithCompletion:(void (^)(void))completion;
- (void)restartServerWithHardwareRAMGB:(NSInteger)ramGB logicalCPUs:(NSInteger)cpus completion:(void (^)(BOOL success, NSString *error))completion;
- (void)stopSynchronouslyForTermination;
- (void)refreshStatusWithCompletion:(void (^)(void))completion;
@end
