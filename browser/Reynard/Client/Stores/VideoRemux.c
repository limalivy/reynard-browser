#include "VideoRemux.h"
#include <libavformat/avformat.h>

static int openInput(const char *path, AVFormatContext **input) {
    AVDictionary *options = NULL;
    av_dict_set(&options, "protocol_whitelist", "file,crypto", 0);
    av_dict_set(&options, "allowed_extensions", "ALL", 0);
    av_dict_set(&options, "extension_picky", "0", 0);
    int status = avformat_open_input(input, path, NULL, &options);
    av_dict_free(&options);
    if (status >= 0) status = avformat_find_stream_info(*input, NULL);
    return status;
}

double ReynardVideoDuration(const char *path) {
    AVFormatContext *input = NULL;
    int found = 0;
    if (openInput(path, &input) >= 0) {
        for (unsigned i = 0; i < input->nb_streams; ++i) {
            if (input->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) found = 1;
        }
    }
    double duration = found && input->duration != AV_NOPTS_VALUE ? (double)input->duration / AV_TIME_BASE : -1;
    avformat_close_input(&input);
    return duration;
}

int ReynardRemuxVideo(const char *inputPath, const char *outputPath) {
    AVFormatContext *input = NULL, *output = NULL;
    AVPacket *packet = av_packet_alloc();
    int *mapping = NULL;
    int64_t *lastDTS = NULL, *offsets = NULL;
    int status = packet ? openInput(inputPath, &input) : AVERROR(ENOMEM);
    if (status < 0) goto done;
    status = avformat_alloc_output_context2(&output, NULL, "mp4", outputPath);
    if (status < 0) goto done;
    mapping = av_malloc_array(input->nb_streams, sizeof(*mapping));
    lastDTS = av_malloc_array(input->nb_streams, sizeof(*lastDTS));
    offsets = av_calloc(input->nb_streams, sizeof(*offsets));
    if (!mapping || !lastDTS || !offsets) { status = AVERROR(ENOMEM); goto done; }
    int hasVideo = 0;
    for (unsigned i = 0; i < input->nb_streams; ++i) {
        AVCodecParameters *parameters = input->streams[i]->codecpar;
        mapping[i] = -1;
        lastDTS[i] = AV_NOPTS_VALUE;
        if (parameters->codec_type != AVMEDIA_TYPE_VIDEO && parameters->codec_type != AVMEDIA_TYPE_AUDIO) continue;
        AVStream *stream = avformat_new_stream(output, NULL);
        if (!stream) { status = AVERROR(ENOMEM); goto done; }
        mapping[i] = stream->index;
        hasVideo |= parameters->codec_type == AVMEDIA_TYPE_VIDEO;
        status = avcodec_parameters_copy(stream->codecpar, parameters);
        if (status < 0) goto done;
        stream->codecpar->codec_tag = 0;
        stream->time_base = input->streams[i]->time_base;
    }
    if (!hasVideo) { status = AVERROR_INVALIDDATA; goto done; }
    status = avio_open(&output->pb, outputPath, AVIO_FLAG_WRITE);
    if (status < 0) goto done;
    status = avformat_write_header(output, NULL);
    if (status < 0) goto done;
    while ((status = av_read_frame(input, packet)) >= 0) {
        int index = packet->stream_index;
        if (mapping[index] >= 0) {
            AVStream *source = input->streams[index];
            AVStream *target = output->streams[mapping[index]];
            av_packet_rescale_ts(packet, source->time_base, target->time_base);
            // HLS discontinuities can restart a segment's clock. Preserve each
            // packet's composition offset while keeping MP4 decode times ordered.
            if (packet->dts != AV_NOPTS_VALUE) {
                int64_t shifted = packet->dts + offsets[index];
                if (lastDTS[index] != AV_NOPTS_VALUE && shifted <= lastDTS[index]) {
                    offsets[index] += lastDTS[index] + FFMAX(packet->duration, 1) - shifted;
                }
                packet->dts += offsets[index];
                if (packet->pts != AV_NOPTS_VALUE) packet->pts += offsets[index];
                lastDTS[index] = packet->dts;
            }
            packet->stream_index = target->index;
            packet->pos = -1;
            status = av_interleaved_write_frame(output, packet);
        }
        av_packet_unref(packet);
        if (status < 0) goto done;
    }
    if (status == AVERROR_EOF) status = av_write_trailer(output);
done:
    av_free(mapping);
    av_free(lastDTS);
    av_free(offsets);
    av_packet_free(&packet);
    avformat_close_input(&input);
    if (output) {
        if (output->pb) avio_closep(&output->pb);
        avformat_free_context(output);
    }
    return status;
}
