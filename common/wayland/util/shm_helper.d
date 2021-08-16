// Copyright © 2017-2021 Rémi Thebault
module wayland.util.shm_helper;

import std.exception : enforce;
import core.sys.posix.stdlib : mkstemp;
import core.sys.posix.unistd;
import core.sys.posix.fcntl;
import core.stdc.config : c_long;

// createMmapableFile inspired from weston source code.

/// Create a file of the given size suitable for mmap.
/// The file is created under XDG_RUNTIME_DIR and should therfore not be
/// backed stored on disk. The shared memory object will be freed by the kernel
/// when it is closed and no more mapping is alive.
int createMmapableFile(size_t size)
{
    import std.process : environment;
    enum tmplt = "/wld-d-XXXXXX";
    string base = environment.get("XDG_RUNTIME_DIR", "/tmp");
    auto path = new char[base.length + tmplt.length + 1];
    path[0 .. base.length] = base;
    path[base.length .. base.length+tmplt.length] = tmplt;
    path[base.length+tmplt.length] = '\0';

    immutable fd = createTmpfileCloexec(path.ptr);
    enforce(fd > 0, "Could not open file for mmap at "~path[0 .. $-1]);

    scope(failure) close(fd);

    import std.format : format;
    enforce(
        ftruncate(fd, size) >= 0,
        format("Could not set mmap file %s to %s bytes", path[0 .. $-1], size)
    );

    return fd;
}

private:

int
setCloexecOrClose(int fd)
{
    assert(fd != -1);
    scope(failure) close(fd);

    auto flags = fcntl(fd, F_GETFD);
    enforce(flags != -1);
    enforce(fcntl(fd, F_SETFD, flags | FD_CLOEXEC) != -1);

    return fd;
}

int
createTmpfileCloexec(char* tmpname)
{
    try
    {
        auto fd = mkstemp(tmpname);
        if (fd >= 0)
        {
            fd = setCloexecOrClose(fd);
            unlink(tmpname);
        }
        return fd;
    }
    catch(Exception ex)
    {
        return -1;
    }
}
