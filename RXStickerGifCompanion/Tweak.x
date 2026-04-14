#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// If a tweak saves GIF bytes under a non-gif extension, rewrite to a temp .gif before Photos import.
// Hooks are registered only when the target class exists (avoids launch crash from MSHookMessageEx(nil, ...)).

static BOOL _tsg_gifHeader(NSData *d) {
    if (!d || d.length < 6) return NO;
    const uint8_t *b = (const uint8_t *)d.bytes;
    return b[0] == 'G' && b[1] == 'I' && b[2] == 'F' && b[3] == '8' && (b[4] == '9' || b[4] == '7') && b[5] == 'a';
}

static BOOL _tsg_fileURLLooksLikeGIF(NSURL *u) {
    if (![u isKindOfClass:[NSURL class]] || !u.isFileURL) return NO;
    NSError *e = nil;
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingFromURL:u error:&e];
    if (!fh || e) return NO;
    @try {
        return _tsg_gifHeader([fh readDataOfLength:6]);
    } @finally {
        [fh closeFile];
    }
}

static NSURL *_tsg_normalizeFileURLArgument(id fileURL) {
    if ([fileURL isKindOfClass:[NSURL class]]) return fileURL;
    if ([fileURL isKindOfClass:[NSString class]]) {
        NSString *p = [(NSString *)fileURL stringByExpandingTildeInPath];
        if (!p.length) return nil;
        return [NSURL fileURLWithPath:p];
    }
    return nil;
}

static NSString *_tsg_lowerExtension(id fileextension) {
    if (!fileextension) return nil;
    if ([fileextension isKindOfClass:[NSString class]])
        return [(NSString *)fileextension lowercaseString];
    if ([fileextension isKindOfClass:[NSNumber class]])
        return [[(NSNumber *)fileextension stringValue] lowercaseString];
    return [[fileextension description] lowercaseString];
}

%group TSG_RXIManager

%hook RXIManager

+ (void)saveMedia:(id)fileURL fileExtension:(id)fileextension {
    NSURL *u = _tsg_normalizeFileURLArgument(fileURL);
    NSString *ext = _tsg_lowerExtension(fileextension);
    if (u && u.isFileURL && ext.length && ![ext isEqualToString:@"gif"] && _tsg_fileURLLooksLikeGIF(u)) {
        NSError *e = nil;
        NSData *all = [NSData dataWithContentsOfURL:u options:NSDataReadingMappedIfSafe error:&e];
        if (!e && _tsg_gifHeader(all)) {
            NSString *path = [[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]] stringByAppendingString:@".gif"];
            NSURL *tmp = [NSURL fileURLWithPath:path];
            if ([all writeToURL:tmp options:NSDataWritingAtomic error:&e] && !e) {
                %orig(tmp, @"gif");
                return;
            }
        }
    }
    %orig;
}

%end

%end

%group TSG_BHIManager

%hook BHIManager

+ (void)saveMedia:(id)fileURL fileExtension:(id)fileextension {
    NSURL *u = _tsg_normalizeFileURLArgument(fileURL);
    NSString *ext = _tsg_lowerExtension(fileextension);
    if (u && u.isFileURL && ext.length && ![ext isEqualToString:@"gif"] && _tsg_fileURLLooksLikeGIF(u)) {
        NSError *e = nil;
        NSData *all = [NSData dataWithContentsOfURL:u options:NSDataReadingMappedIfSafe error:&e];
        if (!e && _tsg_gifHeader(all)) {
            NSString *path = [[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]] stringByAppendingString:@".gif"];
            NSURL *tmp = [NSURL fileURLWithPath:path];
            if ([all writeToURL:tmp options:NSDataWritingAtomic error:&e] && !e) {
                %orig(tmp, @"gif");
                return;
            }
        }
    }
    %orig;
}

%end

%end

%ctor {
    // Install on the next main-queue pass so ObjC classes from the app image are registered
    // (early LC_LOAD_DYLIB constructors can run before all classes are visible to objc_getClass).
    dispatch_async(dispatch_get_main_queue(), ^{
        if (objc_getClass("RXIManager"))
            %init(TSG_RXIManager);
        if (objc_getClass("BHIManager"))
            %init(TSG_BHIManager);
    });
}
