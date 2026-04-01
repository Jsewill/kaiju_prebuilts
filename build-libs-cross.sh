#!/usr/bin/env bash
#
# Cross-compile Bullet3 and SoLoud static libraries for a target architecture.
#
# Usage: ./build-libs-cross.sh <arch>
#   e.g. ./build-libs-cross.sh riscv64
#        ./build-libs-cross.sh aarch64   (for arm64)
#
# Prerequisites:
#   - CMake, make
#   - Cross-compiler toolchain: <arch>-linux-gnu-gcc / g++
#
# Output: .a files are copied into this directory (src/libs/) with _nix_<goarch> suffix.

set -euo pipefail

if [ $# -lt 1 ]; then
	echo "Usage: $0 <arch>"
	echo "  arch: riscv64, aarch64, etc."
	exit 1
fi

ARCH="$1"
CC="${ARCH}-linux-gnu-gcc"
CXX="${ARCH}-linux-gnu-g++"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$(mktemp -d)"

# Map toolchain arch name to Go arch name for library suffixes.
case "$ARCH" in
	riscv64)  GOARCH="riscv64" ;;
	aarch64)  GOARCH="arm64"   ;;
	x86_64)   GOARCH="amd64"   ;;
	*)        GOARCH="$ARCH"   ;;
esac

trap 'rm -rf "$WORK_DIR"' EXIT

echo "=== Building for linux/${GOARCH} (toolchain: ${ARCH}-linux-gnu) ==="
echo "    Work dir: $WORK_DIR"
echo ""

# --- Bullet3 ---
echo "--- Bullet3 ---"
cd "$WORK_DIR"
git clone --depth 1 https://github.com/bulletphysics/bullet3.git
cd bullet3
mkdir build_cross && cd build_cross
cmake .. \
	-DCMAKE_SYSTEM_NAME=Linux \
	-DCMAKE_SYSTEM_PROCESSOR="$ARCH" \
	-DCMAKE_C_COMPILER="$CC" \
	-DCMAKE_CXX_COMPILER="$CXX" \
	-DCMAKE_BUILD_TYPE=Release \
	-DBUILD_SHARED_LIBS=OFF \
	-DBUILD_CPU_DEMOS=OFF \
	-DBUILD_OPENGL3_DEMOS=OFF \
	-DBUILD_BULLET2_DEMOS=OFF \
	-DBUILD_EXTRAS=OFF \
	-DBUILD_UNIT_TESTS=OFF \
	-DUSE_GLUT=OFF \
	-DINSTALL_LIBS=ON
make -j"$(nproc)"

# Copy Bullet3 libraries with the correct naming convention.
for lib in \
	src/BulletDynamics/libBulletDynamics.a \
	src/BulletCollision/libBulletCollision.a \
	src/LinearMath/libLinearMath.a \
	src/BulletSoftBody/libBulletSoftBody.a \
	src/BulletInverseDynamics/libBulletInverseDynamics.a \
	src/Bullet3Dynamics/libBullet3Dynamics.a \
	src/Bullet3Collision/libBullet3Collision.a \
	src/Bullet3Common/libBullet3Common.a \
	src/Bullet3Geometry/libBullet3Geometry.a \
	src/Bullet3OpenCL/libBullet3OpenCL_clew.a \
	src/Bullet3Serialize/Bullet2FileLoader/libBullet2FileLoader.a \
	; do
	if [ -f "$lib" ]; then
		base="$(basename "$lib" .a)"
		dest="${SCRIPT_DIR}/${base}_nix_${GOARCH}.a"
		cp "$lib" "$dest"
		echo "  -> $(basename "$dest")"
	fi
done

# --- SoLoud ---
echo ""
echo "--- SoLoud ---"
cd "$WORK_DIR"
git clone --depth 1 https://github.com/jarikomppa/soloud.git
cd soloud/contrib
mkdir build_cross && cd build_cross
cmake .. \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
	-DCMAKE_SYSTEM_NAME=Linux \
	-DCMAKE_SYSTEM_PROCESSOR="$ARCH" \
	-DCMAKE_C_COMPILER="$CC" \
	-DCMAKE_CXX_COMPILER="$CXX" \
	-DCMAKE_C_FLAGS="-I/usr/include" \
	-DCMAKE_CXX_FLAGS="-I/usr/include" \
	-G "Unix Makefiles" \
	-DSOLOUD_BACKEND_SDL2=OFF \
	-DSOLOUD_BACKEND_ALSA=ON \
	-DSOLOUD_C_API=ON \
	-DSOLOUD_STATIC=ON
cmake --build . --config Release

SOLOUD_LIB="$(find . -name 'libsoloud*.a' | head -1)"
if [ -n "$SOLOUD_LIB" ]; then
	cp "$SOLOUD_LIB" "${SCRIPT_DIR}/libsoloud_nix_${GOARCH}.a"
	echo "  -> libsoloud_nix_${GOARCH}.a"
fi

echo ""
echo "=== Done. Libraries installed to ${SCRIPT_DIR} ==="
