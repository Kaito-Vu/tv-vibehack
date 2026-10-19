#!/usr/bin/env python3
"""Fallback file transfer: send a file to the TV as base64 chunks through plain shell commands.

Usage: b64push.py <local file> <remote path>
"""
import base64
import hashlib
import os
import shlex
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tv  # noqa: E402

CHUNK = 48 * 1024  # raw bytes per shell command (base64 grows it by 4/3)


def main():
    local, remote = sys.argv[1], sys.argv[2]
    with open(local, "rb") as f:
        data = f.read()
    if not data:
        sys.exit(f"{local} is empty")
    want = hashlib.md5(data).hexdigest()
    dev = tv.connect()
    tmp = remote + ".b64"
    q_remote, q_tmp = shlex.quote(remote), shlex.quote(tmp)
    dev.shell(f"rm -f {q_remote} {q_tmp}")
    n = (len(data) + CHUNK - 1) // CHUNK
    for i in range(n):
        part = base64.b64encode(data[i * CHUNK:(i + 1) * CHUNK]).decode()
        out = dev.shell(f"echo '{part}' >> {q_tmp} && echo ok{i}", read_timeout_s=60.0)
        if out.strip() != f"ok{i}":
            print(f"chunk {i} failed: {out}")
            sys.exit(1)
        print(f"\rchunk {i + 1}/{n}", end="", flush=True)
    print()
    out = dev.shell(f"base64 -d {q_tmp} > {q_remote} && rm {q_tmp} && md5sum {q_remote}", read_timeout_s=120.0)
    got = out.split()[0] if out.strip() else ""
    print("md5 remote:", got, "local:", want, "MATCH" if got == want else "MISMATCH")
    dev.close()
    sys.exit(0 if got == want else 1)


if __name__ == "__main__":
    main()
