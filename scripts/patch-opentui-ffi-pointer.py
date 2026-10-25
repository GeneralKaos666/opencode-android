#!/usr/bin/env python3
# RUNS ON: Linux x86_64 CI runner (NOT on Termux, NOT on device).
"""Fix OpenTUI's Bun FFI pointer handling for 64-bit ARM (Android/Termux).

On aarch64, native context handles are 64-bit values that can exceed
JavaScript's 2**53 safe-integer limit. Stock @opentui/core 0.6.8 coerces
them to JS numbers via ``toSafeNumberPointer``, which throws
``Pointer exceeds safe integer range`` (OpenTUI's POINTER_UNSAFE) and crashes
``createContext`` / ``Tui.run`` before any native call happens.

Bun's FFI accepts ``bigint`` for both ``ptr`` arguments and ``toArrayBuffer``
(see bun-types/ffi.d.ts), so the fix is to keep the pointer as a BigInt on the
Bun path instead of coercing it to a number.

Usage: patch-opentui-ffi-pointer.py <upstream-checkout-dir>
Finds node_modules/@opentui/core/chunk-bun-*.js (hash in name varies by
version) and applies two idempotent edits.
"""
import glob
import os
import sys

root = sys.argv[1]

# Bun's package layout (flat fallback for a hand-fetched @opentui/core).
patterns = [
    os.path.join(root, "node_modules", ".bun", "@opentui+core@*",
                 "node_modules", "@opentui", "core", "chunk-bun-*.js"),
    os.path.join(root, "node_modules", "@opentui", "core", "chunk-bun-*.js"),
]

cands = []
for pat in patterns:
    for path in glob.glob(pat):
        try:
            text = open(path, errors="replace").read()
        except OSError:
            continue
        if "toSafeNumberPointer" in text:
            cands.append(path)

if not cands:
    sys.exit("no @opentui/core chunk-bun with toSafeNumberPointer found")

# The Bun branch of toPointer() must keep the pointer as a BigInt:
#   function toPointer(value) {
#     if (isBun && typeof value === "bigint") {
#       return toSafeNumberPointer(value);   <-- throws for > 2**53
#     }
OLD_TOPOINTER = "    return toSafeNumberPointer(value);"
NEW_TOPOINTER = "    return value; // keep BigInt pointer (Bun FFI accepts bigint)"

# toBunPointer() feeds bun.toArrayBuffer() and ptr overrides; bigint is valid
# there too:
#   function toBunPointer(pointer) {
#     return typeof pointer === "bigint" ? toSafeNumberPointer(pointer) : pointer;
#   }
OLD_TOBUN = '  return typeof pointer === "bigint" ? toSafeNumberPointer(pointer) : pointer;'
NEW_TOBUN = "  return pointer; // keep BigInt pointer (Bun FFI accepts bigint)"

patched = 0
already_patched = 0
for path in cands:
    src = open(path, errors="replace").read()
    new = src

    if new.count(OLD_TOPOINTER) == 1:
        new = new.replace(OLD_TOPOINTER, NEW_TOPOINTER)
        patched += 1
    elif OLD_TOPOINTER not in new:
        pass  # already patched (or a different chunk shape)
    else:
        sys.exit(f"expected 1 toPointer anchor in {path}, found {new.count(OLD_TOPOINTER)}")

    if new.count(OLD_TOBUN) == 1:
        new = new.replace(OLD_TOBUN, NEW_TOBUN)
        patched += 1
    elif OLD_TOBUN not in new:
        pass  # already patched (or a different chunk shape)
    else:
        sys.exit(f"expected 1 toBunPointer anchor in {path}, found {new.count(OLD_TOBUN)}")

    if new != src:
        with open(path, "w") as fh:
            fh.write(new)
        print(f"patched {path}")
    else:
        already_patched += 1
        print(f"already patched {path}")

if patched == 0 and already_patched == 0:
    sys.exit("no edits applied: opentui FFI pointer anchors not found")
print(f"applied {patched} edit(s) across {len(cands)} chunk(s)")
