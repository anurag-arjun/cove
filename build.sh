#!/bin/bash
# Build script for Cove (Ghostty fork) on CachyOS
#
# Workarounds:
# 1. --libc: Uses patched CRT objects without .sframe sections (GCC 15 + Zig LLD incompatibility)
# 2. PATH override: Ensures system Python 3.14 is used (not conda) for blueprint-compiler

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBC_CONF="$SCRIPT_DIR/crt-patched/zig-libc.conf"

# Create libc config if it doesn't exist
if [ ! -f "$LIBC_CONF" ]; then
    echo "Setting up patched CRT objects..."
    mkdir -p "$SCRIPT_DIR/crt-patched/lib"
    
    # Symlink system libs
    for f in /usr/lib/lib*.a /usr/lib/lib*.so /usr/lib/lib*.so.*; do
        bn=$(basename "$f")
        ln -sf "$f" "$SCRIPT_DIR/crt-patched/lib/$bn" 2>/dev/null || true
    done
    
    # Create CRT objects with .sframe sections stripped
    for f in crt1.o crti.o crtn.o Scrt1.o gcrt1.o; do
        if [ -f "/usr/lib/$f" ]; then
            objcopy --remove-section=.sframe --remove-section=.rela.sframe \
                "/usr/lib/$f" "$SCRIPT_DIR/crt-patched/lib/$f"
        fi
    done
    
    cat > "$LIBC_CONF" << CONF
include_dir=/usr/include
sys_include_dir=/usr/include
crt_dir=$SCRIPT_DIR/crt-patched/lib
msvc_lib_dir=
kernel32_lib_dir=
gcc_dir=/usr/lib/gcc/x86_64-pc-linux-gnu/$(ls /usr/lib/gcc/x86_64-pc-linux-gnu/ | head -1)
CONF
    echo "CRT setup complete."
fi

# Build with system PATH (avoid conda python) and patched CRT
PATH=/usr/bin:/usr/sbin:/bin:/sbin exec zig build --libc "$LIBC_CONF" "$@"
