// Source mode: install.sh ran from a git checkout with an `upstream` remote (a fork), so DiaTweaks updates come from
// merging upstream into that checkout and building it there, not from the original repo's releases.
#import <Foundation/Foundation.h>

// <home>/source.plist (path, remote, branch), or nil when DiaTweaks updates come from releases.
NSDictionary *DPSourceOf(NSString *home);

// check --json's "tweaks" entry. `installed` and `staged` are the release.plist of what's installed and staged.
NSDictionary *DPSourceCheck(NSString *home, NSDictionary *installed, NSDictionary *staged);

// Merges upstream into the checkout, builds it and copies what it built into `into`. Returns its release.plist, or nil
// with `problem` saying why in words for Settings.
NSDictionary *DPSourceBuild(NSString *home, NSString *into, NSString **problem);
