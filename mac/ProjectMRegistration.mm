#import "stdafx.h"
#import "ProjectMView.h"

#import <atomic>

// Stub for pfc::myassert -- only called when PFC_DEBUG=1 but prebuilt SDK libs are Release
namespace pfc { void myassert(const char*, const char*, unsigned int) {} }

DECLARE_COMPONENT_VERSION("projectMacOS visualizer", "1.0.1",
    "projectMacOS\n\n"
    "Open-source music visualizer for foobar2000 on macOS.\n\n"
    "Full instructions on how to install and use the plugin are available at:\n"
    "https://github.com/gabitoesmiapodo/projectMacOS\n\n"
    "This project is distributed under the GNU Lesser General Public License v2.1.\n"
);

static const GUID guid_cfg_preset_shuffle  = { 0x659c6787, 0x97bb, 0x485b, { 0xa0, 0xfc, 0x45, 0xfb, 0x12, 0xb7, 0x3a, 0xa0 } };
static const GUID guid_cfg_preset_name     = { 0x186c5741, 0x701e, 0x4f2c, { 0xb4, 0x41, 0xe5, 0x57, 0x5c, 0x18, 0xb0, 0xa8 } };
static const GUID guid_cfg_preset_duration  = { 0x48d9b7f5, 0x4446, 0x4ab7, { 0xb8, 0x71, 0xef, 0xc7, 0x59, 0x43, 0xb9, 0xcd } };
static const GUID guid_cfg_preset_favorites = { 0xa3b47c91, 0x2e5f, 0x4d8a, { 0xb6, 0x03, 0x71, 0xe9, 0xca, 0x2f, 0x58, 0xd1 } };

cfg_bool cfg_preset_shuffle(guid_cfg_preset_shuffle, false);
cfg_string cfg_preset_name(guid_cfg_preset_name, "");
cfg_int cfg_preset_duration(guid_cfg_preset_duration, 30);
cfg_string cfg_preset_favorites(guid_cfg_preset_favorites, "");

const void *kPresetMenuPathKey = &kPresetMenuPathKey;

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
    }

    void on_playback_new_track(metadb_handle_ptr p_track) override {
        (void)p_track;
    }

    void on_playback_stop(play_control::t_stop_reason p_reason) override {
        (void)p_reason;
        g_musicPlaybackActive.store(false, std::memory_order_relaxed);
    }

    void on_playback_seek(double p_time) override {
        (void)p_time;
    }

    void on_playback_pause(bool p_state) override {
        g_musicPlaybackActive.store(!p_state, std::memory_order_relaxed);
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
