#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// One behavior: if a tweak saves a file that is actually a GIF but declares another extension, fix it before Photos import.

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

%hook RXIManager
+ (void)saveMedia:(id)fileURL fileExtension:(id)fileextension {
    NSURL *u = (NSURL *)fileURL;
    NSString *ext = [(NSString *)fileextension lowercaseString];
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

%hook BHIManager
+ (void)saveMedia:(id)fileURL fileExtension:(id)fileextension {
    NSURL *u = (NSURL *)fileURL;
    NSString *ext = [(NSString *)fileextension lowercaseString];
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
