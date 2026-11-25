#import <Cocoa/Cocoa.h>
#import "HardwareInspector.h"
#import "DownloadManager.h"
#import "EngineManager.h"
#import "ModelCatalog.h"
#import "ServerController.h"
#import "UpdateManager.h"

@interface MainWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSTabViewDelegate>

@property (nonatomic, copy) void (^onLaunchChatbotRequested)(void);
@property (nonatomic, copy) void (^onStateUpdated)(void);
@property (nonatomic, copy) void (^onUpdateCheckCompleted)(MavReleaseInfo *latestStable, BOOL updateAvailable);

- (instancetype)initWithHardwareInfo:(MavHardwareInfo *)hardware
                     downloadManager:(DownloadManager *)downloadManager
                       engineManager:(EngineManager *)engineManager
                    serverController:(ServerController *)serverController
                       updateManager:(UpdateManager *)updateManager;

- (void)showWindowAndSelectTab:(NSInteger)tabIndex;
- (void)refreshAllViews;
- (void)checkForUpdatesForce:(BOOL)force;
@end
