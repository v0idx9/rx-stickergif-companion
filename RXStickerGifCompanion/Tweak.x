#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>

// UTIs (avoid MobileCoreServices kUTType* which may not be visible under Theos' default flags)
static CFStringRef const kTsgUTIGIF = CFSTR("com.compuserve.gif");
static CFStringRef const kTsgUTIPNG = CFSTR("public.png");

// RXTikTok sometimes hands Photos a still extension (png/jpg) for animated stickers (e.g. animated WebP),
// which looks like a "profile" still. We rewrite to a real multi-frame .gif when we can detect it.

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

static BOOL _tsg_typeAllowsMultiFrameExport(CFStringRef type) {
    if (!type) return NO;
    if (CFStringCompare(type, kTsgUTIGIF, 0) == kCFCompareEqualTo) return YES;
    if (CFStringCompare(type, kTsgUTIPNG, 0) == kCFCompareEqualTo) return YES;
    if (CFStringCompare(type, CFSTR("public.webp"), 0) == kCFCompareEqualTo) return YES;
    if (CFStringCompare(type, CFSTR("org.webmproject.webp"), 0) == kCFCompareEqualTo) return YES;
    return NO;
}

/// When ImageIO sees >1 frame (animated WebP / animated GIF), write a temp animated GIF. Otherwise nil.
static NSURL *_tsg_exportMultiFrameToTempGIF(NSURL *fileURL) {
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)fileURL, NULL);
    if (!src) return nil;

    CFStringRef type = CGImageSourceGetType(src);
    if (!_tsg_typeAllowsMultiFrameExport(type)) {
        CFRelease(src);
        return nil;
    }

    size_t n = CGImageSourceGetCount(src);
    if (n <= 1) {
        CFRelease(src);
        return nil;
    }

    NSString *path = [[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]] stringByAppendingString:@".gif"];
    NSURL *outURL = [NSURL fileURLWithPath:path];
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)outURL, kTsgUTIGIF, n, NULL);
    if (!dest) {
        CFRelease(src);
        return nil;
    }

    NSDictionary *fileProps = @{
        (NSString *)kCGImagePropertyGIFDictionary : @{
            (NSString *)kCGImagePropertyGIFLoopCount : @0,
        },
    };
    CGImageDestinationSetProperties(dest, (__bridge CFDictionaryRef)fileProps);

    const CGFloat defaultDelay = 0.08;
    for (size_t i = 0; i < n; i++) {
        CGImageRef img = CGImageSourceCreateImageAtIndex(src, i, NULL);
        if (!img) continue;

        CFDictionaryRef cprops = CGImageSourceCopyPropertiesAtIndex(src, i, NULL);
        NSDictionary *props = CFBridgingRelease(cprops);
        CGFloat delay = defaultDelay;
        NSDictionary *gifDict = props[(NSString *)kCGImagePropertyGIFDictionary];
        if ([gifDict[(NSString *)kCGImagePropertyGIFUnclampedDelayTime] isKindOfClass:[NSNumber class]]) {
            delay = [gifDict[(NSString *)kCGImagePropertyGIFUnclampedDelayTime] doubleValue];
        } else if ([gifDict[(NSString *)kCGImagePropertyGIFDelayTime] isKindOfClass:[NSNumber class]]) {
            delay = [gifDict[(NSString *)kCGImagePropertyGIFDelayTime] doubleValue];
        }
        if (delay < 0.02) delay = defaultDelay;

        NSDictionary *frameProps = @{
            (NSString *)kCGImagePropertyGIFDictionary : @{
                (NSString *)kCGImagePropertyGIFDelayTime : @(delay),
            },
        };
        CGImageDestinationAddImage(dest, img, (__bridge CFDictionaryRef)frameProps);
        CGImageRelease(img);
    }

    BOOL ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    CFRelease(src);
    return ok ? outURL : nil;
}

/// Returns a file URL to hand to saveMedia instead of `u`, or nil to keep original arguments.
static NSURL *_tsg_substituteGIFForSave(NSURL *u, NSString *ext) {
    if (!u.isFileURL) return nil;

    if (_tsg_fileURLLooksLikeGIF(u)) {
        NSError *e = nil;
        NSData *all = [NSData dataWithContentsOfURL:u options:NSDataReadingMappedIfSafe error:&e];
        if (!e && all && _tsg_gifHeader(all)) {
            NSString *path = [[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]] stringByAppendingString:@".gif"];
            NSURL *tmp = [NSURL fileURLWithPath:path];
            if ([all writeToURL:tmp options:NSDataWritingAtomic error:&e] && !e) return tmp;
        }
    }

    if (ext.length) {
        NSString *low = ext.lowercaseString;
        if ([low isEqualToString:@"mp4"] || [low isEqualToString:@"mov"] || [low isEqualToString:@"m4v"]) return nil;
    }

    return _tsg_exportMultiFrameToTempGIF(u);
}

%group TSG_RXIManager

%hook RXIManager

+ (void)saveMedia:(id)fileURL fileExtension:(id)fileextension {
    NSURL *u = _tsg_normalizeFileURLArgument(fileURL);
    NSString *ext = _tsg_lowerExtension(fileextension);
    if (!u || !u.isFileURL) {
        %orig;
        return;
    }
    if (ext && [ext isEqualToString:@"gif"]) {
        %orig;
        return;
    }
    NSURL *sub = _tsg_substituteGIFForSave(u, ext);
    if (sub) {
        %orig(sub, @"gif");
        return;
    }
    %orig;
}

%end

%end

%group TSG_RXIManager_inst

%hook RXIManager

- (void)saveMedia:(id)fileURL fileExtension:(id)fileextension {
    NSURL *u = _tsg_normalizeFileURLArgument(fileURL);
    NSString *ext = _tsg_lowerExtension(fileextension);
    if (!u || !u.isFileURL) {
        %orig;
        return;
    }
    if (ext && [ext isEqualToString:@"gif"]) {
        %orig;
        return;
    }
    NSURL *sub = _tsg_substituteGIFForSave(u, ext);
    if (sub) {
        %orig(sub, @"gif");
        return;
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
    if (!u || !u.isFileURL) {
        %orig;
        return;
    }
    if (ext && [ext isEqualToString:@"gif"]) {
        %orig;
        return;
    }
    NSURL *sub = _tsg_substituteGIFForSave(u, ext);
    if (sub) {
        %orig(sub, @"gif");
        return;
    }
    %orig;
}

%end

%end

%group TSG_BHIManager_inst

%hook BHIManager

- (void)saveMedia:(id)fileURL fileExtension:(id)fileextension {
    NSURL *u = _tsg_normalizeFileURLArgument(fileURL);
    NSString *ext = _tsg_lowerExtension(fileextension);
    if (!u || !u.isFileURL) {
        %orig;
        return;
    }
    if (ext && [ext isEqualToString:@"gif"]) {
        %orig;
        return;
    }
    NSURL *sub = _tsg_substituteGIFForSave(u, ext);
    if (sub) {
        %orig(sub, @"gif");
        return;
    }
    %orig;
}

%end

%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class rx = objc_getClass("RXIManager");
        if (rx) {
            if (class_getClassMethod(rx, @selector(saveMedia:fileExtension:)))
                %init(TSG_RXIManager);
            if (class_getInstanceMethod(rx, @selector(saveMedia:fileExtension:)))
                %init(TSG_RXIManager_inst);
        }
        Class bh = objc_getClass("BHIManager");
        if (bh) {
            if (class_getClassMethod(bh, @selector(saveMedia:fileExtension:)))
                %init(TSG_BHIManager);
            if (class_getInstanceMethod(bh, @selector(saveMedia:fileExtension:)))
                %init(TSG_BHIManager_inst);
        }
    });
}
