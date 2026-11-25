#import "MarkdownRenderer.h"

@implementation MavResolvedMedia
@end

static BOOL MavCharIsASCIIAlphaNum(unichar c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

static BOOL MavCharIsWhitespace(unichar c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

static BOOL MavIsSafeWebURL(NSString *url) {
    if (!url || url.length == 0) return NO;
    NSString *low = [[url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [low hasPrefix:@"http://"] || [low hasPrefix:@"https://"] || [low hasPrefix:@"mailto:"];
}

static BOOL MavIsRemoteHTTPURL(NSString *url) {
    if (!url || url.length == 0) return NO;
    NSString *low = [[url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [low hasPrefix:@"http://"] || [low hasPrefix:@"https://"];
}

static BOOL MavIsBadgeURL(NSString *url) {
    if (!url) return NO;
    NSString *low = [url lowercaseString];
    return [low rangeOfString:@"img.shields.io"].location != NSNotFound ||
           [low rangeOfString:@"badgen.net"].location != NSNotFound ||
           [low rangeOfString:@"badge.fury.io"].location != NSNotFound ||
           [low rangeOfString:@"shields.io/badge"].location != NSNotFound;
}

static BOOL MavIsDirectVideoExtensionURL(NSString *url) {
    if (!url) return NO;
    NSURL *u = [NSURL URLWithString:url];
    NSString *ext = [[u pathExtension] lowercaseString];
    return [ext isEqualToString:@"mp4"] || [ext isEqualToString:@"m4v"] || [ext isEqualToString:@"mov"];
}

static BOOL MavIsDirectImageExtensionURL(NSString *url) {
    if (!url) return NO;
    NSURL *u = [NSURL URLWithString:url];
    NSString *ext = [[u pathExtension] lowercaseString];
    return [ext isEqualToString:@"png"] || [ext isEqualToString:@"jpg"] ||
           [ext isEqualToString:@"jpeg"] || [ext isEqualToString:@"gif"] ||
           [ext isEqualToString:@"webp"] || [ext isEqualToString:@"svg"];
}

static BOOL MavIsStandaloneAttachmentURL(NSString *trimmedLine) {
    if (!MavIsRemoteHTTPURL(trimmedLine)) return NO;
    if ([trimmedLine rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) {
        return NO;
    }
    NSString *low = [trimmedLine lowercaseString];
    if ([low rangeOfString:@"github.com/user-attachments/assets/"].location != NSNotFound ||
        [low rangeOfString:@"user-images.githubusercontent.com/"].location != NSNotFound) {
        return YES;
    }
    return MavIsDirectVideoExtensionURL(trimmedLine) || MavIsDirectImageExtensionURL(trimmedLine) || MavIsBadgeURL(trimmedLine);
}

static NSString *MavEscapeHTML(NSString *text) {
    if (!text || text.length == 0) return @"";
    NSMutableString *out = [NSMutableString stringWithCapacity:text.length + 16];
    NSUInteger len = text.length;
    for (NSUInteger i = 0; i < len; i++) {
        unichar c = [text characterAtIndex:i];
        switch (c) {
            case '&': [out appendString:@"&amp;"]; break;
            case '<': [out appendString:@"&lt;"]; break;
            case '>': [out appendString:@"&gt;"]; break;
            case '"': [out appendString:@"&quot;"]; break;
            case '\'': [out appendString:@"&#39;"]; break;
            default: [out appendFormat:@"%C", c]; break;
        }
    }
    return out;
}

static NSString *MavNormalizeNewlines(NSString *s) {
    if (!s) return @"";
    NSString *noCRLF = [s stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    return [noCRLF stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
}

static NSString *MavExtractHTMLAttribute(NSString *tag, NSString *attrName) {
    if (!tag || !attrName) return nil;
    NSString *pattern = [NSString stringWithFormat:@"\\b%@\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))", attrName];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                        options:NSRegularExpressionCaseInsensitive
                                                                          error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:tag options:0 range:NSMakeRange(0, tag.length)];
    if (!m) return nil;
    for (NSUInteger g = 1; g < m.numberOfRanges; g++) {
        NSRange r = [m rangeAtIndex:g];
        if (r.location != NSNotFound) {
            return [tag substringWithRange:r];
        }
    }
    return nil;
}

static void MavAppendUniqueMediaURL(NSString *url, NSMutableArray *ordered, NSMutableSet *seen) {
    if (!url || ordered.count >= 25) return;
    NSString *trimmed = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // Strip optional <...> or markdown title suffix (`url "title"`)
    if ([trimmed hasPrefix:@"<"] && [trimmed hasSuffix:@">"] && trimmed.length > 2) {
        trimmed = [trimmed substringWithRange:NSMakeRange(1, trimmed.length - 2)];
    }
    NSRange spaceTitle = [trimmed rangeOfString:@" \""];
    if (spaceTitle.location != NSNotFound) {
        trimmed = [[trimmed substringToIndex:spaceTitle.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    if (!MavIsRemoteHTTPURL(trimmed)) return;
    if ([seen containsObject:trimmed]) return;
    [seen addObject:trimmed];
    [ordered addObject:trimmed];
}

static NSString *MavCleanLinkDestination(NSString *rawDest) {
    if (!rawDest) return @"";
    NSString *t = [rawDest stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([t hasPrefix:@"<"] && [t hasSuffix:@">"] && t.length > 2) {
        t = [t substringWithRange:NSMakeRange(1, t.length - 2)];
    }
    NSRange spaceTitle = [t rangeOfString:@" \""];
    if (spaceTitle.location != NSNotFound) {
        t = [[t substringToIndex:spaceTitle.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    return t;
}

// Finds closing bracket `]` or `)` matching nesting inside inline markdown
static NSUInteger MavFindMatchingBracket(NSString *s, NSUInteger openIdx, unichar openCh, unichar closeCh) {
    NSUInteger len = s.length;
    NSInteger depth = 1;
    for (NSUInteger i = openIdx + 1; i < len; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '\\' && i + 1 < len) {
            i++;
            continue;
        }
        if (c == openCh) {
            depth++;
        } else if (c == closeCh) {
            depth--;
            if (depth == 0) return i;
        }
    }
    return NSNotFound;
}

static NSString *MavRenderMediaElement(NSString *origURL, NSString *altText, BOOL isBadgeContext, NSDictionary *resolvedMedia) {
    NSString *cleanURL = MavCleanLinkDestination(origURL);
    MavResolvedMedia *res = resolvedMedia ? resolvedMedia[cleanURL] : nil;
    NSString *escapedOrig = MavEscapeHTML(cleanURL);
    NSString *escapedAlt = MavEscapeHTML(altText ?: @"");

    if (res && res.fileURLString.length > 0) {
        NSString *escapedFile = MavEscapeHTML(res.fileURLString);
        if (res.isVideo) {
            return [NSString stringWithFormat:
                    @"<div class=\"media-video\"><video controls preload=\"metadata\"><source src=\"%@\" type=\"video/mp4\"></video>"
                    @"<div class=\"video-fallback\"><a href=\"%@\">Open video in browser</a></div></div>",
                    escapedFile, escapedOrig];
        }
        BOOL badge = isBadgeContext || MavIsBadgeURL(cleanURL);
        NSString *cls = badge ? @"md-badge" : @"md-img";
        return [NSString stringWithFormat:@"<img src=\"%@\" alt=\"%@\" class=\"%@\">",
                escapedFile, escapedAlt, cls];
    }

    // Never emit direct remote https:// <img> or <video> in 10.9 WebView
    NSString *label = (altText && altText.length > 0) ? escapedAlt : escapedOrig;
    if (isBadgeContext || MavIsBadgeURL(cleanURL)) {
        return [NSString stringWithFormat:@"<span class=\"badge-pending\">[%@]</span>", label];
    }
    if (MavIsSafeWebURL(cleanURL)) {
        return [NSString stringWithFormat:@"<span class=\"media-pending\"><a href=\"%@\">Media: %@</a> (loading...)</span>",
                escapedOrig, label];
    }
    return [NSString stringWithFormat:@"<span class=\"media-pending\">[%@]</span>", label];
}

static NSString *MavRenderInline(NSString *text, NSDictionary *resolvedMedia) {
    if (!text || text.length == 0) return @"";
    NSMutableString *out = [NSMutableString stringWithCapacity:text.length * 2];
    NSUInteger len = text.length;
    NSUInteger i = 0;

    while (i < len) {
        unichar c = [text characterAtIndex:i];

        // 1. Backslash escape
        if (c == '\\' && i + 1 < len) {
            [out appendString:MavEscapeHTML([text substringWithRange:NSMakeRange(i + 1, 1)])];
            i += 2;
            continue;
        }

        // 2. Inline code `...`
        if (c == '`') {
            NSUInteger ticks = 1;
            while (i + ticks < len && [text characterAtIndex:i + ticks] == '`') ticks++;
            NSString *fence = [text substringWithRange:NSMakeRange(i, ticks)];
            NSRange close = [text rangeOfString:fence options:0 range:NSMakeRange(i + ticks, len - (i + ticks))];
            if (close.location != NSNotFound) {
                NSString *inner = [text substringWithRange:NSMakeRange(i + ticks, close.location - (i + ticks))];
                NSString *trimmed = [inner stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                [out appendFormat:@"<code>%@</code>", MavEscapeHTML(trimmed.length > 0 ? trimmed : inner)];
                i = close.location + ticks;
                continue;
            }
        }

        // 3. Linked image badge: [![alt](imgURL)](hrefURL)
        if (c == '[' && i + 2 < len && [text characterAtIndex:i + 1] == '!' && [text characterAtIndex:i + 2] == '[') {
            NSUInteger altEnd = MavFindMatchingBracket(text, i + 2, '[', ']');
            if (altEnd != NSNotFound && altEnd + 1 < len && [text characterAtIndex:altEnd + 1] == '(') {
                NSUInteger imgEnd = MavFindMatchingBracket(text, altEnd + 1, '(', ')');
                if (imgEnd != NSNotFound && imgEnd + 2 < len &&
                    [text characterAtIndex:imgEnd + 1] == ']' && [text characterAtIndex:imgEnd + 2] == '(') {
                    NSUInteger hrefEnd = MavFindMatchingBracket(text, imgEnd + 2, '(', ')');
                    if (hrefEnd != NSNotFound) {
                        NSString *alt = [text substringWithRange:NSMakeRange(i + 3, altEnd - (i + 3))];
                        NSString *imgURL = [text substringWithRange:NSMakeRange(altEnd + 2, imgEnd - (altEnd + 2))];
                        NSString *hrefURL = MavCleanLinkDestination([text substringWithRange:NSMakeRange(imgEnd + 3, hrefEnd - (imgEnd + 3))]);
                        NSString *imgTag = MavRenderMediaElement(imgURL, alt, YES, resolvedMedia);
                        if (MavIsSafeWebURL(hrefURL)) {
                            [out appendFormat:@"<a class=\"badge-link\" href=\"%@\">%@</a>", MavEscapeHTML(hrefURL), imgTag];
                        } else {
                            [out appendString:imgTag];
                        }
                        i = hrefEnd + 1;
                        continue;
                    }
                }
            }
        }

        // 4. Image / GIF / video: ![alt](src)
        if (c == '!' && i + 1 < len && [text characterAtIndex:i + 1] == '[') {
            NSUInteger altEnd = MavFindMatchingBracket(text, i + 1, '[', ']');
            if (altEnd != NSNotFound && altEnd + 1 < len && [text characterAtIndex:altEnd + 1] == '(') {
                NSUInteger srcEnd = MavFindMatchingBracket(text, altEnd + 1, '(', ')');
                if (srcEnd != NSNotFound) {
                    NSString *alt = [text substringWithRange:NSMakeRange(i + 2, altEnd - (i + 2))];
                    NSString *srcURL = [text substringWithRange:NSMakeRange(altEnd + 2, srcEnd - (altEnd + 2))];
                    [out appendString:MavRenderMediaElement(srcURL, alt, NO, resolvedMedia)];
                    i = srcEnd + 1;
                    continue;
                }
            }
        }

        // 5. Link: [label](href)
        if (c == '[') {
            NSUInteger lblEnd = MavFindMatchingBracket(text, i, '[', ']');
            if (lblEnd != NSNotFound && lblEnd + 1 < len && [text characterAtIndex:lblEnd + 1] == '(') {
                NSUInteger hrefEnd = MavFindMatchingBracket(text, lblEnd + 1, '(', ')');
                if (hrefEnd != NSNotFound) {
                    NSString *label = [text substringWithRange:NSMakeRange(i + 1, lblEnd - (i + 1))];
                    NSString *href = MavCleanLinkDestination([text substringWithRange:NSMakeRange(lblEnd + 2, hrefEnd - (lblEnd + 2))]);
                    MavResolvedMedia *res = resolvedMedia ? resolvedMedia[href] : nil;
                    if (res && res.isVideo) {
                        [out appendString:MavRenderMediaElement(href, label, NO, resolvedMedia)];
                    } else if (MavIsSafeWebURL(href)) {
                        [out appendFormat:@"<a href=\"%@\">%@</a>", MavEscapeHTML(href), MavRenderInline(label, resolvedMedia)];
                    } else {
                        [out appendString:MavRenderInline(label, resolvedMedia)];
                    }
                    i = hrefEnd + 1;
                    continue;
                }
            }
        }

        // 6. Inline safe tags: <br>, <br/>, <img ...>, <video ...>...</video>, or escape everything else
        if (c == '<') {
            NSRange gtRange = [text rangeOfString:@">" options:0 range:NSMakeRange(i, len - i)];
            if (gtRange.location != NSNotFound) {
                NSString *tag = [text substringWithRange:NSMakeRange(i, gtRange.location - i + 1)];
                NSString *lowTag = [tag lowercaseString];
                if ([lowTag isEqualToString:@"<br>"] || [lowTag isEqualToString:@"<br/>"] || [lowTag isEqualToString:@"<br />"]) {
                    [out appendString:@"<br>"];
                    i = gtRange.location + 1;
                    continue;
                }
                if ([lowTag hasPrefix:@"<img "] || [lowTag isEqualToString:@"<img>"]) {
                    NSString *src = MavExtractHTMLAttribute(tag, @"src");
                    NSString *alt = MavExtractHTMLAttribute(tag, @"alt") ?: @"";
                    if (src.length > 0) {
                        [out appendString:MavRenderMediaElement(src, alt, NO, resolvedMedia)];
                    }
                    i = gtRange.location + 1;
                    continue;
                }
                if ([lowTag hasPrefix:@"<video"]) {
                    NSString *src = MavExtractHTMLAttribute(tag, @"src");
                    NSRange closeVid = [text rangeOfString:@"</video>" options:NSCaseInsensitiveSearch range:NSMakeRange(gtRange.location + 1, len - (gtRange.location + 1))];
                    if (!src && closeVid.location != NSNotFound) {
                        NSString *inner = [text substringWithRange:NSMakeRange(gtRange.location + 1, closeVid.location - (gtRange.location + 1))];
                        src = MavExtractHTMLAttribute(inner, @"src");
                    }
                    if (src.length > 0) {
                        [out appendString:MavRenderMediaElement(src, @"video", NO, resolvedMedia)];
                    }
                    i = (closeVid.location != NSNotFound) ? (closeVid.location + 8) : (gtRange.location + 1);
                    continue;
                }
                if ([lowTag hasPrefix:@"<http://"] || [lowTag hasPrefix:@"<https://"]) {
                    NSString *url = [tag substringWithRange:NSMakeRange(1, tag.length - 2)];
                    [out appendFormat:@"<a href=\"%@\">%@</a>", MavEscapeHTML(url), MavEscapeHTML(url)];
                    i = gtRange.location + 1;
                    continue;
                }
            }
            [out appendString:@"&lt;"];
            i++;
            continue;
        }

        // 7. Bare autolink https://... or http://...
        if ((c == 'h') && i + 8 < len) {
            NSString *tail = [text substringFromIndex:i];
            if ([tail hasPrefix:@"https://"] || [tail hasPrefix:@"http://"]) {
                NSUInteger end = i;
                while (end < len) {
                    unichar uc = [text characterAtIndex:end];
                    if (MavCharIsWhitespace(uc) || uc == '<' || uc == '>' || uc == '"' || uc == '\'') break;
                    end++;
                }
                while (end > i) {
                    unichar last = [text characterAtIndex:end - 1];
                    if (last == '.' || last == ',' || last == ')' || last == ';' || last == ':') {
                        end--;
                    } else {
                        break;
                    }
                }
                NSString *url = [text substringWithRange:NSMakeRange(i, end - i)];
                [out appendFormat:@"<a href=\"%@\">%@</a>", MavEscapeHTML(url), MavEscapeHTML(url)];
                i = end;
                continue;
            }
        }

        // 8. Strikethrough ~~...~~
        if (c == '~' && i + 1 < len && [text characterAtIndex:i + 1] == '~') {
            NSRange close = [text rangeOfString:@"~~" options:0 range:NSMakeRange(i + 2, len - (i + 2))];
            if (close.location != NSNotFound && close.location > i + 2) {
                NSString *inner = [text substringWithRange:NSMakeRange(i + 2, close.location - (i + 2))];
                [out appendFormat:@"<del>%@</del>", MavRenderInline(inner, resolvedMedia)];
                i = close.location + 2;
                continue;
            }
        }

        // 9. Bold **...** or __...__
        if ((c == '*' || c == '_') && i + 1 < len && [text characterAtIndex:i + 1] == c) {
            BOOL boundaryOK = (c == '*') || (i == 0 || !MavCharIsASCIIAlphaNum([text characterAtIndex:i - 1]));
            if (boundaryOK) {
                NSString *marker = (c == '*') ? @"**" : @"__";
                NSRange close = [text rangeOfString:marker options:0 range:NSMakeRange(i + 2, len - (i + 2))];
                if (close.location != NSNotFound && close.location > i + 2) {
                    NSUInteger afterClose = close.location + 2;
                    BOOL closeOK = (c == '*') || (afterClose >= len || !MavCharIsASCIIAlphaNum([text characterAtIndex:afterClose]));
                    if (closeOK) {
                        NSString *inner = [text substringWithRange:NSMakeRange(i + 2, close.location - (i + 2))];
                        [out appendFormat:@"<strong>%@</strong>", MavRenderInline(inner, resolvedMedia)];
                        i = afterClose;
                        continue;
                    }
                }
            }
        }

        // 10. Italic *...* or _..._ (respecting word boundaries for _)
        if (c == '*' || c == '_') {
            BOOL boundaryOK = (c == '*') || (i == 0 || !MavCharIsASCIIAlphaNum([text characterAtIndex:i - 1]));
            if (boundaryOK && i + 1 < len && !MavCharIsWhitespace([text characterAtIndex:i + 1])) {
                NSString *marker = (c == '*') ? @"*" : @"_";
                NSUInteger searchStart = i + 1;
                NSRange close = NSMakeRange(NSNotFound, 0);
                while (searchStart < len) {
                    NSRange r = [text rangeOfString:marker options:0 range:NSMakeRange(searchStart, len - searchStart)];
                    if (r.location == NSNotFound) break;
                    // Do not match inside ** or mid-word _
                    if (r.location > i + 1 && !MavCharIsWhitespace([text characterAtIndex:r.location - 1])) {
                        BOOL afterOK = (c == '*') || (r.location + 1 >= len || !MavCharIsASCIIAlphaNum([text characterAtIndex:r.location + 1]));
                        if (afterOK) {
                            close = r;
                            break;
                        }
                    }
                    searchStart = r.location + 1;
                }
                if (close.location != NSNotFound) {
                    NSString *inner = [text substringWithRange:NSMakeRange(i + 1, close.location - (i + 1))];
                    [out appendFormat:@"<em>%@</em>", MavRenderInline(inner, resolvedMedia)];
                    i = close.location + 1;
                    continue;
                }
            }
        }

        // Default literal character
        [out appendString:MavEscapeHTML([text substringWithRange:NSMakeRange(i, 1)])];
        i++;
    }

    return out;
}

static NSArray *MavSplitTableCells(NSString *line) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([trimmed hasPrefix:@"|"]) trimmed = [trimmed substringFromIndex:1];
    if ([trimmed hasSuffix:@"|"] && ![trimmed hasSuffix:@"\\|"]) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }

    NSMutableArray *cells = [NSMutableArray array];
    NSMutableString *cur = [NSMutableString string];
    BOOL inCode = NO;
    NSUInteger len = trimmed.length;
    for (NSUInteger i = 0; i < len; i++) {
        unichar c = [trimmed characterAtIndex:i];
        if (c == '\\' && i + 1 < len && [trimmed characterAtIndex:i + 1] == '|') {
            [cur appendString:@"|"];
            i++;
            continue;
        }
        if (c == '`') {
            inCode = !inCode;
            [cur appendFormat:@"%C", c];
            continue;
        }
        if (c == '|' && !inCode) {
            [cells addObject:[cur stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
            [cur setString:@""];
            continue;
        }
        [cur appendFormat:@"%C", c];
    }
    [cells addObject:[cur stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    return cells;
}

static NSArray *MavParseTableAlignments(NSString *delimiterLine) {
    if (!delimiterLine || [delimiterLine rangeOfString:@"|"].location == NSNotFound) return nil;
    NSArray *cells = MavSplitTableCells(delimiterLine);
    if (cells.count == 0) return nil;

    NSMutableArray *aligns = [NSMutableArray array];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^:?-{1,}:?$" options:0 error:nil];
    for (NSString *cell in cells) {
        if (cell.length == 0) return nil;
        if ([re numberOfMatchesInString:cell options:0 range:NSMakeRange(0, cell.length)] != 1) {
            return nil;
        }
        BOOL leftColon = [cell hasPrefix:@":"];
        BOOL rightColon = [cell hasSuffix:@":"];
        if (leftColon && rightColon) {
            [aligns addObject:@"center"];
        } else if (rightColon) {
            [aligns addObject:@"right"];
        } else {
            [aligns addObject:@"left"];
        }
    }
    return aligns;
}

static BOOL MavIsHorizontalRule(NSString *trimmed) {
    if (trimmed.length < 3) return NO;
    NSString *compact = [trimmed stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (compact.length < 3) return NO;
    unichar first = [compact characterAtIndex:0];
    if (first != '-' && first != '*' && first != '_') return NO;
    for (NSUInteger i = 1; i < compact.length; i++) {
        if ([compact characterAtIndex:i] != first) return NO;
    }
    return YES;
}

static NSString *MavParseOrderedListItem(NSString *trimmed, NSString **outContent) {
    NSUInteger len = trimmed.length;
    NSUInteger digits = 0;
    while (digits < len && [trimmed characterAtIndex:digits] >= '0' && [trimmed characterAtIndex:digits] <= '9') {
        digits++;
    }
    if (digits == 0 || digits >= len) return nil;
    unichar sep = [trimmed characterAtIndex:digits];
    if ((sep == '.' || sep == ')') && digits + 1 < len && ([trimmed characterAtIndex:digits + 1] == ' ' || [trimmed characterAtIndex:digits + 1] == '\t')) {
        if (outContent) {
            *outContent = [[trimmed substringFromIndex:digits + 2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
        return [trimmed substringToIndex:digits];
    }
    return nil;
}

@implementation MarkdownRenderer

+ (NSArray *)extractRemoteMediaURLsFromMarkdown:(NSString *)markdown {
    if (!markdown || markdown.length == 0) return @[];
    NSString *norm = MavNormalizeNewlines(markdown);
    NSArray *lines = [norm componentsSeparatedByString:@"\n"];

    NSMutableArray *ordered = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    BOOL inFence = NO;
    NSString *fenceMarker = nil;

    NSRegularExpression *imgRe = [NSRegularExpression regularExpressionWithPattern:@"!\\[[^\\]]*\\]\\(([^)\\s]+(?:\\s+\"[^\"]*\")?)\\)" options:0 error:nil];
    NSRegularExpression *videoLinkRe = [NSRegularExpression regularExpressionWithPattern:@"\\[[^\\]]*\\]\\((https?://[^)\\s]+\\.(?:mp4|m4v|mov|gif|png|jpg|jpeg|webp|svg)(?:\\?[^)\\s]*)?)\\)" options:NSRegularExpressionCaseInsensitive error:nil];
    NSRegularExpression *htmlSrcRe = [NSRegularExpression regularExpressionWithPattern:@"<(?:img|video|source)\\b[^>]*\\bsrc\\s*=\\s*(?:\"([^\"]+)\"|'([^']+)'|([^\\s>]+))" options:NSRegularExpressionCaseInsensitive error:nil];

    for (NSString *rawLine in lines) {
        NSString *trimmed = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"```"] || [trimmed hasPrefix:@"~~~"]) {
            NSString *marker = [trimmed substringToIndex:3];
            if (!inFence) {
                inFence = YES;
                fenceMarker = marker;
            } else if ([marker isEqualToString:fenceMarker]) {
                inFence = NO;
                fenceMarker = nil;
            }
            continue;
        }
        if (inFence) continue;

        if (MavIsStandaloneAttachmentURL(trimmed)) {
            MavAppendUniqueMediaURL(trimmed, ordered, seen);
        }

        [imgRe enumerateMatchesInString:rawLine options:0 range:NSMakeRange(0, rawLine.length) usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
            (void)f;
            if (m.numberOfRanges > 1) {
                MavAppendUniqueMediaURL([rawLine substringWithRange:[m rangeAtIndex:1]], ordered, seen);
            }
            if (ordered.count >= 25) *stop = YES;
        }];

        [htmlSrcRe enumerateMatchesInString:rawLine options:0 range:NSMakeRange(0, rawLine.length) usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
            (void)f;
            for (NSUInteger g = 1; g < m.numberOfRanges; g++) {
                NSRange r = [m rangeAtIndex:g];
                if (r.location != NSNotFound) {
                    MavAppendUniqueMediaURL([rawLine substringWithRange:r], ordered, seen);
                    break;
                }
            }
            if (ordered.count >= 25) *stop = YES;
        }];

        [videoLinkRe enumerateMatchesInString:rawLine options:0 range:NSMakeRange(0, rawLine.length) usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
            (void)f;
            if (m.numberOfRanges > 1) {
                MavAppendUniqueMediaURL([rawLine substringWithRange:[m rangeAtIndex:1]], ordered, seen);
            }
            if (ordered.count >= 25) *stop = YES;
        }];

        if (ordered.count >= 25) break;
    }

    return ordered;
}

+ (NSString *)renderHTMLFromMarkdown:(NSString *)markdown
                        releaseTitle:(NSString *)title
                          releaseTag:(NSString *)tag
                       resolvedMedia:(NSDictionary *)resolvedMedia {
    (void)title;
    (void)tag;

    NSString *norm = MavNormalizeNewlines(markdown ?: @"");
    NSArray *lines = [norm componentsSeparatedByString:@"\n"];
    NSMutableString *bodyHTML = [NSMutableString string];

    NSUInteger count = lines.count;
    NSUInteger idx = 0;

    while (idx < count) {
        NSString *line = lines[idx];
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        // 1. Blank line
        if (trimmed.length == 0) {
            idx++;
            continue;
        }

        // 2. Fenced code block ``` or ~~~
        if ([trimmed hasPrefix:@"```"] || [trimmed hasPrefix:@"~~~"]) {
            NSString *marker = [trimmed substringToIndex:3];
            NSMutableString *codeBuf = [NSMutableString string];
            idx++;
            while (idx < count) {
                NSString *cl = lines[idx];
                NSString *ct = [cl stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([ct hasPrefix:marker]) {
                    idx++;
                    break;
                }
                if (codeBuf.length > 0) [codeBuf appendString:@"\n"];
                [codeBuf appendString:cl];
                idx++;
            }
            [bodyHTML appendFormat:@"<pre><code>%@</code></pre>\n", MavEscapeHTML(codeBuf)];
            continue;
        }

        // 3. ATX Heading #..######
        if ([trimmed hasPrefix:@"#"]) {
            NSUInteger hashes = 0;
            while (hashes < trimmed.length && hashes < 6 && [trimmed characterAtIndex:hashes] == '#') {
                hashes++;
            }
            if (hashes > 0 && hashes < trimmed.length &&
                ([trimmed characterAtIndex:hashes] == ' ' || [trimmed characterAtIndex:hashes] == '\t')) {
                NSString *headingText = [[trimmed substringFromIndex:hashes] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                [bodyHTML appendFormat:@"<h%lu>%@</h%lu>\n",
                 (unsigned long)hashes, MavRenderInline(headingText, resolvedMedia), (unsigned long)hashes];
                idx++;
                continue;
            }
        }

        // 4. Horizontal Rule
        if (MavIsHorizontalRule(trimmed)) {
            [bodyHTML appendString:@"<hr>\n"];
            idx++;
            continue;
        }

        // 5. GFM Pipe Table
        if ([trimmed rangeOfString:@"|"].location != NSNotFound && idx + 1 < count) {
            NSArray *aligns = MavParseTableAlignments(lines[idx + 1]);
            if (aligns && aligns.count > 0) {
                NSArray *headers = MavSplitTableCells(line);
                [bodyHTML appendString:@"<table>\n<thead>\n<tr>"];
                for (NSUInteger col = 0; col < headers.count; col++) {
                    NSString *al = col < aligns.count ? aligns[col] : @"left";
                    if ([al isEqualToString:@"left"]) {
                        [bodyHTML appendFormat:@"<th>%@</th>", MavRenderInline(headers[col], resolvedMedia)];
                    } else {
                        [bodyHTML appendFormat:@"<th style=\"text-align:%@;\">%@</th>", al, MavRenderInline(headers[col], resolvedMedia)];
                    }
                }
                [bodyHTML appendString:@"</tr>\n</thead>\n<tbody>\n"];
                idx += 2;
                while (idx < count) {
                    NSString *rTrim = [lines[idx] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if (rTrim.length == 0 || [rTrim rangeOfString:@"|"].location == NSNotFound) break;
                    NSArray *cells = MavSplitTableCells(lines[idx]);
                    [bodyHTML appendString:@"<tr>"];
                    NSUInteger cols = MAX(headers.count, cells.count);
                    for (NSUInteger col = 0; col < cols; col++) {
                        NSString *cellVal = col < cells.count ? cells[col] : @"";
                        NSString *al = col < aligns.count ? aligns[col] : @"left";
                        if ([al isEqualToString:@"left"]) {
                            [bodyHTML appendFormat:@"<td>%@</td>", MavRenderInline(cellVal, resolvedMedia)];
                        } else {
                            [bodyHTML appendFormat:@"<td style=\"text-align:%@;\">%@</td>", al, MavRenderInline(cellVal, resolvedMedia)];
                        }
                    }
                    [bodyHTML appendString:@"</tr>\n"];
                    idx++;
                }
                [bodyHTML appendString:@"</tbody>\n</table>\n"];
                continue;
            }
        }

        // 6. Blockquote
        if ([trimmed hasPrefix:@">"]) {
            NSMutableString *quoteHTML = [NSMutableString string];
            while (idx < count) {
                NSString *ql = [lines[idx] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (![ql hasPrefix:@">"]) break;
                NSString *content = [ql substringFromIndex:1];
                if ([content hasPrefix:@" "]) content = [content substringFromIndex:1];
                if (content.length == 0) {
                    [quoteHTML appendString:@"<br>"];
                } else {
                    if (quoteHTML.length > 0 && ![quoteHTML hasSuffix:@"<br>"]) [quoteHTML appendString:@" "];
                    [quoteHTML appendString:MavRenderInline(content, resolvedMedia)];
                }
                idx++;
            }
            [bodyHTML appendFormat:@"<blockquote><p>%@</p></blockquote>\n", quoteHTML];
            continue;
        }

        // 7. Unordered list (- , * , + ) & Task lists (- [ ] / - [x])
        if ((trimmed.length >= 2 &&
             ([trimmed hasPrefix:@"- "] || [trimmed hasPrefix:@"* "] || [trimmed hasPrefix:@"+ "] ||
              [trimmed hasPrefix:@"-\t"] || [trimmed hasPrefix:@"*\t"] || [trimmed hasPrefix:@"+\t"]))) {
            [bodyHTML appendString:@"<ul>\n"];
            while (idx < count) {
                NSString *lt = [lines[idx] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (lt.length < 2 || (![lt hasPrefix:@"- "] && ![lt hasPrefix:@"* "] && ![lt hasPrefix:@"+ "] &&
                                      ![lt hasPrefix:@"-\t"] && ![lt hasPrefix:@"*\t"] && ![lt hasPrefix:@"+\t"])) {
                    break;
                }
                NSString *item = [[lt substringFromIndex:2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([item hasPrefix:@"[x] "] || [item hasPrefix:@"[X] "]) {
                    [bodyHTML appendFormat:@"<li class=\"task-item\"><span class=\"chk checked\">&#10003;</span> %@</li>\n",
                     MavRenderInline([item substringFromIndex:4], resolvedMedia)];
                } else if ([item hasPrefix:@"[ ] "]) {
                    [bodyHTML appendFormat:@"<li class=\"task-item\"><span class=\"chk\">&nbsp;</span> %@</li>\n",
                     MavRenderInline([item substringFromIndex:4], resolvedMedia)];
                } else {
                    [bodyHTML appendFormat:@"<li>%@</li>\n", MavRenderInline(item, resolvedMedia)];
                }
                idx++;
            }
            [bodyHTML appendString:@"</ul>\n"];
            continue;
        }

        // 8. Ordered list (1. item)
        NSString *olFirst = nil;
        if (MavParseOrderedListItem(trimmed, &olFirst)) {
            [bodyHTML appendString:@"<ol>\n"];
            while (idx < count) {
                NSString *lt = [lines[idx] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSString *item = nil;
                if (!MavParseOrderedListItem(lt, &item)) break;
                [bodyHTML appendFormat:@"<li>%@</li>\n", MavRenderInline(item, resolvedMedia)];
                idx++;
            }
            [bodyHTML appendString:@"</ol>\n"];
            continue;
        }

        // 9. Standalone attachment / MP4 / image URL line
        if (MavIsStandaloneAttachmentURL(trimmed)) {
            [bodyHTML appendFormat:@"<p class=\"media-block\">%@</p>\n",
             MavRenderMediaElement(trimmed, [trimmed lastPathComponent], NO, resolvedMedia)];
            idx++;
            continue;
        }

        // 10. Structural centered <p align="center">...</p> or <details>/<summary> wrappers
        NSString *lowTrimmed = [trimmed lowercaseString];
        if ([lowTrimmed isEqualToString:@"<p align=\"center\">"] || [lowTrimmed isEqualToString:@"</p>"]) {
            [bodyHTML appendFormat:@"%@\n", lowTrimmed.length == 4 ? @"</p>" : @"<p class=\"center\">"];
            idx++;
            continue;
        }
        if ([lowTrimmed hasPrefix:@"<p align=\"center\">"] && [lowTrimmed hasSuffix:@"</p>"] && trimmed.length > 22) {
            NSString *inner = [trimmed substringWithRange:NSMakeRange(18, trimmed.length - 22)];
            [bodyHTML appendFormat:@"<p class=\"center\">%@</p>\n", MavRenderInline(inner, resolvedMedia)];
            idx++;
            continue;
        }
        if ([lowTrimmed isEqualToString:@"<details>"] || [lowTrimmed isEqualToString:@"</details>"]) {
            [bodyHTML appendFormat:@"%@\n", lowTrimmed];
            idx++;
            continue;
        }
        if ([lowTrimmed hasPrefix:@"<summary>"] && [lowTrimmed hasSuffix:@"</summary>"]) {
            NSString *inner = [trimmed substringWithRange:NSMakeRange(9, trimmed.length - 19)];
            [bodyHTML appendFormat:@"<summary>%@</summary>\n", MavRenderInline(inner, resolvedMedia)];
            idx++;
            continue;
        }

        // 11. Paragraph (collect contiguous lines until blank or next block marker)
        NSMutableArray *pLines = [NSMutableArray array];
        while (idx < count) {
            NSString *pl = lines[idx];
            NSString *pt = [pl stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (pt.length == 0) break;
            if ([pt hasPrefix:@"```"] || [pt hasPrefix:@"~~~"] || [pt hasPrefix:@"#"] ||
                [pt hasPrefix:@">"] || MavIsHorizontalRule(pt) ||
                [pt hasPrefix:@"- "] || [pt hasPrefix:@"* "] || [pt hasPrefix:@"+ "] ||
                MavParseOrderedListItem(pt, nil) || MavIsStandaloneAttachmentURL(pt)) {
                if (pLines.count > 0) break;
            }
            if ([pt rangeOfString:@"|"].location != NSNotFound && idx + 1 < count && MavParseTableAlignments(lines[idx + 1])) {
                if (pLines.count > 0) break;
            }
            [pLines addObject:pt];
            idx++;
        }

        NSMutableString *pHTML = [NSMutableString string];
        for (NSUInteger pi = 0; pi < pLines.count; pi++) {
            if (pi > 0) [pHTML appendString:@" "];
            [pHTML appendString:MavRenderInline(pLines[pi], resolvedMedia)];
        }
        [bodyHTML appendFormat:@"<p>%@</p>\n", pHTML];
    }

    NSString *css =
        @"body { font-family: 'Helvetica Neue', 'Lucida Grande', sans-serif; font-size: 13px; line-height: 1.55; color: #222; background: #fff; margin: 16px 20px; }\n"
        @"h1, h2, h3, h4 { color: #111; margin: 16px 0 8px 0; line-height: 1.25; }\n"
        @"h1 { font-size: 20px; border-bottom: 1px solid #e5e7eb; padding-bottom: 6px; }\n"
        @"h2 { font-size: 16px; border-bottom: 1px solid #f0f2f5; padding-bottom: 4px; }\n"
        @"h3 { font-size: 14px; }\n"
        @"p { margin: 8px 0; }\n"
        @"p.center { text-align: center; }\n"
        @"a { color: #0969da; text-decoration: none; }\n"
        @"a:hover { text-decoration: underline; }\n"
        @"code { font-family: Menlo, Monaco, monospace; font-size: 12px; background: #f3f4f6; padding: 1px 5px; border-radius: 4px; }\n"
        @"pre { background: #f6f8fa; border: 1px solid #e1e4e8; border-radius: 6px; padding: 10px 12px; overflow-x: auto; margin: 10px 0; }\n"
        @"pre code { background: transparent; padding: 0; font-size: 11.5px; line-height: 1.45; }\n"
        @"blockquote { margin: 10px 0; padding: 4px 12px; color: #57606a; border-left: 3px solid #d0d7de; background: #fafbfc; }\n"
        @"ul, ol { margin: 8px 0; padding-left: 22px; }\n"
        @"li { margin: 3px 0; }\n"
        @"li.task-item { list-style: none; margin-left: -18px; }\n"
        @".chk { display: inline-block; width: 14px; height: 14px; line-height: 14px; text-align: center; font-size: 10px; border: 1px solid #c5ccd3; border-radius: 3px; background: #fff; margin-right: 4px; vertical-align: middle; }\n"
        @".chk.checked { background: #1f883d; border-color: #1f883d; color: #fff; }\n"
        @"hr { border: 0; border-top: 1px solid #e1e4e8; margin: 14px 0; }\n"
        @"table { border-collapse: collapse; width: 100%; margin: 12px 0; font-size: 12.5px; }\n"
        @"th, td { border: 1px solid #d0d7de; padding: 6px 10px; text-align: left; }\n"
        @"th { background: #f6f8fa; font-weight: 600; }\n"
        @"tr:nth-child(even) td { background: #fbfcfd; }\n"
        @"img.md-img { display: block; max-width: 100%; height: auto; border-radius: 6px; margin: 8px 0; border: 1px solid #e5e7eb; }\n"
        @"img.md-badge { display: inline-block; vertical-align: middle; max-height: 24px; margin: 2px 3px 2px 0; }\n"
        @"a.badge-link { text-decoration: none; }\n"
        @".media-video { margin: 10px 0; }\n"
        @".media-video video { max-width: 100%; max-height: 360px; border-radius: 6px; background: #111; display: block; }\n"
        @".video-fallback { font-size: 11px; color: #666; margin-top: 4px; }\n"
        @".badge-pending, .media-pending { display: inline-block; font-size: 11px; color: #666; background: #f3f4f6; padding: 2px 7px; border-radius: 4px; border: 1px solid #e1e4e8; }\n"
        @"details { border: 1px solid #e1e4e8; border-radius: 6px; padding: 6px 10px; margin: 8px 0; background: #fafbfc; }\n"
        @"summary { cursor: pointer; font-weight: 600; }\n";

    return [NSString stringWithFormat:
            @"<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><style>\n%@</style></head>\n<body>\n%@</body></html>\n",
            css, bodyHTML];
}

@end
