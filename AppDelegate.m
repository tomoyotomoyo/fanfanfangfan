#import "AppDelegate.h"
#import "RootViewController.h"

@interface AppDelegate ()
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    // ── Window ──
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    self.window = [[UIWindow alloc] initWithFrame:screenBounds];
    self.window.backgroundColor = [UIColor blackColor];

    self.rootVC = [[RootViewController alloc] init];
    self.window.rootViewController = self.rootVC;
    [self.window makeKeyAndVisible];

    // ── Audio session (keep alive in background) ──
    NSError *audioError = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback
              mode:AVAudioSessionModeDefault
           options:AVAudioSessionCategoryOptionMixWithOthers
                   | AVAudioSessionCategoryOptionDuckOthers
             error:&audioError];
    [session setActive:YES error:nil];

    // Silent audio loop for background keep-alive
    // Use a short WAV generated in-memory
    // (1 sample of silence, looped)
    // If you have a real file, use its URL instead.
    // ── Background task ──
    UIApplication *app = [UIApplication sharedApplication];
    UIBackgroundTaskIdentifier bgTask = [app beginBackgroundTaskWithExpirationHandler:^{
        [app endBackgroundTask:bgTask];
    }];

    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Keep audio playing to prevent suspension
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Restart audio if needed
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Resume if needed
}

@end
