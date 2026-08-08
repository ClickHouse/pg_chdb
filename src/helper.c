/*
 * Starting the chdb_helper process and trading Native blocks with it.
 *
 * libchdb often crashes when an allocation fails. Under postmaster Postgres
 * would kill every backend and run crash recovery. Instead run chDB in an
 * isolated process postmaster never registered.
 */

#include "postgres.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>
#ifdef __linux__
#include <sys/prctl.h>
#endif

#include "lib/stringinfo.h"
#include "mb/pg_wchar.h"
#include "miscadmin.h"
#include "storage/latch.h"
#include "utils/memutils.h"
#include "utils/palloc.h"
#include "utils/wait_event.h"

#include "helper.h"
#include "setup.h"

/* The program that links libchdb, installed beside the extension library. */
#define CHDB_HELPER_PROGRAM "chdb_helper"

#define CHDB_HELPER_ERR_MAX 4096

/* Milliseconds between wakeups while a channel is idle, so errors still drain. */
#define CHDB_HELPER_POLL_MS 1000

struct chdbHelper {
    MemoryContextCallback cleanup;
    pid_t pid;
    int data;      /* our socketpair end, -1 once closed */
    int err;       /* error pipe read end, -1 at EOF */
    int setup;     /* setup pipe write end, -1 once written */
    int data_peer; /* the helper's ends, held only until the fork */
    int err_peer;
    int setup_peer;
    const char* query;
    bool reaped;
    int status;     /* wait status, negative when waitpid gave none */
    int wait_errno; /* why waitpid gave none */
    size_t err_len;
    char err_buf[CHDB_HELPER_ERR_MAX];
};

static void
close_fd(int* fd) {
    if (*fd >= 0) {
        close(*fd);
        *fd = -1;
    }
}

/* Sleeps until `fd` is ready, letting a cancel or a shutdown through. */
static void
wait_fd(int fd, uint32 event) {
    WaitLatchOrSocket(
        MyLatch,
        event | WL_LATCH_SET | WL_TIMEOUT | WL_EXIT_ON_PM_DEATH,
        fd,
        CHDB_HELPER_POLL_MS,
        PG_WAIT_EXTENSION
    );
    ResetLatch(MyLatch);
}

/*
 * Takes whatever the helper has written to its error channel. Keeps the head of
 * it and discards the rest, since a full pipe would stall the helper.
 */
static void
drain_err(chdbHelper* h) {
    char sink[CHDB_HELPER_ERR_MAX];

    while (h->err >= 0) {
        size_t room = sizeof(h->err_buf) - 1 - h->err_len;
        char* into  = room ? h->err_buf + h->err_len : sink;
        ssize_t got = read(h->err, into, room ? room : sizeof(sink));

        if (got > 0) {
            h->err_len += into == sink ? 0 : (size_t)got;
        } else if (got == 0) {
            close_fd(&h->err);
        } else if (errno != EINTR) {
            return; /* EAGAIN, or a pipe we can no longer read */
        }
    }
}

/* Collects the helper's exit status. */
static int
reap(chdbHelper* h) {
    if (h->reaped) {
        return h->status;
    }

    while (waitpid(h->pid, &h->status, 0) < 0) {
        if (errno != EINTR) {
            h->wait_errno = errno;
            h->status     = -1;
            break;
        }
    }
    h->reaped = true;

    return h->status;
}

/* Waits for the helper's error output to end, then reaps it. */
static int
drain_and_reap(chdbHelper* h) {
    while (h->err >= 0) {
        CHECK_FOR_INTERRUPTS();
        drain_err(h);
        if (h->err >= 0) {
            wait_fd(h->err, WL_SOCKET_READABLE);
        }
    }

    return reap(h);
}

/* Memory context callback, kills helper process. */
static void
stop_helper(void* arg) {
    chdbHelper* h = arg;

    close_fd(&h->data);
    close_fd(&h->err);
    close_fd(&h->setup);
    close_fd(&h->data_peer);
    close_fd(&h->err_peer);
    close_fd(&h->setup_peer);
    if (h->pid > 0 && !h->reaped) {
        kill(h->pid, SIGKILL);
        reap(h);
    }
}

/*
 * The helper's error text, minus a Request ID line that would differ between
 * runs and swamp the message. NULL when the helper said nothing.
 *
 * The capture stops at whatever byte filled the buffer, so pull the cut back
 * to a character boundary: half a character reaches the client as text and
 * fails its encoding check.
 */
static const char*
helper_error(chdbHelper* h) {
    /* Strip trailing newlines. */
    while (h->err_len &&
           (h->err_buf[h->err_len - 1] == '\n' || h->err_buf[h->err_len - 1] == '\r')) {
        h->err_len--;
    }
    h->err_len =
        (size_t)pg_encoding_mbcliplen(PG_UTF8, h->err_buf, h->err_len, h->err_len);
    h->err_buf[h->err_len] = '\0';
    if (!h->err_len) {
        return NULL;
    }

    const char* id  = strstr(h->err_buf, "Request ID:");
    const char* eol = id ? strchr(id, '\n') : NULL;
    if (eol) {
        memmove((char*)id, eol + 1, strlen(eol + 1) + 1);
        h->err_len = strlen(h->err_buf);
    }

    return h->err_buf;
}

/* How the helper ended, for a report it left no message of its own for. */
static const char*
helper_end(chdbHelper* h) {
    if (h->status < 0) {
        return psprintf(
            "chDB (pid %d) could not be waited for: %s.",
            (int)h->pid,
            strerror(h->wait_errno)
        );
    }
    if (WIFEXITED(h->status)) {
        if (WEXITSTATUS(h->status) == CHDB_HELPER_LOST_BACKEND) {
            return "chDB lost the channel to the copy.";
        }

        return psprintf("chDB exited with status %d.", WEXITSTATUS(h->status));
    }

    return "chDB ended abnormally.";
}

/* Raises with whatever the helper managed to say before it went. */
static void
report_helper(chdbHelper* h, const char* what) {
    drain_and_reap(h);
    const char* detail = helper_error(h);

    if (h->status >= 0 && WIFSIGNALED(h->status)) {
        ereport(
            ERROR,
            errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
            errmsg("chdb: chDB was terminated by signal %d", WTERMSIG(h->status)),
            errdetail("%s", detail ? detail : "chDB produced no message."),
            errcontext("query: %s", h->query)
        );
    }

    ereport(
        ERROR,
        errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
        errmsg("chdb: %s", what),
        errdetail("%s", detail ? detail : helper_end(h)),
        errcontext("query: %s", h->query)
    );
}

static void
set_flag(int fd, int get, int set, int flag) {
    int flags = fcntl(fd, get);

    if (flags < 0 || fcntl(fd, set, flags | flag) < 0) {
        ereport(
            ERROR,
            errcode_for_socket_access(),
            errmsg("chdb: could not configure the chDB channel: %m")
        );
    }
}

/* Moves a descriptor clear of the standard ones the helper is about to take. */
static int
reserve_fd(int fd) {
    if (fd > CHDB_SETUP_FD) {
        return fd;
    }
    int high = fcntl(fd, F_DUPFD, 10);
    close(fd);

    return high;
}

/* dup2, except that a descriptor already in place only needs to stay open. */
static bool
place_fd(int fd, int target) {
    return fd == target ? fcntl(fd, F_SETFD, 0) == 0 : dup2(fd, target) == target;
}

/*
 * Everything between the fork and the exec runs in a process that still holds
 * the backend's Postgres state, so it may only _exit.
 */
static void
exec_helper(chdbHelper* h, const char* program, bool is_from) {
    char* const argv[] = { (char*)program, NULL };
    int null           = open("/dev/null", O_RDWR);

    h->data_peer  = reserve_fd(h->data_peer);
    h->err_peer   = reserve_fd(h->err_peer);
    h->setup_peer = reserve_fd(h->setup_peer);
    null          = reserve_fd(null);

    /* The channel the copy does not use must not reach the backend's own. */
    if (!place_fd(is_from ? null : h->data_peer, STDIN_FILENO) ||
        !place_fd(is_from ? h->data_peer : null, STDOUT_FILENO) ||
        !place_fd(h->err_peer, STDERR_FILENO) ||
        !place_fd(h->setup_peer, CHDB_SETUP_FD)) {
        _exit(126);
    }

    /* Postgres ignores SIGPIPE; ClickHouse wants the default disposition. */
    signal(SIGPIPE, SIG_DFL);
#ifdef __linux__
    prctl(PR_SET_PDEATHSIG, SIGKILL);
#endif

    execv(argv[0], argv);
    _exit(127);
}

/*
 * Writes `len` bytes to `fd`, taking the helper's error output whenever the
 * channel would block. False with errno set for a write that cannot go on.
 */
static bool
write_all(chdbHelper* h, int fd, const void* p, size_t len) {
    const char* at = p;

    while (len) {
        CHECK_FOR_INTERRUPTS();
        ssize_t put = write(fd, at, len);

        if (put > 0) {
            at += put;
            len -= put;
        } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
            drain_err(h);
            wait_fd(fd, WL_SOCKET_WRITEABLE);
        } else if (errno != EINTR) {
            return false;
        }
    }

    return true;
}

/* Hands the helper its setup payload, then closes the channel it arrived on. */
static void
write_setup(chdbHelper* h, const char* setup, size_t len) {
    if (!write_all(h, h->setup, setup, len)) {
        /*
         * A closed read end means the helper is already going, and it accounts
         * for that better than errno does. Anything else leaves it waiting on
         * a payload that will not arrive, so report without waiting for it.
         */
        if (errno == EPIPE) {
            report_helper(h, "could not start chDB");
        }
        ereport(
            ERROR,
            errcode_for_socket_access(),
            errmsg("chdb: could not send the query to chDB: %m")
        );
    }
    close_fd(&h->setup);
}

static void
append_string(StringInfo buf, const char* str) {
    uint32_t len = (uint32_t)strlen(str);

    appendBinaryStringInfo(buf, (char*)&len, sizeof(len));
    appendBinaryStringInfo(buf, str, len);
}

/* The payload src/setup.h describes. */
static void
build_setup(
    StringInfo buf,
    bool is_from,
    const char* query,
    char* const* names,
    char* const* values,
    size_t nparams
) {
    uint8_t flag   = is_from ? 1 : 0;
    uint16_t count = (uint16_t)nparams;

    appendBinaryStringInfo(buf, (char*)&flag, sizeof(flag));
    append_string(buf, query);
    appendBinaryStringInfo(buf, (char*)&count, sizeof(count));
    for (size_t i = 0; i < nparams; i++) {
        append_string(buf, names[i]);
        append_string(buf, values[i]);
    }

    if (buf->len > CHDB_SETUP_MAX) {
        ereport(
            ERROR,
            errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
            errmsg("chdb: query is too large to send to chDB")
        );
    }
}

/* Both ends land in `h` before anything can raise, so cleanup owns them. */
static void
open_channel(int* first, int* second, bool duplex) {
    int fd[2];

    if ((duplex ? socketpair(AF_UNIX, SOCK_STREAM, 0, fd) : pipe(fd)) < 0) {
        ereport(
            ERROR,
            errcode_for_socket_access(),
            errmsg("chdb: could not open a channel to chDB: %m")
        );
    }
    *first  = fd[0];
    *second = fd[1];
}

chdbHelper*
chdb_helper_start(
    bool is_from,
    const char* query,
    char* const* names,
    char* const* values,
    size_t nparams
) {
    chdbHelper* h = palloc0(sizeof(*h));

    h->pid        = -1;
    h->data       = -1;
    h->err        = -1;
    h->setup      = -1;
    h->data_peer  = -1;
    h->err_peer   = -1;
    h->setup_peer = -1;
    h->query      = query;

    /* Registered first, so every descriptor below has an owner already. */
    h->cleanup.func = stop_helper;
    h->cleanup.arg  = h;
    MemoryContextRegisterResetCallback(CurrentMemoryContext, &h->cleanup);

    char pkglib[MAXPGPATH];
    get_pkglib_path(my_exec_path, pkglib);
    char program[MAXPGPATH];
    snprintf(program, sizeof(program), "%s/%s", pkglib, CHDB_HELPER_PROGRAM);
    if (access(program, X_OK) != 0) {
        ereport(
            ERROR,
            errcode_for_file_access(),
            errmsg("chdb: could not execute \"%s\": %m", program),
            errhint("The chdb extension installs chdb_helper beside its libraries.")
        );
    }

    StringInfoData setup;
    initStringInfo(&setup);
    build_setup(&setup, is_from, query, names, values, nparams);

    open_channel(&h->data, &h->data_peer, true);
    open_channel(&h->err, &h->err_peer, false);
    open_channel(&h->setup_peer, &h->setup, false);

    /* Only the ends the helper is given may survive its exec. */
    set_flag(h->data, F_GETFD, F_SETFD, FD_CLOEXEC);
    set_flag(h->err, F_GETFD, F_SETFD, FD_CLOEXEC);
    set_flag(h->setup, F_GETFD, F_SETFD, FD_CLOEXEC);
    set_flag(h->data, F_GETFL, F_SETFL, O_NONBLOCK);
    set_flag(h->err, F_GETFL, F_SETFL, O_NONBLOCK);
    set_flag(h->setup, F_GETFL, F_SETFL, O_NONBLOCK);

    /* Postgres buffers would otherwise be flushed twice, once by each side. */
    fflush(NULL);
    h->pid = fork();
    if (h->pid < 0) {
        ereport(ERROR, errcode_for_file_access(), errmsg("chdb: could not fork: %m"));
    }
    if (h->pid == 0) {
        exec_helper(h, program, is_from);
    }
    elog(DEBUG1, "chdb: chdb_helper pid %d", (int)h->pid);

    close_fd(&h->data_peer);
    close_fd(&h->err_peer);
    close_fd(&h->setup_peer);
    write_setup(h, setup.data, setup.len);
    pfree(setup.data);

    return h;
}

/*
 * Drain error output when data socket would block. A full error pipe prevents
 * helper from reading or writing data, so draining it lets helper continue.
 */
size_t
chdb_helper_recv(chdbHelper* h, void* buf, size_t len) {
    for (;;) {
        CHECK_FOR_INTERRUPTS();
        ssize_t got = read(h->data, buf, len);
        if (got > 0) {
            return (size_t)got;
        }
        if (got == 0) {
            close_fd(&h->data);
            if (drain_and_reap(h) != 0) {
                report_helper(h, "error executing chDB query");
            }

            return 0; /* end of stream */
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            drain_err(h);
            wait_fd(h->data, WL_SOCKET_READABLE);
        } else if (errno != EINTR) {
            report_helper(h, "error fetching chDB query result");
        }
    }
}

void
chdb_helper_write(chdbHelper* h, const void* p, size_t len) {
    if (!write_all(h, h->data, p, len)) {
        report_helper(h, "error appending to chDB query");
    }
}

void
chdb_helper_finish(chdbHelper* h) {
    /* End of stream for the helper, which then finishes its insert. */
    close_fd(&h->data);

    if (drain_and_reap(h) != 0) {
        report_helper(h, "error finishing chDB query");
    }
}
