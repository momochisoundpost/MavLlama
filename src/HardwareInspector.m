#import "HardwareInspector.h"
#import <AppKit/AppKit.h>
#import <mach/mach.h>
#import <sys/sysctl.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>

@implementation MavHardwareInfo
@end

@implementation HardwareInspector

+ (NSSet *)tokenSetFromString:(NSString *)str {
    if (!str || str.length == 0) return [NSSet set];
    NSArray *parts = [[str uppercaseString] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableSet *set = [NSMutableSet set];
    for (NSString *p in parts) {
        if (p.length > 0) [set addObject:p];
    }
    return set;
}

+ (NSString *)cpuTierForFeatures:(NSString *)features leaf7Features:(NSString *)leaf7 {
    NSSet *feat = [self tokenSetFromString:features];
    NSSet *l7 = [self tokenSetFromString:leaf7];

    BOOL hasAVX = [feat containsObject:@"AVX1.0"] || [feat containsObject:@"AVX"];
    BOOL hasF16C = [feat containsObject:@"F16C"];
    BOOL hasFMA = [feat containsObject:@"FMA"];
    BOOL hasSSE42 = [feat containsObject:@"SSE4.2"];
    BOOL hasAVX2 = [l7 containsObject:@"AVX2"];
    BOOL hasBMI2 = [l7 containsObject:@"BMI2"];

    if (hasAVX2 && hasBMI2 && hasFMA && hasF16C) {
        return @"haswell";
    }
    if (hasAVX && hasF16C) {
        return @"ivybridge";
    }
    if (hasAVX) {
        return @"sandybridge";
    }
    if (hasSSE42) {
        return @"nehalem";
    }
    return @"core2";
}

+ (NSString *)displayNameForCPUTier:(NSString *)tier {
    if ([tier isEqualToString:@"haswell"]) return @"Haswell (AVX2 + FMA + BMI2)";
    if ([tier isEqualToString:@"ivybridge"]) return @"Ivy Bridge (AVX + F16C)";
    if ([tier isEqualToString:@"sandybridge"]) return @"Sandy Bridge (AVX + SSE4.2)";
    if ([tier isEqualToString:@"nehalem"]) return @"Nehalem / Westmere (SSE4.2)";
    return @"Core 2 / Penryn / Harpertown (SSSE3 baseline)";
}

+ (BOOL)isMacProModel:(NSString *)modelIdentifier {
    if (!modelIdentifier) return NO;
    return [[modelIdentifier lowercaseString] hasPrefix:@"macpro"];
}

+ (NSInteger)recommendedContextSizeForRAMGB:(NSInteger)ramGB {
    if (ramGB <= 4) return 2048;
    if (ramGB <= 8) return 8192;
    return 32768;
}

+ (NSString *)osStatusLevelForVersion:(NSString *)productVersion build:(NSString *)buildVersion {
    if (!productVersion || productVersion.length == 0) return @"advisory";
    NSArray *comps = [productVersion componentsSeparatedByString:@"."];
    NSInteger major = comps.count > 0 ? [comps[0] integerValue] : 0;
    NSInteger minor = comps.count > 1 ? [comps[1] integerValue] : 0;
    NSInteger patch = comps.count > 2 ? [comps[2] integerValue] : 0;

    if (major < 10 || (major == 10 && minor < 9)) {
        return @"unsupported";
    }
    if (major == 10 && minor == 9) {
        if (patch >= 5 && [buildVersion isEqualToString:@"13F1911"]) {
            return @"ok";
        }
        return @"advisory";
    }
    return @"ok";
}

+ (NSString *)sysctlStringForName:(const char *)name {
    size_t size = 0;
    if (sysctlbyname(name, NULL, &size, NULL, 0) != 0 || size == 0) {
        return @"";
    }
    char *buf = (char *)malloc(size + 1);
    if (!buf) return @"";
    if (sysctlbyname(name, buf, &size, NULL, 0) != 0) {
        free(buf);
        return @"";
    }
    buf[size] = '\0';
    NSString *res = [NSString stringWithUTF8String:buf] ?: @"";
    free(buf);
    return [res stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (uint64_t)availableRAMBytes {
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    vm_statistics64_data_t vmstat;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vmstat, &count) == KERN_SUCCESS) {
        uint64_t availPages = (uint64_t)vmstat.free_count + (uint64_t)vmstat.inactive_count + (uint64_t)vmstat.speculative_count;
        return availPages * (uint64_t)vm_page_size;
    }
    return 0;
}

+ (uint64_t)freeDiskBytesForPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *probe = path ?: NSHomeDirectory();
    while (probe.length > 1 && ![fm fileExistsAtPath:probe]) {
        probe = [probe stringByDeletingLastPathComponent];
    }
    if (probe.length == 0) probe = @"/";
    NSDictionary *attrs = [fm attributesOfFileSystemForPath:probe error:nil];
    NSNumber *freeNum = attrs[NSFileSystemFreeSize];
    return freeNum ? [freeNum unsignedLongLongValue] : 0;
}

+ (NSString *)detectLanIP {
    struct ifaddrs *interfaces = NULL;
    NSString *result = @"127.0.0.1";
    if (getifaddrs(&interfaces) == 0) {
        struct ifaddrs *temp = interfaces;
        while (temp != NULL) {
            if (temp->ifa_addr && temp->ifa_addr->sa_family == AF_INET) {
                NSString *name = [NSString stringWithUTF8String:temp->ifa_name];
                if (![name isEqualToString:@"lo0"] && (temp->ifa_flags & IFF_UP)) {
                    char addrBuf[INET_ADDRSTRLEN];
                    struct sockaddr_in *sin = (struct sockaddr_in *)temp->ifa_addr;
                    if (inet_ntop(AF_INET, &sin->sin_addr, addrBuf, sizeof(addrBuf))) {
                        NSString *ip = [NSString stringWithUTF8String:addrBuf];
                        if (![ip hasPrefix:@"169.254."]) {
                            result = ip;
                            if ([name isEqualToString:@"en0"] || [name isEqualToString:@"en1"]) {
                                break;
                            }
                        }
                    }
                }
            }
            temp = temp->ifa_next;
        }
        freeifaddrs(interfaces);
    }
    return result;
}

+ (MavHardwareInfo *)inspectWithModelsPath:(NSString *)modelsPath {
    MavHardwareInfo *info = [[MavHardwareInfo alloc] init];

    NSDictionary *sysVer = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    info.osVersion = sysVer[@"ProductVersion"] ?: @"10.9";
    info.osBuild = sysVer[@"ProductBuildVersion"] ?: @"";
    info.osStatusLevel = [self osStatusLevelForVersion:info.osVersion build:info.osBuild];

    info.modelIdentifier = [self sysctlStringForName:"hw.model"];
    if (info.modelIdentifier.length == 0) info.modelIdentifier = @"Mac";
    info.isMacPro = [self isMacProModel:info.modelIdentifier];

    info.cpuBrand = [self sysctlStringForName:"machdep.cpu.brand_string"];
    if (info.cpuBrand.length == 0) info.cpuBrand = @"Intel x86_64";
    info.cpuFeatures = [self sysctlStringForName:"machdep.cpu.features"];
    info.cpuLeaf7Features = [self sysctlStringForName:"machdep.cpu.leaf7_features"];
    info.cpuTier = [self cpuTierForFeatures:info.cpuFeatures leaf7Features:info.cpuLeaf7Features];
    info.cpuTierDisplayName = [self displayNameForCPUTier:info.cpuTier];

    NSSet *featSet = [self tokenSetFromString:info.cpuFeatures];
    NSSet *l7Set = [self tokenSetFromString:info.cpuLeaf7Features];
    info.hasAVX = [featSet containsObject:@"AVX1.0"] || [featSet containsObject:@"AVX"];
    info.hasAVX2 = [l7Set containsObject:@"AVX2"];

    int ncpu = 1;
    size_t ncpuSize = sizeof(ncpu);
    if (sysctlbyname("hw.ncpu", &ncpu, &ncpuSize, NULL, 0) == 0 && ncpu > 0) {
        info.logicalCPUCount = ncpu;
    } else {
        info.logicalCPUCount = 2;
    }

    uint64_t memBytes = 0;
    size_t memSize = sizeof(memBytes);
    sysctlbyname("hw.memsize", &memBytes, &memSize, NULL, 0);
    info.installedRAMBytes = memBytes;
    info.installedRAMGB = (NSInteger)((memBytes + (512ULL * 1024ULL * 1024ULL)) / (1024ULL * 1024ULL * 1024ULL));
    info.availableRAMBytes = [self availableRAMBytes];
    info.freeDiskBytes = [self freeDiskBytesForPath:modelsPath];
    info.lanIP = [self detectLanIP];

    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    NSURL *defaultBrowserURL = [ws URLForApplicationToOpenURL:[NSURL URLWithString:@"http://127.0.0.1"]];
    if (defaultBrowserURL) {
        NSBundle *b = [NSBundle bundleWithURL:defaultBrowserURL];
        NSString *bundleID = [b bundleIdentifier];
        NSString *name = [[NSFileManager defaultManager] displayNameAtPath:[defaultBrowserURL path]];
        if (!name || name.length == 0) {
            name = [[defaultBrowserURL lastPathComponent] stringByDeletingPathExtension];
        }
        info.modernBrowserBundleID = bundleID;
        info.modernBrowserName = name;
    }

    return info;
}

@end
