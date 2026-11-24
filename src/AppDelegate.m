#import "AppDelegate.h"
#import "HardwareInspector.h"
#import "DownloadManager.h"
#import "EngineManager.h"
#import "ModelCatalog.h"
#import "ServerController.h"
#import "MainWindowController.h"

@interface AppDelegate ()
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *menu;
@property (nonatomic, strong) NSMenuItem *statusInfoItem;
@property (nonatomic, strong) NSMenuItem *modelInfoItem;
@property (nonatomic, strong) NSMenuItem *ramInfoItem;
@property (nonatomic, strong) NSMenuItem *downloadInfoItem;
@property (nonatomic, strong) NSMenuItem *lanInfoItem;
@property (nonatomic, strong) NSMenuItem *launchChatbotItem;
@property (nonatomic, strong) NSMenuItem *lanCopyItem;
@property (nonatomic, strong) NSMenuItem *openWindowItem;
@property (nonatomic, strong) NSMenuItem *startItem;
@property (nonatomic, strong) NSMenuItem *stopItem;
@property (nonatomic, strong) NSMenuItem *restartItem;
@property (nonatomic, strong) NSMenuItem *logItem;

@property (nonatomic, strong) MavHardwareInfo *hardware;
@property (nonatomic, strong) DownloadManager *downloadManager;
@property (nonatomic, strong) EngineManager *engineManager;
@property (nonatomic, strong) ServerController *serverController;
@property (nonatomic, strong) MainWindowController *windowController;
@property (nonatomic, strong) NSTimer *pollTimer;
@end

@implementation AppDelegate

- (NSImage *)createMenuBarIcon {
    NSImage *img = [NSImage imageWithSize:NSMakeSize(16, 16) flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        (void)dstRect;
        [[NSColor blackColor] set];

        NSBezierPath *chip = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(2.5, 2.5, 11.0, 11.0) xRadius:2.2 yRadius:2.2];
        [chip setLineWidth:1.4];
        [chip stroke];

        NSBezierPath *core = [NSBezierPath bezierPath];
        [core moveToPoint:NSMakePoint(8.0, 11.2)];
        [core lineToPoint:NSMakePoint(10.6, 8.0)];
        [core lineToPoint:NSMakePoint(8.0, 4.8)];
        [core lineToPoint:NSMakePoint(5.4, 8.0)];
        [core closePath];
        [core fill];

        NSBezierPath *pins = [NSBezierPath bezierPath];
        [pins setLineWidth:1.2];
        CGFloat coords[2] = {6.0, 10.0};
        for (int i = 0; i < 2; i++) {
            CGFloat c = coords[i];
            [pins moveToPoint:NSMakePoint(c, 0.8)];  [pins lineToPoint:NSMakePoint(c, 2.5)];
            [pins moveToPoint:NSMakePoint(c, 13.5)]; [pins lineToPoint:NSMakePoint(c, 15.2)];
            [pins moveToPoint:NSMakePoint(0.8, c)];  [pins lineToPoint:NSMakePoint(2.5, c)];
            [pins moveToPoint:NSMakePoint(13.5, c)]; [pins lineToPoint:NSMakePoint(15.2, c)];
        }
        [pins stroke];
        return YES;
    }];
    [img setTemplate:YES];
    return img;
}

- (NSArray *)installedModelFiles {
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.serverController.modelsDirectory error:nil] ?: @[];
    NSMutableArray *ggufs = [NSMutableArray array];
    for (NSString *f in files) {
        if ([f hasSuffix:@".gguf"]) [ggufs addObject:f];
    }
    return ggufs;
}

- (void)openChatbotInPreferredBrowser {
    NSString *localURLStr = [NSString stringWithFormat:@"http://127.0.0.1:%ld", (long)self.serverController.port];
    NSString *lanURLStr = [NSString stringWithFormat:@"http://%@:%ld", self.hardware.lanIP ?: @"127.0.0.1", (long)self.serverController.port];
    NSURL *url = [NSURL URLWithString:localURLStr];

    self.hardware = [HardwareInspector inspectWithModelsPath:self.serverController.modelsDirectory];
    if (self.hardware.modernBrowserBundleID) {
        BOOL ok = [[NSWorkspace sharedWorkspace] openURLs:@[url]
                                  withAppBundleIdentifier:self.hardware.modernBrowserBundleID
                                                  options:NSWorkspaceLaunchDefault
                            additionalEventParamDescriptor:nil
                                        launchIdentifiers:NULL];
        if (ok) return;
    }

    NSAlert *alert = [NSAlert alertWithMessageText:@"Modern Mavericks Browser Recommended"
                                     defaultButton:@"Open Mavericks Forever"
                                   alternateButton:@"Copy LAN URL"
                                       otherButton:@"Try Default Browser Anyway"
                         informativeTextWithFormat:@"Stock Safari 9 on Mavericks cannot render the modern llama.cpp chat UI.\n\nYou can install Momiji or Chromium Legacy from mavericksforever.com, OR open the chat UI from your phone, tablet, or another PC at:\n\n%@", lanURLStr];
    NSInteger choice = [alert runModal];
    if (choice == NSAlertDefaultReturn) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://mavericksforever.com"]];
    } else if (choice == NSAlertAlternateReturn) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb declareTypes:@[NSPasteboardTypeString] owner:nil];
        [pb setString:lanURLStr forType:NSPasteboardTypeString];
    } else {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (void)handleLaunchChatbot {
    BOOL hasEngine = [self.engineManager isEngineInstalledWithCustomPath:self.serverController.customEnginePath];
    if (!hasEngine) {
        [self.windowController showWindowAndSelectTab:0];
        return;
    }
    if ([self installedModelFiles].count == 0) {
        [self.windowController showWindowAndSelectTab:1];
        return;
    }
    if (self.serverController.isHealthy) {
        [self openChatbotInPreferredBrowser];
        return;
    }
    [self.serverController startServerWithHardwareRAMGB:self.hardware.installedRAMGB
                                            logicalCPUs:self.hardware.logicalCPUCount
                                             completion:^(BOOL success, NSString *err) {
        [self updateMenuUI];
        if (success) {
            [self openChatbotInPreferredBrowser];
        } else {
            NSAlert *alert = [NSAlert alertWithMessageText:@"Could Not Start AI Server"
                                             defaultButton:@"OK"
                                           alternateButton:nil
                                               otherButton:nil
                                 informativeTextWithFormat:@"%@", err ?: @"Unknown error."];
            [alert runModal];
        }
    }];
}

- (void)refreshState {
    self.hardware = [HardwareInspector inspectWithModelsPath:self.serverController.modelsDirectory];
    [self.serverController refreshStatusWithCompletion:^{
        [self updateMenuUI];
    }];
}

- (void)updateMenuUI {
    BOOL running = self.serverController.isRunning;
    BOOL healthy = self.serverController.isHealthy;
    BOOL busy = self.serverController.isBusy;

    NSString *badge = running ? @"AI ON" : @"AI OFF";
    if (busy) badge = @"AI ...";

    if (self.downloadManager.isDownloading) {
        uint64_t dl = self.downloadManager.downloadedBytes;
        uint64_t exp = self.downloadManager.expectedBytes;
        if (exp > 0) {
            double pct = ((double)dl / (double)exp) * 100.0;
            if (pct > 99.9) pct = 99.9;
            badge = [NSString stringWithFormat:@"%@ • DL %.0f%%", running ? @"AI ON" : @"AI OFF", pct];
            [self.downloadInfoItem setTitle:[NSString stringWithFormat:@"Downloading %@: %@ / %@ (%.0f%%)",
                                             self.downloadManager.activeLabel ?: @"File",
                                             [ModelCatalog formatBytes:dl],
                                             [ModelCatalog formatBytes:exp], pct]];
        } else {
            badge = [NSString stringWithFormat:@"%@ • DL", running ? @"AI ON" : @"AI OFF"];
            [self.downloadInfoItem setTitle:[NSString stringWithFormat:@"Downloading %@: %@",
                                             self.downloadManager.activeLabel ?: @"File",
                                             [ModelCatalog formatBytes:dl]]];
        }
        [self.downloadInfoItem setHidden:NO];
    } else {
        [self.downloadInfoItem setHidden:YES];
    }

    [self.statusItem setTitle:[NSString stringWithFormat:@" %@", badge]];

    NSInteger port = self.serverController.port;
    if (healthy) {
        NSString *pids = self.serverController.activePIDsText;
        [self.statusInfoItem setTitle:pids.length > 0
            ? [NSString stringWithFormat:@"Server: Online (PID %@ • Port %ld)", pids, (long)port]
            : [NSString stringWithFormat:@"Server: Online (Port %ld)", (long)port]];
    } else if (running) {
        [self.statusInfoItem setTitle:@"Server: Starting / Busy..."];
    } else {
        [self.statusInfoItem setTitle:[NSString stringWithFormat:@"Server: Stopped (CPU Tier: %@)", self.hardware.cpuTier]];
    }

    NSArray *loaded = self.serverController.loadedModels;
    NSArray *diskModels = [self installedModelFiles];
    if (loaded.count > 0) {
        [self.modelInfoItem setTitle:[NSString stringWithFormat:@"Active Model: %@", [loaded componentsJoinedByString:@", "]]];
    } else if (diskModels.count > 0) {
        [self.modelInfoItem setTitle:[NSString stringWithFormat:@"Models Ready (%lu): %@", (unsigned long)diskModels.count, [diskModels[0] stringByDeletingPathExtension]]];
    } else {
        [self.modelInfoItem setTitle:@"Models Ready: None (open Marketplace)"];
    }

    NSString *freeStr = [ModelCatalog formatBytes:self.hardware.availableRAMBytes];
    if (self.serverController.serverRSSMB > 0.5) {
        NSString *aiMem = self.serverController.serverRSSMB >= 1024.0
            ? [NSString stringWithFormat:@"%.2f GB", self.serverController.serverRSSMB / 1024.0]
            : [NSString stringWithFormat:@"%.0f MB", self.serverController.serverRSSMB];
        [self.ramInfoItem setTitle:[NSString stringWithFormat:@"RAM: %@ free / %ld GB (AI: %@)", freeStr, (long)self.hardware.installedRAMGB, aiMem]];
    } else {
        [self.ramInfoItem setTitle:[NSString stringWithFormat:@"RAM: %@ free / %ld GB", freeStr, (long)self.hardware.installedRAMGB]];
    }

    NSString *hostStr = self.serverController.allowLAN ? (self.hardware.lanIP ?: @"127.0.0.1") : @"127.0.0.1";
    NSString *lanURL = [NSString stringWithFormat:@"http://%@:%ld", hostStr, (long)port];
    [self.lanInfoItem setTitle:[NSString stringWithFormat:@"Web UI: %@", lanURL]];
    [self.lanCopyItem setTitle:[NSString stringWithFormat:@"Copy LAN URL (%@)", lanURL]];

    BOOL hasEngine = [self.engineManager isEngineInstalledWithCustomPath:self.serverController.customEnginePath];
    [self.startItem setEnabled:(hasEngine && !running && !busy)];
    [self.stopItem setEnabled:(running && !busy)];
    [self.restartItem setEnabled:(hasEngine && running && !busy)];
}

- (void)menuWillOpen:(NSMenu *)menu {
    (void)menu;
    [self refreshState];
}

#pragma mark - Menu Actions

- (IBAction)launchChatbotAction:(id)sender {
    (void)sender;
    [self handleLaunchChatbot];
}

- (IBAction)copyLanURLAction:(id)sender {
    (void)sender;
    NSString *hostStr = self.serverController.allowLAN ? (self.hardware.lanIP ?: @"127.0.0.1") : @"127.0.0.1";
    NSString *url = [NSString stringWithFormat:@"http://%@:%ld", hostStr, (long)self.serverController.port];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb declareTypes:@[NSPasteboardTypeString] owner:nil];
    [pb setString:url forType:NSPasteboardTypeString];
}

- (IBAction)openMainWindowAction:(id)sender {
    (void)sender;
    [self.windowController showWindowAndSelectTab:-1];
}

- (IBAction)startServerAction:(id)sender {
    (void)sender;
    [self.serverController startServerWithHardwareRAMGB:self.hardware.installedRAMGB
                                            logicalCPUs:self.hardware.logicalCPUCount
                                             completion:^(BOOL success, NSString *err) {
        [self updateMenuUI];
        if (!success && err) {
            NSAlert *alert = [NSAlert alertWithMessageText:@"Server Start Error"
                                             defaultButton:@"OK"
                                           alternateButton:nil
                                               otherButton:nil
                                 informativeTextWithFormat:@"%@", err];
            [alert runModal];
        }
    }];
}

- (IBAction)stopServerAction:(id)sender {
    (void)sender;
    [self.serverController stopServerWithCompletion:^{
        [self updateMenuUI];
    }];
}

- (IBAction)restartServerAction:(id)sender {
    (void)sender;
    [self.serverController restartServerWithHardwareRAMGB:self.hardware.installedRAMGB
                                              logicalCPUs:self.hardware.logicalCPUCount
                                               completion:^(BOOL success, NSString *err) {
        (void)success;
        (void)err;
        [self updateMenuUI];
    }];
}

- (IBAction)viewLogAction:(id)sender {
    (void)sender;
    NSString *logPath = [ServerController logFilePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
        [[NSFileManager defaultManager] createFileAtPath:logPath contents:[NSData data] attributes:nil];
    }
    [[NSWorkspace sharedWorkspace] openFile:logPath withApplication:@"Console"];
}

#pragma mark - Lifecycle

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    self.downloadManager = [[DownloadManager alloc] init];
    self.engineManager = [[EngineManager alloc] init];
    self.serverController = [[ServerController alloc] initWithEngineManager:self.engineManager];
    self.hardware = [HardwareInspector inspectWithModelsPath:self.serverController.modelsDirectory];

    self.windowController = [[MainWindowController alloc] initWithHardwareInfo:self.hardware
                                                               downloadManager:self.downloadManager
                                                                 engineManager:self.engineManager
                                                              serverController:self.serverController];
    __weak AppDelegate *weakSelf = self;
    self.windowController.onLaunchChatbotRequested = ^{
        [weakSelf handleLaunchChatbot];
    };
    self.windowController.onStateUpdated = ^{
        [weakSelf updateMenuUI];
    };

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [self.statusItem setImage:[self createMenuBarIcon]];
    [self.statusItem setHighlightMode:YES];
    [self.statusItem setTitle:@" AI"];

    self.menu = [[NSMenu alloc] init];
    [self.menu setAutoenablesItems:NO];
    [self.menu setDelegate:self];

    self.statusInfoItem = [[NSMenuItem alloc] initWithTitle:@"Server: Checking..." action:nil keyEquivalent:@""];
    [self.statusInfoItem setEnabled:NO];
    [self.menu addItem:self.statusInfoItem];

    self.modelInfoItem = [[NSMenuItem alloc] initWithTitle:@"Models: Checking..." action:nil keyEquivalent:@""];
    [self.modelInfoItem setEnabled:NO];
    [self.menu addItem:self.modelInfoItem];

    self.ramInfoItem = [[NSMenuItem alloc] initWithTitle:@"RAM: Checking..." action:nil keyEquivalent:@""];
    [self.ramInfoItem setEnabled:NO];
    [self.menu addItem:self.ramInfoItem];

    self.downloadInfoItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [self.downloadInfoItem setEnabled:NO];
    [self.downloadInfoItem setHidden:YES];
    [self.menu addItem:self.downloadInfoItem];

    self.lanInfoItem = [[NSMenuItem alloc] initWithTitle:@"Web UI: http://127.0.0.1:8080" action:nil keyEquivalent:@""];
    [self.lanInfoItem setEnabled:NO];
    [self.menu addItem:self.lanInfoItem];

    [self.menu addItem:[NSMenuItem separatorItem]];

    self.launchChatbotItem = [[NSMenuItem alloc] initWithTitle:@"Launch the chatbot" action:@selector(launchChatbotAction:) keyEquivalent:@"l"];
    [self.launchChatbotItem setTarget:self];
    [self.menu addItem:self.launchChatbotItem];

    self.lanCopyItem = [[NSMenuItem alloc] initWithTitle:@"Copy LAN URL" action:@selector(copyLanURLAction:) keyEquivalent:@"c"];
    [self.lanCopyItem setTarget:self];
    [self.menu addItem:self.lanCopyItem];

    self.openWindowItem = [[NSMenuItem alloc] initWithTitle:@"Open MavLlama (Setup & Models)..." action:@selector(openMainWindowAction:) keyEquivalent:@"o"];
    [self.openWindowItem setTarget:self];
    [self.menu addItem:self.openWindowItem];

    [self.menu addItem:[NSMenuItem separatorItem]];

    self.startItem = [[NSMenuItem alloc] initWithTitle:@"Start AI Server" action:@selector(startServerAction:) keyEquivalent:@"s"];
    [self.startItem setTarget:self];
    [self.menu addItem:self.startItem];

    self.stopItem = [[NSMenuItem alloc] initWithTitle:@"Stop AI Server" action:@selector(stopServerAction:) keyEquivalent:@"k"];
    [self.stopItem setTarget:self];
    [self.menu addItem:self.stopItem];

    self.restartItem = [[NSMenuItem alloc] initWithTitle:@"Restart AI Server" action:@selector(restartServerAction:) keyEquivalent:@"r"];
    [self.restartItem setTarget:self];
    [self.menu addItem:self.restartItem];

    self.logItem = [[NSMenuItem alloc] initWithTitle:@"View Server Log" action:@selector(viewLogAction:) keyEquivalent:@"t"];
    [self.logItem setTarget:self];
    [self.menu addItem:self.logItem];

    [self.menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit MavLlama" action:@selector(terminate:) keyEquivalent:@"q"];
    [self.menu addItem:quitItem];

    [self.statusItem setMenu:self.menu];

    [self refreshState];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(refreshState) userInfo:nil repeats:YES];

    BOOL hasEngine = [self.engineManager isEngineInstalledWithCustomPath:self.serverController.customEnginePath];
    BOOL hasModels = ([self installedModelFiles].count > 0);
    if (!hasEngine) {
        [self.windowController showWindowAndSelectTab:0];
    } else if (!hasModels) {
        [self.windowController showWindowAndSelectTab:1];
    } else if (self.serverController.autoStart) {
        [self startServerAction:nil];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self.pollTimer invalidate];
    [self.downloadManager cancelAndDeletePart:NO];
    [self.serverController stopSynchronouslyForTermination];
}

@end
