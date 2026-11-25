#import <Foundation/Foundation.h>
#import <assert.h>
#import "../src/HardwareInspector.h"
#import "../src/ModelCatalog.h"
#import "../src/DownloadManager.h"
#import "../src/MarkdownRenderer.h"

static void testCPUTiers(void) {
    // Core 2 Duo (Merom/Penryn: SSSE3/SSE4.1, no SSE4.2, no AVX)
    assert([[HardwareInspector cpuTierForFeatures:@"FPU SSE SSE2 SSE3 SSSE3 SSE4.1 EM64T" leaf7Features:@""] isEqualToString:@"core2"]);

    // Nehalem / Westmere (SSE4.2, no AVX)
    assert([[HardwareInspector cpuTierForFeatures:@"FPU SSE3 SSSE3 SSE4.1 SSE4.2 POPCNT" leaf7Features:@""] isEqualToString:@"nehalem"]);

    // Sandy Bridge (AVX1.0, SSE4.2, no F16C, no AVX2)
    assert([[HardwareInspector cpuTierForFeatures:@"SSE4.2 POPCNT AES AVX1.0" leaf7Features:@""] isEqualToString:@"sandybridge"]);

    // Ivy Bridge (AVX1.0 + F16C, no AVX2/BMI2)
    assert([[HardwareInspector cpuTierForFeatures:@"SSE4.2 AVX1.0 F16C RDRAND" leaf7Features:@""] isEqualToString:@"ivybridge"]);

    // Haswell (AVX2 + BMI2 + FMA + F16C)
    assert([[HardwareInspector cpuTierForFeatures:@"SSE4.2 AVX1.0 FMA F16C" leaf7Features:@"BMI1 AVX2 BMI2"] isEqualToString:@"haswell"]);

    // Guard against substring bug: AVX1.0 without leaf7 AVX2 must NOT trigger haswell
    assert(![[HardwareInspector cpuTierForFeatures:@"AVX1.0 FMA F16C" leaf7Features:@"BMI2"] isEqualToString:@"haswell"]);

    NSLog(@"PASS: testCPUTiers");
}

static void testMacProAndContext(void) {
    assert([HardwareInspector isMacProModel:@"MacPro3,1"] == YES);
    assert([HardwareInspector isMacProModel:@"MacPro5,1"] == YES);
    assert([HardwareInspector isMacProModel:@"MacPro6,1"] == YES);
    assert([HardwareInspector isMacProModel:@"MacBookPro8,1"] == NO);
    assert([HardwareInspector isMacProModel:@"iMac12,2"] == NO);

    assert([HardwareInspector recommendedContextSizeForRAMGB:4] == 2048);
    assert([HardwareInspector recommendedContextSizeForRAMGB:8] == 8192);
    assert([HardwareInspector recommendedContextSizeForRAMGB:16] == 32768);
    assert([HardwareInspector recommendedContextSizeForRAMGB:64] == 32768);

    assert([[HardwareInspector osStatusLevelForVersion:@"10.9.5" build:@"13F1911"] isEqualToString:@"ok"]);
    assert([[HardwareInspector osStatusLevelForVersion:@"10.9.2" build:@"13C64"] isEqualToString:@"advisory"]);
    assert([[HardwareInspector osStatusLevelForVersion:@"10.9.5" build:@"13F34"] isEqualToString:@"advisory"]);
    assert([[HardwareInspector osStatusLevelForVersion:@"10.8.5" build:@"12F45"] isEqualToString:@"unsupported"]);

    NSLog(@"PASS: testMacProAndContext");
}

static void testInferenceNotices(void) {
    NSString *sandy = [HardwareInspector inferenceNoticeForIsMacPro:NO modelIdentifier:@"MacBookPro8,1" hasAVX2:NO];
    assert([sandy isEqualToString:@"Note: Mavericks inference is CPU-only (no AVX2, no OpenCL, no Metal)."]);

    NSString *haswell = [HardwareInspector inferenceNoticeForIsMacPro:NO modelIdentifier:@"MacBookPro11,1" hasAVX2:YES];
    assert([haswell isEqualToString:@"Note: Mavericks inference is CPU-only (no OpenCL, no Metal)."]);

    NSString *macPro = [HardwareInspector inferenceNoticeForIsMacPro:YES modelIdentifier:@"MacPro5,1" hasAVX2:NO];
    assert([macPro rangeOfString:@"MacPro5,1"].location != NSNotFound);
    assert([macPro rangeOfString:@"no AVX2, no OpenCL, no Metal"].location != NSNotFound);
    assert([macPro rangeOfString:@"Linux"].location != NSNotFound);
    assert([macPro rangeOfString:@"10–20x"].location != NSNotFound);

    NSString *macProHaswell = [HardwareInspector inferenceNoticeForIsMacPro:YES modelIdentifier:@"MacPro6,1" hasAVX2:YES];
    assert([macProHaswell rangeOfString:@"MacPro6,1"].location != NSNotFound);
    assert([macProHaswell rangeOfString:@"no OpenCL, no Metal"].location != NSNotFound);
    assert([macProHaswell rangeOfString:@"no AVX2"].location == NSNotFound);

    NSLog(@"PASS: testInferenceNotices");
}

static void testMediaClassifier(void) {
    NSString *ext = nil;
    BOOL isVideo = NO;

    // Extensionless github user-attachments MP4 (ftyp box at offset 4)
    const uint8_t mp4Magic[] = {0x00, 0x00, 0x00, 0x18, 'f', 't', 'y', 'p', 'i', 's', 'o', 'm'};
    NSData *mp4Data = [NSData dataWithBytes:mp4Magic length:sizeof(mp4Magic)];
    assert([DownloadManager classifyMediaData:mp4Data contentType:@"video/mp4" urlString:@"https://github.com/user-attachments/assets/1234-uuid" extension:&ext isVideo:&isVideo]);
    assert([ext isEqualToString:@"mp4"] && isVideo == YES);

    // Shields.io SVG badge with no .svg suffix
    NSData *svgData = [@"<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>" dataUsingEncoding:NSUTF8StringEncoding];
    assert([DownloadManager classifyMediaData:svgData contentType:@"image/svg+xml;charset=utf-8" urlString:@"https://img.shields.io/badge/Mavericks-10.9-blue" extension:&ext isVideo:&isVideo]);
    assert([ext isEqualToString:@"svg"] && isVideo == NO);

    // Animated GIF magic bytes even with generic octet-stream content-type
    const uint8_t gifMagic[] = {'G', 'I', 'F', '8', '9', 'a', 0x01, 0x00, 0x01, 0x00};
    NSData *gifData = [NSData dataWithBytes:gifMagic length:sizeof(gifMagic)];
    assert([DownloadManager classifyMediaData:gifData contentType:@"application/octet-stream" urlString:@"https://github.com/user-attachments/assets/abcd" extension:&ext isVideo:&isVideo]);
    assert([ext isEqualToString:@"gif"] && isVideo == NO);

    // Reject text/html error page even on media URL
    NSData *htmlData = [@"<html><body>404</body></html>" dataUsingEncoding:NSUTF8StringEncoding];
    assert([DownloadManager classifyMediaData:htmlData contentType:@"text/html; charset=utf-8" urlString:@"https://github.com/user-attachments/assets/bad" extension:&ext isVideo:&isVideo] == NO);

    NSLog(@"PASS: testMediaClassifier");
}

static void testMarkdownRenderer(void) {
    NSString *md =
        @"# MavLlama 1.1\n"
        @"[![MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)\n\n"
        @"| Tier | SIMD |\n"
        @"| :--- | :---: |\n"
        @"| Core 2 | **SSSE3** |\n\n"
        @"- [x] Added `WebView` markdown viewer\n"
        @"- [ ] World domination\n\n"
        @"![Demo](https://example.com/demo.gif)\n\n"
        @"https://github.com/user-attachments/assets/9999-video\n\n"
        @"<script>alert('xss')</script>\n";

    NSArray *urls = [MarkdownRenderer extractRemoteMediaURLsFromMarkdown:md];
    assert(urls.count == 3);
    assert([urls containsObject:@"https://img.shields.io/badge/license-MIT-blue.svg"]);
    assert([urls containsObject:@"https://example.com/demo.gif"]);
    assert([urls containsObject:@"https://github.com/user-attachments/assets/9999-video"]);

    MavResolvedMedia *badge = [[MavResolvedMedia alloc] init];
    badge.fileURLString = @"file:///tmp/cache/badge.svg";
    badge.isVideo = NO;

    MavResolvedMedia *vid = [[MavResolvedMedia alloc] init];
    vid.fileURLString = @"file:///tmp/cache/clip.mp4";
    vid.isVideo = YES;

    NSDictionary *map = @{
        @"https://img.shields.io/badge/license-MIT-blue.svg": badge,
        @"https://github.com/user-attachments/assets/9999-video": vid
    };

    NSString *html = [MarkdownRenderer renderHTMLFromMarkdown:md releaseTitle:@"MavLlama 1.1" releaseTag:@"v1.1.0" resolvedMedia:map];
    assert([html rangeOfString:@"<h1>MavLlama 1.1</h1>"].location != NSNotFound);
    assert([html rangeOfString:@"<table>"].location != NSNotFound);
    assert([html rangeOfString:@"<td>Core 2</td>"].location != NSNotFound);
    assert([html rangeOfString:@"<strong>SSSE3</strong>"].location != NSNotFound);
    assert([html rangeOfString:@"file:///tmp/cache/badge.svg"].location != NSNotFound);
    assert([html rangeOfString:@"<video controls"].location != NSNotFound);
    assert([html rangeOfString:@"file:///tmp/cache/clip.mp4"].location != NSNotFound);
    // Unresolved image must NEVER emit remote https:// <img src=...> in 10.9 WebView
    assert([html rangeOfString:@"src=\"https://example.com/demo.gif\""].location == NSNotFound);
    // Untrusted script tags must be escaped
    assert([html rangeOfString:@"<script>"].location == NSNotFound);
    assert([html rangeOfString:@"&lt;script&gt;"].location != NSNotFound);

    NSLog(@"PASS: testMarkdownRenderer");
}

static void testCatalogAndFiltering(NSString *catalogPath) {
    NSData *data = [NSData dataWithContentsOfFile:catalogPath];
    assert(data != nil);
    NSError *err = nil;
    NSArray *models = [ModelCatalog parseModelsFromData:data error:&err];
    assert(err == nil);
    assert(models.count == 29);

    for (MavModelEntry *m in models) {
        assert(m.name.length > 0);
        assert(m.filename.length > 0);
        assert([m.url hasPrefix:@"https://"]);
        assert(m.sizeBytes > 0);
    }

    // Standard 4 GB Mac only sees models <= 4 GB
    NSArray *filtered4 = [ModelCatalog filterModels:models forRAMGB:4 isMacPro:NO overrideFilter:NO familyFilter:@"All"];
    assert(filtered4.count == 5);
    for (MavModelEntry *m in filtered4) {
        assert(m.minRAMGB <= 4);
    }

    // Mac Pro lifts all RAM restrictions even with 4 GB
    NSArray *macProAll = [ModelCatalog filterModels:models forRAMGB:4 isMacPro:YES overrideFilter:NO familyFilter:@"All"];
    assert(macProAll.count == 29);

    // Explicit override lifts restrictions
    NSArray *overrideAll = [ModelCatalog filterModels:models forRAMGB:4 isMacPro:NO overrideFilter:YES familyFilter:@"All"];
    assert(overrideAll.count == 29);

    // Family filtering
    NSArray *gemma16 = [ModelCatalog filterModels:models forRAMGB:16 isMacPro:NO overrideFilter:NO familyFilter:@"Gemma"];
    assert(gemma16.count == 5); // 3-1B, 4-E2B, 4-E4B, 3-12B, 4-26B-A4B-IQ2_M

    NSArray *deepseekMacPro = [ModelCatalog filterModels:models forRAMGB:16 isMacPro:YES overrideFilter:NO familyFilter:@"DeepSeek"];
    assert(deepseekMacPro.count == 4); // R1-1.5B, R1-8B, R1-14B, V2-Lite MoE

    NSLog(@"PASS: testCatalogAndFiltering");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *catalogPath = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"catalog/models.json";
        testCPUTiers();
        testMacProAndContext();
        testInferenceNotices();
        testMediaClassifier();
        testMarkdownRenderer();
        testCatalogAndFiltering(catalogPath);
        NSLog(@"ALL MAVLLAMA CORE TESTS PASSED");
    }
    return 0;
}
