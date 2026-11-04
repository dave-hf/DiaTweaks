// More dev tools, for scripts, with the developer tools on. Each writes a file beside the dylib:
//     com.diapatches.dev.classes, object a regex   every Objective-C class whose name matches, with its superclass,
//                                                  methods and ivars, to classes.txt.
//     com.diapatches.dev.mirror, object a class    every visible view of that class, its view controller and what their
//                                                  Swift properties hold, to mirror.txt.
#import "DevTools/DevTools.h"
#include <dlfcn.h>

NSString *DPMirrorDescription(id object, NSInteger maxDepth);

static void DPWriteBesideDylib(NSString *name, NSString *text) {
    Dl_info dylib;
    dladdr((const void *)DPWriteBesideDylib, &dylib);
    [text writeToFile:[@(dylib.dli_fname).stringByDeletingLastPathComponent stringByAppendingPathComponent:name] atomically:YES
             encoding:NSUTF8StringEncoding error:nil];
}

static void DPDescribeMethods(Class cls, NSString *prefix, NSMutableString *out) {
    unsigned count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned i = 0; i < count; i++)
        [out appendFormat:@"  %@%@  %s\n", prefix, NSStringFromSelector(method_getName(methods[i])), method_getTypeEncoding(methods[i]) ?: ""];
    free(methods);
}

static NSString *DPDescribeClasses(NSString *pattern) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSMutableString *out = [NSMutableString new];
    if (!regex) return @"bad pattern\n";
    unsigned count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned i = 0; i < count; i++) {
        // Some generated class names aren't valid UTF-8, and a nil name would make the regex throw and crash Dia.
        NSString *name = [NSString stringWithUTF8String:class_getName(classes[i])];
        if (!name || ![regex firstMatchInString:name options:0 range:NSMakeRange(0, name.length)]) continue;
        Class superclass = class_getSuperclass(classes[i]);
        const char *image = class_getImageName(classes[i]);
        [out appendFormat:@"%@ : %s  (%@)\n", name, superclass ? class_getName(superclass) : "-", image ? @(image).lastPathComponent : @""];
        DPDescribeMethods(object_getClass(classes[i]), @"+", out);
        DPDescribeMethods(classes[i], @"-", out);
        unsigned ivarCount = 0;
        Ivar *ivars = class_copyIvarList(classes[i], &ivarCount);
        for (unsigned j = 0; j < ivarCount; j++) [out appendFormat:@"  ivar %s %s\n", ivar_getName(ivars[j]), ivar_getTypeEncoding(ivars[j]) ?: ""];
        free(ivars);
    }
    free(classes);
    return out;
}

// "Class" or "Class depth". Each view also gets its layer's look, which Mirror can't see.
static NSString *DPMirrorViews(NSString *request) {
    NSArray<NSString *> *parts = [request componentsSeparatedByString:@" "];
    NSString *className = parts.firstObject;
    NSInteger depth = parts.count > 1 ? MAX(1, MIN(parts[1].integerValue, 12)) : 5;
    NSMutableString *out = [NSMutableString new];
    for (NSWindow *window in NSApp.windows) {
        NSView *root = window.contentView.superview;
        NSMutableArray<NSView *> *found = [NSMutableArray new];
        DPFindView(root, ^BOOL(NSView *view) {
            if ([NSStringFromClass(view.class) isEqual:className]) [found addObject:view];
            return NO;
        });
        for (NSView *view in found) {
            CALayer *layer = view.layer;
            [out appendFormat:@"== %@ in window \"%@\" frame=%@ alpha=%g hidden=%d appearance=%@\n", className, window.title,
                              NSStringFromRect(view.frame), view.alphaValue, view.hiddenOrHasHiddenAncestor, view.effectiveAppearance.name];
            for (CALayer *l = layer; l; l = l.sublayers.firstObject) {
                [out appendFormat:@"   layer %@ opacity=%g background=%@ filter=%@\n", l.class, l.opacity,
                                  l.backgroundColor ? [NSColor colorWithCGColor:l.backgroundColor] : @"none", l.compositingFilter ?: @"none"];
                if ([l isKindOfClass:CAGradientLayer.class])
                    for (id color in ((CAGradientLayer *)l).colors) [out appendFormat:@"     stop %@\n", [NSColor colorWithCGColor:(__bridge CGColorRef)color]];
            }
            [out appendFormat:@"%@\n", DPMirrorDescription(view, depth)];
            for (NSResponder *next = view.nextResponder; next; next = next.nextResponder)
                if ([next isKindOfClass:NSViewController.class]) {
                    [out appendFormat:@"-- its view controller\n%@\n", DPMirrorDescription(next, 4)];
                    break;
                }
        }
    }
    return out.length ? out : [NSString stringWithFormat:@"no visible %@\n", className];
}

void DPInstallInspect(void) {
    NSDistributedNotificationCenter *center = NSDistributedNotificationCenter.defaultCenter;
    [center addObserverForName:@"com.diapatches.dev.classes" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        @try { DPWriteBesideDylib(@"classes.txt", DPDescribeClasses([note.object isKindOfClass:NSString.class] ? note.object : @".")); }
        @catch (NSException *e) { DPWriteBesideDylib(@"classes.txt", e.description); }
    }];
    [center addObserverForName:@"com.diapatches.dev.mirror" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        @try { DPWriteBesideDylib(@"mirror.txt", [note.object isKindOfClass:NSString.class] ? DPMirrorViews(note.object) : @"name a view class\n"); }
        @catch (NSException *e) { DPWriteBesideDylib(@"mirror.txt", e.description); }
    }];
}
