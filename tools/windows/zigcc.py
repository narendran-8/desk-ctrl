#!/usr/bin/env python3
"""Linker for x86_64-pc-windows-gnu with zig: drops the mingw runtime libraries rustc asks for
(zig brings its own mingw-w64 runtime) and the self-contained start-up objects."""
import os, subprocess, sys
drop_libs = {"-lmsvcrt", "-lmingw32", "-lmingwex", "-lmoldname", "-lgcc", "-lgcc_eh", "-lpthread", "-lmsvcrt"}
args = []
# Library search dirs given as "-L dir" (the windows crates ship import libraries there).
libdirs = [sys.argv[i + 1] for i, a in enumerate(sys.argv[:-1]) if a == "-L"] + [a[2:] for a in sys.argv if a.startswith("-L") and len(a) > 2]
def import_lib(name):
    for d in libdirs:
        p = os.path.join(d, f"lib{name}.a")
        if os.path.exists(p):
            return p
    return None
for a in sys.argv[1:]:
    if a == "-l:libpthread.a":
        continue
    if a.startswith("-lwindows."):
        p = import_lib(a[2:])
        if p:
            args.append(p)
            continue
    if a in drop_libs:
        continue
    if a.endswith(("crt2.o", "dllcrt2.o", "rsbegin.o", "rsend.o", "libpthread.a", "libmsvcrt.a")) or a == "-nostartfiles":
        continue
    if a.startswith("-L") and "self-contained" in a:
        continue
    args.append(a)
args.append("-lunwind")
zig = os.path.expanduser("~/winbuild/zigenv/bin/python")
if os.environ.get("ZIGCC_DEBUG"):
    print(" ".join(sys.argv[1:]), file=sys.stderr)
sys.exit(subprocess.call([zig, "-m", "ziglang", "cc", "-target", "x86_64-windows-gnu", *args]))
