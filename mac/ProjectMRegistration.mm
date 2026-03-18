#import "stdafx.h"
#import "ProjectMView.h"

#import <atomic>

// Stub for pfc::myassert -- only called when PFC_DEBUG=1 but prebuilt SDK libs are Release
namespace pfc { void myassert(const char*, const char*, unsigned int) {} }

DECLARE_COMPONENT_VERSION("projectMacOS visualizer", "1.0.4",
    "projectMacOS\n\n"
    "Open-source music visualizer for foobar2000 on macOS.\n\n"
    "Full instructions on how to install and use the plugin are available at:\n"
    "https://github.com/gabitoesmiapodo/projectMacOS\n\n"
    "This project is distributed under the GNU Lesser General Public License v2.1.\n"
);

static const GUID guid_cfg_preset_shuffle        = { 0x659c6787, 0x97bb, 0x485b, { 0xa0, 0xfc, 0x45, 0xfb, 0x12, 0xb7, 0x3a, 0xa0 } };
static const GUID guid_cfg_preset_name           = { 0x186c5741, 0x701e, 0x4f2c, { 0xb4, 0x41, 0xe5, 0x57, 0x5c, 0x18, 0xb0, 0xa8 } };
static const GUID guid_cfg_preset_duration       = { 0x48d9b7f5, 0x4446, 0x4ab7, { 0xb8, 0x71, 0xef, 0xc7, 0x59, 0x43, 0xb9, 0xcd } };
static const GUID guid_cfg_preset_favorites      = { 0xa3b47c91, 0x2e5f, 0x4d8a, { 0xb6, 0x03, 0x71, 0xe9, 0xca, 0x2f, 0x58, 0xd1 } };
static const GUID guid_cfg_cycle_favorites_mode  = { 0xd72e4a1f, 0x8c3b, 0x4e92, { 0xa1, 0x5d, 0x30, 0xf8, 0x7c, 0x2b, 0x6e, 0x49 } };
static const GUID guid_cfg_debug_logging       = { 0xb4e91c3a, 0x6d27, 0x4f85, { 0x93, 0xa1, 0xd8, 0x5e, 0x4b, 0x72, 0xf6, 0x0c } };
// Performance
static const GUID guid_cfg_fps_cap               = { 0x7a1b3c5d, 0xe2f4, 0x4a68, { 0x91, 0xb3, 0xc5, 0xd7, 0xe9, 0xf1, 0x23, 0x45 } };
static const GUID guid_cfg_idle_fps              = { 0x8b2c4d6e, 0xf3a5, 0x4b79, { 0xa2, 0xc4, 0xd6, 0xe8, 0xfa, 0x12, 0x34, 0x56 } };
static const GUID guid_cfg_resolution_scale      = { 0x9c3d5e7f, 0xa4b6, 0x4c8a, { 0xb3, 0xd5, 0xe7, 0xf9, 0x1b, 0x23, 0x45, 0x67 } };
static const GUID guid_cfg_vsync                 = { 0xad4e6f80, 0xb5c7, 0x4d9b, { 0xc4, 0xe6, 0xf8, 0x0a, 0x2c, 0x34, 0x56, 0x78 } };
static const GUID guid_cfg_mesh_quality          = { 0xbe5f7091, 0xc6d8, 0x4eac, { 0xd5, 0xf7, 0x09, 0x1b, 0x3d, 0x45, 0x67, 0x89 } };
static const GUID guid_cfg_auto_pause            = { 0xcf608102, 0xd7e9, 0x4fbd, { 0xe6, 0x08, 0x1a, 0x2c, 0x4e, 0x56, 0x78, 0x9a } };
// Transitions
static const GUID guid_cfg_soft_cut_duration     = { 0xd0719213, 0xe8fa, 0x40ce, { 0xf7, 0x19, 0x2b, 0x3d, 0x5f, 0x67, 0x89, 0xab } };
static const GUID guid_cfg_hard_cuts             = { 0xe1820324, 0xf90b, 0x41df, { 0x08, 0x2a, 0x3c, 0x4e, 0x60, 0x78, 0x9a, 0xbc } };
static const GUID guid_cfg_hard_cut_sensitivity  = { 0xf2931435, 0x0a1c, 0x42e0, { 0x19, 0x3b, 0x4d, 0x5f, 0x71, 0x89, 0xab, 0xcd } };
static const GUID guid_cfg_duration_randomization = { 0x14b53657, 0x2c3e, 0x4402, { 0x3b, 0x5d, 0x6f, 0x71, 0x93, 0xab, 0xcd, 0xef } };
// Visualization
static const GUID guid_cfg_beat_sensitivity      = { 0x25c64768, 0x3d4f, 0x4513, { 0x4c, 0x6e, 0x70, 0x82, 0xa4, 0xbc, 0xde, 0xf0 } };
static const GUID guid_cfg_aspect_correction     = { 0x36d75879, 0x4e50, 0x4624, { 0x5d, 0x7f, 0x81, 0x93, 0xb5, 0xcd, 0xef, 0x01 } };
// Presets
static const GUID guid_cfg_custom_presets_folder = { 0x690a8bac, 0x7183, 0x4957, { 0x80, 0xa2, 0xb4, 0xc6, 0xe8, 0xf0, 0x12, 0x34 } };
static const GUID guid_cfg_preset_sort_order     = { 0x7a1b9cbd, 0x8294, 0x4a68, { 0x91, 0xb3, 0xc5, 0xd7, 0xf9, 0x01, 0x23, 0x45 } };

cfg_bool cfg_preset_shuffle(guid_cfg_preset_shuffle, false);
cfg_string cfg_preset_name(guid_cfg_preset_name, "");
cfg_int cfg_preset_duration(guid_cfg_preset_duration, 30);
cfg_string cfg_preset_favorites(guid_cfg_preset_favorites, "");
cfg_int cfg_cycle_favorites_mode(guid_cfg_cycle_favorites_mode, 0);
cfg_bool cfg_debug_logging(guid_cfg_debug_logging, false);
// Performance
cfg_int cfg_fps_cap(guid_cfg_fps_cap, 60);
cfg_int cfg_idle_fps(guid_cfg_idle_fps, 30);
cfg_int cfg_resolution_scale(guid_cfg_resolution_scale, 1);
cfg_bool cfg_vsync(guid_cfg_vsync, true);
cfg_int cfg_mesh_quality(guid_cfg_mesh_quality, 1);
cfg_bool cfg_auto_pause(guid_cfg_auto_pause, false);
// Transitions
cfg_int cfg_soft_cut_duration(guid_cfg_soft_cut_duration, 3);
cfg_bool cfg_hard_cuts(guid_cfg_hard_cuts, false);
cfg_int cfg_hard_cut_sensitivity(guid_cfg_hard_cut_sensitivity, 1);
cfg_int cfg_duration_randomization(guid_cfg_duration_randomization, 0);
// Visualization
cfg_int cfg_beat_sensitivity(guid_cfg_beat_sensitivity, 1);
cfg_bool cfg_aspect_correction(guid_cfg_aspect_correction, true);
// Presets
cfg_string cfg_custom_presets_folder(guid_cfg_custom_presets_folder, "");
cfg_int cfg_preset_sort_order(guid_cfg_preset_sort_order, 0);

const void *kPresetMenuPathKey = &kPresetMenuPathKey;

std::atomic<uint32_t> g_settingsGeneration(0);
std::atomic<bool> g_forcePresetReload{false};

namespace {

std::atomic<bool> g_musicPlaybackActive(false);

class playback_state_callback : public play_callback_static {
public:
    unsigned get_flags() override {
        return flag_on_playback_starting | flag_on_playback_stop | flag_on_playback_pause;
    }

    void on_playback_starting(play_control::t_track_command p_command, bool p_paused) override {
        (void)p_command;
        g_musicPlaybackActive.store(!p_paused, std::memory_order_relaxed);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:PMPlaybackStateChangedNotification object:nil];
        });
    }

    void on_playback_new_track(metadb_handle_ptr p_track) override {
        (void)p_track;
    }

    void on_playback_stop(play_control::t_stop_reason p_reason) override {
        (void)p_reason;
        g_musicPlaybackActive.store(false, std::memory_order_relaxed);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:PMPlaybackStateChangedNotification object:nil];
        });
    }

    void on_playback_seek(double p_time) override {
        (void)p_time;
    }

    void on_playback_pause(bool p_state) override {
        g_musicPlaybackActive.store(!p_state, std::memory_order_relaxed);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:PMPlaybackStateChangedNotification object:nil];
        });
    }

    void on_playback_edited(metadb_handle_ptr p_track) override {
        (void)p_track;
    }

    void on_playback_dynamic_info(const file_info &p_info) override {
        (void)p_info;
    }

    void on_playback_dynamic_info_track(const file_info &p_info) override {
        (void)p_info;
    }

    void on_playback_time(double p_time) override {
        (void)p_time;
    }

    void on_volume_change(float p_new_val) override {
        (void)p_new_val;
    }
};

play_callback_static_factory_t<playback_state_callback> g_playback_state_callback_factory;

} // anonymous namespace

bool PMIsMusicPlaybackActive(void) {
    return g_musicPlaybackActive.load(std::memory_order_relaxed);
}

void PMSyncMusicPlaybackState(void) {
    static_api_ptr_t<play_control> playbackControl;
    bool isActive = playbackControl->is_playing() && !playbackControl->is_paused();
    g_musicPlaybackActive.store(isActive, std::memory_order_relaxed);
}

void PMSettingsDidChange(void) {
    g_settingsGeneration.fetch_add(1, std::memory_order_relaxed);
}

NSString * const PMPlaybackStateChangedNotification = @"PMPlaybackStateChanged";

// MARK: - View Controller

@interface ProjectMViewController : NSViewController
@end

@implementation ProjectMViewController

- (void)loadView {
    self.view = [[ProjectMView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
}

@end

// MARK: - foobar2000 UI Element Registration

namespace {

class ui_element_projectMacOS_mac : public ui_element_mac {
public:
    service_ptr instantiate(service_ptr arg) override {
        ProjectMViewController *vc = [[ProjectMViewController alloc] init];
        return fb2k::wrapNSObject(vc);
    }

    bool match_name(const char *name) override {
        return strcmp(name, "projectMacOS") == 0;
    }

    fb2k::stringRef get_name() override {
        return fb2k::makeString("projectMacOS");
    }

    GUID get_guid() override {
        return { 0x489c7f0e, 0x2073, 0x442b, {0xaf, 0x4a, 0x00, 0x51, 0x99, 0x12, 0xaf, 0x70 } };
    }
};

FB2K_SERVICE_FACTORY(ui_element_projectMacOS_mac);

} // anonymous namespace
