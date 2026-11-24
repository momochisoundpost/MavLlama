#import <Foundation/Foundation.h>

@interface MavModelEntry : NSObject
@property (nonatomic, copy) NSString *modelId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *family;
@property (nonatomic, copy) NSString *quant;
@property (nonatomic, copy) NSString *filename;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, assign) uint64_t sizeBytes;
@property (nonatomic, assign) NSInteger minRAMGB;
@property (nonatomic, copy) NSString *architecture;
@property (nonatomic, copy) NSString *paramsTotal;
@property (nonatomic, copy) NSString *paramsActive;
@property (nonatomic, copy) NSString *notes;
@property (nonatomic, assign) BOOL isLocalCustom;
@property (nonatomic, assign) BOOL installedOnDisk;
@property (nonatomic, assign) uint64_t partialBytes;
@end

@interface ModelCatalog : NSObject
+ (NSString *)remoteCatalogURL;
+ (NSArray *)loadEmbeddedCatalog;
+ (NSArray *)parseModelsFromData:(NSData *)data error:(NSError **)outError;
+ (NSArray *)filterModels:(NSArray *)models
                 forRAMGB:(NSInteger)ramGB
                 isMacPro:(BOOL)isMacPro
           overrideFilter:(BOOL)overrideFilter
             familyFilter:(NSString *)familyFilter;
+ (NSArray *)reconcileModels:(NSArray *)catalogModels
               withModelsDir:(NSString *)modelsDir
                downloadsDir:(NSString *)downloadsDir;
+ (NSString *)formatBytes:(uint64_t)bytes;
@end
