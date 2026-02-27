#import "stdafx.h"
#import "ProjectMView.h"
#import "ProjectMMenuLogic.h"

#include "zipfs.hpp"

#import <ctime>
#import <cstdlib>
#include <exception>

namespace {

static void callbackPresetSwitched(bool is_hard_cut, unsigned int index, void *user_data);
static void callbackPresetSwitchFailed(const char *preset_filename, const char *message, void *user_data);

static BOOL PMPresetPathsMatch(NSString *lhs, NSString *rhs) {
    if (lhs.length == 0 || rhs.length == 0) return NO;
    if ([lhs isEqualToString:rhs]) return YES;
    NSString *lhsName = [[lhs lastPathComponent] lowercaseString];
    NSString *rhsName = [[rhs lastPathComponent] lowercaseString];
    if (lhsName.length > 0 && [lhsName isEqualToString:rhsName]) return YES;
    return [lhs hasSuffix:rhs] || [rhs hasSuffix:lhs];
}

} // anonymous namespace

@implementation ProjectMView (Presets)

- (NSString *)projectMacOSDataDirectoryPath {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/foobar2000/projectMacOS"];
}

- (NSString *)projectMacOSZipPath {
    return [[self projectMacOSDataDirectoryPath] stringByAppendingPathExtension:@"zip"];
}

- (NSString *)zipExtractionDirectoryPath {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/projectMacOS/zip-content"];
}

- (NSString *)zipExtractionMetadataPath {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/projectMacOS/zip-content-meta.json"];
}

- (void)cleanupExtractedPresetCache {
    NSString *extractRoot = [self zipExtractionDirectoryPath];
    if (extractRoot.length == 0) return;

    [[NSFileManager defaultManager] removeItemAtPath:extractRoot error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[self zipExtractionMetadataPath] error:nil];
}

- (BOOL)zipFingerprintForPath:(NSString *)zipPath
                        mtime:(NSTimeInterval *)mtime
                     sizeByte:(uint64_t *)sizeByte {
    if (mtime) *mtime = 0;
    if (sizeByte) *sizeByte = 0;

    if (zipPath.length == 0) return NO;

    NSError *error = nil;
    NSDictionary<NSFileAttributeKey, id> *attrs =
        [[NSFileManager defaultManager] attributesOfItemAtPath:zipPath error:&error];
    if (!attrs || error) {
        return NO;
    }

    NSDate *modDate = attrs[NSFileModificationDate];
    NSNumber *fileSize = attrs[NSFileSize];
    if (![modDate isKindOfClass:[NSDate class]] || ![fileSize isKindOfClass:[NSNumber class]]) {
        return NO;
    }

    if (mtime) *mtime = modDate.timeIntervalSince1970;
    if (sizeByte) *sizeByte = fileSize.unsignedLongLongValue;
    return YES;
}

- (BOOL)readZipCacheMetadataAtPath:(NSString *)metadataPath
                   expectedZipPath:(NSString *)zipPath
                             mtime:(NSTimeInterval *)mtime
                          sizeByte:(uint64_t *)sizeByte
                      metadataFile:(BOOL *)metadataFile {
    if (mtime) *mtime = 0;
    if (sizeByte) *sizeByte = 0;
    if (metadataFile) *metadataFile = NO;

    if (metadataPath.length == 0 || zipPath.length == 0) {
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:metadataPath isDirectory:&isDir] || isDir) {
        return NO;
    }

    if (metadataFile) *metadataFile = YES;

    NSError *readError = nil;
    NSData *jsonData = [NSData dataWithContentsOfFile:metadataPath options:NSDataReadingMappedIfSafe error:&readError];
    if (!jsonData || readError) {
        return NO;
    }

    NSError *parseError = nil;
    id payload = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&parseError];
    if (![payload isKindOfClass:[NSDictionary class]] || parseError) {
        return NO;
    }

    NSDictionary *metadata = (NSDictionary *)payload;
    NSNumber *schemaVersion = metadata[@"schema_version"];
    NSString *storedZipPath = metadata[@"zip_path"];
    NSNumber *storedMtime = metadata[@"zip_mtime_sec"];
    NSNumber *storedSize = metadata[@"zip_size_bytes"];

    if (![schemaVersion isKindOfClass:[NSNumber class]] || schemaVersion.integerValue != 1) {
        return NO;
    }
    if (![storedZipPath isKindOfClass:[NSString class]] ||
        ![[storedZipPath stringByStandardizingPath] isEqualToString:[zipPath stringByStandardizingPath]]) {
        return NO;
    }
    if (![storedMtime isKindOfClass:[NSNumber class]] || ![storedSize isKindOfClass:[NSNumber class]]) {
        return NO;
    }

    if (mtime) *mtime = storedMtime.doubleValue;
    if (sizeByte) *sizeByte = storedSize.unsignedLongLongValue;
    return YES;
}

- (BOOL)writeZipCacheMetadataAtPath:(NSString *)metadataPath
                            zipPath:(NSString *)zipPath
                              mtime:(NSTimeInterval)mtime
                           sizeByte:(uint64_t)sizeByte
                   extractDurationMs:(NSInteger)extractDurationMs {
    if (metadataPath.length == 0 || zipPath.length == 0) {
        return NO;
    }

    NSDictionary *metadata = @{
        @"schema_version": @1,
        @"zip_path": [zipPath stringByStandardizingPath],
        @"zip_mtime_sec": @(mtime),
        @"zip_size_bytes": @(sizeByte),
        @"last_extract_duration_ms": @(extractDurationMs),
        @"last_verified_utc": @((NSInteger)time(NULL)),
    };

    NSError *serializeError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:metadata options:0 error:&serializeError];
    if (!jsonData || serializeError) {
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *metadataDir = [metadataPath stringByDeletingLastPathComponent];
    if (metadataDir.length > 0) {
        [fm createDirectoryAtPath:metadataDir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSString *tmpPath = [metadataPath stringByAppendingString:@".tmp"];
    [fm removeItemAtPath:tmpPath error:nil];

    NSError *writeError = nil;
    if (![jsonData writeToFile:tmpPath options:NSDataWritingAtomic error:&writeError]) {
        [fm removeItemAtPath:tmpPath error:nil];
        return NO;
    }

    [fm removeItemAtPath:metadataPath error:nil];
    NSError *moveError = nil;
    if (![fm moveItemAtPath:tmpPath toPath:metadataPath error:&moveError]) {
        [fm removeItemAtPath:tmpPath error:nil];
        return NO;
    }

    return YES;
}

- (void)clearZipCacheAtRoot:(NSString *)extractRoot metadataPath:(NSString *)metadataPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (extractRoot.length > 0) {
        [fm removeItemAtPath:extractRoot error:nil];
        [fm removeItemAtPath:[extractRoot stringByAppendingString:@".tmp"] error:nil];
    }
    if (metadataPath.length > 0) {
        [fm removeItemAtPath:metadataPath error:nil];
    }
}

- (uint32_t)addPresetsFromPath:(NSString *)path recursive:(BOOL)recursive {
    if (path.length == 0 || !_playlist) return 0;

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir]) {
        return 0;
    }

    NSMutableArray<NSString *> *candidatePaths = [NSMutableArray array];
    if (isDir) {
        if (recursive) {
            NSDirectoryEnumerator<NSString *> *enumerator = [fm enumeratorAtPath:path];
            for (NSString *entry in enumerator) {
                if ([[entry lastPathComponent] hasPrefix:@"."]) continue;

                NSString *fullPath = [path stringByAppendingPathComponent:entry];
                BOOL childIsDir = NO;
                if ([fm fileExistsAtPath:fullPath isDirectory:&childIsDir] && childIsDir) {
                    continue;
                }

                if ([[[entry pathExtension] lowercaseString] isEqualToString:@"milk"]) {
                    [candidatePaths addObject:fullPath];
                }
            }
        } else {
            NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:path error:nil];
            for (NSString *entry in entries) {
                if ([entry hasPrefix:@"."]) continue;

                NSString *fullPath = [path stringByAppendingPathComponent:entry];
                BOOL childIsDir = NO;
                if ([fm fileExistsAtPath:fullPath isDirectory:&childIsDir] && childIsDir) {
                    continue;
                }

                if ([[[entry pathExtension] lowercaseString] isEqualToString:@"milk"]) {
                    [candidatePaths addObject:fullPath];
                }
            }
        }
    } else if ([[[path pathExtension] lowercaseString] isEqualToString:@"milk"]) {
        [candidatePaths addObject:path];
    }

    [candidatePaths sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    uint32_t added = 0;
    for (NSString *candidatePath in candidatePaths) {
        bool fileAdded = false;
        try {
            fileAdded = projectm_playlist_add_preset(_playlist, [candidatePath UTF8String], false);
        } catch (...) {
            FB2K_console_print("projectM: exception while adding preset path, skipping: ", [candidatePath UTF8String]);
            continue;
        }

        if (!fileAdded) {
            continue;
        }

        added += 1;
    }

    return added;
}

- (BOOL)isDirectoryPresetContainer:(NSString *)path {
    if (path.length == 0) return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir] || !isDir) {
        return NO;
    }

    NSString *presetsPath = [path stringByAppendingPathComponent:@"Presets"];
    BOOL presetsIsDir = NO;
    if ([fm fileExistsAtPath:presetsPath isDirectory:&presetsIsDir] && presetsIsDir) {
        return YES;
    }

    NSError *error = nil;
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:path error:&error];
    if (!entries || error) return NO;

    for (NSString *entry in entries) {
        if ([[[entry pathExtension] lowercaseString] isEqualToString:@"milk"]) {
            return YES;
        }
    }

    return NO;
}

- (NSString *)normalizedSingleTopLevelDirectoryForRoot:(NSString *)rootPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:rootPath error:&error];
    if (!entries || error) return rootPath;

    NSMutableArray<NSString *> *visibleEntries = [NSMutableArray array];
    for (NSString *entry in entries) {
        if (![entry hasPrefix:@"."]) {
            [visibleEntries addObject:entry];
        }
    }

    if (visibleEntries.count != 1) return rootPath;

    NSString *singleEntryPath = [rootPath stringByAppendingPathComponent:visibleEntries.firstObject];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:singleEntryPath isDirectory:&isDir] && isDir) {
        return singleEntryPath;
    }

    return rootPath;
}

- (NSString *)prepareDataDirectoryFromZipAtPath:(NSString *)zipPath {
    bool zipInitialized = false;
    @try {
        if (zipPath.length == 0) return nil;

        zipPath = [zipPath stringByStandardizingPath];
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:zipPath isDirectory:&isDir] || isDir) {
            return nil;
        }

        NSString *extractRoot = [self zipExtractionDirectoryPath];
        NSString *metadataPath = [self zipExtractionMetadataPath];

        NSTimeInterval currentMtime = 0;
        uint64_t currentSize = 0;
        if (![self zipFingerprintForPath:zipPath mtime:&currentMtime sizeByte:&currentSize]) {
            FB2K_console_print("projectM: zip-cache cannot stat ZIP for fingerprinting.");
            return nil;
        }

        NSTimeInterval cachedMtime = 0;
        uint64_t cachedSize = 0;
        BOOL metadataFile = NO;
        BOOL metadataValid = [self readZipCacheMetadataAtPath:metadataPath
                                               expectedZipPath:zipPath
                                                         mtime:&cachedMtime
                                                      sizeByte:&cachedSize
                                                  metadataFile:&metadataFile];
        BOOL fingerprintMatches = metadataValid && PMZipCacheFingerprintMatches(cachedMtime, cachedSize, currentMtime, currentSize);

        BOOL cacheDirExists = NO;
        BOOL cacheIsDir = NO;
        cacheDirExists = [fm fileExistsAtPath:extractRoot isDirectory:&cacheIsDir] && cacheIsDir;
        NSString *normalizedCachedRoot = cacheDirExists ? [self normalizedSingleTopLevelDirectoryForRoot:extractRoot] : nil;
        BOOL cacheLooksValid = normalizedCachedRoot.length > 0 && [self isDirectoryPresetContainer:normalizedCachedRoot];

        if (PMShouldReuseZipExtractionCache(metadataValid, fingerprintMatches, cacheLooksValid)) {
            FB2K_console_print("projectM: zip-cache=hit");
            return normalizedCachedRoot;
        }

        const char *missReason = "metadata_missing";
        if (metadataFile && !metadataValid) {
            missReason = "metadata_invalid";
        } else if (metadataValid && !fingerprintMatches) {
            missReason = "fingerprint_changed";
        } else if (metadataValid && fingerprintMatches && !cacheLooksValid) {
            missReason = "cache_invalid";
        }

        FB2K_console_print("projectM: zip-cache=miss reason=", missReason);
        [self clearZipCacheAtRoot:extractRoot metadataPath:metadataPath];

        NSString *extractTempRoot = [extractRoot stringByAppendingString:@".tmp"];
        NSError *error = nil;
        if (![fm createDirectoryAtPath:extractTempRoot withIntermediateDirectories:YES attributes:nil error:&error]) {
            FB2K_console_print("projectM: cannot create temporary ZIP extraction path: ", [extractTempRoot UTF8String]);
            return nil;
        }

        CFAbsoluteTime extractionStart = CFAbsoluteTimeGetCurrent();

        try {
            zipfs::init([zipPath UTF8String]);
            zipInitialized = true;

            for (const zipfs::file_info *fi = zipfs::gotofirstfile(); fi; fi = zipfs::gotonextfile()) {
                NSString *entryPath = @(fi->full_name.c_str());
                if (entryPath.length == 0) continue;
                if ([entryPath hasPrefix:@"__MACOSX/"]) continue;

                NSString *outputPath = [extractTempRoot stringByAppendingPathComponent:entryPath];
                if (fi->is_dir) {
                    [fm createDirectoryAtPath:outputPath withIntermediateDirectories:YES attributes:nil error:nil];
                    continue;
                }

                NSString *parentPath = [outputPath stringByDeletingLastPathComponent];
                [fm createDirectoryAtPath:parentPath withIntermediateDirectories:YES attributes:nil error:nil];

                std::string content = zipfs::readfile(fi->full_name);
                NSData *data = content.empty() ? [NSData data] : [NSData dataWithBytes:content.data() length:content.size()];
                if (![data writeToFile:outputPath atomically:NO]) {
                    FB2K_console_print("projectM: failed writing extracted file: ", [outputPath UTF8String]);
                }
            }
        } catch (...) {
            FB2K_console_print("projectM: ZIP extraction failed.");
        }

        BOOL extractedDir = NO;
        if (![fm fileExistsAtPath:extractTempRoot isDirectory:&extractedDir] || !extractedDir) {
            [self clearZipCacheAtRoot:extractRoot metadataPath:metadataPath];
            return nil;
        }

        NSString *normalizedTempRoot = [self normalizedSingleTopLevelDirectoryForRoot:extractTempRoot];
        if (![self isDirectoryPresetContainer:normalizedTempRoot]) {
            FB2K_console_print("projectM: ZIP extraction produced no usable Presets data.");
            [self clearZipCacheAtRoot:extractRoot metadataPath:metadataPath];
            return nil;
        }

        NSError *moveError = nil;
        if (![fm moveItemAtPath:extractTempRoot toPath:extractRoot error:&moveError]) {
            FB2K_console_print("projectM: cannot finalize ZIP extraction cache path.");
            [self clearZipCacheAtRoot:extractRoot metadataPath:metadataPath];
            return nil;
        }

        NSString *normalizedExtractRoot = [self normalizedSingleTopLevelDirectoryForRoot:extractRoot];
        NSInteger extractDurationMs = (NSInteger)((CFAbsoluteTimeGetCurrent() - extractionStart) * 1000.0);
        FB2K_console_print("projectM: zip-cache extracted ms=", pfc::format_int((int64_t)extractDurationMs).c_str());

        if (![self writeZipCacheMetadataAtPath:metadataPath
                                       zipPath:zipPath
                                         mtime:currentMtime
                                      sizeByte:currentSize
                              extractDurationMs:extractDurationMs]) {
            FB2K_console_print("projectM: zip-cache metadata write failed; cache will refresh next startup.");
        }

        return normalizedExtractRoot;
    }
    @catch (NSException *exception) {
        FB2K_console_print("projectM: Objective-C exception in prepareDataDirectoryFromZipAtPath: ", [[exception description] UTF8String]);
        return nil;
    }
    @finally {
        if (zipInitialized) {
            zipfs::done();
        }
    }
}

- (NSString *)resolvedDataDirectoryPathUsedZip:(BOOL *)usedZip {
    if (usedZip) *usedZip = NO;

    NSString *zipPath = [self projectMacOSZipPath];
    NSString *extractedPath = [self prepareDataDirectoryFromZipAtPath:zipPath];
    if (extractedPath.length > 0) {
        if (usedZip) *usedZip = YES;
        return extractedPath;
    }

    NSString *folderPath = [self projectMacOSDataDirectoryPath];
    if ([self isDirectoryPresetContainer:folderPath]) {
        return [folderPath stringByStandardizingPath];
    }

    return nil;
}

- (void)loadDefaultPresetFallback {
    if (!_projectM) return;

    static const char *kBuiltInFallbackPreset =
        "[preset00]\n"
        "fGammaAdj=2.000000\n"
        "fDecay=0.990000\n"
        "fVideoEchoZoom=2.000000\n"
        "fVideoEchoAlpha=0.000000\n"
        "nVideoEchoOrientation=0\n"
        "nWaveMode=0\n"
        "bAdditiveWaves=0\n"
        "bWaveDots=0\n"
        "bModWaveAlphaByVolume=0\n"
        "bMaximizeWaveColor=1\n"
        "bTexWrap=1\n"
        "bDarkenCenter=0\n"
        "bMotionVectorsOn=0\n"
        "nMotionVectorsX=12\n"
        "nMotionVectorsY=9\n"
        "fWaveAlpha=0.500000\n"
        "fWaveScale=71.269997\n"
        "fWaveSmoothing=0.500000\n"
        "fWaveParam=0.000000\n"
        "fModWaveAlphaStart=0.750000\n"
        "fModWaveAlphaEnd=0.950000\n"
        "fWarpAnimSpeed=1.000000\n"
        "fWarpScale=2.853000\n"
        "fZoomExponent=3.600000\n"
        "fShader=0.000000\n"
        "zoom=1.014000\n"
        "rot=-0.020000\n"
        "cx=0.500000\n"
        "cy=0.500000\n"
        "dx=0.000000\n"
        "dy=0.000000\n"
        "warp=0.309000\n"
        "sx=1.000000\n"
        "sy=1.000000\n"
        "wave_r=0.600000\n"
        "wave_g=0.600000\n"
        "wave_b=0.600000\n"
        "wave_x=0.500000\n"
        "wave_y=0.470000\n"
        "per_frame_1=zoom = zoom + 0.023*( 0.60*sin(0.339*time) + 0.40*sin(0.276*time) );\n"
        "per_frame_2=rot = rot + 0.030*( 0.60*sin(0.381*time) + 0.40*sin(0.579*time) );\n"
        "per_pixel_1=rot=rot+0.04*rad*cos(ang*4+time*1.9);\n"
        "bRedBlueStereo=1\n"
        "fRating=5.000000\n";

    try {
        projectm_load_preset_data(_projectM, kBuiltInFallbackPreset, false);
        cfg_preset_name = "projectMacOS.milk";
        [self showPresetOverlayName:@"projectMacOS"];
        FB2K_console_print("projectM: built-in fallback preset loaded.");
    } catch (...) {
        cfg_preset_name = "";
        FB2K_console_print("projectM: built-in fallback preset failed to load.");
    }
}

- (void)loadPresetsFromCurrentSource {
    try {
        @try {
            if (!_projectM) return;

            if (!_playlist) {
                _playlist = projectm_playlist_create(_projectM);
                if (!_playlist) {
                    FB2K_console_print("projectM: projectm_playlist_create() failed.");
                    [self loadDefaultPresetFallback];
                    return;
                }
            }

            projectm_playlist_clear(_playlist);

            projectm_playlist_set_shuffle(_playlist, cfg_preset_shuffle);

            _activePresetsRootPath = nil;

            BOOL loadedFromZip = NO;
            NSString *activeDataDirPath = [self resolvedDataDirectoryPathUsedZip:&loadedFromZip];

            if (activeDataDirPath.length > 0) {
                FB2K_console_print("projectM: loading presets from ", loadedFromZip ? "ZIP source" : "folder source");
                FB2K_console_print("projectM: active preset data path=", [activeDataDirPath UTF8String]);

            NSString *texturesPath = [activeDataDirPath stringByAppendingPathComponent:@"Textures"];
            const char *texPaths[] = {[texturesPath UTF8String], [activeDataDirPath UTF8String]};
            projectm_set_texture_search_paths(_projectM, texPaths, 2);

            NSString *presetsPath = [activeDataDirPath stringByAppendingPathComponent:@"Presets"];
            uint32_t added = [self addPresetsFromPath:presetsPath recursive:YES];
            if (added > 0) {
                _activePresetsRootPath = presetsPath;
            }

            if (added == 0) {
                added = [self addPresetsFromPath:activeDataDirPath recursive:loadedFromZip];
                if (added > 0) {
                    _activePresetsRootPath = activeDataDirPath;
                }
            }

            projectm_playlist_set_retry_count(_playlist, 0);
            projectm_playlist_set_preset_switched_event_callback(_playlist, callbackPresetSwitched, (__bridge void *)self);
            projectm_playlist_set_preset_switch_failed_event_callback(_playlist, callbackPresetSwitchFailed, (__bridge void *)self);

            uint32_t totalPresets = projectm_playlist_size(_playlist);
            int presetIndex = -1;
            auto savedName = cfg_preset_name.get();
            if (savedName.length() > 0 && totalPresets > 0) {
                char **items = projectm_playlist_items(_playlist, 0, totalPresets);
                for (uint32_t i = 0; items && items[i]; ++i) {
                    if ([[@(items[i]) lastPathComponent] isEqualToString:@(savedName.get_ptr())]) {
                        presetIndex = (int)i;
                        break;
                    }
                }
                if (items) projectm_playlist_free_string_array(items);
            }

            if (presetIndex >= 0) {
                projectm_playlist_set_position(_playlist, presetIndex, true);
                [self refreshCurrentPresetName:(uint32_t)presetIndex showOverlay:YES];
            } else if (totalPresets > 0) {
                std::srand((unsigned)std::time(0));
                uint32_t randomIndex = (uint32_t)(std::rand() % totalPresets);
                projectm_playlist_set_position(_playlist, randomIndex, true);
                [self refreshCurrentPresetName:randomIndex showOverlay:YES];
            } else {
                FB2K_console_print("projectM: source found but contains no presets, using default preset.");
                [self loadDefaultPresetFallback];
            }
                return;
            }

            FB2K_console_print("projectM: no data source found. Checked default ZIP and default folder.");
            [self loadDefaultPresetFallback];
        }
        @catch (NSException *exception) {
            FB2K_console_print("projectM: Objective-C exception in loadPresetsFromCurrentSource: ", [[exception description] UTF8String]);
            [self loadDefaultPresetFallback];
        }
    } catch (const std::exception &e) {
        FB2K_console_print("projectM: C++ exception in loadPresetsFromCurrentSource: ", e.what());
        [self loadDefaultPresetFallback];
    } catch (...) {
        FB2K_console_print("projectM: unknown C++ exception in loadPresetsFromCurrentSource");
        [self loadDefaultPresetFallback];
    }
}

- (NSString *)presetsDirectoryPath {
    if (_activePresetsRootPath.length > 0) {
        return _activePresetsRootPath;
    }
    return [[self projectMacOSDataDirectoryPath] stringByAppendingPathComponent:@"Presets"];
}

- (NSString *)currentPresetDisplayName {
    auto savedName = cfg_preset_name.get();
    NSString *savedPresetName = savedName.length() > 0 ? @(savedName.get_ptr()) : nil;
    return PMCurrentPresetDisplayName(savedPresetName);
}

- (void)refreshCurrentPresetName:(uint32_t)index showOverlay:(BOOL)showOverlay {
    if (!_playlist) return;
    char *filename = projectm_playlist_item(_playlist, index);
    if (!filename) return;

    _lastPresetSwitchTimestamp = CFAbsoluteTimeGetCurrent();

    NSString *fullName = @(filename);
    NSString *baseName = [fullName lastPathComponent];
    cfg_preset_name = [baseName UTF8String];

    if (showOverlay) {
        [self showPresetOverlayName:[baseName stringByDeletingPathExtension]];
    }

    projectm_playlist_free_string(filename);
}

- (void)handlePresetLoadFailureForFilename:(NSString *)presetFilename message:(NSString *)message {
    if (!_playlist) return;

    NSString *safePresetName = PMFailedPresetConsoleName(presetFilename);
    NSString *safeReason = PMConsoleReasonOrDefault(message);
    FB2K_console_print("projectM: failed to load preset, skipping: ", [safePresetName UTF8String], " reason=", [safeReason UTF8String]);

    CGLContextObj cglContext = [[self openGLContext] CGLContextObj];
    BOOL contextLocked = NO;

    @try {
        if (cglContext) {
            CGLLockContext(cglContext);
            contextLocked = YES;
            [[self openGLContext] makeCurrentContext];
        }

        uint32_t totalPresets = projectm_playlist_size(_playlist);
        if (totalPresets > 0 && presetFilename.length > 0) {
            NSString *normalizedFailed = [[presetFilename stringByStandardizingPath] stringByResolvingSymlinksInPath];
            char **items = projectm_playlist_items(_playlist, 0, totalPresets);
            uint32_t failedIndex = UINT32_MAX;
            for (uint32_t i = 0; items && items[i]; ++i) {
                NSString *candidatePath = @(items[i]);
                NSString *normalizedCandidate = [[candidatePath stringByStandardizingPath] stringByResolvingSymlinksInPath];
                if (PMPresetPathsMatch(normalizedCandidate, normalizedFailed)) {
                    failedIndex = i;
                    break;
                }
            }
            if (items) projectm_playlist_free_string_array(items);

            if (failedIndex != UINT32_MAX) {
                projectm_playlist_remove_preset(_playlist, failedIndex);
                totalPresets = projectm_playlist_size(_playlist);
            }
        }

        if (PMShouldUseFallbackAfterPresetLoadFailure(totalPresets)) {
            [self loadDefaultPresetFallback];
            return;
        }

        uint32_t randomIndex = (uint32_t)arc4random_uniform(totalPresets);
        projectm_playlist_set_position(_playlist, randomIndex, true);
        [self refreshCurrentPresetName:randomIndex showOverlay:YES];
    }
    @catch (NSException *exception) {
        FB2K_console_print("projectM: Objective-C exception while handling preset load failure: ", [[exception description] UTF8String]);
        [self loadDefaultPresetFallback];
    }
    @finally {
        if (contextLocked) {
            CGLUnlockContext(cglContext);
        }
    }
}

@end

namespace {

static void callbackPresetSwitched(bool is_hard_cut, unsigned int index, void *user_data) {
    (void)is_hard_cut;
    ProjectMView *view = (__bridge ProjectMView *)user_data;
    if (!view || !view->_playlist)
        return;
    [view refreshCurrentPresetName:(uint32_t)index showOverlay:!cfg_preset_shuffle];
}

static void callbackPresetSwitchFailed(const char *preset_filename, const char *message, void *user_data) {
    ProjectMView *view = (__bridge ProjectMView *)user_data;
    if (!view) return;

    NSString *presetName = preset_filename ? @(preset_filename) : nil;
    NSString *failureMessage = message ? @(message) : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        [view handlePresetLoadFailureForFilename:presetName message:failureMessage];
    });
}

} // anonymous namespace
