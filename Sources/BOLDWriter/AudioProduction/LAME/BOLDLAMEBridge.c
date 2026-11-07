#include "include/BOLDLAMEBridge.h"
#include "include/lame.h"
#include <stdlib.h>

static void bold_lame_silence_report(const char *format, va_list arguments) {
    (void)format;
    (void)arguments;
}

void *bold_lame_create(int sample_rate, int bitrate_kbps, int quality,
                       const uint16_t *title, const uint16_t *author,
                       const uint16_t *album, const uint16_t *track) {
    lame_t encoder = lame_init();
    if (encoder == NULL) return NULL;
    lame_set_errorf(encoder, bold_lame_silence_report);
    lame_set_debugf(encoder, bold_lame_silence_report);
    lame_set_msgf(encoder, bold_lame_silence_report);
    if (lame_set_num_channels(encoder, 2) < 0 ||
        lame_set_in_samplerate(encoder, sample_rate) < 0 ||
        lame_set_out_samplerate(encoder, sample_rate) < 0 ||
        lame_set_brate(encoder, bitrate_kbps) < 0 ||
        lame_set_quality(encoder, quality) < 0) {
        lame_close(encoder);
        return NULL;
    }
    id3tag_v2_only(encoder);
    if (title != NULL && id3tag_set_textinfo_utf16(encoder, "TIT2", title) < 0) goto fail;
    if (author != NULL && id3tag_set_textinfo_utf16(encoder, "TPE1", author) < 0) goto fail;
    if (album != NULL && id3tag_set_textinfo_utf16(encoder, "TALB", album) < 0) goto fail;
    if (track != NULL && id3tag_set_textinfo_utf16(encoder, "TRCK", track) < 0) goto fail;
    if (lame_init_params(encoder) < 0) goto fail;
    return encoder;
fail:
    lame_close(encoder);
    return NULL;
}

int bold_lame_encode(void *encoder, const int16_t *samples, int frames,
                     unsigned char *output, int output_capacity) {
    if (encoder == NULL || samples == NULL || output == NULL || output_capacity <= 0) return -1;
    return lame_encode_buffer_interleaved((lame_t)encoder, (short int *)samples,
                                          frames, output, output_capacity);
}

int bold_lame_flush(void *encoder, unsigned char *output, int output_capacity) {
    if (encoder == NULL || output == NULL || output_capacity <= 0) return -1;
    return lame_encode_flush((lame_t)encoder, output, output_capacity);
}

void bold_lame_close(void *encoder) {
    if (encoder != NULL) lame_close((lame_t)encoder);
}
