const details = () => ({
  id: 'Tdarr_Plugin_scubbo_hevc_to_h264',
  Stage: 'Pre-processing',
  Name: 'Scubbo - Browser-DirectPlay MP4 (H264, bitrate-capped)',
  Type: 'Video',
  Operation: 'Transcode',
  Description: 'Makes files browser-Direct-Play: H264 video + AAC audio + MP4 container + faststart, '
    + 'capped at ~12 Mbps so they stream cleanly. HEVC (8/10-bit, via CUDA scale_cuda) and '
    + 'over-bitrate H264 are transcoded to a capped H264 MP4; already-H264 files under the cap are '
    + 'fast-remuxed to MP4 with no re-encode. Audio copied if AAC, else re-encoded to AAC. '
    + 'Subtitles dropped. AV1/mpeg4 left untouched.',
  Version: '3.0',
  Tags: 'pre-processing,ffmpeg,nvenc h264,mp4',
  Inputs: [],
});

// Overall bitrate (video+audio) above which an already-H264 file is re-encoded down instead of
// just remuxed. ~14 Mbps overall ≈ ~12 Mbps video, which streams cleanly in a browser.
const BITRATE_THRESHOLD = 14000000;

// eslint-disable-next-line no-unused-vars
const plugin = (file, librarySettings, inputs, otherArguments) => {
  const response = {
    processFile: false,
    preset: '',
    container: '.mp4',
    handBrakeMode: false,
    FFmpegMode: true,
    reQueueAfter: true,
    infoLog: '',
  };

  const videoStream = file.ffProbeData.streams.find(
    (s) => s.codec_type === 'video' && !(s.disposition && s.disposition.attached_pic === 1),
  ) || file.ffProbeData.streams.find((s) => s.codec_type === 'video');

  if (!videoStream) {
    response.infoLog += 'No video stream found. Skipping.\n';
    return response;
  }

  const codec = (videoStream.codec_name || '').toLowerCase();
  const container = (file.container || '').toLowerCase();
  const bitrate = Number(file.bit_rate)
    || Number((file.ffProbeData.format || {}).bit_rate)
    || 0;

  // Copy audio when it's already AAC, otherwise re-encode to AAC so the MP4 muxes cleanly
  // (DTS/TrueHD aren't valid in MP4) and browsers can play it.
  const audioStream = file.ffProbeData.streams.find((s) => s.codec_type === 'audio');
  const audioArgs = (audioStream && (audioStream.codec_name || '').toLowerCase() === 'aac')
    ? '-c:a copy'
    : '-c:a aac -b:a 256k';
  const tail = `${audioArgs} -sn -movflags +faststart -max_muxing_queue_size 9999`;

  // Already a good browser file: H264, MP4, under the bitrate cap.
  if (codec === 'h264' && container === 'mp4' && bitrate > 0 && bitrate <= BITRATE_THRESHOLD) {
    response.infoLog += 'Already H264 MP4 under bitrate cap. Nothing to do.\n';
    return response;
  }

  // H264 under the cap but wrong container: fast remux into MP4, no re-encode.
  if (codec === 'h264' && bitrate > 0 && bitrate <= BITRATE_THRESHOLD) {
    response.processFile = true;
    response.preset = `,-map 0:v:0 -map 0:a? -c:v copy ${tail}`;
    response.infoLog += `H264 in ${container} at ${Math.round(bitrate / 1e6)} Mbps; `
      + 'remuxing to MP4 (+faststart).\n';
    return response;
  }

  // Needs a real encode: HEVC (any), or H264 above the bitrate cap. Decode on the GPU, downconvert
  // 10-bit inside CUDA (scale_cuda), encode H264 capped at ~12 Mbps.
  if (codec === 'hevc' || codec === 'h264') {
    response.processFile = true;
    response.preset = '-hwaccel cuda -hwaccel_output_format cuda,'
      + '-map 0:v:0 -map 0:a? -vf scale_cuda=format=yuv420p '
      + `-c:v h264_nvenc -preset p5 -cq 21 -maxrate 12M -bufsize 24M ${tail}`;
    response.infoLog += `${codec.toUpperCase()} at ${Math.round(bitrate / 1e6)} Mbps; `
      + 'transcoding to H264 MP4 capped at 12 Mbps (+faststart, 10-bit safe).\n';
    return response;
  }

  response.infoLog += `Video codec is ${codec} (not H264/HEVC); leaving untouched.\n`;
  return response;
};

module.exports.details = details;
module.exports.plugin = plugin;
