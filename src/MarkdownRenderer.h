#import <Foundation/Foundation.h>

@interface MavResolvedMedia : NSObject
@property (nonatomic, copy) NSString *fileURLString;
@property (nonatomic, assign) BOOL isVideo;
@end

@interface MarkdownRenderer : NSObject
+ (NSArray *)extractRemoteMediaURLsFromMarkdown:(NSString *)markdown;
+ (NSString *)renderHTMLFromMarkdown:(NSString *)markdown
                        releaseTitle:(NSString *)title
                          releaseTag:(NSString *)tag
                       resolvedMedia:(NSDictionary *)resolvedMedia;
@end
