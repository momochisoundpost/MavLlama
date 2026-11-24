#import "ModelCatalog.h"

@implementation MavModelEntry
@end

@implementation ModelCatalog

+ (NSString *)remoteCatalogURL {
    return @"https://raw.githubusercontent.com/momochisoundpost/MavLlama/main/catalog/models.json";
}

+ (NSArray *)loadEmbeddedCatalog {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"models" ofType:@"json"];
    if (!path) return @[];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return @[];
    return [self parseModelsFromData:data error:nil] ?: @[];
}

+ (NSArray *)parseModelsFromData:(NSData *)data error:(NSError **)outError {
    if (!data) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:outError];
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    NSArray *rawModels = json[@"models"];
    if (![rawModels isKindOfClass:[NSArray class]]) return nil;

    NSMutableArray *list = [NSMutableArray arrayWithCapacity:rawModels.count];
    for (id item in rawModels) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *d = (NSDictionary *)item;
        MavModelEntry *m = [[MavModelEntry alloc] init];
        m.modelId = [d[@"id"] description] ?: @"";
        m.name = [d[@"name"] description] ?: @"";
        m.family = [d[@"family"] description] ?: @"Other";
        m.quant = [d[@"quant"] description] ?: @"";
        m.filename = [d[@"filename"] description] ?: @"";
        m.url = [d[@"url"] description] ?: @"";
        m.sizeBytes = [d[@"sizeBytes"] unsignedLongLongValue];
        m.minRAMGB = [d[@"minRAMGB"] integerValue];
        m.architecture = [d[@"architecture"] description] ?: @"dense";
        m.paramsTotal = [d[@"paramsTotal"] description] ?: @"";
        m.paramsActive = [d[@"paramsActive"] description] ?: @"";
        m.notes = [d[@"notes"] description] ?: @"";
        if (m.filename.length > 0 && m.url.length > 0) {
            [list addObject:m];
        }
    }
    return list;
}

+ (NSArray *)filterModels:(NSArray *)models
                 forRAMGB:(NSInteger)ramGB
                 isMacPro:(BOOL)isMacPro
           overrideFilter:(BOOL)overrideFilter
             familyFilter:(NSString *)familyFilter {
    BOOL allowAllRAM = isMacPro || overrideFilter;
    BOOL filterFamily = familyFilter && familyFilter.length > 0 && ![familyFilter isEqualToString:@"All"];

    NSMutableArray *result = [NSMutableArray array];
    for (MavModelEntry *m in models) {
        if (!allowAllRAM && !m.installedOnDisk && !m.isLocalCustom && m.minRAMGB > ramGB) {
            continue;
        }
        if (filterFamily && ![[m.family lowercaseString] isEqualToString:[familyFilter lowercaseString]]) {
            continue;
        }
        [result addObject:m];
    }
    return result;
}

+ (NSArray *)reconcileModels:(NSArray *)catalogModels
               withModelsDir:(NSString *)modelsDir
                downloadsDir:(NSString *)downloadsDir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *diskFiles = [fm contentsOfDirectoryAtPath:modelsDir error:nil] ?: @[];
    NSMutableDictionary *diskMap = [NSMutableDictionary dictionary];
    for (NSString *f in diskFiles) {
        if ([f hasSuffix:@".gguf"]) {
            NSString *full = [modelsDir stringByAppendingPathComponent:f];
            NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
            diskMap[f] = @([attrs fileSize]);
        }
    }

    NSArray *partFiles = [fm contentsOfDirectoryAtPath:downloadsDir error:nil] ?: @[];
    NSMutableDictionary *partMap = [NSMutableDictionary dictionary];
    for (NSString *f in partFiles) {
        if ([f hasSuffix:@".gguf.part"]) {
            NSString *baseName = [f substringToIndex:f.length - 5]; // strip ".part"
            NSString *full = [downloadsDir stringByAppendingPathComponent:f];
            NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
            partMap[baseName] = @([attrs fileSize]);
        }
    }

    NSMutableSet *seenFilenames = [NSMutableSet set];
    NSMutableArray *merged = [NSMutableArray arrayWithCapacity:catalogModels.count];
    for (MavModelEntry *orig in catalogModels) {
        MavModelEntry *m = [[MavModelEntry alloc] init];
        m.modelId = orig.modelId;
        m.name = orig.name;
        m.family = orig.family;
        m.quant = orig.quant;
        m.filename = orig.filename;
        m.url = orig.url;
        m.sizeBytes = orig.sizeBytes;
        m.minRAMGB = orig.minRAMGB;
        m.architecture = orig.architecture;
        m.paramsTotal = orig.paramsTotal;
        m.paramsActive = orig.paramsActive;
        m.notes = orig.notes;
        m.isLocalCustom = orig.isLocalCustom;
        m.installedOnDisk = (diskMap[orig.filename] != nil);
        if (m.installedOnDisk && m.sizeBytes == 0) {
            m.sizeBytes = [diskMap[orig.filename] unsignedLongLongValue];
        }
        m.partialBytes = partMap[orig.filename] ? [partMap[orig.filename] unsignedLongLongValue] : 0;
        [seenFilenames addObject:orig.filename];
        [merged addObject:m];
    }

    NSArray *sortedDisk = [diskFiles sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *f in sortedDisk) {
        if (![f hasSuffix:@".gguf"] || [seenFilenames containsObject:f]) continue;
        MavModelEntry *custom = [[MavModelEntry alloc] init];
        custom.modelId = [f stringByDeletingPathExtension];
        custom.name = [f stringByDeletingPathExtension];
        custom.family = @"Local";
        custom.quant = @"GGUF";
        custom.filename = f;
        custom.url = @"";
        custom.sizeBytes = [diskMap[f] unsignedLongLongValue];
        custom.minRAMGB = 0;
        custom.architecture = @"local";
        custom.paramsTotal = @"Custom";
        custom.paramsActive = @"";
        custom.notes = @"Local or custom GGUF file present in your Models folder.";
        custom.isLocalCustom = YES;
        custom.installedOnDisk = YES;
        custom.partialBytes = 0;
        [merged addObject:custom];
    }

    return merged;
}

+ (NSString *)formatBytes:(uint64_t)bytes {
    double b = (double)bytes;
    if (b >= 1024.0 * 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.2f GiB", b / (1024.0 * 1024.0 * 1024.0)];
    }
    if (b >= 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.1f MiB", b / (1024.0 * 1024.0)];
    }
    if (b >= 1024.0) {
        return [NSString stringWithFormat:@"%.0f KiB", b / 1024.0];
    }
    return [NSString stringWithFormat:@"%llu B", bytes];
}

@end
