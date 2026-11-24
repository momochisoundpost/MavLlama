#import <Foundation/Foundation.h>
#import "DownloadManager.h"

@interface MavEngineTierInfo : NSObject
@property (nonatomic, copy) NSString *tier;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *sha256;
@property (nonatomic, assign) uint64_t sizeBytes;
@end

@interface EngineManager : NSObject
@property (nonatomic, copy, readonly) NSString *releaseTag;
@property (nonatomic, copy, readonly) NSString *llamaCppCommit;
@property (nonatomic, strong, readonly) NSDictionary *tiersByName;

+ (NSString *)defaultEngineDirectory;
+ (NSString *)defaultDownloadsDirectory;
- (NSString *)managedServerBinaryPath;
- (NSString *)activeServerBinaryPathWithCustomPath:(NSString *)customPath;
- (NSDictionary *)installedMetadata;
- (BOOL)isEngineInstalledWithCustomPath:(NSString *)customPath;
- (MavEngineTierInfo *)infoForTier:(NSString *)tier;

- (void)installEngineForTier:(NSString *)tier
             downloadManager:(DownloadManager *)downloadManager
                    progress:(MavDownloadProgressBlock)progressBlock
                  completion:(void (^)(BOOL success, NSString *message))completion;

- (BOOL)installLocalArchiveAtPath:(NSString *)archivePath
                        tierLabel:(NSString *)tierLabel
                            error:(NSError **)outError;
@end
