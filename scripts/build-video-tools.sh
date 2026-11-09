#!/bin/bash
set -euo pipefail
export MACOSX_DEPLOYMENT_TARGET=26.0
ROOT="$(cd "$(dirname "$0")/../.work/media" && pwd)"
PREFIX="$ROOT/prefix"
CMAKE="$ROOT/cmake/cmake-4.4.5-macos-universal/CMake.app/Contents/bin/cmake"
mkdir -p "$PREFIX" "$ROOT/x265-build"
python3 - "$ROOT/x265/x265_4.1/source/CMakeLists.txt" <<'PYCODE'
from pathlib import Path
import sys
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('SET CMP0025 OLD','SET CMP0025 NEW').replace('SET CMP0054 OLD','SET CMP0054 NEW'))
PYCODE
"$CMAKE" -S "$ROOT/x265/x265_4.1/source" -B "$ROOT/x265-build" -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DENABLE_ASSEMBLY=OFF -DHIGH_BIT_DEPTH=OFF
"$CMAKE" --build "$ROOT/x265-build" -j 6
"$CMAKE" --install "$ROOT/x265-build"
cat > "$ROOT/x265-pkg-config" <<PKG
#!/bin/sh
case "\$*" in
 --version) echo 1.0; exit 0;;
 *x265*) case "\$*" in
  *--cflags*) echo '-I$PREFIX/include';;
  *--libs*) echo '-L$PREFIX/lib -lx265 -lc++';;
  *--modversion*) echo '4.1';;
 esac; exit 0;;
 *) exit 1;;
esac
PKG
chmod +x "$ROOT/x265-pkg-config"
cd "$ROOT/ffmpeg/ffmpeg-9.0.2"
./configure --prefix="$PREFIX" --disable-autodetect --disable-shared --enable-static --enable-gpl --enable-libx265 --pkg-config="$ROOT/x265-pkg-config" --extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib" --extra-libs=-lc++ --enable-videotoolbox --enable-audiotoolbox --disable-doc --disable-ffplay --disable-everything --enable-ffmpeg --enable-ffprobe --enable-protocol=file,pipe --enable-demuxer=mov,lavfi --enable-indev=lavfi --enable-muxer=mp4,mov,null --enable-parser=h264,hevc,aac,mpeg4video --enable-decoder=wrapped_avframe,h264,hevc,mpeg4,prores,aac,mp3,alac,pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le --enable-encoder=pcm_s16le,wrapped_avframe,h264_videotoolbox,hevc_videotoolbox,libx265,aac --enable-filter=scale,format,null,anull,aresample,fps,setsar,transpose,hflip,vflip,trim,atrim,setpts,asetpts,ssim,testsrc2,sine --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,extract_extradata
make -j 6
make install
