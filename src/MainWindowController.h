#import <Cocoa/Cocoa.h>
#import "HardwareInspector.h"
#import "DownloadManager.h"
#import "EngineManager.h"
#import "ModelCatalog.h"
#import "ServerController.h"

@interface MainWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, copy) void (^onLaunchChatbotRequested)(void);
@property (nonatomic, copy) void (^onStateUpdated)(void);

- (instancetype)initWithHardwareInfo:(MavHardwareInfo *)hardware
                     downloadManager:(DownloadManager *)downloadManager
                       engineManager:(EngineManager *)engineManager
                    serverController:(ServerController *)serverController;

- (void)showWindowAndSelectTab:(NSInteger)tabIndex;
- (void)refreshAllViews;
@end
