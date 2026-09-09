#!/usr/bin/python3
"""Fixed local operations behind Easy Capture's bounded JSON/pipe protocol."""
import json
import math
import os
import re
import signal
import subprocess
import sys
import time

# -I excludes cwd and ambient Python paths. Only our reviewed sibling module
# is added; all other imports above are the system standard library.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from capture_runtime import CaptureError, Cancelled, CaptureFile, Control, Runner, output_directory

MAX_JSON = 1048576
MAX_EVENT = 32768
MAX_PIXELS = 67108864
MAX_SCREENSHOT = 268435456
MAX_RECORDING = 17179869184
MAX_DURATION = 28800
NAME = re.compile(r'[A-Za-z0-9_][A-Za-z0-9_.:-]{0,255}\Z')
RECT = re.compile(r'(-?\d{1,6}),(-?\d{1,6}) (\d{1,5})x(\d{1,5})\Z')


def safe_name(value):
    if not isinstance(value, str) or not NAME.fullmatch(value):
        raise CaptureError('Invalid device identifier')
    return value


def label(value):
    if not isinstance(value, str) or len(value) > 1024:
        raise CaptureError('Invalid device description')
    return re.sub(r'[<>&\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]', '', value)[:128]


def integer(value, low, high):
    if type(value) is not int or not low <= value <= high:
        raise CaptureError('Invalid display geometry')
    return value


def document(raw):
    if len(raw) > MAX_JSON:
        raise CaptureError('Response exceeded limit')
    # Reject pathological nesting before the JSON parser allocates a tree.
    depth = 0
    quoted = escaped = False
    for char in raw.decode('utf-8', 'strict'):
        if escaped:
            escaped = False
        elif quoted and char == '\\':
            escaped = True
        elif char == '"':
            quoted = not quoted
        elif not quoted and char in '[{':
            depth += 1
            if depth > 16:
                raise CaptureError('Response nesting exceeded limit')
        elif not quoted and char in ']}':
            depth -= 1
    def invalid_constant(_):
        raise CaptureError('Non-finite JSON number')
    value = json.loads(raw, parse_constant=invalid_constant)
    count = 0
    def walk(item):
        nonlocal count
        count += 1
        if count > 32768:
            raise CaptureError('Response item count exceeded limit')
        if isinstance(item, dict):
            for key, entry in item.items():
                if len(key) > 1024:
                    raise CaptureError('Response key exceeded limit')
                walk(entry)
        elif isinstance(item, list):
            for entry in item:
                walk(entry)
        elif isinstance(item, str) and len(item) > 16384:
            raise CaptureError('Response field exceeded limit')
    walk(value)
    return value


def array(value, limit):
    if not isinstance(value, list) or len(value) > limit:
        raise CaptureError('Response list exceeded limit')
    return value


def query(runner, argv):
    code, raw = runner.run(argv, limit=MAX_JSON, timeout=5)
    if code:
        raise CaptureError('Could not read desktop devices')
    return document(raw)


def monitors(runner):
    result = []
    for item in array(query(runner, ['/usr/bin/hyprctl', 'monitors', '-j']), 16):
        if not isinstance(item, dict):
            raise CaptureError('Invalid monitor response')
        if item.get('disabled') is True:
            continue
        scale = item.get('scale')
        if type(scale) not in (int, float) or not math.isfinite(scale) or not 0.25 <= scale <= 8:
            raise CaptureError('Invalid monitor scale')
        width = integer(item.get('width'), 1, 16384)
        height = integer(item.get('height'), 1, 16384)
        if width * height > MAX_PIXELS:
            raise CaptureError('Display dimensions exceeded limit')
        transform = integer(item.get('transform', 0), 0, 7)
        w, h = math.floor(width / scale), math.floor(height / scale)
        if transform % 2:
            w, h = h, w
        result.append(dict(id=integer(item.get('id'), 0, 128), name=safe_name(item.get('name')),
                           width=width, height=height, scale=scale, x=integer(item.get('x'), -131072, 131072),
                           y=integer(item.get('y'), -131072, 131072), w=w, h=h,
                           workspace=integer(item.get('activeWorkspace', {}).get('id'), -2147483648, 2147483647),
                           special=integer(item.get('specialWorkspace', {}).get('id', 0), -2147483648, 2147483647)))
    if len({m['name'] for m in result}) != len(result):
        raise CaptureError('Duplicate monitor identifiers')
    return result


def microphones(runner):
    inputs = []
    seen = set()
    for item in array(query(runner, ['/usr/bin/pactl', '--format=json', 'list', 'sources']), 128):
        if not isinstance(item, dict):
            raise CaptureError('Invalid microphone response')
        name = safe_name(item.get('name'))
        props = item.get('properties') or {}
        if not isinstance(props, dict):
            raise CaptureError('Invalid microphone properties')
        if item.get('monitor_source') or name.endswith('.monitor') or props.get('device.class') == 'monitor' or props.get('media.class') == 'Audio/Sink':
            continue
        if item.get('monitor_of_sink') not in (None, -1, 4294967295, '4294967295', 'n/a'):
            continue
        if name not in seen:
            inputs.append(dict(name=name, label=label(item.get('description') or name)))
            seen.add(name)
        if len(inputs) > 32:
            raise CaptureError('Too many microphone inputs')
    return inputs


def geometry(rect):
    if not isinstance(rect, str):
        raise CaptureError('Invalid capture rectangle')
    match = RECT.fullmatch(rect)
    if not match:
        raise CaptureError('Invalid capture rectangle')
    x, y, w, h = map(int, match.groups())
    integer(x, -131072, 131072)
    integer(y, -131072, 131072)
    integer(w, 1, 16384)
    integer(h, 1, 16384)
    if w * h > MAX_PIXELS:
        raise CaptureError('Capture area is too large')
    return x, y, w, h


def format_rect(m):
    return f'{m["x"]},{m["y"]} {m["w"]}x{m["h"]}'


def app_rectangles(runner, displays):
    rects = {format_rect(m) for m in displays}
    for item in array(query(runner, ['/usr/bin/hyprctl', 'clients', '-j']), 512):
        if not isinstance(item, dict):
            raise CaptureError('Invalid window response')
        if item.get('hidden') is True or item.get('mapped') is False:
            continue
        workspace = item.get('workspace', {}).get('id')
        visible = any(m['id'] == item.get('monitor') and
                      (item.get('pinned') is True or workspace == m['workspace'] or
                       (m['special'] != 0 and workspace == m['special'])) for m in displays)
        if not visible:
            continue
        pos, size = item.get('at'), item.get('size')
        if not isinstance(pos, list) or not isinstance(size, list) or len(pos) != 2 or len(size) != 2:
            raise CaptureError('Invalid window rectangle')
        x, y = [integer(n, -131072, 131072) for n in pos]
        w, h = [integer(n, 1, 16384) for n in size]
        rect = f'{x},{y} {w}x{h}'
        geometry(rect)
        rects.add(rect)
    return sorted(rects)


def request(raw):
    data = document(raw)
    keys = {'action', 'target', 'monitor', 'desktop', 'microphone', 'input'}
    if not isinstance(data, dict) or set(data) != keys:
        raise CaptureError('Invalid capture request')
    if data['action'] not in ('screenshot', 'record') or data['target'] not in ('region', 'app', 'monitor'):
        raise CaptureError('Invalid capture action')
    if type(data['desktop']) is not bool or type(data['microphone']) is not bool:
        raise CaptureError('Invalid audio options')
    for name in ('monitor', 'input'):
        if data[name] != '':
            safe_name(data[name])
    if data['action'] == 'screenshot' and (data['desktop'] or data['microphone'] or data['input']):
        raise CaptureError('Screenshots cannot enable audio')
    return data


def audio_arguments(data):
    sources = []
    if data['desktop']:
        sources.append('default_output')
    if data['microphone']:
        sources.append('device:' + safe_name(data['input']) if data['input'] else 'default_input')
    return ['-a', '|'.join(sources), '-ac', 'aac'] if sources else []


def recorder_arguments(data, selected, fd):
    if isinstance(selected, dict):
        size = '3840x2160' if selected['width'] > 3840 or selected['height'] > 2160 else '0x0'
        target = ['-w', safe_name(selected['name']), '-s', size]
    else:
        x, y, w, h = geometry(selected)
        target = ['-w', 'region', '-region', f'{w}x{h}+{x}+{y}']
    return ['/usr/bin/gpu-screen-recorder', *target, '-c', 'mp4', '-k', 'auto', '-f', '60',
            '-fm', 'cfr', '-fallback-cpu-encoding', 'yes', *audio_arguments(data), '-o', f'/proc/self/fd/{fd}']


def emit(event, **fields):
    raw = json.dumps(dict(event=event, **fields), ensure_ascii=True, separators=(',', ':')) + '\n'
    if len(raw) > MAX_EVENT:
        raise CaptureError('Helper event exceeded limit')
    sys.stdout.write(raw)
    sys.stdout.flush()


def notify(runner, title, body):
    try:
        runner.run(['/usr/bin/notify-send', '--app-name=Easy Capture', '--', title, label(body)], limit=1024, timeout=3)
    except (OSError, CaptureError):
        pass


def choose(runner, data, displays):
    if data['target'] == 'monitor':
        for monitor in displays:
            if monitor['name'] == data['monitor']:
                return monitor, None
        raise CaptureError('Selected monitor is unavailable')
    emit('phase', phase='picking')
    candidates = app_rectangles(runner, displays) if data['target'] == 'app' else []
    freeze = runner.start(['/usr/bin/hyprpicker', '-r', '-z'], stdout=subprocess.DEVNULL)
    try:
        # Match the native helper's freeze warmup while still observing cancel.
        for _ in range(10):
            runner.check()
            time.sleep(0.01)
        if freeze.exited():
            raise CaptureError('Could not freeze the desktop')
        command = ['/usr/bin/slurp', '-f', '%x,%y %wx%h']
        if data['target'] == 'app':
            command.append('-r')
        code, raw = runner.run(command, input_bytes=('\n'.join(candidates) + '\n').encode() if candidates else b'',
                               timeout=120, limit=256)
        if code or not raw.strip():
            raise Cancelled()
        rect = raw.decode('ascii', 'strict').strip()
        x, y, w, h = geometry(rect)
        if candidates and rect not in candidates:
            raise CaptureError('Picker returned an unknown app rectangle')
        if w * h * max((m['scale'] for m in displays), default=1) ** 2 > MAX_PIXELS:
            raise CaptureError('Capture area is too large at the display scale')
        if not any(x < m['x'] + m['w'] and x + w > m['x'] and y < m['y'] + m['h'] and y + h > m['y'] for m in displays):
            raise CaptureError('Capture is outside available monitors')
        for monitor in displays:
            if format_rect(monitor) == rect:
                return monitor, freeze
        return rect, freeze
    except BaseException:
        runner.release(freeze)
        raise


def record(runner, data, selected, output):
    emit('phase', phase='starting')
    child = runner.start(recorder_arguments(data, selected, output.fd), stdout=subprocess.DEVNULL, pass_fds=(output.fd,), file_size_limit=MAX_RECORDING + 16777216)
    started = time.monotonic()
    stop_at = None
    recording = False
    reason = ''
    try:
        while True:
            runner.check()
            now = time.monotonic()
            size = os.fstat(output.fd).st_size
            if child.exited():
                break
            if not recording and size > 0:
                recording = True
                emit('phase', phase='recording')
            if not recording and now - started > 15:
                raise CaptureError('Screen recording failed to start')
            if size > MAX_RECORDING or now - started > MAX_DURATION:
                reason = 'Recording reached its size or duration limit'
            if (runner.control.stop or reason) and stop_at is None:
                child.signal(signal.SIGINT)
                stop_at = now
                emit('phase', phase='stopping')
            if stop_at is not None and now - stop_at > 10:
                raise CaptureError('Recorder could not finalize the file')
            time.sleep(0.05)
        code = runner.release(child)
        child = None
        if not recording or code not in (0, -signal.SIGINT):
            raise CaptureError('Screen recording failed')
        if os.fstat(output.fd).st_size > MAX_RECORDING + 16777216:
            raise CaptureError('Recording exceeded file-size limit')
        output.publish()
        emit('saved', name=output.name, warning=reason)
        notify(runner, 'Screen recording saved', output.name)
    finally:
        if child:
            runner.release(child)


def screenshot(runner, selected, freeze, output):
    emit('phase', phase='screenshotting')
    target = ['-o', selected['name']] if isinstance(selected, dict) else ['-g', selected]
    try:
        code, _ = runner.run(['/usr/bin/grim', '-t', 'png', *target, '-'], stdout=output.fd,
                             timeout=15, file_limit=(output.fd, MAX_SCREENSHOT))
        if code:
            raise CaptureError('Screenshot failed')
        # Bound decoder work before handing our generated file to clipboard tools.
        header = os.pread(output.fd, 24, 0)
        if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
            raise CaptureError('Screenshot has an invalid image header')
        width, height = int.from_bytes(header[16:20], 'big'), int.from_bytes(header[20:24], 'big')
        if not (0 < width <= 16384 and 0 < height <= 16384 and width * height <= MAX_PIXELS):
            raise CaptureError('Screenshot dimensions exceeded limit')
        output.publish()
    finally:
        if freeze:
            runner.release(freeze)
    emit('saved', name=output.name, warning='')
    notify(runner, 'Screenshot saved', output.name)
    os.lseek(output.fd, 0, os.SEEK_SET)
    # Foreground clipboard ownership stays attached to this helper. It ends on
    # replacement, the next capture, shell reload, or removal of the last widget.
    child = runner.start(['/usr/bin/wl-copy', '--foreground', '--type', 'image/png'], stdin=output.fd, stdout=subprocess.DEVNULL)
    try:
        emit('phase', phase='clipboard')
        deadline = time.monotonic() + MAX_DURATION
        while not child.exited():
            runner.check()
            if time.monotonic() > deadline:
                break
            time.sleep(0.05)
        code = runner.release(child)
        child = None
        if code:
            raise CaptureError('Screenshot saved, but clipboard copy failed')
    finally:
        if child:
            runner.release(child)


def capture(runner, data):
    displays = monitors(runner)
    if not displays:
        raise CaptureError('No monitors are available')
    if data['microphone']:
        inputs = microphones(runner)
        if not inputs or (data['input'] and data['input'] not in {i['name'] for i in inputs}):
            raise CaptureError('Selected microphone is unavailable')
    selected, freeze = choose(runner, data, displays)
    output = None
    try:
        output = CaptureFile(output_directory(runner.env, data['action']), data['action'])
        if data['action'] == 'record':
            if freeze:
                runner.release(freeze)
                freeze = None
            record(runner, data, selected, output)
        else:
            held_freeze, freeze = freeze, None
            screenshot(runner, selected, held_freeze, output)
    finally:
        if freeze:
            runner.release(freeze)
        if output:
            output.close()


def main():
    control = Control(fd=0 if len(sys.argv) == 2 and sys.argv[1] == "capture" else None)
    runner = Runner(control=control)
    def cancel(_signal, _frame):
        control.cancelled = True
    signal.signal(signal.SIGTERM, cancel)
    signal.signal(signal.SIGINT, cancel)
    try:
        if len(sys.argv) != 2 or sys.argv[1] not in ('monitors', 'microphones', 'capture'):
            raise CaptureError('Unknown helper operation')
        op = sys.argv[1]
        if op == 'capture':
            capture(runner, request(control.read_request()))
        elif op == 'monitors':
            emit('monitors', items=[{k: m[k] for k in ('name', 'width', 'height')} for m in monitors(runner)])
        else:
            emit('microphones', items=microphones(runner))
        return 0
    except Cancelled:
        emit('cancelled')
        return 0
    except (CaptureError, OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        # Never copy raw child output, paths or device strings into an error.
        message = str(error) if isinstance(error, CaptureError) else 'Capture operation failed'
        emit('error', message=message)
        if len(sys.argv) == 2 and sys.argv[1] == 'capture':
            notify(runner, 'Capture failed', message)
        return 1
    finally:
        runner.close()


if __name__ == '__main__':
    sys.exit(main())
