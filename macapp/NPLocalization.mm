// 界面语言表：英文原文 → 简体中文
// 译文对照 Notepad4 英文资源与 Windows 中文编辑器习惯用语
#import "NPLocalization.h"

static NSString *const NPLanguageKey = @"NPLanguage";
static BOOL sLangOverride = NO;
static NPLanguage sLangOverrideValue = NPLanguageChinese;

// 菜单/对话框/状态栏文案
static NSDictionary<NSString *, NSString *> *NPLTable(void) {
	static NSDictionary *table;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		table = @{
			// ===== 菜单栏 =====
			@"File": @"文件", @"Edit": @"编辑", @"Search": @"搜索", @"View": @"视图",
			@"Scheme": @"方案", @"Settings": @"设置", @"Tools": @"工具", @"Help": @"帮助",

			// ===== 应用菜单 =====
			@"About Notepad4": @"关于 Notepad4",
			@"Hide Notepad4": @"隐藏 Notepad4",
			@"Hide Others": @"隐藏其他",
			@"Show All": @"全部显示",
			@"Quit Notepad4": @"退出 Notepad4",

			// ===== 文件 =====
			@"New": @"新建",
			@"New Window": @"新建窗口",
			@"Open...": @"打开...",
			@"Save": @"保存",
			@"Save As...": @"另存为...",
			@"Save Backup": @"保存备份",
			@"Save Copy...": @"保存副本...",
			@"File Mode": @"文件模式",
			@"Read Only File": @"只读文件",
			@"Read Only Mode": @"只读模式",
			@"Revert": @"还原",
			@"Reload": @"重新载入",
			@"As UTF-8": @"按 UTF-8",
			@"As ANSI": @"按 ANSI",
			@"As GBK": @"按 GBK",
			@"With Encoding...": @"指定编码...",
			@"Encoding": @"编码",
			@"UTF-8 BOM": @"UTF-8 BOM",
			@"UTF-16LE BOM": @"UTF-16LE BOM",
			@"UTF-16BE BOM": @"UTF-16BE BOM",
			@"Line Endings": @"换行符",
			@"Windows (CR+LF)": @"Windows (CR+LF)",
			@"Unix/macOS (LF)": @"Unix/macOS (LF)",
			@"Page Setup...": @"页面设置...",
			@"Print...": @"打印...",
			@"Properties...": @"属性...",
			@"Open Containing Folder": @"打开所在文件夹",
			@"Recent (History)...": @"最近文件...",
			@"Exit": @"退出",

			// ===== 编辑 =====
			@"Undo": @"撤销",
			@"Redo": @"重做",
			@"Cut": @"剪切",
			@"Copy": @"复制",
			@"Paste": @"粘贴",
			@"Delete": @"删除",
			@"Select All": @"全选",
			@"Swap": @"交换",
			@"Clear Document": @"清空文档",
			@"Clear Clipboard": @"清空剪贴板",
			@"Copy to Clipboard": @"复制到剪贴板",
			@"File Name": @"文件名",
			@"Full Path Name": @"完整路径",
			@"Copy All": @"复制全部",
			@"Copy as RTF": @"复制为 RTF",
			@"Selection": @"选择",
			@"Duplicate": @"创建副本",
			@"Toggle Line Comment": @"切换行注释",
			@"Indent": @"增加缩进",
			@"Unindent": @"减少缩进",
			@"Strip Trailing Blanks": @"删除行尾空白",
			@"Remove Blank Lines": @"删除空行",
			@"Lines": @"行",
			@"Move Up": @"上移",
			@"Move Down": @"下移",
			@"Transpose": @"对调字符",
			@"Duplicate Line": @"复制行",
			@"Cut Line": @"剪切行",
			@"Copy Line": @"复制行",
			@"Delete Line": @"删除行",
			@"Join Lines": @"合并行",
			@"Split Lines": @"拆分行",
			@"Convert": @"转换",
			@"UPPER CASE": @"转为大写",
			@"lower case": @"转为小写",
			@"Invert Case": @"反转大小写",
			@"Title Case": @"词首大写",
			@"Tabify Selection (Indent)": @"空格转制表符（缩进）",
			@"Untabify Selection (Indent)": @"制表符转空格（缩进）",
			@"Insert": @"插入",
			@"Complete Word": @"单词补全",
			@"New GUID": @"新建 GUID",
			@"Current Date Time": @"当前日期时间",
			@"Unix Timestamp": @"Unix 时间戳",

			// ===== 搜索 =====
			@"Find...": @"查找...",
			@"Save Find Text": @"保存查找内容",
			@"Find Next": @"查找下一个",
			@"Find Previous": @"查找上一个",
			@"Replace...": @"替换...",
			@"Replace Next": @"替换下一个",
			@"Find Matching Brace": @"匹配括号",
			@"Select Word": @"选择单词",
			@"Bookmarks": @"书签",
			@"Toggle": @"切换书签",
			@"Goto Next": @"下一个书签",
			@"Goto Previous": @"上一个书签",
			@"Clear All": @"清除所有书签",
			@"Goto": @"转到",
			@"Goto Line...": @"转到行...",

			// ===== 视图 =====
			@"Word Wrap": @"自动换行",
			@"Long Line Marker": @"长行标记",
			@"Indentation Guides": @"缩进参考线",
			@"Show Whitespace": @"显示空白字符",
			@"Show Line Endings": @"显示行尾符",
			@"Visual Brace Matching": @"括号匹配高亮",
			@"Line Numbers": @"行号",
			@"Bookmark Margin": @"书签边距",
			@"Show Code Folding": @"代码折叠",
			@"Zoom": @"缩放",
			@"Zoom In": @"放大",
			@"Zoom Out": @"缩小",
			@"Reset Zoom": @"重置缩放",
			@"Toggle Full Screen": @"全屏",

			// ===== 方案 =====
			@"Syntax Scheme...": @"语法方案...",
			@"Use Default Code Style": @"使用默认代码样式",
			@"Customize Schemes": @"自定义方案",
			@"Toggle Folds": @"折叠/展开",
			@"Style Theme": @"界面主题",
			@"Follow System": @"跟随系统",
			@"Light": @"浅色",
			@"Dark": @"深色",

			// ===== 设置 =====
			@"Insert Tabs as Spaces": @"用空格代替制表符",
			@"Tab Settings...": @"制表符设置...",
			@"Auto Completion Settings...": @"自动补全设置...",
			@"Appearance": @"外观",
			@"Show Menu": @"显示菜单栏",
			@"Show Toolbar": @"显示工具栏",
			@"Show Statusbar": @"显示状态栏",
			@"Save Settings On Exit": @"退出时保存设置",
			@"Save Settings Now": @"立即保存设置",
			@"Language": @"语言",

			// ===== 工具 =====
			@"Execute Document": @"运行文档",
			@"Open Document With...": @"用其他程序打开...",
			@"Run Command...": @"运行命令...",
			@"Action on Selection": @"对选区操作",
			@"Open File, Folder, Link, etc.": @"打开文件、文件夹、链接等",
			@"Search with &Google": @"用 Google 搜索",
			@"Standard Encode": @"标准编码",
			@"URL Safe Encode": @"URL 安全编码",
			@"Decode": @"解码",
			@"Web Tools": @"网页工具",
			@"URL Encode": @"URL 编码",
			@"URL Decode": @"URL 解码",
			@"Escape HTML/XML Chars": @"转义 HTML/XML 字符",
			@"Unescape HTML/XML Chars": @"反转义 HTML/XML 字符",
			@"Project Home": @"项目主页",

			// ===== 状态栏 =====
			@"Ln %@ / %@": @"行 %@ / %@",
			@"Col %@ / %@": @"列 %@ / %@",
			@"Ch %@ / %@": @"字符 %@ / %@",
			@"Sel %@ / %@": @"选择 %@ / %@",
			@"SelLn %@": @"选择行 %@",
			@"Fnd 0": @"查找 0",
			@"Text File": @"文本文件",
			@"INS": @"插入",
			@"OVR": @"覆盖",

			// ===== 查找/替换面板 =====
			@"Find": @"查找",
			@"Replace With": @"替换为",
			@"Replace": @"替换",
			@"Replace All": @"全部替换",
			@"Match Case": @"区分大小写",
			@"Whole Word": @"全字匹配",
			@"Regex": @"正则",
			@"Previous": @"上一个",
			@"Next": @"下一个",
			@"Replaced %ld occurrences": @"已替换 %ld 处",
			@"No matches found": @"未找到匹配",

			// ===== 文档/窗口 =====
			@"Reload with Encoding": @"指定编码重新载入",
			@"Reload": @"重新载入",
			@"Cancel": @"取消",
			@"OK": @"确定",
			@"Save changes?": @"是否保存更改？",
			@"The document has unsaved changes.": @"文档有未保存的更改。",
			@"Save": @"保存",
			@"Don't Save": @"不保存",
			@"Goto Line": @"转到行",
			@"Tab Settings": @"制表符设置",
			@"Tab Width": @"制表符宽度",
			@"Indent Width": @"缩进宽度",
			@"Use Tabs": @"使用制表符",
			@"Auto Completion Settings": @"自动补全设置",
			@"Auto complete on typing": @"输入时自动补全",
			@"Settings saved": @"设置已保存",
			@"Save the file first": @"请先保存文件",
			@"Run Command": @"运行命令",
			@"Command exited with status %d": @"命令退出状态 %d",
			@"Reload with Encoding...": @"指定编码重新载入...",
			@"Services": @"服务",
			@"Add to Favorites": @"添加到收藏夹",
			@"No favorites": @"（无收藏）",
			@"No recent files": @"（无最近文件）",
			@"Properties": @"属性",
			@"Failed to save backup": @"保存备份失败",
			@"Untitled": @"无标题",
			@" - Notepad4": @" - Notepad4",
			@" — Modified": @" — 已修改",
			@"Cannot decode file content": @"无法解码文件内容",
			@"Failed to write with current encoding": @"按当前编码写出失败",
		};
	});
	return table;
}

NPLanguage NPLanguageGet(void) {
	if (sLangOverride) return sLangOverrideValue;
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if ([d objectForKey:NPLanguageKey] == nil) return NPLanguageChinese;
	const NSInteger v = [d integerForKey:NPLanguageKey];
	return (v == NPLanguageEnglish) ? NPLanguageEnglish : NPLanguageChinese;
}

void NPLanguageSet(NPLanguage lang) {
	[[NSUserDefaults standardUserDefaults] setInteger:lang forKey:NPLanguageKey];
}

void NPLanguageOverrideForTesting(NPLanguage lang) {
	sLangOverride = YES;
	sLangOverrideValue = lang;
}

NSString *NPL(NSString *english) {
	if (english.length == 0) return english;
	if (NPLanguageGet() == NPLanguageEnglish) return english;
	NSDictionary *table = NPLTable();
	NSString *hit = table[english];
	if (hit) return hit;
	// 菜单项形如 "New\tCtrl+N"：只查标题部分，加速键原样保留
	const NSRange tab = [english rangeOfString:@"\t"];
	if (tab.location != NSNotFound) {
		NSString *base = [english substringToIndex:tab.location];
		NSString *suffix = [english substringFromIndex:tab.location];
		NSString *baseZh = table[base];
		if (baseZh) return [baseZh stringByAppendingString:suffix];
	}
	return english;
}
