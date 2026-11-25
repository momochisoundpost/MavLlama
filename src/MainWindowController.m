#import "MainWindowController.h"
#import "MarkdownRenderer.h"
#import <WebKit/WebKit.h>

@interface MavRoundedIconView : NSView
@property (nonatomic, strong) NSImage *iconImage;
@end

@implementation MavRoundedIconView
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    if (!self.iconImage) return;
    [NSGraphicsContext saveGraphicsState];
    NSBezierPath *clip = [NSBezierPath bezierPathWithRoundedRect:[self bounds] xRadius:16.0 yRadius:16.0];
    [clip addClip];
    [self.iconImage drawInRect:[self bounds]
                      fromRect:NSZeroRect
                     operation:NSCompositeSourceOver
                      fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];
}
@end

@interface MavAboutCardView : NSView
@end

@implementation MavAboutCardView
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect r = NSInsetRect([self bounds], 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:r xRadius:10.0 yRadius:10.0];
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.05] setFill];
    [path fill];
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.15] setStroke];
    [path setLineWidth:1.0];
    [path stroke];
}
@end

@interface MainWindowController ()
@property (nonatomic, strong) MavHardwareInfo *hardware;
@property (nonatomic, strong) DownloadManager *downloadManager;
@property (nonatomic, strong) EngineManager *engineManager;
@property (nonatomic, strong) ServerController *serverController;
@property (nonatomic, strong) UpdateManager *updateManager;

@property (nonatomic, strong) NSTabView *tabView;

// Tab 1: System Check & Engine
@property (nonatomic, strong) NSTextField *osCheckLabel;
@property (nonatomic, strong) NSTextField *cpuCheckLabel;
@property (nonatomic, strong) NSTextField *ramDiskCheckLabel;
@property (nonatomic, strong) NSTextField *browserCheckLabel;
@property (nonatomic, strong) NSTextField *inferenceNoticeLabel;
@property (nonatomic, strong) NSButton *mavericksForeverBtn;
@property (nonatomic, strong) NSTextField *engineStatusLabel;
@property (nonatomic, strong) NSProgressIndicator *engineProgress;
@property (nonatomic, strong) NSTextField *engineProgressLabel;
@property (nonatomic, strong) NSButton *downloadEngineBtn;
@property (nonatomic, strong) NSButton *localArchiveBtn;
@property (nonatomic, strong) NSButton *customBinaryBtn;

// Tab 2: Model Marketplace
@property (nonatomic, strong) NSTextField *marketHeaderLabel;
@property (nonatomic, strong) NSButton *overrideRAMCheck;
@property (nonatomic, strong) NSPopUpButton *familyPopup;
@property (nonatomic, strong) NSTableView *modelTable;
@property (nonatomic, strong) NSTextField *modelNotesLabel;
@property (nonatomic, strong) NSProgressIndicator *modelProgress;
@property (nonatomic, strong) NSTextField *modelProgressLabel;
@property (nonatomic, strong) NSButton *downloadModelBtn;
@property (nonatomic, strong) NSButton *cancelModelBtn;
@property (nonatomic, strong) NSButton *deleteModelBtn;
@property (nonatomic, strong) NSButton *importModelBtn;
@property (nonatomic, strong) NSButton *customURLBtn;
@property (nonatomic, strong) NSButton *refreshCatalogBtn;
@property (nonatomic, strong) NSButton *launchFromMarketBtn;

@property (nonatomic, strong) NSArray *catalogModels;
@property (nonatomic, strong) NSArray *displayedModels;

// Tab 3: Server & Settings
@property (nonatomic, strong) NSTextField *modelsDirField;
@property (nonatomic, strong) NSButton *allowLANCheck;
@property (nonatomic, strong) NSTextField *portField;
@property (nonatomic, strong) NSPopUpButton *threadsPopup;
@property (nonatomic, strong) NSPopUpButton *ctxPopup;
@property (nonatomic, strong) NSButton *autoStartCheck;
@property (nonatomic, strong) NSTextField *serverBannerLabel;

// Tab 4: Updates
@property (nonatomic, strong) NSTextField *updatesStatusLabel;
@property (nonatomic, strong) NSButton *checkUpdatesBtn;
@property (nonatomic, strong) NSPopUpButton *releasePopup;
@property (nonatomic, strong) NSButton *viewOnGitHubBtn;
@property (nonatomic, strong) WebView *releaseWebView;
@property (nonatomic, strong) NSProgressIndicator *updateProgress;
@property (nonatomic, strong) NSTextField *updateProgressLabel;
@property (nonatomic, strong) NSButton *installUpdateBtn;
@property (nonatomic, strong) NSArray *releases;
@property (nonatomic, strong) MavReleaseInfo *latestStableRelease;
@property (nonatomic, strong) MavReleaseInfo *selectedRelease;
@property (nonatomic, assign) BOOL hasLoadedReleases;
@property (nonatomic, assign) BOOL isCheckingReleases;

// Tab 5: About
@property (nonatomic, strong) NSTextField *aboutStorageLabel;
@end

@implementation MainWindowController

- (instancetype)initWithHardwareInfo:(MavHardwareInfo *)hardware
                     downloadManager:(DownloadManager *)downloadManager
                       engineManager:(EngineManager *)engineManager
                    serverController:(ServerController *)serverController
                       updateManager:(UpdateManager *)updateManager {
    NSRect frame = NSMakeRect(0, 0, 800, 560);
    NSUInteger mask = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;
    NSWindow *win = [[NSWindow alloc] initWithContentRect:frame
                                                styleMask:mask
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    [win setTitle:@"MavLlama — OS X Mavericks Local LLM Runner"];
    [win setMinSize:NSMakeSize(740, 520)];
    [win setReleasedWhenClosed:NO];
    [win center];

    self = [super initWithWindow:win];
    if (self) {
        _hardware = hardware;
        _downloadManager = downloadManager;
        _engineManager = engineManager;
        _serverController = serverController;
        _updateManager = updateManager ?: [[UpdateManager alloc] init];
        _catalogModels = [ModelCatalog loadEmbeddedCatalog];
        _displayedModels = @[];
        _releases = @[];
        [self buildUI];
        [self refreshAllViews];
        [self refreshRemoteCatalogInBackground];
    }
    return self;
}

- (NSTextField *)makeLabel:(NSRect)frame text:(NSString *)text bold:(BOOL)bold size:(CGFloat)size {
    NSTextField *tf = [[NSTextField alloc] initWithFrame:frame];
    [tf setBezeled:NO];
    [tf setDrawsBackground:NO];
    [tf setEditable:NO];
    [tf setSelectable:YES];
    [tf setStringValue:text ?: @""];
    [tf setFont:bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size]];
    [[tf cell] setLineBreakMode:NSLineBreakByWordWrapping];
    return tf;
}

- (NSButton *)makeButton:(NSRect)frame title:(NSString *)title action:(SEL)sel {
    NSButton *btn = [[NSButton alloc] initWithFrame:frame];
    [btn setBezelStyle:NSRoundedBezelStyle];
    [btn setTitle:title];
    [btn setTarget:self];
    [btn setAction:sel];
    return btn;
}

- (void)buildUI {
    NSView *content = [[self window] contentView];
    NSRect bounds = [content bounds];

    self.tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(14, 12, bounds.size.width - 28, bounds.size.height - 24)];
    [self.tabView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [self.tabView setDelegate:self];
    [content addSubview:self.tabView];

    [self buildSystemTab];
    [self buildMarketplaceTab];
    [self buildSettingsTab];
    [self buildUpdatesTab];
    [self buildAboutTab];
}

- (void)buildSystemTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] initWithIdentifier:@"system"];
    [tab setLabel:@"System Check & Engine"];
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 750, 480)];

    [v addSubview:[self makeLabel:NSMakeRect(18, 438, 700, 22) text:@"Mavericks Hardware & Environment Check" bold:YES size:14]];

    self.osCheckLabel = [self makeLabel:NSMakeRect(18, 408, 700, 20) text:@"" bold:NO size:12];
    self.cpuCheckLabel = [self makeLabel:NSMakeRect(18, 382, 700, 20) text:@"" bold:NO size:12];
    self.ramDiskCheckLabel = [self makeLabel:NSMakeRect(18, 356, 700, 20) text:@"" bold:NO size:12];
    self.browserCheckLabel = [self makeLabel:NSMakeRect(18, 314, 530, 36) text:@"" bold:NO size:12];
    [v addSubview:self.osCheckLabel];
    [v addSubview:self.cpuCheckLabel];
    [v addSubview:self.ramDiskCheckLabel];
    [v addSubview:self.browserCheckLabel];

    self.mavericksForeverBtn = [self makeButton:NSMakeRect(558, 318, 170, 28) title:@"Open Mavericks Forever" action:@selector(openMavericksForever:)];
    [v addSubview:self.mavericksForeverBtn];

    self.inferenceNoticeLabel = [self makeLabel:NSMakeRect(18, 256, 710, 48) text:@"" bold:YES size:11.5];
    [v addSubview:self.inferenceNoticeLabel];

    NSBox *sep = [[NSBox alloc] initWithFrame:NSMakeRect(18, 240, 710, 2)];
    [sep setBoxType:NSBoxSeparator];
    [v addSubview:sep];

    [v addSubview:[self makeLabel:NSMakeRect(18, 208, 700, 22) text:@"Tailored llama.cpp Engine (Zero-Compiler Runtime)" bold:YES size:14]];
    self.engineStatusLabel = [self makeLabel:NSMakeRect(18, 166, 710, 36) text:@"" bold:NO size:12];
    [v addSubview:self.engineStatusLabel];

    self.engineProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(18, 134, 520, 18)];
    [self.engineProgress setIndeterminate:NO];
    [self.engineProgress setMinValue:0.0];
    [self.engineProgress setMaxValue:100.0];
    [self.engineProgress setHidden:YES];
    [v addSubview:self.engineProgress];

    self.engineProgressLabel = [self makeLabel:NSMakeRect(548, 132, 180, 20) text:@"" bold:NO size:11.5];
    [v addSubview:self.engineProgressLabel];

    self.downloadEngineBtn = [self makeButton:NSMakeRect(18, 86, 210, 32) title:@"Download Tailored Engine" action:@selector(downloadEngineClicked:)];
    self.localArchiveBtn = [self makeButton:NSMakeRect(238, 86, 200, 32) title:@"Install Local Engine .tar.gz..." action:@selector(installLocalArchiveClicked:)];
    self.customBinaryBtn = [self makeButton:NSMakeRect(448, 86, 195, 32) title:@"Use Existing llama-server..." action:@selector(chooseCustomBinaryClicked:)];
    [v addSubview:self.downloadEngineBtn];
    [v addSubview:self.localArchiveBtn];
    [v addSubview:self.customBinaryBtn];

    [v addSubview:[self makeLabel:NSMakeRect(18, 24, 710, 44)
                             text:@"Tip: MavLlama bundles its own minimal OpenSSL 3 + curl runtime and ships separate SSE3/SSSE3 (Core 2 Duo), SSE4.2 (Nehalem), AVX (Sandy Bridge), AVX+F16C (Ivy Bridge), and AVX2 (Haswell) builds so even an unpatched 10.9.0 Mac runs safely."
                             bold:NO
                             size:11]];

    [tab setView:v];
    [self.tabView addTabViewItem:tab];
}

- (void)buildMarketplaceTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] initWithIdentifier:@"marketplace"];
    [tab setLabel:@"Model Marketplace"];
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 750, 480)];

    self.marketHeaderLabel = [self makeLabel:NSMakeRect(16, 428, 720, 36) text:@"" bold:YES size:12];
    [v addSubview:self.marketHeaderLabel];

    self.overrideRAMCheck = [[NSButton alloc] initWithFrame:NSMakeRect(16, 396, 285, 22)];
    [self.overrideRAMCheck setButtonType:NSSwitchButton];
    [self.overrideRAMCheck setTitle:@"Show all models (override RAM filter)"];
    [self.overrideRAMCheck setTarget:self];
    [self.overrideRAMCheck setAction:@selector(filterChanged:)];
    [v addSubview:self.overrideRAMCheck];

    [v addSubview:[self makeLabel:NSMakeRect(320, 398, 55, 18) text:@"Family:" bold:NO size:12]];
    self.familyPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(376, 394, 130, 26) pullsDown:NO];
    [self.familyPopup addItemsWithTitles:@[@"All", @"Gemma", @"DeepSeek", @"Qwen", @"Llama", @"Phi", @"SmolLM", @"Local"]];
    [self.familyPopup setTarget:self];
    [self.familyPopup setAction:@selector(filterChanged:)];
    [v addSubview:self.familyPopup];

    self.refreshCatalogBtn = [self makeButton:NSMakeRect(600, 393, 134, 28) title:@"Refresh Catalog" action:@selector(refreshCatalogClicked:)];
    [v addSubview:self.refreshCatalogBtn];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 128, 718, 256)];
    [scroll setHasVerticalScroller:YES];
    [scroll setHasHorizontalScroller:NO];
    [scroll setBorderType:NSBezelBorder];
    [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    self.modelTable = [[NSTableView alloc] initWithFrame:[scroll bounds]];
    [self.modelTable setUsesAlternatingRowBackgroundColors:YES];
    [self.modelTable setDataSource:self];
    [self.modelTable setDelegate:self];

    NSArray *cols = @[
        @[@"name", @"Model", @255],
        @[@"family", @"Family", @80],
        @[@"arch", @"Type", @85],
        @[@"size", @"Size", @80],
        @[@"ram", @"Min RAM", @70],
        @[@"status", @"Status", @125]
    ];
    for (NSArray *spec in cols) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
        [[col headerCell] setStringValue:spec[1]];
        [col setWidth:[spec[2] doubleValue]];
        [col setEditable:NO];
        [self.modelTable addTableColumn:col];
    }
    [scroll setDocumentView:self.modelTable];
    [v addSubview:scroll];

    self.modelNotesLabel = [self makeLabel:NSMakeRect(16, 86, 718, 34) text:@"Select a model to inspect details." bold:NO size:11.5];
    [v addSubview:self.modelNotesLabel];

    self.modelProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(16, 56, 510, 18)];
    [self.modelProgress setIndeterminate:NO];
    [self.modelProgress setMinValue:0.0];
    [self.modelProgress setMaxValue:100.0];
    [self.modelProgress setHidden:YES];
    [v addSubview:self.modelProgress];

    self.modelProgressLabel = [self makeLabel:NSMakeRect(534, 54, 200, 20) text:@"" bold:NO size:11.5];
    [v addSubview:self.modelProgressLabel];

    self.downloadModelBtn = [self makeButton:NSMakeRect(16, 16, 118, 30) title:@"Download" action:@selector(downloadModelClicked:)];
    self.cancelModelBtn = [self makeButton:NSMakeRect(138, 16, 90, 30) title:@"Cancel" action:@selector(cancelDownloadClicked:)];
    self.deleteModelBtn = [self makeButton:NSMakeRect(232, 16, 90, 30) title:@"Delete" action:@selector(deleteModelClicked:)];
    self.importModelBtn = [self makeButton:NSMakeRect(326, 16, 145, 30) title:@"Import Local .gguf..." action:@selector(importLocalGGUFClicked:)];
    self.customURLBtn = [self makeButton:NSMakeRect(475, 16, 122, 30) title:@"Custom URL..." action:@selector(customURLClicked:)];
    self.launchFromMarketBtn = [self makeButton:NSMakeRect(602, 16, 132, 30) title:@"Launch Chatbot" action:@selector(launchChatbotClicked:)];
    [v addSubview:self.downloadModelBtn];
    [v addSubview:self.cancelModelBtn];
    [v addSubview:self.deleteModelBtn];
    [v addSubview:self.importModelBtn];
    [v addSubview:self.customURLBtn];
    [v addSubview:self.launchFromMarketBtn];

    [tab setView:v];
    [self.tabView addTabViewItem:tab];
}

- (void)buildSettingsTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] initWithIdentifier:@"settings"];
    [tab setLabel:@"Server & Settings"];
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 750, 480)];

    [v addSubview:[self makeLabel:NSMakeRect(18, 434, 680, 22) text:@"Local Server & Storage Configuration" bold:YES size:14]];

    [v addSubview:[self makeLabel:NSMakeRect(18, 396, 130, 20) text:@"Models Folder:" bold:NO size:12]];
    self.modelsDirField = [[NSTextField alloc] initWithFrame:NSMakeRect(150, 394, 410, 24)];
    [self.modelsDirField setEditable:NO];
    [v addSubview:self.modelsDirField];
    [v addSubview:[self makeButton:NSMakeRect(566, 392, 85, 28) title:@"Choose..." action:@selector(chooseModelsDirClicked:)]];
    [v addSubview:[self makeButton:NSMakeRect(654, 392, 80, 28) title:@"Reset" action:@selector(resetModelsDirClicked:)]];

    self.allowLANCheck = [[NSButton alloc] initWithFrame:NSMakeRect(150, 354, 480, 22)];
    [self.allowLANCheck setButtonType:NSSwitchButton];
    [self.allowLANCheck setTitle:@"Allow LAN access (bind 0.0.0.0 so tablets & PCs on your Wi-Fi can open Web UI)"];
    [v addSubview:self.allowLANCheck];

    [v addSubview:[self makeLabel:NSMakeRect(18, 316, 130, 20) text:@"Listen Port:" bold:NO size:12]];
    self.portField = [[NSTextField alloc] initWithFrame:NSMakeRect(150, 314, 100, 24)];
    [v addSubview:self.portField];

    [v addSubview:[self makeLabel:NSMakeRect(18, 276, 130, 20) text:@"CPU Threads:" bold:NO size:12]];
    self.threadsPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, 272, 180, 26) pullsDown:NO];
    [self.threadsPopup addItemsWithTitles:@[@"Auto", @"1", @"2", @"4", @"8", @"12", @"16"]];
    [v addSubview:self.threadsPopup];

    [v addSubview:[self makeLabel:NSMakeRect(18, 236, 130, 20) text:@"Context Window:" bold:NO size:12]];
    self.ctxPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, 232, 220, 26) pullsDown:NO];
    [self.ctxPopup addItemsWithTitles:@[@"Auto (by RAM)", @"2048", @"4096", @"8192", @"16384", @"32768"]];
    [v addSubview:self.ctxPopup];

    self.autoStartCheck = [[NSButton alloc] initWithFrame:NSMakeRect(150, 194, 450, 22)];
    [self.autoStartCheck setButtonType:NSSwitchButton];
    [self.autoStartCheck setTitle:@"Auto-start AI server when MavLlama opens (off by default)"];
    [v addSubview:self.autoStartCheck];

    self.serverBannerLabel = [self makeLabel:NSMakeRect(18, 128, 710, 48) text:@"" bold:NO size:12];
    [v addSubview:self.serverBannerLabel];

    [v addSubview:[self makeButton:NSMakeRect(18, 76, 195, 32) title:@"Save & Restart Server" action:@selector(saveSettingsClicked:)]];
    [v addSubview:[self makeButton:NSMakeRect(222, 76, 165, 32) title:@"Open Models Folder" action:@selector(openModelsFolderClicked:)]];
    [v addSubview:[self makeButton:NSMakeRect(396, 76, 150, 32) title:@"Open Server Log" action:@selector(openServerLogClicked:)]];
    [v addSubview:[self makeButton:NSMakeRect(556, 76, 175, 32) title:@"Launch the chatbot" action:@selector(launchChatbotClicked:)]];

    [tab setView:v];
    [self.tabView addTabViewItem:tab];
}

- (void)buildUpdatesTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] initWithIdentifier:@"updates"];
    [tab setLabel:@"Updates"];
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 750, 480)];
    [v setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    self.updatesStatusLabel = [self makeLabel:NSMakeRect(18, 444, 560, 20)
                                         text:[NSString stringWithFormat:@"Installed: v%@ \u2014 Ready to check for updates.", [self.updateManager currentAppVersion]]
                                         bold:YES
                                         size:13];
    [self.updatesStatusLabel setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [v addSubview:self.updatesStatusLabel];

    self.checkUpdatesBtn = [self makeButton:NSMakeRect(592, 439, 140, 28) title:@"Check Again" action:@selector(checkUpdatesClicked:)];
    [self.checkUpdatesBtn setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [v addSubview:self.checkUpdatesBtn];

    NSTextField *relLbl = [self makeLabel:NSMakeRect(18, 408, 60, 18) text:@"Release:" bold:NO size:12];
    [relLbl setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
    [v addSubview:relLbl];

    self.releasePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(80, 403, 502, 26) pullsDown:NO];
    [self.releasePopup addItemWithTitle:@"Loading GitHub Releases..."];
    [self.releasePopup setTarget:self];
    [self.releasePopup setAction:@selector(releaseSelectionChanged:)];
    [self.releasePopup setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [v addSubview:self.releasePopup];

    self.viewOnGitHubBtn = [self makeButton:NSMakeRect(592, 402, 140, 28) title:@"View on GitHub" action:@selector(viewReleaseOnGitHubClicked:)];
    [self.viewOnGitHubBtn setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [v addSubview:self.viewOnGitHubBtn];

    NSBox *frameBox = [[NSBox alloc] initWithFrame:NSMakeRect(18, 64, 714, 330)];
    [frameBox setTitlePosition:NSNoTitle];
    [frameBox setBoxType:NSBoxCustom];
    [frameBox setBorderType:NSLineBorder];
    [frameBox setBorderWidth:1.0];
    [frameBox setBorderColor:[NSColor colorWithCalibratedWhite:0.78 alpha:1.0]];
    [frameBox setContentViewMargins:NSMakeSize(0, 0)];
    [frameBox setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    NSView *boxContent = [frameBox contentView];
    self.releaseWebView = [[WebView alloc] initWithFrame:[boxContent bounds]];
    [self.releaseWebView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [self.releaseWebView setPolicyDelegate:self];
    [frameBox addSubview:self.releaseWebView];
    [v addSubview:frameBox];

    self.updateProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(18, 28, 300, 18)];
    [self.updateProgress setIndeterminate:NO];
    [self.updateProgress setMinValue:0.0];
    [self.updateProgress setMaxValue:100.0];
    [self.updateProgress setHidden:YES];
    [self.updateProgress setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
    [v addSubview:self.updateProgress];

    self.updateProgressLabel = [self makeLabel:NSMakeRect(326, 26, 160, 18) text:@"" bold:NO size:11.5];
    [self.updateProgressLabel setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [v addSubview:self.updateProgressLabel];

    self.installUpdateBtn = [self makeButton:NSMakeRect(496, 20, 236, 32) title:@"Checking Releases..." action:@selector(installUpdateClicked:)];
    [self.installUpdateBtn setEnabled:NO];
    [self.installUpdateBtn setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
    [v addSubview:self.installUpdateBtn];

    [tab setView:v];
    [self.tabView addTabViewItem:tab];
    [self loadPlaceholderReleaseNotes];
}

- (void)buildAboutTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] initWithIdentifier:@"about"];
    [tab setLabel:@"About"];
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 750, 480)];
    [v setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"llama-icon" ofType:@"png"];
    NSImage *iconImg = iconPath ? [[NSImage alloc] initWithContentsOfFile:iconPath] : [NSApp applicationIconImage];
    MavRoundedIconView *iconView = [[MavRoundedIconView alloc] initWithFrame:NSMakeRect(339, 368, 72, 72)];
    iconView.iconImage = iconImg;
    [iconView setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin];
    [v addSubview:iconView];

    NSTextField *titleLbl = [self makeLabel:NSMakeRect(125, 330, 500, 28) text:@"MavLlama" bold:YES size:20];
    [titleLbl setAlignment:NSCenterTextAlignment];
    [titleLbl setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin];
    [v addSubview:titleLbl];

    NSString *verStr = [NSString stringWithFormat:@"Current Version: %@", [self.updateManager currentAppVersion]];
    NSTextField *verLbl = [self makeLabel:NSMakeRect(125, 306, 500, 20) text:verStr bold:NO size:12.5];
    [verLbl setAlignment:NSCenterTextAlignment];
    [verLbl setTextColor:[NSColor colorWithCalibratedWhite:0.42 alpha:1.0]];
    [verLbl setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin];
    [v addSubview:verLbl];

    MavAboutCardView *card = [[MavAboutCardView alloc] initWithFrame:NSMakeRect(115, 196, 520, 92)];
    [card setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin];

    NSTextField *taglineLbl = [self makeLabel:NSMakeRect(16, 44, 488, 36)
                                         text:@"MavLlama \u2014 So I put local LLMs on Mavericks because nobody did it."
                                         bold:YES
                                         size:13];
    [taglineLbl setAlignment:NSCenterTextAlignment];
    [card addSubview:taglineLbl];

    NSTextField *creditLbl = [self makeLabel:NSMakeRect(16, 14, 488, 22)
                                        text:@"built in public by Caitlyn Momochi"
                                        bold:NO
                                        size:12];
    NSFont *italicFont = [[NSFontManager sharedFontManager] convertFont:[NSFont systemFontOfSize:12.0] toHaveTrait:NSItalicFontMask];
    if (italicFont) [creditLbl setFont:italicFont];
    [creditLbl setAlignment:NSCenterTextAlignment];
    [creditLbl setTextColor:[NSColor colorWithCalibratedWhite:0.35 alpha:1.0]];
    [card addSubview:creditLbl];
    [v addSubview:card];

    NSButton *ytBtn = [self makeButton:NSMakeRect(125, 142, 116, 32) title:@"YouTube" action:@selector(openSocialYouTube:)];
    NSButton *xBtn = [self makeButton:NSMakeRect(253, 142, 116, 32) title:@"Twitter / X" action:@selector(openSocialTwitter:)];
    NSButton *ghBtn = [self makeButton:NSMakeRect(381, 142, 116, 32) title:@"GitHub" action:@selector(openSocialGitHub:)];
    NSButton *igBtn = [self makeButton:NSMakeRect(509, 142, 116, 32) title:@"Instagram" action:@selector(openSocialInstagram:)];
    NSArray *socialBtns = @[ytBtn, xBtn, ghBtn, igBtn];
    for (NSButton *b in socialBtns) {
        [b setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin];
        [v addSubview:b];
    }

    self.aboutStorageLabel = [self makeLabel:NSMakeRect(75, 84, 600, 40) text:@"" bold:NO size:11];
    [self.aboutStorageLabel setAlignment:NSCenterTextAlignment];
    [self.aboutStorageLabel setTextColor:[NSColor colorWithCalibratedWhite:0.45 alpha:1.0]];
    [self.aboutStorageLabel setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin];
    [v addSubview:self.aboutStorageLabel];

    [tab setView:v];
    [self.tabView addTabViewItem:tab];
}

- (void)showWindowAndSelectTab:(NSInteger)tabIndex {
    if (tabIndex >= 0 && tabIndex < [self.tabView numberOfTabViewItems]) {
        [self.tabView selectTabViewItemAtIndex:tabIndex];
        if (tabIndex == 3 && !self.hasLoadedReleases && !self.isCheckingReleases) {
            [self checkForUpdatesForce:NO];
        }
    }
    [self refreshAllViews];
    [self showWindow:nil];
    [[self window] makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    (void)tabView;
    if ([[tabViewItem identifier] isEqualToString:@"updates"] && !self.hasLoadedReleases && !self.isCheckingReleases) {
        [self checkForUpdatesForce:NO];
    }
}

- (void)refreshRemoteCatalogInBackground {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *err = nil;
        NSData *data = [DownloadManager fetchDataFromURL:[ModelCatalog remoteCatalogURL] error:&err];
        if (!data) return;
        NSArray *parsed = [ModelCatalog parseModelsFromData:data error:nil];
        if (parsed && parsed.count > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.catalogModels = parsed;
                [self refreshMarketplaceTable];
            });
        }
    });
}

- (void)refreshAllViews {
    NSString *modelsDir = [self.serverController modelsDirectory];
    self.hardware = [HardwareInspector inspectWithModelsPath:modelsDir];

    // OS check
    NSString *osPrefix = @"[OK]";
    if ([self.hardware.osStatusLevel isEqualToString:@"advisory"]) {
        osPrefix = @"[OK - Older 10.9 build]";
    } else if ([self.hardware.osStatusLevel isEqualToString:@"unsupported"]) {
        osPrefix = @"[Warning]";
    }
    [self.osCheckLabel setStringValue:[NSString stringWithFormat:@"%@ OS X %@ (%@) — Bundled OpenSSL 3 + curl TLS active",
                                       osPrefix, self.hardware.osVersion,
                                       self.hardware.osBuild.length > 0 ? self.hardware.osBuild : @"unknown build"]];

    [self.cpuCheckLabel setStringValue:[NSString stringWithFormat:@"[OK] CPU: %@ (%ld threads) — Selected Tier: %@",
                                        self.hardware.cpuBrand, (long)self.hardware.logicalCPUCount, self.hardware.cpuTierDisplayName]];

    [self.ramDiskCheckLabel setStringValue:[NSString stringWithFormat:@"[OK] RAM: %ld GB installed (%@ free) | Free disk on Models drive: %@",
                                            (long)self.hardware.installedRAMGB,
                                            [ModelCatalog formatBytes:self.hardware.availableRAMBytes],
                                            [ModelCatalog formatBytes:self.hardware.freeDiskBytes]]];

    if ([self.hardware.modernBrowserBundleID isEqualToString:@"com.apple.Safari"]) {
        [self.browserCheckLabel setStringValue:[NSString stringWithFormat:@"[OK] Default Browser: Safari (Aqua WebKit supported; unpatched Safari 9 needs Aqua WebKit or Momiji). LAN URL: http://%@:%ld",
                                                self.hardware.lanIP, (long)self.serverController.port]];
        [self.mavericksForeverBtn setHidden:NO];
    } else if (self.hardware.modernBrowserName) {
        [self.browserCheckLabel setStringValue:[NSString stringWithFormat:@"[OK] Default Browser: %@ (used by Launch the chatbot). LAN URL: http://%@:%ld",
                                                self.hardware.modernBrowserName, self.hardware.lanIP, (long)self.serverController.port]];
        [self.mavericksForeverBtn setHidden:YES];
    } else {
        [self.browserCheckLabel setStringValue:[NSString stringWithFormat:@"[Advisory] No default browser detected. Install Aqua WebKit or Momiji at mavericksforever.com, or open LAN URL http://%@:%ld.",
                                                self.hardware.lanIP, (long)self.serverController.port]];
        [self.mavericksForeverBtn setHidden:NO];
    }

    NSString *notice = [HardwareInspector inferenceNoticeForIsMacPro:self.hardware.isMacPro
                                                        modelIdentifier:self.hardware.modelIdentifier
                                                                hasAVX2:self.hardware.hasAVX2];
    [self.inferenceNoticeLabel setStringValue:notice];
    [self.inferenceNoticeLabel setTextColor:self.hardware.isMacPro
        ? [NSColor colorWithCalibratedRed:0.65 green:0.32 blue:0.0 alpha:1.0]
        : [NSColor colorWithCalibratedWhite:0.30 alpha:1.0]];
    [self.inferenceNoticeLabel setHidden:NO];

    // Engine status
    NSString *activeBin = [self.engineManager activeServerBinaryPathWithCustomPath:self.serverController.customEnginePath];
    NSDictionary *meta = [self.engineManager installedMetadata];
    if (activeBin) {
        if (self.serverController.customEnginePath.length > 0 && [activeBin isEqualToString:self.serverController.customEnginePath]) {
            [self.engineStatusLabel setStringValue:[NSString stringWithFormat:@"[Ready] Using custom llama-server binary: %@", activeBin]];
        } else {
            [self.engineStatusLabel setStringValue:[NSString stringWithFormat:@"[Ready] Tailored engine installed (%@ / %@) at %@",
                                                    meta[@"tier"] ?: self.hardware.cpuTier,
                                                    meta[@"releaseTag"] ?: self.engineManager.releaseTag,
                                                    activeBin]];
        }
    } else {
        MavEngineTierInfo *tierInfo = [self.engineManager infoForTier:self.hardware.cpuTier];
        NSString *sizeStr = tierInfo && tierInfo.sizeBytes > 0 ? [ModelCatalog formatBytes:tierInfo.sizeBytes] : @"~15 MB";
        [self.engineStatusLabel setStringValue:[NSString stringWithFormat:@"[Missing] No llama-server installed yet. Ready to download '%@' build (%@).",
                                                self.hardware.cpuTier, sizeStr]];
    }

    BOOL dlActive = self.downloadManager.isDownloading;
    [self.downloadEngineBtn setEnabled:!dlActive];
    [self.localArchiveBtn setEnabled:!dlActive];
    [self.customBinaryBtn setEnabled:!dlActive];

    [self refreshMarketplaceTable];
    [self refreshSettingsViews];
    [self refreshUpdatesControls];
    [self refreshAboutViews];
}

- (void)refreshAboutViews {
    NSString *appSup = [EngineManager defaultEngineDirectory];
    NSString *baseSup = [appSup stringByDeletingLastPathComponent];
    NSString *modelsDir = self.serverController.modelsDirectory ?: [ServerController defaultModelsDirectory];
    [self.aboutStorageLabel setStringValue:[NSString stringWithFormat:
                                            @"Engine & settings stored in %@\nModels stored in %@",
                                            baseSup, modelsDir]];
}

- (void)refreshMarketplaceTable {
    NSArray *reconciled = [ModelCatalog reconcileModels:self.catalogModels
                                          withModelsDir:self.serverController.modelsDirectory
                                           downloadsDir:[EngineManager defaultDownloadsDirectory]];

    if (self.hardware.isMacPro) {
        [self.overrideRAMCheck setHidden:YES];
        NSString *caps = self.hardware.hasAVX2 ? @"no OpenCL, no Metal" : @"no AVX2, no OpenCL, no Metal";
        [self.marketHeaderLabel setStringValue:[NSString stringWithFormat:@"Hey Mac Pro (%@, %ld GB RAM) \u2014 All models unlocked! Note: Mavericks inference is CPU-only (%@); Linux yields 10\u201320x the speed.",
                                                self.hardware.modelIdentifier, (long)self.hardware.installedRAMGB, caps]];
        [self.marketHeaderLabel setTextColor:[NSColor colorWithCalibratedRed:0.65 green:0.32 blue:0.0 alpha:1.0]];
    } else {
        [self.overrideRAMCheck setHidden:NO];
        [self.marketHeaderLabel setStringValue:[NSString stringWithFormat:@"Showing models tailored for %ld GB RAM (%@ free disk). Check override below to browse larger models.",
                                                (long)self.hardware.installedRAMGB,
                                                [ModelCatalog formatBytes:self.hardware.freeDiskBytes]]];
        [self.marketHeaderLabel setTextColor:[NSColor controlTextColor]];
    }

    BOOL override = ([self.overrideRAMCheck state] == NSOnState);
    NSString *family = [self.familyPopup titleOfSelectedItem] ?: @"All";
    self.displayedModels = [ModelCatalog filterModels:reconciled
                                             forRAMGB:self.hardware.installedRAMGB
                                             isMacPro:self.hardware.isMacPro
                                       overrideFilter:override
                                         familyFilter:family];
    [self.modelTable reloadData];
    [self updateMarketplaceButtons];
}

- (void)refreshSettingsViews {
    [self.modelsDirField setStringValue:self.serverController.modelsDirectory];
    [self.allowLANCheck setState:self.serverController.allowLAN ? NSOnState : NSOffState];
    [self.portField setStringValue:[NSString stringWithFormat:@"%ld", (long)self.serverController.port]];
    [self.autoStartCheck setState:self.serverController.autoStart ? NSOnState : NSOffState];

    NSString *threadTitle = self.serverController.threads > 0 ? [NSString stringWithFormat:@"%ld", (long)self.serverController.threads] : @"Auto";
    if ([self.threadsPopup itemWithTitle:threadTitle]) {
        [self.threadsPopup selectItemWithTitle:threadTitle];
    } else {
        [self.threadsPopup selectItemAtIndex:0];
    }

    NSString *ctxTitle = self.serverController.ctxSize > 0 ? [NSString stringWithFormat:@"%ld", (long)self.serverController.ctxSize] : @"Auto (by RAM)";
    if ([self.ctxPopup itemWithTitle:ctxTitle]) {
        [self.ctxPopup selectItemWithTitle:ctxTitle];
    } else {
        [self.ctxPopup selectItemAtIndex:0];
    }

    NSString *hostStr = self.serverController.allowLAN ? self.hardware.lanIP : @"127.0.0.1";
    NSString *status = self.serverController.isHealthy
        ? [NSString stringWithFormat:@"Online (PID %@, RAM %.0f MB) — Web UI: http://%@:%ld",
           self.serverController.activePIDsText ?: @"-", self.serverController.serverRSSMB, hostStr, (long)self.serverController.port]
        : (self.serverController.isRunning ? @"Starting..." : @"Stopped");
    [self.serverBannerLabel setStringValue:[NSString stringWithFormat:@"Server Status: %@\nLog file: %@", status, [ServerController logFilePath]]];
}

- (MavModelEntry *)selectedModel {
    NSInteger row = [self.modelTable selectedRow];
    if (row >= 0 && row < (NSInteger)self.displayedModels.count) {
        return self.displayedModels[(NSUInteger)row];
    }
    return nil;
}

- (void)updateMarketplaceButtons {
    MavModelEntry *m = [self selectedModel];
    BOOL dlActive = self.downloadManager.isDownloading;

    if (m) {
        [self.modelNotesLabel setStringValue:[NSString stringWithFormat:@"%@ (%@ %@): %@",
                                              m.name, m.quant, m.paramsTotal, m.notes]];
    } else {
        [self.modelNotesLabel setStringValue:@"Select a model to inspect details or import a local .gguf file."];
    }

    [self.downloadModelBtn setEnabled:(!dlActive && m != nil && !m.installedOnDisk && m.url.length > 0)];
    [self.downloadModelBtn setTitle:(m && m.partialBytes > 0) ? @"Resume" : @"Download"];
    [self.cancelModelBtn setEnabled:dlActive];
    [self.deleteModelBtn setEnabled:(!dlActive && m != nil && (m.installedOnDisk || m.partialBytes > 0))];
    [self.importModelBtn setEnabled:!dlActive];
    [self.customURLBtn setEnabled:!dlActive];
}

#pragma mark - NSTableViewDataSource / Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.displayedModels.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableView;
    if (row < 0 || row >= (NSInteger)self.displayedModels.count) return @"";
    MavModelEntry *m = self.displayedModels[(NSUInteger)row];
    NSString *ident = [tableColumn identifier];
    if ([ident isEqualToString:@"name"]) return m.name;
    if ([ident isEqualToString:@"family"]) return m.family;
    if ([ident isEqualToString:@"arch"]) {
        if ([m.architecture isEqualToString:@"moe"]) {
            return [NSString stringWithFormat:@"MoE (%@/%@)", m.paramsTotal, m.paramsActive];
        }
        if ([m.architecture isEqualToString:@"reasoning"]) return @"Reasoning";
        if ([m.architecture isEqualToString:@"local"]) return @"Custom";
        return @"Dense";
    }
    if ([ident isEqualToString:@"size"]) return [ModelCatalog formatBytes:m.sizeBytes];
    if ([ident isEqualToString:@"ram"]) return m.minRAMGB > 0 ? [NSString stringWithFormat:@"%ld GB+", (long)m.minRAMGB] : @"-";
    if ([ident isEqualToString:@"status"]) {
        if (m.installedOnDisk) return @"Installed";
        if (m.partialBytes > 0) {
            double pct = m.sizeBytes > 0 ? ((double)m.partialBytes / (double)m.sizeBytes) * 100.0 : 0.0;
            return [NSString stringWithFormat:@"Paused (%.0f%%)", pct];
        }
        return @"Available";
    }
    return @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    [self updateMarketplaceButtons];
}

#pragma mark - Actions

- (IBAction)openMavericksForever:(id)sender {
    (void)sender;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://mavericksforever.com"]];
}

- (IBAction)downloadEngineClicked:(id)sender {
    (void)sender;
    [self.engineProgress setHidden:NO];
    [self.engineProgress setDoubleValue:0.0];
    [self.engineProgressLabel setStringValue:@"Starting..."];
    [self.downloadEngineBtn setEnabled:NO];

    [self.engineManager installEngineForTier:self.hardware.cpuTier
                             downloadManager:self.downloadManager
                                    progress:^(uint64_t dl, uint64_t total) {
        double pct = total > 0 ? ((double)dl / (double)total) * 100.0 : 0.0;
        [self.engineProgress setDoubleValue:pct];
        [self.engineProgressLabel setStringValue:[NSString stringWithFormat:@"%@ / %@",
                                                  [ModelCatalog formatBytes:dl],
                                                  total > 0 ? [ModelCatalog formatBytes:total] : @"?"]];
        if (self.onStateUpdated) self.onStateUpdated();
    } completion:^(BOOL success, NSString *message) {
        [self.engineProgress setHidden:YES];
        [self.engineProgressLabel setStringValue:message ?: @""];
        if (!success) {
            NSAlert *alert = [NSAlert alertWithMessageText:@"Engine Install Failed"
                                             defaultButton:@"OK"
                                           alternateButton:nil
                                               otherButton:nil
                                 informativeTextWithFormat:@"%@", message ?: @"Unknown error."];
            [alert runModal];
        }
        [self refreshAllViews];
        if (self.onStateUpdated) self.onStateUpdated();
    }];
}

- (IBAction)installLocalArchiveClicked:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowedFileTypes:@[@"gz", @"tgz"]];
    [panel setMessage:@"Select a mavllama-engine-*.tar.gz archive:"];
    if ([panel runModal] == NSFileHandlingPanelOKButton) {
        NSString *path = [[panel URL] path];
        NSError *err = nil;
        if (![self.engineManager installLocalArchiveAtPath:path tierLabel:self.hardware.cpuTier error:&err]) {
            NSAlert *alert = [NSAlert alertWithMessageText:@"Archive Install Failed"
                                             defaultButton:@"OK"
                                           alternateButton:nil
                                               otherButton:nil
                                 informativeTextWithFormat:@"%@", [err localizedDescription] ?: @"Invalid archive."];
            [alert runModal];
        } else {
            self.serverController.customEnginePath = @"";
        }
        [self refreshAllViews];
        if (self.onStateUpdated) self.onStateUpdated();
    }
}

- (IBAction)chooseCustomBinaryClicked:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setMessage:@"Select an existing executable llama-server binary:"];
    if ([panel runModal] == NSFileHandlingPanelOKButton) {
        NSString *path = [[panel URL] path];
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
            self.serverController.customEnginePath = path;
        }
        [self refreshAllViews];
        if (self.onStateUpdated) self.onStateUpdated();
    }
}

- (IBAction)filterChanged:(id)sender {
    (void)sender;
    [self refreshMarketplaceTable];
}

- (IBAction)refreshCatalogClicked:(id)sender {
    (void)sender;
    [self refreshRemoteCatalogInBackground];
}

- (void)startModelDownloadForEntry:(MavModelEntry *)m {
    uint64_t freeBytes = [HardwareInspector freeDiskBytesForPath:self.serverController.modelsDirectory];
    if (m.sizeBytes > 0 && freeBytes > 0 && m.sizeBytes + (512ULL * 1024ULL * 1024ULL) > freeBytes) {
        NSAlert *diskAlert = [NSAlert alertWithMessageText:@"Low Disk Space Warning"
                                             defaultButton:@"Download Anyway"
                                           alternateButton:@"Cancel"
                                               otherButton:nil
                                 informativeTextWithFormat:@"This model needs %@, and your Models volume has %@ free.",
                                                           [ModelCatalog formatBytes:m.sizeBytes],
                                                           [ModelCatalog formatBytes:freeBytes]];
        if ([diskAlert runModal] != NSAlertDefaultReturn) return;
    }

    NSString *partPath = [[EngineManager defaultDownloadsDirectory] stringByAppendingPathComponent:[m.filename stringByAppendingString:@".part"]];
    NSString *destPath = [self.serverController.modelsDirectory stringByAppendingPathComponent:m.filename];

    [self.modelProgress setHidden:NO];
    [self.modelProgress setDoubleValue:0.0];
    [self.modelProgressLabel setStringValue:@"Connecting..."];
    [self updateMarketplaceButtons];

    [self.downloadManager downloadURL:m.url
                        expectedBytes:m.sizeBytes
                       expectedSHA256:nil
                             partPath:partPath
                             destPath:destPath
                                label:m.name
                             progress:^(uint64_t dl, uint64_t total) {
        double pct = total > 0 ? ((double)dl / (double)total) * 100.0 : 0.0;
        [self.modelProgress setDoubleValue:pct];
        [self.modelProgressLabel setStringValue:[NSString stringWithFormat:@"%@ / %@ (%.0f%%)",
                                                 [ModelCatalog formatBytes:dl],
                                                 total > 0 ? [ModelCatalog formatBytes:total] : @"?", pct]];
        if (self.onStateUpdated) self.onStateUpdated();
    } completion:^(BOOL success, NSString *errMsg) {
        [self.modelProgress setHidden:YES];
        [self.modelProgressLabel setStringValue:success ? @"Download complete!" : (errMsg ?: @"Failed")];
        if (!success && errMsg && [errMsg rangeOfString:@"cancelled"].location == NSNotFound) {
            NSAlert *alert = [NSAlert alertWithMessageText:@"Model Download Failed"
                                             defaultButton:@"OK"
                                           alternateButton:nil
                                               otherButton:nil
                                 informativeTextWithFormat:@"%@", errMsg];
            [alert runModal];
        } else if (success && self.serverController.isRunning) {
            [self.serverController restartServerWithHardwareRAMGB:self.hardware.installedRAMGB
                                                    logicalCPUs:self.hardware.logicalCPUCount
                                                     completion:nil];
        }
        [self refreshAllViews];
        if (self.onStateUpdated) self.onStateUpdated();
    }];
}

- (IBAction)downloadModelClicked:(id)sender {
    (void)sender;
    MavModelEntry *m = [self selectedModel];
    if (!m) return;
    [self startModelDownloadForEntry:m];
}

- (IBAction)cancelDownloadClicked:(id)sender {
    (void)sender;
    [self.downloadManager cancelAndDeletePart:NO];
    [self.modelProgressLabel setStringValue:@"Paused (can resume later)"];
    [self refreshMarketplaceTable];
    if (self.onStateUpdated) self.onStateUpdated();
}

- (IBAction)deleteModelClicked:(id)sender {
    (void)sender;
    MavModelEntry *m = [self selectedModel];
    if (!m) return;
    NSAlert *confirm = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Delete %@?", m.filename]
                                       defaultButton:@"Delete"
                                     alternateButton:@"Cancel"
                                         otherButton:nil
                           informativeTextWithFormat:@"This removes the model file from disk to free up %@.", [ModelCatalog formatBytes:m.sizeBytes]];
    if ([confirm runModal] == NSAlertDefaultReturn) {
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:[self.serverController.modelsDirectory stringByAppendingPathComponent:m.filename] error:nil];
        [fm removeItemAtPath:[[EngineManager defaultDownloadsDirectory] stringByAppendingPathComponent:[m.filename stringByAppendingString:@".part"]] error:nil];
        if (self.serverController.isRunning) {
            [self.serverController restartServerWithHardwareRAMGB:self.hardware.installedRAMGB
                                                    logicalCPUs:self.hardware.logicalCPUCount
                                                     completion:nil];
        }
        [self refreshAllViews];
        if (self.onStateUpdated) self.onStateUpdated();
    }
}

- (IBAction)importLocalGGUFClicked:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowedFileTypes:@[@"gguf"]];
    [panel setMessage:@"Choose a .gguf model file to import into MavLlama:"];
    if ([panel runModal] == NSFileHandlingPanelOKButton) {
        NSString *src = [[panel URL] path];
        NSString *dest = [self.serverController.modelsDirectory stringByAppendingPathComponent:[src lastPathComponent]];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:dest error:nil];
        NSError *err = nil;
        if (![fm createSymbolicLinkAtPath:dest withDestinationPath:src error:&err]) {
            [fm copyItemAtPath:src toPath:dest error:&err];
        }
        if (self.serverController.isRunning) {
            [self.serverController restartServerWithHardwareRAMGB:self.hardware.installedRAMGB
                                                    logicalCPUs:self.hardware.logicalCPUCount
                                                     completion:nil];
        }
        [self refreshAllViews];
        if (self.onStateUpdated) self.onStateUpdated();
    }
}

- (IBAction)customURLClicked:(id)sender {
    (void)sender;
    NSAlert *alert = [NSAlert alertWithMessageText:@"Download Custom GGUF URL"
                                     defaultButton:@"Download"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@"Paste a direct HuggingFace or HTTP/HTTPS .gguf download URL:"];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 420, 24)];
    [input setStringValue:@"https://"];
    [alert setAccessoryView:input];
    if ([alert runModal] == NSAlertDefaultReturn) {
        NSString *urlStr = [[input stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSURL *u = [NSURL URLWithString:urlStr];
        NSString *fname = [u lastPathComponent];
        if (!u || fname.length == 0 || ![fname hasSuffix:@".gguf"]) {
            fname = @"custom-model.gguf";
        }
        MavModelEntry *custom = [[MavModelEntry alloc] init];
        custom.name = [fname stringByDeletingPathExtension];
        custom.filename = fname;
        custom.url = urlStr;
        custom.sizeBytes = 0;
        [self startModelDownloadForEntry:custom];
    }
}

- (IBAction)chooseModelsDirClicked:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setCanCreateDirectories:YES];
    if ([panel runModal] == NSFileHandlingPanelOKButton) {
        self.serverController.modelsDirectory = [[panel URL] path];
        [self refreshAllViews];
    }
}

- (IBAction)resetModelsDirClicked:(id)sender {
    (void)sender;
    self.serverController.modelsDirectory = nil;
    [self refreshAllViews];
}

- (IBAction)saveSettingsClicked:(id)sender {
    (void)sender;
    self.serverController.allowLAN = ([self.allowLANCheck state] == NSOnState);
    NSInteger portVal = [self.portField integerValue];
    if (portVal > 0 && portVal <= 65535) {
        self.serverController.port = portVal;
    }
    NSString *tTitle = [self.threadsPopup titleOfSelectedItem];
    self.serverController.threads = [tTitle isEqualToString:@"Auto"] ? 0 : [tTitle integerValue];

    NSString *cTitle = [self.ctxPopup titleOfSelectedItem];
    self.serverController.ctxSize = [cTitle hasPrefix:@"Auto"] ? 0 : [cTitle integerValue];

    self.serverController.autoStart = ([self.autoStartCheck state] == NSOnState);

    if (self.serverController.isRunning) {
        [self.serverController restartServerWithHardwareRAMGB:self.hardware.installedRAMGB
                                                logicalCPUs:self.hardware.logicalCPUCount
                                                 completion:^(BOOL ok, NSString *err) {
            (void)ok;
            (void)err;
            [self refreshAllViews];
            if (self.onStateUpdated) self.onStateUpdated();
        }];
    } else {
        [self refreshAllViews];
        if (self.onStateUpdated) self.onStateUpdated();
    }
}

- (IBAction)openModelsFolderClicked:(id)sender {
    (void)sender;
    [[NSWorkspace sharedWorkspace] openFile:self.serverController.modelsDirectory];
}

- (IBAction)openServerLogClicked:(id)sender {
    (void)sender;
    NSString *logPath = [ServerController logFilePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
        [[NSFileManager defaultManager] createFileAtPath:logPath contents:[NSData data] attributes:nil];
    }
    [[NSWorkspace sharedWorkspace] openFile:logPath withApplication:@"Console"];
}

- (IBAction)launchChatbotClicked:(id)sender {
    (void)sender;
    if (self.onLaunchChatbotRequested) {
        self.onLaunchChatbotRequested();
    }
}

#pragma mark - Updates Tab & WebView

- (void)loadPlaceholderReleaseNotes {
    NSString *ver = [self.updateManager currentAppVersion];
    NSString *placeholderMD = [NSString stringWithFormat:
                               @"# MavLlama v%@\n\nClick **Check Again** to fetch GitHub release notes (supports tables, badges, images/GIFs, and embedded MP4 demos).",
                               ver];
    NSString *html = [MarkdownRenderer renderHTMLFromMarkdown:placeholderMD
                                                 releaseTitle:ver
                                                   releaseTag:ver
                                                resolvedMedia:@{}];
    [[self.releaseWebView mainFrame] loadHTMLString:html baseURL:nil];
}

- (void)checkForUpdatesForce:(BOOL)force {
    if (self.isCheckingReleases) return;
    self.isCheckingReleases = YES;
    [self.checkUpdatesBtn setEnabled:NO];
    [self.updatesStatusLabel setStringValue:[NSString stringWithFormat:@"Installed: v%@ \u2014 Checking GitHub Releases...",
                                             [self.updateManager currentAppVersion]]];

    [self.updateManager checkForUpdatesForceRefresh:force
                                         completion:^(NSArray *releases,
                                                      MavReleaseInfo *latestStable,
                                                      BOOL updateAvailable,
                                                      NSError *error) {
        self.isCheckingReleases = NO;
        [self.checkUpdatesBtn setEnabled:YES];

        if (error || !releases) {
            [self.updatesStatusLabel setStringValue:[NSString stringWithFormat:@"Installed: v%@ \u2014 Release check failed (%@)",
                                                     [self.updateManager currentAppVersion],
                                                     [error localizedDescription] ?: @"network error"]];
            [self refreshUpdatesControls];
            return;
        }

        self.hasLoadedReleases = YES;
        self.releases = releases;
        self.latestStableRelease = latestStable;

        if (self.onUpdateCheckCompleted) {
            self.onUpdateCheckCompleted(latestStable, updateAvailable);
        }

        [self.releasePopup removeAllItems];
        NSInteger selectIdx = 0;
        for (NSUInteger i = 0; i < releases.count; i++) {
            MavReleaseInfo *r = releases[i];
            NSString *tagSuffix = @"";
            if (r == latestStable) {
                tagSuffix = @" (Latest)";
            } else if (r.prerelease) {
                tagSuffix = @" (Pre-release)";
            }
            NSString *title = [NSString stringWithFormat:@"%@ \u2014 %@%@", r.tagName, r.name, tagSuffix];
            [self.releasePopup addItemWithTitle:title];
            if (r == latestStable) {
                selectIdx = (NSInteger)i;
            }
        }
        if (releases.count == 0) {
            [self.releasePopup addItemWithTitle:@"No published GitHub releases yet"];
            self.selectedRelease = nil;
        } else {
            [self.releasePopup selectItemAtIndex:selectIdx];
            self.selectedRelease = releases[(NSUInteger)selectIdx];
        }

        NSString *inst = [self.updateManager currentAppVersion];
        if (updateAvailable && latestStable) {
            [self.updatesStatusLabel setStringValue:[NSString stringWithFormat:@"Installed: v%@ \u2022 Update Available: %@!",
                                                     inst, latestStable.tagName]];
        } else if (latestStable) {
            [self.updatesStatusLabel setStringValue:[NSString stringWithFormat:@"Installed: v%@ \u2022 Latest: %@ (Up to Date)",
                                                     inst, latestStable.tagName]];
        } else {
            [self.updatesStatusLabel setStringValue:[NSString stringWithFormat:@"Installed: v%@ \u2022 Loaded %lu release(s)",
                                                     inst, (unsigned long)releases.count]];
        }

        [self renderSelectedReleaseNotes];
        [self refreshUpdatesControls];
    }];
}

- (void)renderSelectedReleaseNotes {
    MavReleaseInfo *rel = self.selectedRelease;
    if (!rel) {
        [self loadPlaceholderReleaseNotes];
        return;
    }
    [self.updateManager renderRelease:rel
                          initialHTML:^(NSString *html, NSURL *baseURL) {
        [[self.releaseWebView mainFrame] loadHTMLString:html baseURL:baseURL];
    } updatedHTML:^(NSString *html, NSURL *baseURL) {
        if (self.selectedRelease == rel) {
            [[self.releaseWebView mainFrame] loadHTMLString:html baseURL:baseURL];
        }
    }];
}

- (void)dealloc {
    [_releaseWebView setPolicyDelegate:nil];
}

- (void)refreshUpdatesControls {
    MavReleaseInfo *sel = self.selectedRelease;
    BOOL dlActive = self.downloadManager.isDownloading || self.updateManager.isInstalling;

    [self.viewOnGitHubBtn setEnabled:(sel != nil && sel.htmlURL.length > 0)];
    [self.checkUpdatesBtn setEnabled:!self.isCheckingReleases];

    if (!sel) {
        [self.installUpdateBtn setTitle:self.isCheckingReleases ? @"Checking Releases..." : @"No Release Selected"];
        [self.installUpdateBtn setEnabled:NO];
        return;
    }
    if (!sel.appZipDownloadURL || sel.appZipDownloadURL.length == 0) {
        [self.installUpdateBtn setTitle:@"No App Bundle in This Release"];
        [self.installUpdateBtn setEnabled:NO];
        return;
    }

    NSComparisonResult cmp = [UpdateManager compareVersion:sel.tagName toVersion:[self.updateManager currentAppVersion]];
    if (cmp == NSOrderedSame) {
        [self.installUpdateBtn setTitle:[NSString stringWithFormat:@"Up to Date (%@)", sel.tagName]];
        [self.installUpdateBtn setEnabled:NO];
    } else if (sel.prerelease) {
        [self.installUpdateBtn setTitle:[NSString stringWithFormat:@"Install Pre-release %@ & Relaunch", sel.tagName]];
        [self.installUpdateBtn setEnabled:!dlActive];
    } else if (cmp == NSOrderedDescending) {
        [self.installUpdateBtn setTitle:[NSString stringWithFormat:@"Update to %@ & Relaunch", sel.tagName]];
        [self.installUpdateBtn setEnabled:!dlActive];
    } else {
        [self.installUpdateBtn setTitle:[NSString stringWithFormat:@"Downgrade to %@ & Relaunch", sel.tagName]];
        [self.installUpdateBtn setEnabled:!dlActive];
    }
}

- (IBAction)checkUpdatesClicked:(id)sender {
    (void)sender;
    [self checkForUpdatesForce:YES];
}

- (IBAction)releaseSelectionChanged:(id)sender {
    (void)sender;
    NSInteger idx = [self.releasePopup indexOfSelectedItem];
    if (idx >= 0 && idx < (NSInteger)self.releases.count) {
        self.selectedRelease = self.releases[(NSUInteger)idx];
    } else {
        self.selectedRelease = nil;
    }
    [self renderSelectedReleaseNotes];
    [self refreshUpdatesControls];
}

- (IBAction)viewReleaseOnGitHubClicked:(id)sender {
    (void)sender;
    if (self.selectedRelease && self.selectedRelease.htmlURL.length > 0) {
        NSURL *u = [NSURL URLWithString:self.selectedRelease.htmlURL];
        if (u) [[NSWorkspace sharedWorkspace] openURL:u];
    }
}

- (IBAction)installUpdateClicked:(id)sender {
    (void)sender;
    MavReleaseInfo *rel = self.selectedRelease;
    if (!rel) return;

    NSComparisonResult cmp = [UpdateManager compareVersion:rel.tagName toVersion:[self.updateManager currentAppVersion]];
    if (rel.prerelease || cmp == NSOrderedAscending) {
        NSString *kind = rel.prerelease ? @"pre-release" : @"older version";
        NSAlert *confirm = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Install %@ (%@)?", rel.tagName, kind]
                                           defaultButton:@"Install & Relaunch"
                                         alternateButton:@"Cancel"
                                             otherButton:nil
                               informativeTextWithFormat:@"You are currently running v%@ and selected %@ (%@). Replace MavLlama.app and relaunch?",
                            [self.updateManager currentAppVersion], rel.tagName, kind];
        if ([confirm runModal] != NSAlertDefaultReturn) {
            return;
        }
    }

    [self.updateProgress setHidden:NO];
    [self.updateProgress setDoubleValue:0.0];
    [self.updateProgressLabel setStringValue:@"Downloading..."];
    [self.installUpdateBtn setEnabled:NO];

    [self.updateManager installRelease:rel
                       downloadManager:self.downloadManager
                      serverController:self.serverController
                              progress:^(uint64_t dl, uint64_t total) {
        double pct = total > 0 ? ((double)dl / (double)total) * 100.0 : 0.0;
        [self.updateProgress setDoubleValue:pct];
        [self.updateProgressLabel setStringValue:[NSString stringWithFormat:@"%@ / %@",
                                                  [ModelCatalog formatBytes:dl],
                                                  total > 0 ? [ModelCatalog formatBytes:total] : @"?"]];
        if (self.onStateUpdated) self.onStateUpdated();
    } completion:^(BOOL launchedUpdater, NSString *errorMessage) {
        [self.updateProgress setHidden:YES];
        if (!launchedUpdater) {
            [self.updateProgressLabel setStringValue:errorMessage ?: @"Update failed"];
            NSAlert *errAlert = [NSAlert alertWithMessageText:@"Update Failed"
                                                defaultButton:@"OK"
                                              alternateButton:nil
                                                  otherButton:nil
                                    informativeTextWithFormat:@"%@", errorMessage ?: @"Unknown error."];
            [errAlert runModal];
        } else {
            [self.updateProgressLabel setStringValue:@"Restarting MavLlama..."];
        }
        [self refreshAllViews];
        if (self.onStateUpdated) self.onStateUpdated();
    }];
}

- (void)webView:(WebView *)webView
decidePolicyForNavigationAction:(NSDictionary *)actionInformation
        request:(NSURLRequest *)request
          frame:(WebFrame *)frame
decisionListener:(id<WebPolicyDecisionListener>)listener {
    (void)webView;
    (void)frame;
    NSInteger navType = [actionInformation[WebActionNavigationTypeKey] integerValue];
    NSURL *url = [request URL];
    NSString *scheme = [[url scheme] lowercaseString];
    if (navType == WebNavigationTypeLinkClicked &&
        ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"mailto"])) {
        [[NSWorkspace sharedWorkspace] openURL:url];
        [listener ignore];
        return;
    }
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"mailto"]) {
        [listener ignore];
        return;
    }
    [listener use];
}

- (void)webView:(WebView *)webView
decidePolicyForNewWindowAction:(NSDictionary *)actionInformation
        request:(NSURLRequest *)request
   newFrameName:(NSString *)frameName
decisionListener:(id<WebPolicyDecisionListener>)listener {
    (void)webView;
    (void)actionInformation;
    (void)frameName;
    NSURL *url = [request URL];
    NSString *scheme = [[url scheme] lowercaseString];
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"mailto"]) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
    [listener ignore];
}

#pragma mark - About Social Links

- (IBAction)openSocialYouTube:(id)sender {
    (void)sender;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.youtube.com/@bukancaitlyn"]];
}

- (IBAction)openSocialTwitter:(id)sender {
    (void)sender;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://x.com/Y2Karyl"]];
}

- (IBAction)openSocialGitHub:(id)sender {
    (void)sender;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/momochisoundpost"]];
}

- (IBAction)openSocialInstagram:(id)sender {
    (void)sender;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.instagram.com/bukancaitlyn/"]];
}

@end
