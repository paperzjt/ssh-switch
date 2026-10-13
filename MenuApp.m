#import <Cocoa/Cocoa.h>

static NSDictionary *Translations(void) {
    static NSDictionary *translations;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"locales" ofType:@"json"];
        NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
        NSDictionary *catalog = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        translations = [catalog[@"zh"] isKindOfClass:[NSDictionary class]] ? catalog[@"zh"] : @{};
    });
    return translations;
}

static BOOL UsesChinese(void) {
    NSString *override = [[NSUserDefaults standardUserDefaults] stringForKey:@"InterfaceLanguage"];
    if ([override isEqualToString:@"zh"]) return YES;
    if ([override isEqualToString:@"en"]) return NO;
    NSString *language = NSLocale.preferredLanguages.firstObject ?: @"en";
    return [language hasPrefix:@"zh"];
}

static NSString *L(NSString *english) {
    return UsesChinese() ? (Translations()[english] ?: english) : english;
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, copy) NSArray<NSString *> *accounts;
@property(nonatomic, copy) NSString *activeAccount;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:24];
    self.statusItem.length = 24;
    self.statusItem.button.image = [self statusIcon];
    self.statusItem.button.toolTip = L(@"GitHub SSH Account Switcher");
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"GitHub SSH"];
    menu.delegate = self;
    self.statusItem.menu = menu;
}

- (NSImage *)statusIcon {
    NSImage *composite = [[NSImage alloc] initWithSize:NSMakeSize(24, 18)];
    [composite lockFocus];
    NSBezierPath *key = [NSBezierPath bezierPath];
    key.lineWidth = 1.8;
    key.lineCapStyle = NSLineCapStyleRound;
    key.lineJoinStyle = NSLineJoinStyleRound;
    [key appendBezierPathWithOvalInRect:NSMakeRect(4.4, 9.3, 5.4, 5.4)];
    [key moveToPoint:NSMakePoint(7.1, 9.4)];
    [key lineToPoint:NSMakePoint(7.1, 2.4)];
    [key moveToPoint:NSMakePoint(7.1, 4.5)];
    [key lineToPoint:NSMakePoint(10.1, 4.5)];
    [key moveToPoint:NSMakePoint(7.1, 6.6)];
    [key lineToPoint:NSMakePoint(9.2, 6.6)];
    [key stroke];
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:7 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: NSColor.blackColor,
    };
    [@"git" drawAtPoint:NSMakePoint(13.5, 5.3) withAttributes:attributes];
    [composite unlockFocus];
    composite.template = YES;
    return composite;
}

- (NSDictionary *)runBackend:(NSArray<NSString *> *)arguments {
    NSString *script = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"app.py"];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/python3"];
    task.arguments = [@[script] arrayByAddingObjectsFromArray:arguments];
    NSMutableDictionary *environment = [[NSProcessInfo processInfo].environment mutableCopy];
    environment[@"GITHUB_KEY_SWITCHER_LANGUAGE"] = UsesChinese() ? @"zh" : @"en";
    environment[@"GITHUB_KEY_SWITCHER_PASSPHRASE_PROMPT"] = L(@"Enter the SSH key passphrase (it will not be saved)");
    environment[@"GITHUB_KEY_SWITCHER_CANCEL"] = L(@"Cancel");
    environment[@"GITHUB_KEY_SWITCHER_CONTINUE"] = L(@"Continue");
    task.environment = environment;
    NSPipe *out = [NSPipe pipe];
    task.standardOutput = out;
    task.standardError = [NSPipe pipe];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [self showError:error.localizedDescription];
        return nil;
    }
    NSData *data = [[out fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:nil];
    if (task.terminationStatus != 0 || ![result isKindOfClass:[NSDictionary class]]) {
        NSString *message = result[@"error"] ?: L(@"The operation failed. Check the key files and permissions.");
        [self showError:message];
        return nil;
    }
    return result;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    NSDictionary *state = [self runBackend:@[@"list"]];
    self.accounts = state[@"profiles"] ?: @[];
    self.activeAccount = state[@"active"] == [NSNull null] ? nil : state[@"active"];

    if (self.accounts.count == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:L(@"No saved accounts") action:nil keyEquivalent:@""];
        empty.enabled = NO;
        [menu addItem:empty];
    } else {
        for (NSString *name in self.accounts) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name action:@selector(switchAccount:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = name;
            if ([name isEqualToString:self.activeAccount]) item.state = NSControlStateValueOn;
            [menu addItem:item];
        }
    }
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[self item:L(@"Save Current Account…") action:@selector(saveCurrent:)]];
    [menu addItem:[self item:L(@"Import Key Pair…") action:@selector(importKey:)]];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[self item:L(@"Refresh GitHub Usernames…") action:@selector(refreshUsernames:)]];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *languageItem = [[NSMenuItem alloc] initWithTitle:L(@"Language") action:nil keyEquivalent:@""];
    NSMenu *languageMenu = [[NSMenu alloc] initWithTitle:L(@"Language")];
    NSString *override = [[NSUserDefaults standardUserDefaults] stringForKey:@"InterfaceLanguage"];
    [languageMenu addItem:[self languageItem:L(@"System Default") value:@"system" selected:!override]];
    [languageMenu addItem:[self languageItem:@"English" value:@"en" selected:[override isEqualToString:@"en"]]];
    [languageMenu addItem:[self languageItem:L(@"Chinese (Simplified)") value:@"zh" selected:[override isEqualToString:@"zh"]]];
    languageItem.submenu = languageMenu;
    [menu addItem:languageItem];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[self item:L(@"Open ~/.ssh") action:@selector(openSSH:)]];
    [menu addItem:[self item:L(@"Quit") action:@selector(quit:)]];
}

- (NSMenuItem *)languageItem:(NSString *)title value:(NSString *)value selected:(BOOL)selected {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(setLanguage:) keyEquivalent:@""];
    item.target = self;
    item.representedObject = value;
    item.state = selected ? NSControlStateValueOn : NSControlStateValueOff;
    return item;
}

- (void)setLanguage:(NSMenuItem *)item {
    NSString *language = item.representedObject;
    if ([language isEqualToString:@"system"]) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"InterfaceLanguage"];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:language forKey:@"InterfaceLanguage"];
    }
    [self menuNeedsUpdate:self.statusItem.menu];
}

- (NSMenuItem *)item:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    return item;
}

- (void)switchAccount:(NSMenuItem *)item {
    NSString *name = item.representedObject;
    NSDictionary *state = [self runBackend:@[@"list"]];
    if (!state) return;
    NSDictionary *identity = state[@"identities"][name];
    NSString *active = [state[@"active"] isKindOfClass:[NSString class]] ? state[@"active"] : nil;
    if ([active isEqualToString:name]) return;
    NSString *emailBehavior = [identity isKindOfClass:[NSDictionary class]] && [identity[@"email"] length]
        ? [NSString stringWithFormat:L(@"Use the saved email when switching: %@"), identity[@"email"]]
        : L(@"No email is saved for this account; the current global user.email will be kept.");
    if (!active.length) {
        NSAlert *confirm = [[NSAlert alloc] init];
        confirm.messageText = [NSString stringWithFormat:L(@"Switch to %@?"), name];
        confirm.informativeText = [NSString stringWithFormat:L(@"The current SSH key is not a saved account. It will be backed up before switching.\n%@"), emailBehavior];
        [confirm addButtonWithTitle:L(@"Back Up and Switch")];
        [confirm addButtonWithTitle:L(@"Cancel")];
        if ([confirm runModal] != NSAlertFirstButtonReturn) return;
    }
    [self runBackend:@[@"activate", name]];
}

- (void)saveCurrent:(id)sender {
    NSTextField *field = [NSTextField textFieldWithString:@""];
    field.frame = NSMakeRect(0, 0, 360, 24);
    field.placeholderString = L(@"e.g. Work account");
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = L(@"Save Current SSH Account");
    alert.informativeText = L(@"Choose a local name for the current ~/.ssh/id_rsa key.");
    alert.accessoryView = field;
    [alert addButtonWithTitle:L(@"Save")];
    [alert addButtonWithTitle:L(@"Cancel")];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *name = field.stringValue;
    if (!name.length) { [self showError:L(@"Enter an account name.")] ; return; }
    [self runBackend:@[@"save-current", name]];
}

- (void)importKey:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = L(@"Choose SSH Private Key");
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    if ([panel runModal] != NSModalResponseOK) return;
    NSString *privatePath = panel.URL.path;
    NSString *publicPath = [privatePath stringByAppendingString:@".pub"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:publicPath]) {
        NSOpenPanel *pub = [NSOpenPanel openPanel];
        pub.title = L(@"Choose Matching Public Key");
        pub.canChooseFiles = YES;
        pub.canChooseDirectories = NO;
        if ([pub runModal] != NSModalResponseOK) return;
        publicPath = pub.URL.path;
    }
    NSTextField *field = [NSTextField textFieldWithString:[privatePath.lastPathComponent stringByDeletingPathExtension]];
    field.frame = NSMakeRect(0, 0, 360, 24);
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = L(@"Import GitHub SSH Account");
    alert.informativeText = L(@"Choose a local name. The key pair will be copied to ~/.ssh/github-accounts.");
    alert.accessoryView = field;
    [alert addButtonWithTitle:L(@"Import")];
    [alert addButtonWithTitle:L(@"Cancel")];
    if ([alert runModal] != NSAlertFirstButtonReturn || !field.stringValue.length) return;
    [self runBackend:@[@"import", field.stringValue, privatePath, publicPath]];
}

- (void)openSSH:(id)sender {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".ssh"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

- (void)refreshUsernames:(id)sender {
    NSDictionary *result = [self runBackend:@[@"refresh"]];
    if (!result) return;
    NSArray *errors = [result[@"errors"] isKindOfClass:[NSArray class]] ? result[@"errors"] : @[];
    if (errors.count) {
        [self showError:[NSString stringWithFormat:L(@"Some accounts could not be refreshed:\n%@"), [errors componentsJoinedByString:@"\n"]]];
    }
}

- (void)showError:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = L(@"Operation Failed");
    alert.informativeText = message ?: L(@"Unknown error.");
    [alert addButtonWithTitle:L(@"OK")];
    [alert runModal];
}

- (void)quit:(id)sender { [NSApp terminate:nil]; }
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
