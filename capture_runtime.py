"""Bounded child processes and descriptor-owned capture files (Linux only)."""
import json
import os
import pwd
import re
import resource
import select
import signal
import stat
import subprocess
import time
import secrets


class CaptureError(Exception):
    pass


class Cancelled(Exception):
    pass


def environment():
    home = pwd.getpwuid(os.getuid()).pw_dir
    env = {'HOME': home, 'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8'}
    # Required local desktop endpoints; no loader, shell, Python or proxy overrides.
    for name in ('XDG_RUNTIME_DIR', 'HYPRLAND_INSTANCE_SIGNATURE', 'WAYLAND_DISPLAY', 'DISPLAY', 'DBUS_SESSION_BUS_ADDRESS',
                 'XDG_CONFIG_HOME', 'XDG_PICTURES_DIR', 'XDG_VIDEOS_DIR',
                 'OMARCHY_SCREENSHOT_DIR', 'OMARCHY_SCREENRECORD_DIR'):
        value = os.environ.get(name, '')
        if value and len(value) <= 4096 and not re.search(r'[\x00-\x1f\x7f]', value):
            env[name] = value
    return env


class Control:
    """Small commands over the inherited QML pipe. EOF always cancels."""
    def __init__(self, fd=0):
        self.fd = fd
        self.buffer = bytearray()
        self.cancelled = False
        self.stop = False

    def read_request(self):
        deadline = time.monotonic() + 5
        while b'\n' not in self.buffer:
            if time.monotonic() >= deadline:
                raise CaptureError('Capture request timed out')
            if select.select([self.fd], [], [], 0.05)[0]:
                data = os.read(self.fd, 4096)
                if not data:
                    raise Cancelled()
                self.buffer.extend(data)
                if len(self.buffer) > 8192:
                    raise CaptureError('Capture request exceeded limit')
        line, _, rest = self.buffer.partition(b'\n')
        self.buffer = bytearray(rest)
        return bytes(line)

    def poll(self):
        if self.cancelled:
            raise Cancelled()
        if self.fd is None:
            return
        while select.select([self.fd], [], [], 0)[0]:
            data = os.read(self.fd, 128)
            if not data:
                raise Cancelled()
            self.buffer.extend(data)
            if len(self.buffer) > 128:
                raise Cancelled()
        while b'\n' in self.buffer:
            line, _, rest = self.buffer.partition(b'\n')
            self.buffer = bytearray(rest)
            if line == b'stop':
                self.stop = True
            else:
                raise Cancelled()


class Child:
    """Keep the session leader unreaped until every group signal is sent.

    The unreaped leader reserves its PID/PGID, even if it exits before its
    descendants. Never use Popen.poll() here: it would release that identity.
    """
    def __init__(self, argv, env, *, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, pass_fds=(), file_size_limit=None):
        def limits():
            resource.setrlimit(resource.RLIMIT_FSIZE, (file_size_limit, file_size_limit))
        self.proc = subprocess.Popen(argv, env=env, stdin=stdin, stdout=stdout,
                                     stderr=subprocess.DEVNULL, start_new_session=True,
                                     pass_fds=pass_fds, close_fds=True,
                                     preexec_fn=limits if file_size_limit is not None else None)
        try:
            self.pidfd = os.pidfd_open(self.proc.pid)
        except BaseException:
            # Popen has not been polled/reaped, so the process identity is held.
            os.killpg(self.proc.pid, signal.SIGKILL)
            self.proc.wait()
            raise
        self.closed = False

    def exited(self):
        return bool(select.select([self.pidfd], [], [], 0)[0])

    def signal(self, sig):
        if not self.closed:
            try:
                os.killpg(self.proc.pid, sig)
            except ProcessLookupError:
                pass

    def finish(self):
        if self.closed:
            return self.proc.returncode
        self.signal(signal.SIGTERM)
        # Do not cancel escalation just because the group leader exited.
        time.sleep(0.05)
        self.signal(signal.SIGKILL)
        try:
            return self.proc.wait(timeout=2)
        finally:
            self.closed = True
            os.close(self.pidfd)
            if self.proc.stdout:
                self.proc.stdout.close()
            if self.proc.stdin and hasattr(self.proc.stdin, 'close'):
                self.proc.stdin.close()


class Runner:
    def __init__(self, env=None, control=None):
        self.env = environment() if env is None else env
        self.control = control
        self.children = []

    def check(self):
        if self.control:
            self.control.poll()

    def start(self, argv, **kwargs):
        if not argv or not argv[0].startswith('/usr/bin/'):
            raise CaptureError('Invalid executable')
        child = Child(argv, self.env, **kwargs)
        self.children.append(child)
        return child

    def release(self, child):
        try:
            return child.finish()
        finally:
            if child in self.children:
                self.children.remove(child)

    def close(self):
        for child in list(self.children):
            self.release(child)

    def run(self, argv, *, timeout=5, limit=262144, input_bytes=None, stdin=None,
            stdout=None, pass_fds=(), file_limit=None):
        # Small request pipes are filled before exec using an anonymous memfd;
        # no producer can block on an unread stdin pipe.
        input_fd = None
        if input_bytes is not None:
            if len(input_bytes) > 65536:
                raise CaptureError('Command input exceeded limit')
            input_fd = os.memfd_create('easy-capture-input', os.MFD_CLOEXEC)
            view = memoryview(input_bytes)
            while view:
                count = os.write(input_fd, view)
                if count <= 0:
                    raise CaptureError('Could not prepare command input')
                view = view[count:]
            os.lseek(input_fd, 0, os.SEEK_SET)
            stdin = input_fd
        child = None
        try:
            child = self.start(argv, stdin=subprocess.DEVNULL if stdin is None else stdin,
                               stdout=subprocess.PIPE if stdout is None else stdout, pass_fds=pass_fds,
                               file_size_limit=file_limit[1] if file_limit else None)
            deadline = time.monotonic() + timeout
            output = bytearray()
            pipe = child.proc.stdout
            if pipe:
                os.set_blocking(pipe.fileno(), False)
            eof = pipe is None
            while True:
                self.check()
                if time.monotonic() >= deadline:
                    raise CaptureError('Command timed out')
                if file_limit and os.fstat(file_limit[0]).st_size > file_limit[1]:
                    raise CaptureError('Capture exceeded file-size limit')
                if pipe and not eof:
                    try:
                        chunk = os.read(pipe.fileno(), min(65536, limit + 1 - len(output)))
                        if chunk:
                            output.extend(chunk)
                            if len(output) > limit:
                                raise CaptureError('Command output exceeded limit')
                        else:
                            eof = True
                    except BlockingIOError:
                        pass
                if child.exited() and eof:
                    break
                time.sleep(0.01)
            code = self.release(child)
            child = None
            return code, bytes(output)
        finally:
            if child:
                self.release(child)
            if input_fd is not None:
                os.close(input_fd)


def open_directory(path, *, create=False):
    """Walk a configured absolute output path without resolving symlinks."""
    if not isinstance(path, str) or not path.startswith('/') or len(path) > 4096:
        raise CaptureError('Output directory must be an absolute path')
    parts = path.split('/')[1:]
    if any(p in ('.', '..') for p in parts):
        raise CaptureError('Output directory contains traversal')
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for part in filter(None, parts):
            try:
                nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=fd)
            except FileNotFoundError:
                if not create:
                    raise
                try:
                    os.mkdir(part, 0o700, dir_fd=fd)
                except FileExistsError:
                    pass
                nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=fd)
            info = os.fstat(nxt)
            if info.st_uid not in (0, os.getuid()) or (info.st_mode & 0o022 and not info.st_mode & stat.S_ISVTX):
                os.close(nxt)
                raise CaptureError('Output directory has unsafe ownership or permissions')
            os.close(fd)
            fd = nxt
        if os.fstat(fd).st_uid != os.getuid():
            raise CaptureError('Output directory must belong to your account')
        return fd
    except BaseException:
        os.close(fd)
        raise


def plugin_config_directory(env):
    """The review directory for this plugin's private settings."""
    base = env.get('XDG_CONFIG_HOME') or (env['HOME'] + '/.config')
    if not isinstance(base, str) or not base.startswith('/') or len(base) > 4096:
        raise CaptureError('Invalid plugin config base')
    return base.rstrip('/') + '/omarchy/plugins/chyld.easy-capture'


def validate_zipline(server, token):
    """Bounded share-server credentials; no control characters or secrets kept local."""
    if not isinstance(server, str) or not isinstance(token, str):
        raise CaptureError('Invalid share settings')
    if not server.startswith('https://') or len(server) > 2048:
        raise CaptureError('Share server must be an https URL')
    if not token or len(token) > 4096:
        raise CaptureError('Share token is missing or too long')
    if re.search(r'[\x00-\x1f\x7f]', server + token):
        raise CaptureError('Share settings contain control characters')
    return server, token


def read_zipline_config(env):
    """Return (server, token) from the private 0600 config file, or None."""
    directory = plugin_config_directory(env)
    path = directory + '/zipline.json'
    try:
        dfd = open_directory(directory)
    except FileNotFoundError:
        return None
    try:
        try:
            fd = os.open('zipline.json', os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=dfd)
        except FileNotFoundError:
            return None
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1 or info.st_size > 8192:
                raise CaptureError('Unsafe share settings file')
            data = bytearray()
            while len(data) <= 8192:
                chunk = os.read(fd, 8193 - len(data))
                if not chunk:
                    break
                data.extend(chunk)
            if len(data) > 8192:
                raise CaptureError('Share settings exceeded limit')
        finally:
            os.close(fd)
    finally:
        os.close(dfd)
    try:
        parsed = json.loads(bytes(data).decode('utf-8', 'strict'))
    except (ValueError, UnicodeDecodeError):
        raise CaptureError('Invalid share settings file')
    if not isinstance(parsed, dict) or set(parsed) != {'server', 'token'}:
        raise CaptureError('Invalid share settings file')
    return validate_zipline(parsed['server'], parsed['token'])


def write_zipline_config(env, server, token):
    """Atomically persist credentials to a private 0600 file."""
    validate_zipline(server, token)
    fd = open_directory(plugin_config_directory(env), create=True)
    try:
        payload = json.dumps({'server': server, 'token': token}, ensure_ascii=True, separators=(',', ':')).encode('utf-8')
        if len(payload) > 8192:
            raise CaptureError('Share settings exceeded limit')
        tmp = os.open('.zipline.tmp', os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=fd)
        try:
            view = memoryview(payload)
            while view:
                count = os.write(tmp, view)
                if count <= 0:
                    raise CaptureError('Could not write share settings')
                view = view[count:]
            os.fsync(tmp)
        finally:
            os.close(tmp)
        os.replace('.zipline.tmp', 'zipline.json', src_dir_fd=fd, dst_dir_fd=fd)
        os.fsync(fd)
    finally:
        os.close(fd)


def read_config(env):
    """Read XDG directory declarations as data, never execute shell syntax."""
    directory = env.get('XDG_CONFIG_HOME', env['HOME'] + '/.config')
    try:
        dfd = open_directory(directory)
    except FileNotFoundError:
        return {}
    try:
        try:
            fd = os.open('user-dirs.dirs', os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=dfd)
        except FileNotFoundError:
            return {}
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1 or info.st_mode & 0o022 or info.st_size > 16384:
                raise CaptureError('Unsafe XDG user directory configuration')
            chunks = bytearray()
            while len(chunks) <= 16384:
                chunk = os.read(fd, 16385 - len(chunks))
                if not chunk:
                    break
                chunks.extend(chunk)
            data = bytes(chunks)
            if len(data) > 16384:
                raise CaptureError('XDG directory configuration exceeded limit')
        finally:
            os.close(fd)
    finally:
        os.close(dfd)
    result = {}
    for line in data.decode('utf-8', 'strict').splitlines():
        match = re.fullmatch(r'\s*(XDG_PICTURES_DIR|XDG_VIDEOS_DIR)="([^"`\\]*)"\s*', line)
        if not match:
            continue
        value = match[2]
        if value.startswith('$HOME/'):
            value = env['HOME'] + value[5:]
        if '$' in value or not value.startswith('/') or re.search(r'[\x00-\x1f\x7f]', value):
            raise CaptureError('Invalid XDG output directory')
        result[match[1]] = value
    return result


def output_directory(env, action):
    recording = action == 'record'
    override = 'OMARCHY_SCREENRECORD_DIR' if recording else 'OMARCHY_SCREENSHOT_DIR'
    xdg = 'XDG_VIDEOS_DIR' if recording else 'XDG_PICTURES_DIR'
    if env.get(override):
        return env[override]
    if env.get(xdg):
        return env[xdg]
    return read_config(env).get(xdg, env['HOME'] + ('/Videos' if recording else '/Pictures'))


class CaptureFile:
    """An anonymous 0600 inode, published through its fd without overwrites."""
    def __init__(self, directory, action):
        self.directory = directory
        self.dirfd = open_directory(directory, create=True)
        self.fd = None
        self.name = ''
        self.action = action
        try:
            self.fd = os.open('.', os.O_TMPFILE | os.O_RDWR | os.O_CLOEXEC, 0o600, dir_fd=self.dirfd)
            os.fchmod(self.fd, 0o600)
        except BaseException:
            self.close()
            raise CaptureError('Output filesystem must support anonymous capture files')

    def publish(self):
        info = os.fstat(self.fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size <= 0:
            raise CaptureError('Capture produced an empty file')
        os.fsync(self.fd)
        prefix, extension = ('screenrecording', 'mp4') if self.action == 'record' else ('screenshot', 'png')
        for _ in range(4):
            name = f'{prefix}-{time.strftime("%Y-%m-%d_%H-%M-%S")}-{secrets.token_hex(8)}.{extension}'
            try:
                os.link(f'/proc/self/fd/{self.fd}', name, dst_dir_fd=self.dirfd, follow_symlinks=True)
            except FileExistsError:
                continue
            os.fsync(self.dirfd)
            self.name = name
            return name
        raise CaptureError('Could not allocate a unique capture filename')

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None
        if self.dirfd is not None:
            os.close(self.dirfd)
            self.dirfd = None
