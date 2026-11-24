#import <Foundation/Foundation.h>

@interface MavHardwareInfo : NSObject
@property (nonatomic, copy) NSString *modelIdentifier;
@property (nonatomic, copy) NSString *osVersion;
@property (nonatomic, copy) NSString *osBuild;
@property (nonatomic, copy) NSString *osStatusLevel; // @"ok", @"advisory", @"unsupported"
@property (nonatomic, copy) NSString *cpuBrand;
@property (nonatomic, copy) NSString *cpuFeatures;
@property (nonatomic, copy) NSString *cpuLeaf7Features;
@property (nonatomic, copy) NSString *cpuTier; // @"core2", @"nehalem", @"sandybridge", @"ivybridge", @"haswell"
@property (nonatomic, copy) NSString *cpuTierDisplayName;
@property (nonatomic, assign) NSInteger logicalCPUCount;
@property (nonatomic, assign) uint64_t installedRAMBytes;
@property (nonatomic, assign) NSInteger installedRAMGB;
@property (nonatomic, assign) uint64_t availableRAMBytes;
@property (nonatomic, assign) uint64_t freeDiskBytes;
@property (nonatomic, assign) BOOL isMacPro;
@property (nonatomic, assign) BOOL hasAVX;
@property (nonatomic, assign) BOOL hasAVX2;
@property (nonatomic, copy) NSString *lanIP;
@property (nonatomic, copy) NSString *modernBrowserName;
@property (nonatomic, copy) NSString *modernBrowserBundleID;
@end

@interface HardwareInspector : NSObject
+ (NSString *)cpuTierForFeatures:(NSString *)features leaf7Features:(NSString *)leaf7;
+ (NSString *)displayNameForCPUTier:(NSString *)tier;
+ (BOOL)isMacProModel:(NSString *)modelIdentifier;
+ (NSInteger)recommendedContextSizeForRAMGB:(NSInteger)ramGB;
+ (NSString *)osStatusLevelForVersion:(NSString *)productVersion build:(NSString *)buildVersion;
+ (MavHardwareInfo *)inspectWithModelsPath:(NSString *)modelsPath;
+ (uint64_t)availableRAMBytes;
+ (uint64_t)freeDiskBytesForPath:(NSString *)path;
+ (NSString *)detectLanIP;
@end
