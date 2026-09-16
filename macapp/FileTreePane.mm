#import "FileTreePane.h"
#import "NPLocalization.h"

@interface NPFileNode : NSObject
@property (nonatomic, strong) NSURL *url;
@property (nonatomic) BOOL isDir;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray<NPFileNode *> *children;
@end
@implementation NPFileNode
@end

@interface FileTreePane () <NSOutlineViewDataSource, NSOutlineViewDelegate>
@end

@implementation FileTreePane {
	NSOutlineView *_outline;
	NSScrollView *_scroll;
	NSTextField *_hint;
	NPFileNode *_root;
	NSURL *_rootURL;
}

- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.wantsLayer = YES;
		self.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
		_hint = [NSTextField labelWithString:NPL(@"Open a file to show its folder.")];
		_hint.font = [NSFont systemFontOfSize:11];
		_hint.textColor = [NSColor secondaryLabelColor];
		_hint.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:_hint];
		[self.leadingAnchor constraintEqualToAnchor:_hint.leadingAnchor constant:-8].active = YES;
		[self.trailingAnchor constraintEqualToAnchor:_hint.trailingAnchor constant:8].active = YES;
		[self.topAnchor constraintEqualToAnchor:_hint.topAnchor constant:-6].active = YES;

		_outline = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
		_outline.headerView = nil;
		_outline.rowHeight = 20;
		_outline.indentationPerLevel = 12;
		_outline.allowsEmptySelection = YES;
		_outline.focusRingType = NSFocusRingTypeNone;
		NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
		col.resizingMask = NSTableColumnAutoresizingMask;
		[_outline addTableColumn:col];
		_outline.outlineTableColumn = col;
		_outline.dataSource = self;
		_outline.delegate = self;
		_outline.target = self;
		_outline.action = @selector(rowClicked:);
		_scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
		_scroll.drawsBackground = NO;
		_scroll.hasVerticalScroller = YES;
		_scroll.hasHorizontalScroller = NO;
		_scroll.autohidesScrollers = YES;
		_scroll.documentView = _outline;
		_scroll.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:_scroll];
		[self.leadingAnchor constraintEqualToAnchor:_scroll.leadingAnchor].active = YES;
		[self.trailingAnchor constraintEqualToAnchor:_scroll.trailingAnchor].active = YES;
		[_hint.bottomAnchor constraintEqualToAnchor:_scroll.topAnchor constant:-2].active = YES;
		[self.bottomAnchor constraintEqualToAnchor:_scroll.bottomAnchor].active = YES;
		[self setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
		[self setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	}
	return self;
}

- (NSURL *)rootURL { return _rootURL; }

static BOOL NPSkipName(NSString *name) {
	if (name.length == 0) return YES;
	if ([name hasPrefix:@"."]) return YES;
	if ([name isEqualToString:@"Thumbs.db"]) return YES;
	return NO;
}

- (NPFileNode *)nodeForURL:(NSURL *)url {
	NPFileNode *n = [NPFileNode new];
	n.url = url;
	n.name = url.lastPathComponent ?: @"";
	BOOL dir = NO;
	[[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&dir];
	n.isDir = dir;
	return n;
}

- (void)loadChildren:(NPFileNode *)node {
	if (!node.isDir || node.children) return;
	NSArray *urls = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:node.url
		includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLNameKey]
		options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
	NSMutableArray *dirs = [NSMutableArray array];
	NSMutableArray *files = [NSMutableArray array];
	for (NSURL *u in urls) {
		if (NPSkipName(u.lastPathComponent)) continue;
		NPFileNode *c = [self nodeForURL:u];
		[(c.isDir ? dirs : files) addObject:c];
	}
	NSComparator cmp = ^NSComparisonResult(NPFileNode *a, NPFileNode *b) {
		return [a.name localizedStandardCompare:b.name];
	};
	[dirs sortUsingComparator:cmp];
	[files sortUsingComparator:cmp];
	node.children = [[dirs arrayByAddingObjectsFromArray:files] mutableCopy];
}

- (void)showDirectory:(NSURL *)dir selected:(NSURL *)file {
	if (dir.path.length == 0) {
		_root = nil;
		_rootURL = nil;
		_hint.stringValue = NPL(@"Open a file to show its folder.");
		[_outline reloadData];
		return;
	}
	const BOOL same = [_rootURL.path isEqualToString:dir.path];
	if (!same) {
		_rootURL = dir;
		_root = [self nodeForURL:dir];
		_root.name = dir.lastPathComponent ?: dir.path;
		[self loadChildren:_root];
		_hint.stringValue = _root.name ?: @"";
		[_outline reloadData];
		[_outline expandItem:_root];
	}
	if (file.path.length == 0) return;
	for (NPFileNode *n in _root.children) {
		if ([n.url.path isEqualToString:file.path]) {
			NSInteger row = [_outline rowForItem:n];
			if (row >= 0) [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
			break;
		}
	}
}

- (NSArray<NSString *> *)visibleNames {
	NSMutableArray *out = [NSMutableArray array];
	if (_root.name.length) [out addObject:_root.name];
	for (NPFileNode *n in _root.children)
		if (n.name.length) [out addObject:n.name];
	return out;
}

- (BOOL)selectAndOpenName:(NSString *)name {
	if (name.length == 0) return NO;
	for (NPFileNode *n in _root.children) {
		if ([n.name isEqualToString:name] && !n.isDir) {
			if (self.onOpenFile) self.onOpenFile(n.url);
			return YES;
		}
	}
	return NO;
}

- (void)rowClicked:(id)sender {
	(void)sender;
	id item = [_outline itemAtRow:_outline.clickedRow];
	if (![item isKindOfClass:[NPFileNode class]]) return;
	NPFileNode *n = item;
	if (n.isDir) {
		if ([_outline isItemExpanded:n]) [_outline collapseItem:n];
		else [_outline expandItem:n];
		return;
	}
	if (self.onOpenFile) self.onOpenFile(n.url);
}

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item {
	(void)ov;
	if (item == nil) return _root ? 1 : 0;
	NPFileNode *n = item;
	[self loadChildren:n];
	return (NSInteger)n.children.count;
}
- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(id)item {
	(void)ov;
	if (item == nil) return _root;
	NPFileNode *n = item;
	[self loadChildren:n];
	if (index < 0 || (NSUInteger)index >= n.children.count) return nil;
	return n.children[(NSUInteger)index];
}
- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item {
	(void)ov;
	return [item isKindOfClass:[NPFileNode class]] && [(NPFileNode *)item isDir];
}
- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)col item:(id)item {
	(void)col;
	NSTableCellView *cell = [ov makeViewWithIdentifier:@"np4file" owner:self];
	if (!cell) {
		cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
		cell.identifier = @"np4file";
		NSTextField *tf = [NSTextField labelWithString:@""];
		tf.font = [NSFont systemFontOfSize:12];
		tf.lineBreakMode = NSLineBreakByTruncatingMiddle;
		tf.translatesAutoresizingMaskIntoConstraints = NO;
		cell.textField = tf;
		[cell addSubview:tf];
		[cell.leadingAnchor constraintEqualToAnchor:tf.leadingAnchor constant:-2].active = YES;
		[cell.trailingAnchor constraintEqualToAnchor:tf.trailingAnchor constant:2].active = YES;
		[cell.centerYAnchor constraintEqualToAnchor:tf.centerYAnchor].active = YES;
	}
	cell.textField.stringValue = [item isKindOfClass:[NPFileNode class]] ? [(NPFileNode *)item name] : @"";
	return cell;
}

@end
