#!/usr/bin/env python3
"""Run a command in its own process group with a hard wall-clock timeout."""
import argparse
import os
import signal
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--seconds', type=float, required=True)
parser.add_argument('command', nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command[1:] if args.command[:1] == ['--'] else args.command
if not command or args.seconds <= 0:
    parser.error('a positive timeout and command are required')
process = subprocess.Popen(command, start_new_session=True)
try:
    sys.exit(process.wait(timeout=args.seconds))
except (subprocess.TimeoutExpired, KeyboardInterrupt):
    os.killpg(process.pid, signal.SIGKILL)
    process.wait()
    print('Command interrupted or timed out.', file=sys.stderr)
    sys.exit(124)
