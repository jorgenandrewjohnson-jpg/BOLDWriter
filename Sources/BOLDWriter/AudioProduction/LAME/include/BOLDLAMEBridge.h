#ifndef BOLD_LAME_BRIDGE_H
#define BOLD_LAME_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
void *bold_lame_create(int sample_rate, int bitrate_kbps, int quality,
                       const uint16_t *title, const uint16_t *author,
                       const uint16_t *album, const uint16_t *track);
int bold_lame_encode(void *encoder, const int16_t *interleaved_stereo,
                     int frames_per_channel, unsigned char *output, int output_capacity);
int bold_lame_flush(void *encoder, unsigned char *output, int output_capacity);
void bold_lame_close(void *encoder);
#ifdef __cplusplus
}
#endif
#endif
