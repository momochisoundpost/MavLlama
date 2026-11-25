#import <Foundation/Foundation.h>
#import "DownloadManager.h"

@class ServerController;

@interface MavReleaseInfo : NSObject
@property (nonatomic, copy) NSString *tagName;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *body;
@property (nonatomic, copy) NSString *htmlURL;
@property (nonatomic, copy) NSString *publishedAt;
@property (nonatomic, assign) BOOL prerelease;
@property (nonatomic, assign) BOOL draft;
@property (nonatomic, copy) NSString *appZipAssetName;
@property (nonatomic, copy) NSString *appZipDownloadURL;
@property (nonatomic, assign) uint64_t appZipSizeBytes;
@property (nonatomic, copy) NSString *checksumsDownloadURL;
@end

@interface UpdateManager : NSObject
@property (atomic, assign, readonly) BOOL isInstalling;
+ (NSComparisonResult)compareVersion:(NSString *)v1 toVersion:(NSString *)v2;
+ (NSArray *)parseReleasesFromData:(NSData *)jsonData error:(NSError **)outError;
+ (MavReleaseInfo *)latestStableReleaseFromReleases:(NSArray *)releases;
+ (NSString *)parseSHA256ForFilename:(NSString *)filename fromChecksumsText:(NSString *)text;
+ (NSString *)updaterShellScriptContents;

- (NSString *)currentAppVersion;

- (void)checkForUpdatesForceRefresh:(BOOL)force
                         completion:(void (^)(NSArray *releases,
                                              MavReleaseInfo *latestStable,
                                              BOOL updateAvailable,
                                              NSError *error))completion;

- (void)renderRelease:(MavReleaseInfo *)release
          initialHTML:(void (^)(NSString *html, NSURL *baseURL))initialBlock
          updatedHTML:(void (^)(NSString *html, NSURL *baseURL))updatedBlock;

- (void)installRelease:(MavReleaseInfo *)release
       downloadManager:(DownloadManager *)downloadManager
      serverController:(ServerController *)serverController
              progress:(MavDownloadProgressBlock)progressBlock
            completion:(void (^)(BOOL launchedUpdater, NSString *errorMessage))completion;
@end
