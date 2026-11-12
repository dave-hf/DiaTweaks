#import "Source.h"

#pragma mark - Running tools

static NSString *trimmed(NSString *text) {
    return [text ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

// Run from Dia, the PATH is the bare system one; cargo lives where rustup puts it. Git must never wait for a password.
static NSDictionary *toolEnvironment(void) {
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    NSString *cargo = [environment[@"CARGO_HOME"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@".cargo"] stringByAppendingPathComponent:@"bin"];
    environment[@"PATH"] = [NSString stringWithFormat:@"%@:/usr/bin:/bin:/usr/sbin:/sbin:%@", environment[@"PATH"] ?: @"/usr/bin", cargo];
    environment[@"GIT_TERMINAL_PROMPT"] = @"0";
    environment[@"GIT_MERGE_AUTOEDIT"] = @"no";
    return environment;
}

// Output is stdout and stderr together. Gives up after `seconds`, returning -2.
static int runIn(NSString *dir, NSArray<NSString *> *argv, int seconds, NSString **output) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:argv[0]];
    task.arguments = [argv subarrayWithRange:NSMakeRange(1, argv.count - 1)];
    if (dir) task.currentDirectoryURL = [NSURL fileURLWithPath:dir];
    task.environment = toolEnvironment();
    NSPipe *pipe = NSPipe.pipe;
    task.standardOutput = task.standardError = pipe;
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    if (![task launchAndReturnError:NULL]) return -1;
    __block NSData *data;
    dispatch_semaphore_t read = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        data = [pipe.fileHandleForReading readDataToEndOfFile];
        dispatch_semaphore_signal(read);
    });
    BOOL late = dispatch_semaphore_wait(read, dispatch_time(DISPATCH_TIME_NOW, (int64_t)seconds * NSEC_PER_SEC)) != 0;
    if (late) {
        [task terminate];
        dispatch_semaphore_wait(read, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    }
    [task waitUntilExit];
    if (output) *output = late ? @"timed out" : [[NSString alloc] initWithData:data ?: NSData.data encoding:NSUTF8StringEncoding];
    return late ? -2 : task.terminationStatus;
}

// Trimmed output when git succeeds, else nil.
static NSString *git(NSString *repo, NSArray<NSString *> *args, int seconds) {
    NSString *output;
    int status = runIn(repo, [@[ @"/usr/bin/git" ] arrayByAddingObjectsFromArray:args], seconds, &output);
    return status == 0 ? trimmed(output) : nil;
}

static NSArray<NSString *> *lines(NSString *text) {
    return text.length ? [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] : @[];
}

// /usr/bin/git without Apple's developer tools would open their installer instead of running.
static BOOL haveTools(void) { return runIn(nil, @[ @"/usr/bin/xcode-select", @"-p" ], 10, NULL) == 0; }

static NSString *shortPath(NSString *path) { return path.stringByAbbreviatingWithTildeInPath; }

#pragma mark - The checkout

NSDictionary *DPSourceOf(NSString *home) {
    NSDictionary *source = [NSDictionary dictionaryWithContentsOfFile:[home stringByAppendingPathComponent:@"source.plist"]];
    return [source[@"path"] isKindOfClass:NSString.class] ? source : nil;
}

static NSString *upstreamRef(NSDictionary *source) {
    return [NSString stringWithFormat:@"%@/%@", source[@"remote"] ?: @"upstream", source[@"branch"] ?: @"main"];
}

// owner/name and its web address, for a GitHub remote.
static NSString *webOf(NSString *repo, NSString *remote, NSString **name) {
    NSString *url = git(repo, @[ @"remote", @"get-url", remote ], 10);
    for (NSString *prefix in @[ @"git@github.com:", @"ssh://git@github.com/", @"https://github.com/" ]) {
        if (![url hasPrefix:prefix]) continue;
        NSString *path = [url substringFromIndex:prefix.length];
        if ([path hasSuffix:@".git"]) path = [path substringToIndex:path.length - 4];
        if ([path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
        *name = path;
        return [@"https://github.com/" stringByAppendingString:path];
    }
    *name = url.length ? url : remote;
    return nil;
}

// Why the checkout can't be updated as it is, or nil.
static NSString *blocker(NSString *repo) {
    if (!git(repo, @[ @"symbolic-ref", @"-q", @"HEAD" ], 10)) return [NSString stringWithFormat:@"Check out a branch in %@ first", shortPath(repo)];
    NSString *changes = git(repo, @[ @"status", @"--porcelain", @"--untracked-files=no" ], 30);
    if (changes.length) return [NSString stringWithFormat:@"Commit or stash your changes in %@ first", shortPath(repo)];
    return nil;
}

static NSString *problemFile(NSString *home) { return [home stringByAppendingPathComponent:@"source-problem.plist"]; }

#pragma mark - Check

NSDictionary *DPSourceCheck(NSString *home, NSDictionary *installed, NSDictionary *staged) {
    NSDictionary *source = DPSourceOf(home);
    NSString *repo = source[@"path"], *remote = source[@"remote"] ?: @"upstream", *ref = upstreamRef(source), *upstream;
    NSMutableDictionary *result = [@{
        @"source" : @YES, @"path" : shortPath(repo), @"installed" : installed[@"tag"] ?: NSNull.null,
        @"installedBranch" : installed[@"branch"] ?: NSNull.null, @"installedDirty" : @([installed[@"dirty"] boolValue]),
        @"staged" : staged[@"tag"] ?: NSNull.null, @"latest" : NSNull.null, @"available" : @NO, @"size" : @0,
        @"releaseNotes" : NSNull.null, @"error" : NSNull.null, @"problem" : NSNull.null, @"changes" : @[], @"local" : @[],
    } mutableCopy];
    if (![NSFileManager.defaultManager fileExistsAtPath:[repo stringByAppendingPathComponent:@".git"]])
        return result[@"problem"] = [NSString stringWithFormat:@"Can’t find your DiaTweaks folder at %@. Run ./install.sh from where it is now.", shortPath(repo)], result;
    if (!haveTools()) return result[@"problem"] = @"Install Apple’s developer tools: xcode-select --install", result;

    NSString *web = webOf(repo, remote, &upstream);
    result[@"upstream"] = upstream;
    // Offline, what was fetched last still says what's new.
    if (!git(repo, @[ @"fetch", @"--quiet", remote, source[@"branch"] ?: @"main" ], 20))
        result[@"error"] = [NSString stringWithFormat:@"Couldn’t reach %@", upstream];
    NSString *head = git(repo, @[ @"rev-parse", @"HEAD" ], 10), *tip = git(repo, @[ @"rev-parse", @"--verify", @"-q", ref ], 10);
    if (!head || !tip) return result[@"problem"] = [NSString stringWithFormat:@"%@ has no %@ to update from", shortPath(repo), ref], result;

    NSArray *changes = lines(git(repo, @[ @"log", @"--no-merges", @"--format=%s", [NSString stringWithFormat:@"HEAD..%@", tip] ], 20));
    // Commits made in the checkout since it was installed, which Update Now also builds.
    NSString *was = installed[@"commit"];
    NSArray *local = [was isKindOfClass:NSString.class] && git(repo, @[ @"cat-file", @"-e", [was stringByAppendingString:@"^{commit}"] ], 10)
        ? lines(git(repo, @[ @"log", @"--no-merges", @"--format=%s", [NSString stringWithFormat:@"%@..HEAD", was] ], 20)) : @[];
    BOOL newer = ![head isEqual:was] && ![head isEqual:staged[@"commit"]];
    result[@"changes"] = changes;
    result[@"local"] = local;
    result[@"latest"] = [(changes.count ? tip : head) substringToIndex:7];
    result[@"available"] = @((BOOL)(changes.count > 0 || newer));
    result[@"branch"] = git(repo, @[ @"symbolic-ref", @"-q", @"--short", @"HEAD" ], 10) ?: NSNull.null;
    NSString *base = git(repo, @[ @"merge-base", @"HEAD", tip ], 10);
    if (web && changes.count && base) result[@"releaseNotes"] = [NSString stringWithFormat:@"%@/compare/%@...%@", web, base, tip];

    // A failed update stays explained until the checkout or upstream moves on.
    NSDictionary *failed = [NSDictionary dictionaryWithContentsOfFile:problemFile(home)];
    NSString *problem = [failed[@"head"] isEqual:head] && [failed[@"tip"] isEqual:tip] ? failed[@"problem"] : nil;
    if ([result[@"available"] boolValue]) result[@"problem"] = blocker(repo) ?: problem ?: NSNull.null;
    return result;
}

#pragma mark - Update

// Dia quarantines what it and its children write, and macOS then won't run what was built, like build/diapatch writing
// patches.json in the middle of make.
static void unquarantine(NSString *path) { runIn(nil, @[ @"/usr/bin/xattr", @"-dr", @"com.apple.quarantine", path ], 120, NULL); }

static NSString *tail(NSString *output) {
    NSArray *all = lines(trimmed(output));
    return [[all subarrayWithRange:NSMakeRange(all.count > 4 ? all.count - 4 : 0, MIN(all.count, 4))] componentsJoinedByString:@"\n"];
}

static NSDictionary *build(NSDictionary *source, NSString *into, NSString **problem) {
    NSString *repo = source[@"path"], *remote = source[@"remote"] ?: @"upstream", *ref = upstreamRef(source), *upstream, *output;
    webOf(repo, remote, &upstream);
    if (!haveTools()) return *problem = @"Install Apple’s developer tools: xcode-select --install", nil;
    if ((*problem = blocker(repo))) return nil;
    if (!git(repo, @[ @"fetch", @"--quiet", remote, source[@"branch"] ?: @"main" ], 120))
        return *problem = [NSString stringWithFormat:@"Couldn’t reach %@", upstream], nil;
    if (runIn(repo, @[ @"/usr/bin/git", @"merge", @"--no-edit", ref ], 120, &output) != 0) {
        git(repo, @[ @"merge", @"--abort" ], 30);
        *problem = [output containsString:@"CONFLICT"]
            ? [NSString stringWithFormat:@"The changes from %@ conflict with yours. Run git merge %@ in %@ and fix them.", upstream, ref, shortPath(repo)]
            : [NSString stringWithFormat:@"Couldn’t merge %@: %@", ref, tail(output)];
        return nil;
    }
    unquarantine(repo);
    NSString *buildDir = [repo stringByAppendingPathComponent:@"build"];
    BOOL built = runIn(repo, @[ @"/usr/bin/make", @"-s", @"build/diapatch", @"build/DiaPatches.dylib" ], 1800, &output) == 0;
    unquarantine(buildDir);
    built = built && runIn(repo, @[ @"/usr/bin/make", @"-s" ], 600, &output) == 0;
    if (!built) return *problem = [NSString stringWithFormat:@"The build failed:\n%@", tail(output)], nil;

    // The diatweaks command needs Rust, which is optional, as in install.sh.
    // The same files as a release: what make builds, and the app icons install.sh copies from assets.
    NSMutableArray *files = [@[ @"build/diapatch", @"build/DiaPatches.dylib", @"build/patches.json", @"assets/app-icons" ] mutableCopy];
    if (runIn(repo, @[ @"/usr/bin/env", @"cargo", @"build", @"--release", @"--quiet", @"--manifest-path", @"cli/Cargo.toml" ], 1800, NULL) == 0)
        [files addObject:@"cli/target/release/diatweaks"];
    for (NSString *file in files) {
        NSError *error;
        NSString *from = [repo stringByAppendingPathComponent:file], *to = [into stringByAppendingPathComponent:file.lastPathComponent];
        if (![NSFileManager.defaultManager copyItemAtPath:from toPath:to error:&error])
            return *problem = [NSString stringWithFormat:@"Couldn’t copy %@: %@", file, error.localizedDescription], nil;
    }
    unquarantine(into);
    NSString *head = git(repo, @[ @"rev-parse", @"HEAD" ], 10);
    return @{ @"tag" : [head substringToIndex:7], @"commit" : head, @"branch" : git(repo, @[ @"symbolic-ref", @"-q", @"--short", @"HEAD" ], 10) ?: @"" };
}

NSDictionary *DPSourceBuild(NSString *home, NSString *into, NSString **problem) {
    NSDictionary *source = DPSourceOf(home);
    if (!source) return *problem = @"DiaTweaks wasn’t installed from a checkout", nil;
    NSDictionary *release = build(source, into, problem);
    NSString *repo = source[@"path"];
    if (release) [NSFileManager.defaultManager removeItemAtPath:problemFile(home) error:NULL];
    else [@{ @"problem" : *problem, @"head" : git(repo, @[ @"rev-parse", @"HEAD" ], 10) ?: @"",
             @"tip" : git(repo, @[ @"rev-parse", @"--verify", @"-q", upstreamRef(source) ], 10) ?: @"" } writeToFile:problemFile(home) atomically:YES];
    return release;
}
