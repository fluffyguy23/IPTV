#include "VLCBridge.h"

#include <stdlib.h>
#include <string.h>
#include <vlc/vlc.h>

/* One shared engine instance for the whole app. */
static libvlc_instance_t *g_vlc = NULL;

struct VB_Player {
    libvlc_media_player_t *mp;
};

bool vb_global_init(const char *plugin_path, bool verbose) {
    if (g_vlc != NULL) {
        return true;
    }
    if (plugin_path != NULL && plugin_path[0] != '\0') {
        /* Tell libVLC where to find its plugins when embedded. */
        setenv("VLC_PLUGIN_PATH", plugin_path, 1);
    }
    const char *args[8];
    int n = 0;
    args[n++] = "--no-video-title-show";
    args[n++] = "--no-sub-autodetect-file";
    args[n++] = "--no-osd";
    if (!verbose) {
        args[n++] = "--quiet";
    } else {
        args[n++] = "--verbose=2";
    }
    g_vlc = libvlc_new(n, args);
    return g_vlc != NULL;
}

const char *vb_version(void) {
    return libvlc_get_version();
}

VB_Player *vb_player_create(void) {
    if (g_vlc == NULL) {
        return NULL;
    }
    VB_Player *p = (VB_Player *)calloc(1, sizeof(VB_Player));
    if (p == NULL) {
        return NULL;
    }
    p->mp = libvlc_media_player_new(g_vlc);
    if (p->mp == NULL) {
        free(p);
        return NULL;
    }
    return p;
}

void vb_player_destroy(VB_Player *p) {
    if (p == NULL) {
        return;
    }
    if (p->mp != NULL) {
        libvlc_media_player_stop(p->mp);
        libvlc_media_player_release(p->mp);
    }
    free(p);
}

void vb_player_set_drawable(VB_Player *p, void *nsview) {
    if (p == NULL || p->mp == NULL) {
        return;
    }
    libvlc_media_player_set_nsobject(p->mp, nsview);
}

void vb_player_set_media_url(VB_Player *p, const char *url,
                             const char *const *options, int n_options) {
    if (p == NULL || p->mp == NULL || g_vlc == NULL || url == NULL) {
        return;
    }
    libvlc_media_t *media = libvlc_media_new_location(g_vlc, url);
    if (media == NULL) {
        return;
    }
    for (int i = 0; i < n_options; i++) {
        if (options[i] != NULL) {
            libvlc_media_add_option(media, options[i]);
        }
    }
    libvlc_media_player_set_media(p->mp, media);
    libvlc_media_release(media);
}

void vb_player_play(VB_Player *p) {
    if (p && p->mp) libvlc_media_player_play(p->mp);
}

void vb_player_set_paused(VB_Player *p, bool paused) {
    if (p && p->mp) libvlc_media_player_set_pause(p->mp, paused ? 1 : 0);
}

void vb_player_stop(VB_Player *p) {
    if (p && p->mp) libvlc_media_player_stop(p->mp);
}

bool vb_player_is_playing(VB_Player *p) {
    return (p && p->mp) ? libvlc_media_player_is_playing(p->mp) != 0 : false;
}

VB_State vb_player_get_state(VB_Player *p) {
    if (!p || !p->mp) return VB_STATE_NOTHING;
    return (VB_State)libvlc_media_player_get_state(p->mp);
}

bool vb_player_is_seekable(VB_Player *p) {
    return (p && p->mp) ? libvlc_media_player_is_seekable(p->mp) != 0 : false;
}

int64_t vb_player_get_time(VB_Player *p) {
    return (p && p->mp) ? (int64_t)libvlc_media_player_get_time(p->mp) : 0;
}

int64_t vb_player_get_length(VB_Player *p) {
    return (p && p->mp) ? (int64_t)libvlc_media_player_get_length(p->mp) : 0;
}

void vb_player_set_time(VB_Player *p, int64_t ms) {
    if (p && p->mp) libvlc_media_player_set_time(p->mp, (libvlc_time_t)ms);
}

float vb_player_get_position(VB_Player *p) {
    return (p && p->mp) ? libvlc_media_player_get_position(p->mp) : 0.f;
}

void vb_player_set_position(VB_Player *p, float pos) {
    if (p && p->mp) libvlc_media_player_set_position(p->mp, pos);
}

void vb_player_set_volume(VB_Player *p, int volume) {
    if (p && p->mp) libvlc_audio_set_volume(p->mp, volume);
}

int vb_player_get_volume(VB_Player *p) {
    return (p && p->mp) ? libvlc_audio_get_volume(p->mp) : 0;
}

void vb_player_set_mute(VB_Player *p, bool mute) {
    if (p && p->mp) libvlc_audio_set_mute(p->mp, mute ? 1 : 0);
}

bool vb_player_get_mute(VB_Player *p) {
    return (p && p->mp) ? libvlc_audio_get_mute(p->mp) > 0 : false;
}

void vb_player_set_rate(VB_Player *p, float rate) {
    if (p && p->mp) libvlc_media_player_set_rate(p->mp, rate);
}

void vb_player_set_aspect_ratio(VB_Player *p, const char *ratio) {
    if (p && p->mp) libvlc_video_set_aspect_ratio(p->mp, ratio);
}

/* ---- Track helpers (walk libvlc_track_description_t linked lists) ---- */

static bool track_at(libvlc_track_description_t *head, int index,
                     int *out_id, char *name_buf, int buf_len) {
    libvlc_track_description_t *cur = head;
    int i = 0;
    bool found = false;
    while (cur != NULL) {
        if (i == index) {
            if (out_id) *out_id = cur->i_id;
            if (name_buf && buf_len > 0) {
                if (cur->psz_name) {
                    strncpy(name_buf, cur->psz_name, buf_len - 1);
                    name_buf[buf_len - 1] = '\0';
                } else {
                    name_buf[0] = '\0';
                }
            }
            found = true;
            break;
        }
        cur = cur->p_next;
        i++;
    }
    return found;
}

int vb_player_audio_track_count(VB_Player *p) {
    return (p && p->mp) ? libvlc_audio_get_track_count(p->mp) : 0;
}

int vb_player_spu_count(VB_Player *p) {
    return (p && p->mp) ? libvlc_video_get_spu_count(p->mp) : 0;
}

bool vb_player_audio_track_at(VB_Player *p, int index, int *out_id,
                              char *name_buf, int buf_len) {
    if (!p || !p->mp) return false;
    libvlc_track_description_t *head = libvlc_audio_get_track_description(p->mp);
    bool r = track_at(head, index, out_id, name_buf, buf_len);
    if (head) libvlc_track_description_list_release(head);
    return r;
}

bool vb_player_spu_at(VB_Player *p, int index, int *out_id,
                      char *name_buf, int buf_len) {
    if (!p || !p->mp) return false;
    libvlc_track_description_t *head = libvlc_video_get_spu_description(p->mp);
    bool r = track_at(head, index, out_id, name_buf, buf_len);
    if (head) libvlc_track_description_list_release(head);
    return r;
}

int vb_player_get_audio_track(VB_Player *p) {
    return (p && p->mp) ? libvlc_audio_get_track(p->mp) : -1;
}

void vb_player_set_audio_track(VB_Player *p, int id) {
    if (p && p->mp) libvlc_audio_set_track(p->mp, id);
}

int vb_player_get_spu(VB_Player *p) {
    return (p && p->mp) ? libvlc_video_get_spu(p->mp) : -1;
}

void vb_player_set_spu(VB_Player *p, int id) {
    if (p && p->mp) libvlc_video_set_spu(p->mp, id);
}
