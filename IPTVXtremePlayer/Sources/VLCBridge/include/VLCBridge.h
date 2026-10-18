/*
 * VLCBridge.h
 * A small, stable C wrapper around libVLC 3.x, so the Swift layer never has to
 * import VLC's own headers. All player handles are opaque.
 */
#ifndef VLCBRIDGE_H
#define VLCBRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct VB_Player VB_Player;

/* Playback state mirrors libvlc_state_t. */
typedef enum {
    VB_STATE_NOTHING = 0,
    VB_STATE_OPENING = 1,
    VB_STATE_BUFFERING = 2,
    VB_STATE_PLAYING = 3,
    VB_STATE_PAUSED = 4,
    VB_STATE_STOPPED = 5,
    VB_STATE_ENDED = 6,
    VB_STATE_ERROR = 7
} VB_State;

/* Initialize the shared libVLC engine exactly once.
 * plugin_path: directory containing VLC plugins, or NULL to use VLC defaults.
 * Returns true on success. Safe to call multiple times (no-op after first). */
bool vb_global_init(const char *plugin_path, bool verbose);

/* libVLC human-readable version string (static, do not free). */
const char *vb_version(void);

VB_Player *vb_player_create(void);
void vb_player_destroy(VB_Player *p);

/* Attach rendering to an NSView* (pass the pointer via Unmanaged.toOpaque()). */
void vb_player_set_drawable(VB_Player *p, void *nsview);

/* Load a media URL/MRL with optional libVLC per-media options
 * (e.g. ":network-caching=1500"). */
void vb_player_set_media_url(VB_Player *p, const char *url,
                             const char *const *options, int n_options);

void vb_player_play(VB_Player *p);
void vb_player_set_paused(VB_Player *p, bool paused);
void vb_player_stop(VB_Player *p);

bool vb_player_is_playing(VB_Player *p);
VB_State vb_player_get_state(VB_Player *p);
bool vb_player_is_seekable(VB_Player *p);

int64_t vb_player_get_time(VB_Player *p);    /* ms */
int64_t vb_player_get_length(VB_Player *p);  /* ms, -1/0 if unknown (live) */
void vb_player_set_time(VB_Player *p, int64_t ms);
float vb_player_get_position(VB_Player *p);  /* 0..1 */
void vb_player_set_position(VB_Player *p, float pos);

void vb_player_set_volume(VB_Player *p, int volume); /* 0..200 */
int vb_player_get_volume(VB_Player *p);
void vb_player_set_mute(VB_Player *p, bool mute);
bool vb_player_get_mute(VB_Player *p);

void vb_player_set_rate(VB_Player *p, float rate);
/* ratio like "16:9", "4:3", or NULL to reset to source. */
void vb_player_set_aspect_ratio(VB_Player *p, const char *ratio);

/* Track enumeration. Walk by index; writes id and UTF-8 name into caller buffer. */
int vb_player_audio_track_count(VB_Player *p);
int vb_player_spu_count(VB_Player *p);
bool vb_player_audio_track_at(VB_Player *p, int index, int *out_id,
                              char *name_buf, int buf_len);
bool vb_player_spu_at(VB_Player *p, int index, int *out_id,
                      char *name_buf, int buf_len);
int vb_player_get_audio_track(VB_Player *p);
void vb_player_set_audio_track(VB_Player *p, int id);
int vb_player_get_spu(VB_Player *p);
void vb_player_set_spu(VB_Player *p, int id);

#ifdef __cplusplus
}
#endif

#endif /* VLCBRIDGE_H */
