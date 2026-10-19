#!/usr/bin/env python3
"""Minimal ADB-over-TCP client for an Android TV using adb_shell (no adb binary needed).

Set TV_HOST to the TV's IP. Usage:
    tv.py --probe                      connect and print model / Android version
    tv.py <shell command...>           run one shell command
    tv.py --batch < commands.txt       one command per line, same connection
    tv.py --push <local> <remote>      small files only (see b64push.py for larger ones)
    tv.py --pull <remote> <local>
"""
import os
import sys

from adb_shell.adb_device import AdbDeviceTcp
from adb_shell.auth.keygen import keygen
from adb_shell.auth.sign_pythonrsa import PythonRSASigner

HOST = os.environ.get("TV_HOST")
PORT = int(os.environ.get("TV_PORT", "5555"))
if not HOST:
    sys.exit("Set TV_HOST to your TV's IP address, e.g.  TV_HOST=192.168.1.50 tools/tv.py --probe\n"
             "(find it under Settings → Network, or look for the TV in `arp -a`)")
KEYDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "adbkey")
KEY = os.path.join(KEYDIR, "adbkey")


def get_signer():
    # The private key lets whoever holds it open a shell on every TV that was told "always allow",
    # so keep it to the current user.
    os.makedirs(KEYDIR, mode=0o700, exist_ok=True)
    if not (os.path.exists(KEY) and os.path.exists(KEY + ".pub")):
        keygen(KEY)
    try:
        os.chmod(KEY, 0o600)
        os.chmod(KEY + ".pub", 0o644)
    except OSError:
        pass  # Windows has no POSIX modes
    with open(KEY) as f:
        priv = f.read()
    with open(KEY + ".pub") as f:
        pub = f.read()
    return PythonRSASigner(pub, priv)


def connect(timeout=120):
    dev = AdbDeviceTcp(HOST, PORT, default_transport_timeout_s=float(timeout))
    try:
        dev.connect(rsa_keys=[get_signer()], transport_timeout_s=float(timeout), auth_timeout_s=timeout)
    except OSError as e:
        sys.exit(f"Could not connect to the TV at {HOST}:{PORT} ({e}).\n"
                 "Check TV_HOST, that the TV is on and on the same Wi-Fi, and that USB/network debugging is enabled.")
    except Exception as e:  # adb_shell raises its own types for refused or timed-out authorisation
        sys.exit(f"Connected to {HOST}:{PORT} but the TV did not accept this computer ({type(e).__name__}: {e}).\n"
                 "Look for the 'Allow USB debugging?' prompt on the TV and accept it.")
    return dev


def main():
    args = sys.argv[1:]
    if args and args[0].startswith("--") and args[0] not in ("--probe", "--push", "--pull", "--batch"):
        sys.exit(__doc__)
    if args and args[0] in ("--push", "--pull") and len(args) != 3:
        sys.exit(__doc__)
    dev = connect()
    if not args or args == ["--probe"]:
        for p in ("ro.product.model", "ro.product.device", "ro.build.version.release",
                  "ro.build.version.sdk", "ro.build.display.id", "ro.product.manufacturer"):
            print(f"{p} = {dev.shell(f'getprop {p}').strip()}")
    elif args[0] == "--push" and len(args) == 3:
        dev.push(args[1], args[2], transport_timeout_s=300.0, read_timeout_s=300.0)
        print(f"pushed {args[1]} -> {args[2]}")
    elif args[0] == "--pull" and len(args) == 3:
        dev.pull(args[1], args[2], transport_timeout_s=300.0, read_timeout_s=300.0)
        print(f"pulled {args[1]} -> {args[2]}")
    elif args[0] == "--batch":
        # one shell command per stdin line, each run separately on the same connection.
        # utf-8-sig drops the BOM Windows PowerShell may prepend to piped stdin.
        sys.stdin.reconfigure(encoding="utf-8-sig")
        for line in sys.stdin:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            out = dev.shell(line, read_timeout_s=120.0)
            sys.stdout.write(f"$ {line}\n{out}")
            if out and not out.endswith("\n"):
                sys.stdout.write("\n")
            sys.stdout.flush()
    else:
        out = dev.shell(" ".join(args), read_timeout_s=120.0)
        sys.stdout.write(out)
    dev.close()


if __name__ == "__main__":
    main()
