#import "Settings/SourceUpdate.h"

static NSTextField *DPOneLine(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

// A row's title keeps its width; the value beside it, like a long path, is what gets cut short, in the middle.
static NSTextField *DPTitle(NSString *text) {
    NSTextField *label = DPOneLine(text, 13, NSFontWeightRegular, NSColor.labelColor);
    [label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

static NSTextField *DPValue(NSString *text) {
    NSTextField *label = DPOneLine(text, 13, NSFontWeightRegular, NSColor.secondaryLabelColor);
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    return label;
}

static NSArray *DPList(id value) { return [value isKindOfClass:NSArray.class] ? value : @[]; }
static NSString *DPText(id value) { return [value isKindOfClass:NSString.class] && [value length] ? value : nil; }
static NSString *DPPlural(NSUInteger n, NSString *one) { return [NSString stringWithFormat:@"%lu %@%@", n, one, n == 1 ? @"" : @"s"]; }

BOOL DPIsSource(NSDictionary *found) { return [found[@"source"] boolValue]; }

// "feat(dylib): add tidy tabs (#129)" → feat, "Add tidy tabs".
static NSString *DPChangeText(NSString *subject, NSString **type) {
    static NSRegularExpression *conventional;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        conventional = [NSRegularExpression regularExpressionWithPattern:@"^([a-z]+)(?:\\([^)]*\\))?!?:\\s*(.+?)(?:\\s*\\(#\\d+\\))?$" options:0 error:nil];
    });
    NSTextCheckingResult *match = [conventional firstMatchInString:subject options:0 range:NSMakeRange(0, subject.length)];
    *type = match ? [subject substringWithRange:[match rangeAtIndex:1]] : @"";
    NSString *text = match ? [subject substringWithRange:[match rangeAtIndex:2]] : subject;
    return text.length ? [[text substringToIndex:1].uppercaseString stringByAppendingString:[text substringFromIndex:1]] : subject;
}

// One row per kind of change: New, Fixes, Other.
static NSArray<NSView *> *DPChangeRows(NSArray<NSString *> *subjects, NSString *onlyHeading) {
    NSMutableDictionary<NSString *, NSMutableArray *> *groups = [NSMutableDictionary new];
    for (NSString *subject in subjects) {
        if (![subject isKindOfClass:NSString.class]) continue;
        NSString *type, *text = DPChangeText(subject, &type);
        NSString *group = onlyHeading ?: [type isEqual:@"feat"] ? @"New" : [@[@"fix", @"perf"] containsObject:type] ? @"Fixes" : @"Other";
        [groups[group] ?: (groups[group] = [NSMutableArray new]) addObject:text];
    }
    NSMutableArray<NSView *> *rows = [NSMutableArray new];
    for (NSString *group in onlyHeading ? @[onlyHeading] : @[@"New", @"Fixes", @"Other"]) {
        NSArray<NSString *> *texts = groups[group];
        if (!texts.count) continue;
        NSMutableArray<NSView *> *column = [NSMutableArray arrayWithObject:DPOneLine(group, 11, NSFontWeightSemibold, NSColor.secondaryLabelColor)];
        NSUInteger shown = texts.count > 6 ? 5 : texts.count;
        for (NSUInteger i = 0; i < shown; i++)
            [column addObject:DPOneLine([@"•  " stringByAppendingString:texts[i]], 12, NSFontWeightRegular, NSColor.labelColor)];
        if (shown < texts.count)
            [column addObject:DPOneLine([NSString stringWithFormat:@"and %lu more", texts.count - shown], 12, NSFontWeightRegular, NSColor.secondaryLabelColor)];
        [rows addObject:DPRow(DPColumn(column, 3), [NSView new])];
    }
    return rows;
}

static NSView *DPOpenRow(NSString *title, NSString *value, NSString *symbol, void (^open)(void)) {
    NSStackView *trailing = [NSStackView stackViewWithViews:@[DPSymbol(symbol, 11, NSColor.secondaryLabelColor)]];
    if (value) [trailing insertArrangedSubview:DPValue(value) atIndex:0];
    trailing.spacing = 6;
    return DPLinkRow(DPRow(DPTitle(title), trailing), title, open);
}

NSView *DPSourceGroup(NSDictionary *found, NSString *state, BOOL failed, BOOL installsOnQuit, NSView *trailing, NSTextField **detail) {
    NSArray *changes = DPList(found[@"changes"]), *local = DPList(found[@"local"]);
    NSString *problem = DPText(found[@"problem"]), *upstream = DPText(found[@"upstream"]) ?: @"upstream";
    BOOL staged = [state isEqual:@"staged"];
    NSString *title = staged ? [NSString stringWithFormat:@"DiaTweaks %@", found[@"staged"]]
        : changes.count ? [DPPlural(changes.count, @"new change") stringByAppendingString:@" to DiaTweaks"]
        : local.count ? [DPPlural(local.count, @"change") stringByAppendingString:@" of yours to install"]
        : [NSString stringWithFormat:@"DiaTweaks %@", found[@"latest"]];
    NSString *line = staged ? (installsOnQuit ? @"Installs when you quit" : @"Ready to install")
        : failed && !problem ? @"Update failed"
        : changes.count ? [@"From " stringByAppendingString:upstream] : @"Built from your folder";
    *detail = DPOneLine(line, 11, NSFontWeightRegular, failed && !problem ? NSColor.systemRedColor : NSColor.secondaryLabelColor);
    NSStackView *leading = [NSStackView stackViewWithViews:@[
        DPIconTileOfSize(@"wand.and.stars", NSColor.systemPurpleColor, 30),
        DPColumn(@[DPOneLine(title, 13, NSFontWeightRegular, NSColor.labelColor), *detail], 2),
    ]];
    leading.spacing = 10;

    NSMutableArray<NSView *> *rows = [NSMutableArray arrayWithObject:DPRow(leading, trailing)];
    if (problem && !staged) [rows addObject:DPRow(DPLabel(problem, 12, NSFontWeightRegular, NSColor.systemOrangeColor), [NSView new])];
    if (!staged) {
        [rows addObjectsFromArray:DPChangeRows(changes, nil)];
        [rows addObjectsFromArray:DPChangeRows(local, changes.count ? @"Yours, Not Installed Yet" : @"Yours")];
    }
    NSURL *compare = DPText(found[@"releaseNotes"]) ? [NSURL URLWithString:found[@"releaseNotes"]] : nil;
    if (compare && !staged)
        [rows addObject:DPOpenRow(@"See Changes on GitHub", nil, @"arrow.up.right", ^{ [NSWorkspace.sharedWorkspace openURL:compare]; })];
    return DPGroup(rows);
}

NSArray<NSView *> *DPSourceInstalledRows(NSDictionary *found) {
    NSString *tag = DPText(found[@"installed"]), *branch = DPText(found[@"installedBranch"]);
    NSString *version = !tag ? @"Unknown" : branch ? [NSString stringWithFormat:@"%@ @ %@", branch, tag] : tag;
    if ([found[@"installedDirty"] boolValue]) version = [version stringByAppendingString:@" + uncommitted changes"];
    NSString *path = DPText(found[@"path"]);
    NSMutableArray<NSView *> *rows = [NSMutableArray arrayWithObject:
        DPRow(DPTitle(@"DiaTweaks"), DPValue(version))];
    if (DPText(found[@"upstream"]))
        [rows addObject:DPRow(DPTitle(@"Updates From"), DPValue(found[@"upstream"]))];
    if (path) {
        NSURL *folder = [NSURL fileURLWithPath:path.stringByExpandingTildeInPath];
        [rows addObject:DPOpenRow(@"Folder", path, @"folder", ^{ [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[folder]]; })];
    }
    return rows;
}

NSString *DPSourceAutoText(DPAutoLevel level) {
    return @[@"Only checks when you open this page", @"Checks when Dia opens and lists new changes here",
             @"Merges and builds them, then you choose when to install", @"Merges, builds and installs them when you quit Dia"][level];
}
