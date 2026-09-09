"""Controlled QML integration fixture. Never launches a capture command."""
import json
from pathlib import Path
import signal
import sys
import time


def emit(event, **data):
    print(json.dumps(dict(event=event, **data)), flush=True)


def stopped(*_):
    Path(__file__).with_name('cancelled-test-marker').write_text('stopped')
    sys.exit(0)


signal.signal(signal.SIGTERM, stopped)
operation = sys.argv[1]
if operation == 'monitors':
    emit('monitors', items=[dict(name='DP-1', width=1920, height=1080), dict(name='DP-2', width=1920, height=1080)])
elif operation == 'microphones':
    emit('microphones', items=[dict(name='onboard', label='Onboard'), dict(name='usb', label='USB headset')])
else:
    data = json.loads(sys.stdin.buffer.readline(8193))
    Path(__file__).with_name('request-test-marker').write_text(json.dumps(data))
    emit('phase', phase='recording')
    line = sys.stdin.buffer.readline(129)
    if line == b'stop\n':
        emit('phase', phase='stopping')
        emit('saved', name='screenrecording-2026-09-09_00-00-00-abcd1234abcd1234.mp4', warning='')
    else:
        stopped()
