#import <Foundation/Foundation.h>

typedef void (^MavDownloadProgressBlock)(uint64_t downloadedBytes, uint64_t expectedBytes);
typedef void (^MavDownloadCompletionBlock)(BOOL success, NSString *errorMessage);

@interface DownloadManager : NSObject
@property (nonatomic, readonly) BOOL isDownloading;
@property (nonatomic, copy, readonly) NSString *activeLabel;
@property (nonatomic, assign, readonly) uint64_t downloadedBytes;
@property (nonatomic, assign, readonly) uint64_t expectedBytes;

+ (NSString *)resolvedCurlPath;
+ (NSString *)resolvedCABundlePath;
+ (NSString *)sha256ForFileAtPath:(NSString *)path;
+ (NSData *)fetchDataFromURL:(NSString *)urlString error:(NSError **)outError;

- (void)downloadURL:(NSString *)urlString
       expectedBytes:(uint64_t)expectedBytes
      expectedSHA256:(NSString *)expectedSHA256
            partPath:(NSString *)partPath
            destPath:(NSString *)destPath
               label:(NSString *)label
            progress:(MavDownloadProgressBlock)progressBlock
          completion:(MavDownloadCompletionBlock)completionBlock;

- (void)cancelAndDeletePart:(BOOL)deletePart;
@end
