#import "RootViewController.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ── FilzaJailedDS exploit headers ──
#import "kexploit/kexploit_opa334.h"
#import "kexploit/kutils.h"
#import "sandbox_escape.h"
#import "apfs_own.h"

// ── External functions from kexploit/krw ──
#include "kexploit/krw.h"

@implementation RootViewController {
    WKUserContentController *userCC;
    BOOL pipelineDone;
    BOOL escapeOK;
    NSString *luaSourcePath;   // found LuaSource dir
    NSArray *foundFiles;       // 2KB .luac files
    NSData *modData;           // mod file with placeholder applied
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupWebView];
}

- (void)setupWebView {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    userCC = [[WKUserContentController alloc] init];
    [userCC addScriptMessageHandler:self name:@"injectorAction"];
    config.userContentController = userCC;

    CGRect frame = self.view.bounds;
    self.webView = [[WKWebView alloc] initWithFrame:frame configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.webView];

    // Load index.html from bundle
    NSString *htmlPath = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    if (htmlPath) {
        NSURL *url = [NSURL fileURLWithPath:htmlPath];
        [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
    } else {
        // Fallback: inline HTML
        [self.webView loadHTMLString:@"<h1>index.html not found</h1>" baseURL:nil];
    }
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    // Start the escape pipeline shortly after page load
    [self performSelector:@selector(runEscapePipeline) withObject:nil afterDelay:0.5];
}

#pragma mark - JS Bridge

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body isEqualToString:@"execute"]) {
        [self doInject];
    }
}

- (void)jsLog:(NSString *)msg level:(NSString *)level {
    NSString *js = [NSString stringWithFormat:@"window.injectorLog(%@,%@);",
                    [self jsString:msg], [self jsString:level]];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)jsShowButton:(NSString *)label {
    NSString *js = [NSString stringWithFormat:@"window.injectorShowButton(%@);",
                    [self jsString:label]];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)jsHideButton {
    [self.webView evaluateJavaScript:@"window.injectorHideButton();" completionHandler:nil];
}

// Escape a string for JS literal context
- (NSString *)jsString:(NSString *)s {
    NSString *esc = [s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    esc = [esc stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    esc = [esc stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    return [NSString stringWithFormat:@"\"%@\"", esc];
}

#pragma mark - Escape Pipeline

- (void)runEscapePipeline {
    // ── Step 1: Kernel exploit ──
    [self jsLog:@"[*] initializing darksword exploit..." level:@"dim"];
    int ret = kexploit_opa334();
    if (ret != 0) {
        [self jsLog:@"[!] kernel exploit failed" level:@"error"];
        escapeOK = NO;
        return;
    }
    [self jsLog:@"[+] get r/w FD — kernel read/write established" level:@"ok"];

    // ── Step 2: Find self proc ──
    uint64_t selfProc = proc_self();
    if (!selfProc) {
        [self jsLog:@"[!] proc_self() returned 0" level:@"error"];
        escapeOK = NO;
        return;
    }
    [self jsLog:@"[+] proc self resolved" level:@"ok"];

    // ── Step 3: Sandbox escape ──
    [self jsLog:@"[*] escaping sandbox..." level:@"dim"];
    int se = sandbox_escape(selfProc);
    if (se != 0) {
        [self jsLog:@"[!] sandbox escape failed" level:@"error"];
        escapeOK = NO;
        return;
    }
    [self jsLog:@"[+] escape sandbox — sandbox restrictions lifted" level:@"ok"];

    // ── Step 4: Root elevate ──
    [self jsLog:@"[*] elevating to root..." level:@"dim"];
    int re = sandbox_elevate_to_root(selfProc);
    if (re != 0) {
        [self jsLog:@"[!] root elevation failed (continuing with sandbox only)" level:@"error"];
        // Non-fatal: sandbox escape alone gives full FS access via apfs_own
    } else {
        [self jsLog:@"[+] uid=0 — root privileges acquired" level:@"ok"];
    }

    // ── Step 5: Find DFM game data container ──
    [self jsLog:@"[*] scanning for DeltaForce application data..." level:@"dim"];
    [self findDFMContainer];
}

- (void)findDFMContainer {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dataDir = @"/var/mobile/Containers/Data/Application";
        NSString *foundPath = nil;

        for (NSString *uuid in [fm contentsOfDirectoryAtPath:dataDir error:nil]) {
            NSString *metaPath = [dataDir stringByAppendingPathComponent:uuid];
            metaPath = [metaPath stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
            NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
            if (!meta) continue;
            NSString *bid = meta[@"MCMMetadataIdentifier"];
            if (!bid) continue;
            // Match DFM bundle IDs
            if ([bid containsString:@"DeltaForce"] ||
                [bid containsString:@"deltaforce"] ||
                [bid containsString:@"dfm"] ||
                [bid containsString:@"DFM"] ||
                [bid containsString:@"tencent.dfm"]) {
                foundPath = [dataDir stringByAppendingPathComponent:uuid];
                break;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!foundPath) {
                // Try alternate: scan for the LuaSource path directly
                [self jsLog:@"[*] container not found by bundle ID, trying path scan..." level:@"dim"];
                [self findLuaSourceByPathScan];
                return;
            }
            [self jsLog:[NSString stringWithFormat:@"[+] found game container: %@", foundPath] level:@"ok"];
            luaSourcePath = [foundPath stringByAppendingPathComponent:@"Documents/DeltaForce/Saved/LuaSource"];
            [self scanLuaSourceDir];
        });
    });
}

- (void)findLuaSourceByPathScan {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dataDir = @"/var/mobile/Containers/Data/Application";

        for (NSString *uuid in [fm contentsOfDirectoryAtPath:dataDir error:nil]) {
            NSString *candidate = [dataDir stringByAppendingPathComponent:uuid];
            candidate = [candidate stringByAppendingPathComponent:@"Documents/DeltaForce/Saved/LuaSource"];
            if ([fm fileExistsAtPath:candidate]) {
                luaSourcePath = candidate;
                break;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!luaSourcePath) {
                // Try /var/containers (system app variant)
                [self jsLog:@"[!] LuaSource directory not found in any container" level:@"error"];
                escapeOK = NO;
                return;
            }
            [self jsLog:[NSString stringWithFormat:@"[+] found LuaSource: %@", luaSourcePath] level:@"ok"];
            [self scanLuaSourceDir];
        });
    });
}

- (void)scanLuaSourceDir {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *contents = [fm contentsOfDirectoryAtPath:luaSourcePath error:nil];
        NSMutableArray *matches = [NSMutableArray array];

        for (NSString *name in contents) {
            NSString *full = [luaSourcePath stringByAppendingPathComponent:name];
            NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
            uint64_t size = [attrs fileSize];
            // Target: files around 2KB (1024-4096 range, .luac extension or any)
            if (size >= 1024 && size <= 4096) {
                [matches addObject:full];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            foundFiles = [matches copy];
            if (foundFiles.count == 0) {
                [self jsLog:@"[!] no ~2KB files found in LuaSource" level:@"error"];
                escapeOK = NO;
                return;
            }
            [self jsLog:[NSString stringWithFormat:@"[+] found %lu target file(s):", (unsigned long)foundFiles.count] level:@"ok"];
            for (NSString *f in foundFiles) {
                [self jsLog:[NSString stringWithFormat:@"    -> %@", f.lastPathComponent] level:@"dim"];
            }
            [self prepareModFile];
        });
    });
}

- (void)prepareModFile {
    // Load the mod file from app bundle, replace "东东电竞" with placeholder
    NSString *modPath = [[NSBundle mainBundle] pathForResource:@"mod_104k" ofType:@"luac"];
    if (!modPath) {
        [self jsLog:@"[!] mod_104k.luac not found in bundle" level:@"error"];
        escapeOK = NO;
        return;
    }
    NSData *raw = [NSData dataWithContentsOfFile:modPath];
    if (!raw) {
        [self jsLog:@"[!] failed to read mod file" level:@"error"];
        escapeOK = NO;
        return;
    }

    // Replace "东东电竞" (UTF-8: E4 B8 9C E4 B8 9C E7 94 B5 E7 AB 9E) with "????????"
    // and "dongdong" with "________"
    NSMutableData *mdata = [raw mutableCopy];
    // UTF-8 bytes for 东东电竞
    uint8_t ddjz[] = {0xE4, 0xB8, 0x9C, 0xE4, 0xB8, 0x9C, 0xE7, 0x94, 0xB5, 0xE7, 0xAB, 0x9E};
    uint8_t placeholder[] = {0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F}; // "????????????"

    // Find and replace 东东电竞
    const uint8_t *bytes = mdata.bytes;
    NSUInteger len = mdata.length;
    NSUInteger replaced = 0;
    for (NSUInteger i = 0; i + sizeof(ddjz) <= len; i++) {
        if (memcmp(bytes + i, ddjz, sizeof(ddjz)) == 0) {
            [mdata replaceBytesInRange:NSMakeRange(i, sizeof(ddjz)) withBytes:placeholder length:sizeof(placeholder)];
            replaced++;
            i += sizeof(placeholder) - 1;
            bytes = mdata.bytes; // refresh pointer after mutation
            len = mdata.length;
        }
    }

    // Find and replace "dongdong" (8 bytes ASCII) with "________" (8 bytes)
    const char *dd = "dongdong";
    const char *ph = "________";
    size_t ddLen = strlen(dd);
    bytes = mdata.bytes;
    len = mdata.length;
    NSUInteger replaced2 = 0;
    for (NSUInteger i = 0; i + ddLen <= len; i++) {
        if (memcmp(bytes + i, dd, ddLen) == 0) {
            [mdata replaceBytesInRange:NSMakeRange(i, ddLen) withBytes:ph length:ddLen];
            replaced2++;
            i += ddLen - 1;
            bytes = mdata.bytes;
            len = mdata.length;
        }
    }

    modData = [mdata copy];
    [self jsLog:[NSString stringWithFormat:@"[+] mod loaded: %lu bytes, sanitized %lu+%lu marks",
                 (unsigned long)modData.length, (unsigned long)replaced, (unsigned long)replaced2] level:@"ok"];

    // ── Show action button ──
    pipelineDone = YES;
    escapeOK = YES;
    [self jsLog:@"[*] ready for injection" level:@"dim"];
    [self performSelector:@selector(showActionButton) withObject:nil afterDelay:0.3];
}

- (void)showActionButton {
    [self jsShowButton:@"[ 是否加载游戏模组 ]"];
}

#pragma mark - Injection

- (void)doInject {
    if (!escapeOK || !modData || !luaSourcePath) {
        [self jsLog:@"[!] not ready for injection" level:@"error"];
        return;
    }

    [self jsLog:@"[*] injecting mod files..." level:@"dim"];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger success = 0;

    for (NSString *target in foundFiles) {
        // Backup original
        NSString *backup = [target stringByAppendingPathExtension:@"bak"];
        if (![fm fileExistsAtPath:backup]) {
            [fm copyItemAtPath:target toPath:backup error:nil];
        }
        // Write mod data
        NSError *writeErr = nil;
        [modData writeToFile:target options:NSDataWritingAtomic error:&writeErr];
        if (writeErr) {
            // Fallback: use apfs_own to chown then retry
            apfs_own([target UTF8String], 0, 0);
            [modData writeToFile:target options:NSDataWritingAtomic error:nil];
        }
        if ([fm fileExistsAtPath:target]) {
            NSDictionary *attrs = [fm attributesOfItemAtPath:target error:nil];
            if ([attrs fileSize] == modData.length) {
                success++;
                [self jsLog:[NSString stringWithFormat:@"  [+] replaced: %@", target.lastPathComponent] level:@"ok"];
            }
        }
    }

    [self jsLog:[NSString stringWithFormat:@"[+] injection complete: %lu/%lu files", (unsigned long)success, (unsigned long)foundFiles.count] level:@"ok"];
    [self jsLog:@"[*] 完成游戏前请不要退出" level:@"ok"];
}

@end
