#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface RootViewController : UIViewController <WKNavigationDelegate, WKScriptMessageHandler>

@property (strong, nonatomic) WKWebView *webView;

// Called from JS bridge when user taps action button
- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message;

// Inject a log line into the WebView terminal
- (void)jsLog:(NSString *)msg level:(NSString *)level;

// The main escape pipeline
- (void)runEscapePipeline;

@end
