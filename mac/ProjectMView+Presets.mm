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
    return PMZipExtractionCachePath();
}

- (NSString *)zipExtractionMetadataPath {
    return PMZipExtractionMetadataPath();
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

    uint32_t added = 0;
    for (NSString *candidatePath in candidatePaths) {
        bool fileAdded = false;
        try {
            fileAdded = projectm_playlist_add_preset(_playlist, [candidatePath UTF8String], false);
        } catch (...) {
            PMLog("projectM: exception while adding preset path, skipping: ", [candidatePath UTF8String]);
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
            PMLogError("projectM: zip-cache cannot stat ZIP for fingerprinting.");
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
            PMLog("projectM: zip-cache=hit");
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

        PMLog("projectM: zip-cache=miss reason=", missReason);
        [self clearZipCacheAtRoot:extractRoot metadataPath:metadataPath];

        NSString *extractTempRoot = [extractRoot stringByAppendingString:@".tmp"];
        NSError *error = nil;
        if (![fm createDirectoryAtPath:extractTempRoot withIntermediateDirectories:YES attributes:nil error:&error]) {
            PMLogError("projectM: cannot create temporary ZIP extraction path: ", [extractTempRoot UTF8String]);
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
                    PMLogError("projectM: failed writing extracted file: ", [outputPath UTF8String]);
                }
            }
        } catch (...) {
            PMLogError("projectM: ZIP extraction failed.");
        }

        BOOL extractedDir = NO;
        if (![fm fileExistsAtPath:extractTempRoot isDirectory:&extractedDir] || !extractedDir) {
            [self clearZipCacheAtRoot:extractRoot metadataPath:metadataPath];
            return nil;
        }

        NSString *normalizedTempRoot = [self normalizedSingleTopLevelDirectoryForRoot:extractTempRoot];
        if (![self isDirectoryPresetContainer:normalizedTempRoot]) {
            PMLogError("projectM: ZIP extraction produced no usable Presets data.");
            [self clearZipCacheAtRoot:extractRoot metadataPath:metadataPath];
            return nil;
        }

        NSError *moveError = nil;
        if (![fm moveItemAtPath:extractTempRoot toPath:extractRoot error:&moveError]) {
            PMLogError("projectM: cannot finalize ZIP extraction cache path.");
            [self clearZipCacheAtRoot:extractRoot metadataPath:metadataPath];
            return nil;
        }

        NSString *normalizedExtractRoot = [self normalizedSingleTopLevelDirectoryForRoot:extractRoot];
        NSInteger extractDurationMs = (NSInteger)((CFAbsoluteTimeGetCurrent() - extractionStart) * 1000.0);
        PMLog("projectM: zip-cache extracted ms=", pfc::format_int((int64_t)extractDurationMs).c_str());

        if (![self writeZipCacheMetadataAtPath:metadataPath
                                       zipPath:zipPath
                                         mtime:currentMtime
                                      sizeByte:currentSize
                              extractDurationMs:extractDurationMs]) {
            PMLog("projectM: zip-cache metadata write failed; cache will refresh next startup.");
        }

        return normalizedExtractRoot;
    }
    @catch (NSException *exception) {
        PMLogError("projectM: Objective-C exception in prepareDataDirectoryFromZipAtPath: ", [[exception description] UTF8String]);
        return nil;
    }
    @finally {
        if (zipInitialized) {
            zipfs::done();
        }
    }
}

- (NSString *)resolvedDataDirectoryPathUsedZip:(BOOL *)usedZip outError:(NSString **)outError {
    if (usedZip) *usedZip = NO;
    if (outError) *outError = nil;

    // Check custom presets source first (folder or .zip)
    auto customFolder = cfg_custom_presets_folder.get();
    NSString *customPath = customFolder.length() > 0 ? @(customFolder.get_ptr()) : nil;
    if (customPath.length > 0) {
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL isDir = NO;
        BOOL exists = [fm fileExistsAtPath:customPath isDirectory:&isDir];

        if (exists && !isDir && [[customPath.pathExtension lowercaseString] isEqualToString:@"zip"]) {
            // Custom ZIP source
            NSString *extractedPath = [self prepareDataDirectoryFromZipAtPath:customPath];
            if (extractedPath.length > 0) {
                if (usedZip) *usedZip = YES;
                PMLog("projectM: using custom presets ZIP: ", [customPath UTF8String]);
                return extractedPath;
            }
            PMLogError("projectM: custom presets ZIP extraction failed: ", [customPath UTF8String]);
            if (outError) *outError = @"ZIP contains no usable presets.";
            return nil;
        } else if (exists && isDir) {
            // Custom folder source -- validated the same way as an extracted ZIP:
            // isDirectoryPresetContainer checks for a Presets/ subfolder with .milk files.
            if ([self isDirectoryPresetContainer:customPath]) {
                PMLog("projectM: using custom presets folder: ", [customPath UTF8String]);
                return [customPath stringByStandardizingPath];
            }
            PMLogError("projectM: custom folder not a valid preset source: ", [customPath UTF8String]);
            if (outError) *outError = @"No Presets folder found.";
            return nil;
        } else {
            PMLogError("projectM: custom presets folder not found: ", [customPath UTF8String]);
            if (outError) *outError = @"Source not found.";
            return nil;
        }
    }

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
        PMLog("projectM: built-in fallback preset loaded.");
    } catch (...) {
        cfg_preset_name = "";
        PMLogError("projectM: built-in fallback preset failed to load.");
    }
}

- (void)buildPresetPathIndex {
    if (!_playlist) {
        _presetPathIndex = nil;
        return;
    }

    uint32_t count = projectm_playlist_size(_playlist);
    if (count == 0) {
        _presetPathIndex = nil;
        return;
    }

    char **items = projectm_playlist_items(_playlist, 0, count);
    if (!items) {
        _presetPathIndex = nil;
        return;
    }

    NSMutableDictionary<NSString *, NSNumber *> *index = [NSMutableDictionary dictionaryWithCapacity:count];
    for (uint32_t i = 0; items[i]; ++i) {
        NSString *path = @(items[i]);
        NSString *normalized = PMNormalizePath(path);
        if (normalized.length > 0) {
            index[normalized] = @(i);
        }
    }
    projectm_playlist_free_string_array(items);

    _presetPathIndex = [index copy];
    PMLog("projectM: built preset path index with ", pfc::format_int(index.count).c_str(), " entries");
}

- (void)loadPresetsFromCurrentSource {
    try {
        NSString *errorString = nil;
        @try {
            if (!_projectM) return;

            if (!_playlist) {
                _playlist = projectm_playlist_create(_projectM);
                if (!_playlist) {
                    PMLogError("projectM: projectm_playlist_create() failed.");
                    [self loadDefaultPresetFallback];
                    return;
                }
            }

            projectm_playlist_clear(_playlist);

            projectm_playlist_set_shuffle(_playlist, cfg_preset_shuffle);

            _activePresetsRootPath = nil;
            _presetPathIndex = nil;

            BOOL loadedFromZip = NO;
            NSString *activeDataDirPath = [self resolvedDataDirectoryPathUsedZip:&loadedFromZip outError:&errorString];

            if (activeDataDirPath.length > 0) {
                PMLog("projectM: loading presets from ", loadedFromZip ? "ZIP source" : "folder source");
                PMLog("projectM: active preset data path=", [activeDataDirPath UTF8String]);

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

                projectm_playlist_set_preset_switched_event_callback(_playlist, callbackPresetSwitched, (__bridge void *)self);
                projectm_playlist_set_preset_switch_failed_event_callback(_playlist, callbackPresetSwitchFailed, (__bridge void *)self);

                // Apply sort order
                int sortOrder = PMValidatedPresetSortOrder((int)cfg_preset_sort_order);
                projectm_playlist_sort_order sortDirection = (sortOrder == 0) ? SORT_ORDER_ASCENDING : SORT_ORDER_DESCENDING;
                projectm_playlist_sort(_playlist, 0, projectm_playlist_size(_playlist), SORT_PREDICATE_FILENAME_ONLY, sortDirection);

                // Compute fingerprint for preset index cache
                NSString *fingerprint = nil;
                {
                    if (loadedFromZip) {
                        NSString *zipPathForFingerprint = nil;
                        auto customFolder = cfg_custom_presets_folder.get();
                        NSString *cp = customFolder.length() > 0 ? @(customFolder.get_ptr()) : nil;
                        if (cp.length > 0 && [[cp.pathExtension lowercaseString] isEqualToString:@"zip"])
                            zipPathForFingerprint = [cp stringByStandardizingPath];
                        else
                            zipPathForFingerprint = [self projectMacOSZipPath];
                        NSTimeInterval zipMtime = 0;
                        uint64_t zipSize = 0;
                        if ([self zipFingerprintForPath:zipPathForFingerprint mtime:&zipMtime sizeByte:&zipSize]) {
                            fingerprint = PMPresetIndexFingerprint(@"zip", zipMtime, zipSize, sortOrder);
                        }
                    } else {
                        NSString *folderPath = _activePresetsRootPath;
                        if (folderPath.length > 0) {
                            NSError *statError = nil;
                            NSDictionary<NSFileAttributeKey, id> *attrs =
                                [[NSFileManager defaultManager] attributesOfItemAtPath:folderPath error:&statError];
                            if (attrs && !statError) {
                                NSTimeInterval folderMtime = [attrs[NSFileModificationDate] timeIntervalSince1970];
                                uint64_t presetCount = projectm_playlist_size(_playlist);
                                fingerprint = PMPresetIndexFingerprint(@"folder", folderMtime, presetCount, sortOrder);
                            }
                        }
                    }
                }

                // Try to read preset index cache
                BOOL cacheHit = NO;
                if (fingerprint.length > 0) {
                    NSString *cachePath = PMPresetIndexCachePath();
                    NSData *cacheData = [NSData dataWithContentsOfFile:cachePath options:NSDataReadingMappedIfSafe error:nil];
                    if (cacheData) {
                        id payload = [NSJSONSerialization JSONObjectWithData:cacheData options:0 error:nil];
                        if ([payload isKindOfClass:[NSDictionary class]]) {
                            NSDictionary *cacheDict = (NSDictionary *)payload;
                            NSNumber *schemaVersion = cacheDict[@"schema_version"];
                            NSString *cachedFP = cacheDict[@"source_fingerprint"];
                            NSNumber *cachedCountNum = cacheDict[@"preset_count"];
                            NSDictionary *indexDict = cacheDict[@"index"];

                            if ([schemaVersion isKindOfClass:[NSNumber class]] && schemaVersion.integerValue == 1 &&
                                [cachedFP isKindOfClass:[NSString class]] &&
                                [cachedCountNum isKindOfClass:[NSNumber class]] &&
                                [indexDict isKindOfClass:[NSDictionary class]]) {
                                uint32_t playlistSize = projectm_playlist_size(_playlist);
                                NSUInteger cachedCount = cachedCountNum.unsignedIntegerValue;
                                if (PMPresetIndexShouldReuseCache(cachedFP, fingerprint, cachedCount, playlistSize)) {
                                    // Deserialize index
                                    NSMutableDictionary<NSString *, NSNumber *> *loadedIndex =
                                        [NSMutableDictionary dictionaryWithCapacity:indexDict.count];
                                    for (NSString *key in indexDict) {
                                        id val = indexDict[key];
                                        if ([key isKindOfClass:[NSString class]] && [val isKindOfClass:[NSNumber class]]) {
                                            loadedIndex[key] = (NSNumber *)val;
                                        }
                                    }
                                    _presetPathIndex = [loadedIndex copy];
                                    PMLog("projectM: preset-index cache=hit");
                                    cacheHit = YES;
                                }
                            }
                        }
                    }
                }

                if (!cacheHit) {
                    PMLog("projectM: preset-index cache=miss");
                    [self buildPresetPathIndex];

                    // Write cache after successful build
                    if (_presetPathIndex != nil && fingerprint.length > 0) {
                        uint32_t playlistSize = projectm_playlist_size(_playlist);
                        NSDictionary *cachePayload = @{
                            @"schema_version": @1,
                            @"source_fingerprint": fingerprint,
                            @"preset_count": @(playlistSize),
                            @"index": _presetPathIndex,
                        };
                        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:cachePayload options:0 error:nil];
                        if (jsonData) {
                            NSString *cachePath = PMPresetIndexCachePath();
                            NSFileManager *fm = [NSFileManager defaultManager];
                            NSString *cacheDir = [cachePath stringByDeletingLastPathComponent];
                            [fm createDirectoryAtPath:cacheDir withIntermediateDirectories:YES attributes:nil error:nil];
                            NSString *tmpPath = [cachePath stringByAppendingString:@".tmp"];
                            [fm removeItemAtPath:tmpPath error:nil];
                            NSError *writeError = nil;
                            if ([jsonData writeToFile:tmpPath options:0 error:&writeError]) {
                                [fm removeItemAtPath:cachePath error:nil];
                                NSError *moveError = nil;
                                if (![fm moveItemAtPath:tmpPath toPath:cachePath error:&moveError]) {
                                    [fm removeItemAtPath:tmpPath error:nil];
                                    PMLog("projectM: preset-index cache write failed (rename): ",
                                          [[moveError localizedDescription] UTF8String]);
                                }
                            } else {
                                [fm removeItemAtPath:tmpPath error:nil];
                                PMLog("projectM: preset-index cache write failed: ",
                                      [[writeError localizedDescription] UTF8String]);
                            }
                        }
                    }
                }

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
                    projectm_playlist_set_position(_playlist, presetIndex, PMUseHardCutTransitions());
                    [self refreshCurrentPresetName:(uint32_t)presetIndex];
                } else if (totalPresets > 0) {
                    std::srand((unsigned)std::time(0));
                    uint32_t randomIndex = (uint32_t)(std::rand() % totalPresets);
                    projectm_playlist_set_position(_playlist, randomIndex, PMUseHardCutTransitions());
                    [self refreshCurrentPresetName:randomIndex];
                } else {
                    PMLogError("projectM: source found but contains no presets, using default preset.");
                    [self loadDefaultPresetFallback];
                }
                return;
            }

            PMLogError("projectM: no data source found. Checked default ZIP and default folder.");
            [self loadDefaultPresetFallback];
        }
        @catch (NSException *exception) {
            PMLogError("projectM: Objective-C exception in loadPresetsFromCurrentSource: ", [[exception description] UTF8String]);
            [self loadDefaultPresetFallback];
        }
        @finally {
            NSDictionary *userInfo = errorString.length > 0 ? @{@"error": errorString} : @{};
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:PMPresetsDidReloadNotification
                                                                    object:nil
                                                                  userInfo:userInfo];
            });
        }
    } catch (const std::exception &e) {
        PMLogError("projectM: C++ exception in loadPresetsFromCurrentSource: ", e.what());
        [self loadDefaultPresetFallback];
    } catch (...) {
        PMLogError("projectM: unknown C++ exception in loadPresetsFromCurrentSource");
        [self loadDefaultPresetFallback];
    }
}

- (void)resortCurrentPlaylist {
    if (!_playlist) return;

    uint32_t count = projectm_playlist_size(_playlist);
    if (count == 0) return;

    int sortOrder = PMValidatedPresetSortOrder((int)cfg_preset_sort_order);
    projectm_playlist_sort_order sortDirection = (sortOrder == 0) ? SORT_ORDER_ASCENDING : SORT_ORDER_DESCENDING;
    projectm_playlist_sort(_playlist, 0, count, SORT_PREDICATE_FILENAME_ONLY, sortDirection);

    [self buildPresetPathIndex];

    // Refresh current preset identity (index changed after sort)
    uint32_t currentPos = projectm_playlist_get_position(_playlist);
    if (currentPos < count) {
        [self refreshCurrentPresetName:currentPos];
    }

    // Invalidate on-disk cache (fingerprint includes sort order)
    [[NSFileManager defaultManager] removeItemAtPath:PMPresetIndexCachePath() error:nil];

    PMLog("projectM: re-sorted ", pfc::format_int(count).c_str(), " presets");
}

- (void)deletePresetIndexCache {
    [[NSFileManager defaultManager] removeItemAtPath:PMPresetIndexCachePath() error:nil];
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

- (void)refreshCurrentPresetName:(uint32_t)index {
    if (!_playlist) return;
    char *filename = projectm_playlist_item(_playlist, index);
    if (!filename) return;

    _lastPresetSwitchTimestamp = CFAbsoluteTimeGetCurrent();

    NSString *fullName = @(filename);
    NSString *baseName = [fullName lastPathComponent];

    cfg_preset_name = [baseName UTF8String];
    projectm_playlist_free_string(filename);

    __weak ProjectMView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        ProjectMView *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_currentPresetPath = fullName;
    });
}

- (void)handlePresetLoadFailureForFilename:(NSString *)presetFilename message:(NSString *)message {
    if (!_playlist) return;

    NSString *safePresetName = PMFailedPresetConsoleName(presetFilename);
    NSString *safeReason = PMConsoleReasonOrDefault(message);
    PMLogError("projectM: failed to load preset, skipping: ", [safePresetName UTF8String], " reason=", [safeReason UTF8String]);

    CGLContextObj cglContext = [[self openGLContext] CGLContextObj];
    BOOL contextLocked = NO;

    @try {
        if (cglContext) {
            CGLLockContext(cglContext);
            contextLocked = YES;
            [[self openGLContext] makeCurrentContext];
        }

        uint32_t totalPresets = projectm_playlist_size(_playlist);
        BOOL presetRemoved = NO;
        if (totalPresets > 0 && presetFilename.length > 0) {
            NSString *normalizedFailed = PMNormalizePath(presetFilename);
            uint32_t failedIndex = UINT32_MAX;

            // O(1) dictionary lookup (exact match)
            NSNumber *cachedIndex = _presetPathIndex[normalizedFailed];
            if (cachedIndex && cachedIndex.unsignedIntValue < totalPresets) {
                failedIndex = cachedIndex.unsignedIntValue;
            }

            // Fallback: linear scan with fuzzy matching (PMPresetPathsMatch)
            if (failedIndex == UINT32_MAX) {
                char **items = projectm_playlist_items(_playlist, 0, totalPresets);
                for (uint32_t i = 0; items && items[i]; ++i) {
                    NSString *candidatePath = @(items[i]);
                    NSString *normalizedCandidate = PMNormalizePath(candidatePath);
                    if (PMPresetPathsMatch(normalizedCandidate, normalizedFailed)) {
                        failedIndex = i;
                        break;
                    }
                }
                if (items) projectm_playlist_free_string_array(items);
            }

            if (failedIndex != UINT32_MAX) {
                projectm_playlist_remove_preset(_playlist, failedIndex);
                totalPresets = projectm_playlist_size(_playlist);
                presetRemoved = YES;
            }
        }

        if (PMShouldUseFallbackAfterPresetLoadFailure(totalPresets)) {
            [self loadDefaultPresetFallback];
            return;
        }

        uint32_t randomIndex = (uint32_t)arc4random_uniform(totalPresets);
        projectm_playlist_set_position(_playlist, randomIndex, PMUseHardCutTransitions());
        [self refreshCurrentPresetName:randomIndex];
        if (presetRemoved) {
            [self buildPresetPathIndex];
        }
    }
    @catch (NSException *exception) {
        PMLogError("projectM: Objective-C exception while handling preset load failure: ", [[exception description] UTF8String]);
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
    [view refreshCurrentPresetName:(uint32_t)index];
    char *name = projectm_playlist_item(view->_playlist, index);
    if (name) {
        PMLog("projectM: preset switched to ", [[[@(name) lastPathComponent] stringByDeletingPathExtension] UTF8String]);
        projectm_playlist_free_string(name);
    }
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
