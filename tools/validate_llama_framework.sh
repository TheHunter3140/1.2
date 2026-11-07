#!/usr/bin/env bash
set -euo pipefail

FW="${1:-llama.xcframework}"
IOS_FW="$FW/ios-arm64/llama.framework"
BIN="$IOS_FW/llama"
LLAMA_H="$IOS_FW/Headers/llama.h"
MTMD_H="$IOS_FW/Headers/mtmd.h"
MTMD_HELPER_H="$IOS_FW/Headers/mtmd-helper.h"

fail() { echo "ERREUR XCFramework: $*" >&2; exit 1; }
require_file() { [[ -f "$1" ]] || fail "fichier absent: $1"; }
require_header_symbol() {
  local header="$1" symbol="$2"
  grep -Eq "${symbol}" "$header" || fail "API absente de $(basename "$header"): $symbol"
  echo "  API header OK: $symbol"
}

[[ -d "$FW" ]] || fail "framework introuvable: $FW"
require_file "$IOS_FW/Info.plist"
require_file "$BIN"
require_file "$LLAMA_H"
require_file "$MTMD_H"
require_file "$MTMD_HELPER_H"

PLATFORM=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$IOS_FW/Info.plist")
MIN_OS=$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$IOS_FW/Info.plist")
[[ "$PLATFORM" == "iPhoneOS" ]] || fail "plateforme iOS inattendue: $PLATFORM"
[[ "$MIN_OS" == "16.4" ]] || fail "minimum iOS attendu 16.4, reçu: $MIN_OS"
ARCHS=$(xcrun lipo -archs "$BIN")
[[ " $ARCHS " == *" arm64 "* ]] || fail "tranche arm64 absente: $ARCHS"
echo "  Plateforme: $PLATFORM | iOS minimum: $MIN_OS | architectures: $ARCHS"

for symbol in \
  'llama_model_load_from_file' \
  'llama_init_from_model' \
  'llama_batch_get_one' \
  'llama_memory_seq_rm' \
  'llama_sampler_init_penalties' \
  'llama_supports_gpu_offload' \
  'flash_attn_type' \
  'type_k' \
  'type_v'; do
  require_header_symbol "$LLAMA_H" "$symbol"
done

for symbol in 'mtmd_init_from_file' 'mtmd_tokenize' 'mtmd_support_vision' 'mtmd_support_audio'; do
  require_header_symbol "$MTMD_H" "$symbol"
done
for symbol in 'mtmd_helper_bitmap_init_from_file' 'mtmd_helper_eval_chunks'; do
  require_header_symbol "$MTMD_HELPER_H" "$symbol"
done

# Header declarations alone are insufficient: confirm the framework exports
# the public entry points that Pal will link against.
SYMBOLS=$(nm -gU "$BIN")
for symbol in \
  '_llama_batch_get_one' \
  '_llama_memory_seq_rm' \
  '_mtmd_init_from_file' \
  '_mtmd_tokenize' \
  '_mtmd_helper_eval_chunks'; do
  grep -Eq "[[:space:]]${symbol}$" <<< "$SYMBOLS" || fail "symbole non exporté: $symbol"
  echo "  Symbole exporté OK: $symbol"
done

# Do not use `strings` to detect a Mach-O section: on macOS the section
# name is not guaranteed to be emitted as a printable string. Inspect the
# Mach-O load commands instead, then separately confirm the Metal runtime.
if ! otool -l "$BIN" | grep -q '__ggml_metallib'; then
  fail "section Mach-O __ggml_metallib absente du binaire iOS"
fi
if ! strings -a "$BIN" | grep -q 'ggml_metal_init'; then
  fail "implémentation ggml_metal_init introuvable dans le binaire iOS"
fi
echo "  Section Metal embarquée (__ggml_metallib): OK"
echo "  Implémentation Metal (ggml_metal_init): OK"
echo "Validation du XCFramework terminée avec succès."
