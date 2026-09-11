// 主窗口控制器（多标签，复刻 Windows 版 Notepad4 布局）
#import <Cocoa/Cocoa.h>
#import "EditorDocument.h"

@interface MainWindowController : NSWindowController <NSWindowDelegate, NSMenuDelegate, NSSplitViewDelegate>

@property (nonatomic, strong) EditorDocument *editorDocument;

- (void)refreshStatus;
- (void)updateWindowTitle;

- (BOOL)handleKeyEquivalent:(NSEvent *)event;
- (void)languageChinese;
- (void)languageEnglish;
- (void)languageSystem;
- (void)languagePicked:(NSMenuItem *)sender;
- (NSArray<NSString *> *)inWindowMenuTitles;
- (void)dumpInWindowMenus:(NSMutableString *)out;
- (NSArray *)menuLeafCatalog;
- (NSInteger)inWindowFlyoutCount;
- (BOOL)clickInWindowMenuPath:(NSArray<NSString *> *)names;
- (void)openInWindowMenuAtIndex:(NSInteger)index;
- (void)closeInWindowMenu;
- (CGFloat)inWindowDropDownHeight;
- (NSRect)inWindowDropDownFrame;
- (NSRect)inWindowLastPanelFrame;
- (CGFloat)inWindowLastPanelContentHeight;
- (NSInteger)inWindowCheckedRowCount;
- (NSArray<NSString *> *)inWindowLastPanelRowNames;
- (NSRect)inWindowRowFrameNamed:(NSString *)name;
- (BOOL)scrollInWindowLastPanelToName:(NSString *)name;
- (BOOL)inWindowDropDownHasScroller;
- (NSString *)documentPropertiesText;
- (void)syncMenuItemStates;
- (void)viewBraceMatch;
- (void)viewCodeFolding;
- (void)foldToggleCurrent;
- (void)foldAll;
- (void)unfoldAll;
- (void)tbOpenMenu;
- (void)tbFoldMenu;
- (NSInteger)tabCount;
- (BOOL)hasTabNewButton;
- (void)fileCloseTab;
- (void)fileNew;
- (void)fileNewWindow;
- (void)openURLInTab:(NSURL *)url;
- (NSString *)projectHomeURL;
- (BOOL)currentTabIsReusable;
- (BOOL)windowIsUsable;
- (void)presentWindow;
- (void)viewPreview;
- (BOOL)previewOn;
- (NSString *)previewHTML;
- (NSString *)previewLastPageHTML;
- (BOOL)previewLastRefreshInPlace;
- (BOOL)previewLastRefreshDidScroll;
- (BOOL)previewUsesLineMap;
- (BOOL)previewScrollLinked;
- (NSInteger)previewLastSyncLine;
- (CGFloat)previewLastSyncFrac;
- (NSInteger)editorFirstVisibleLine;
- (BOOL)setEditorFirstVisibleLine:(NSInteger)line;
- (void)syncPreviewToEditor;
- (void)applyPreviewScrollLine:(NSInteger)line fraction:(CGFloat)frac;
- (NSInteger)lastAppliedEditorLineFromPreview;
- (void)refreshPreviewNow;
- (CGFloat)previewDividerThickness;
- (CGFloat)previewSplitPosition;
- (CGFloat)previewPaneWidth;
- (BOOL)setPreviewSplitPosition:(CGFloat)pos;
- (NSButton *)previewStatusButton;
+ (NSArray *)liveControllers;
+ (NSInteger)liveControllerCount;
@end
