/**
 * mml_native.c
 *
 * Cross-platform C wrapper around OS memory-mapping APIs.
 *
 * Supported platforms:
 *   • POSIX  (Linux, macOS, Android, iOS)   → mmap / msync / munmap
 *   • Win32  (Windows)                       → CreateFileMapping / MapViewOfFile
 *
 * Build:
 *   Linux/macOS:  gcc -O2 -shared -fPIC -o mml_native.so mml_native.c
 *   Windows:      cl /O2 /LD mml_native.c /Fe:mml_native.dll
 *   CMake:        see CMakeLists.txt
 *
 * Error codes returned by every function:
 *   0  = MML_OK
 *  -1  = MML_ERR_INVALID_ARG
 *  -2  = MML_ERR_IO
 *  -3  = MML_ERR_OUT_OF_MEMORY
 *  -4  = MML_ERR_NOT_SUPPORTED
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ── Error codes ─────────────────────────────────────────────────────────── */

#define MML_OK              0
#define MML_ERR_INVALID_ARG (-1)
#define MML_ERR_IO          (-2)
#define MML_ERR_OOM         (-3)
#define MML_ERR_UNSUPPORTED (-4)

/* ── Flags ───────────────────────────────────────────────────────────────── */

#define MML_FLAG_READ_ONLY   0x01
#define MML_FLAG_CREATE      0x02
#define MML_FLAG_SEQUENTIAL  0x04
#define MML_FLAG_RANDOM      0x08

/* ── Handle ──────────────────────────────────────────────────────────────── */

typedef struct MmlHandle {
    void*   data;       /* pointer to first mapped byte              */
    int64_t size;       /* mapped length in bytes                    */
    int     flags;      /* original open flags                       */
#if defined(_WIN32)
    HANDLE  file_handle;
    HANDLE  map_handle;
#else
    int     fd;
#endif
} MmlHandle;

/* ═══════════════════════════════════════════════════════════════════════════
 * POSIX implementation
 * ═══════════════════════════════════════════════════════════════════════════ */
#if !defined(_WIN32)

#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <errno.h>

#ifdef __linux__
#  include <sys/mman.h>   /* MADV_SEQUENTIAL / MADV_RANDOM */
#endif

int mml_open(const char* path, int64_t size, int flags, MmlHandle** out) {
    if (!path || !out) return MML_ERR_INVALID_ARG;

    MmlHandle* h = (MmlHandle*)calloc(1, sizeof(MmlHandle));
    if (!h) return MML_ERR_OOM;

    h->flags = flags;

    /* ── Open / create the file ─────────────────────────────────────────── */
    int open_flags = (flags & MML_FLAG_READ_ONLY) ? O_RDONLY : O_RDWR;
    if (flags & MML_FLAG_CREATE) open_flags |= O_CREAT;

    h->fd = open(path, open_flags, 0644);
    if (h->fd < 0) { free(h); return MML_ERR_IO; }

    /* ── Resize if requested ─────────────────────────────────────────────── */
    if ((flags & MML_FLAG_CREATE) && size > 0) {
        if (ftruncate(h->fd, (off_t)size) < 0) {
            close(h->fd); free(h); return MML_ERR_IO;
        }
    }

    /* ── Determine actual mapped size ────────────────────────────────────── */
    struct stat st;
    if (fstat(h->fd, &st) < 0) {
        close(h->fd); free(h); return MML_ERR_IO;
    }
    h->size = (int64_t)st.st_size;
    if (h->size == 0) { close(h->fd); free(h); return MML_ERR_IO; }

    /* ── Map the file ────────────────────────────────────────────────────── */
    int prot  = PROT_READ | ((flags & MML_FLAG_READ_ONLY) ? 0 : PROT_WRITE);
    int mflags = MAP_SHARED;

    h->data = mmap(NULL, (size_t)h->size, prot, mflags, h->fd, 0);
    if (h->data == MAP_FAILED) {
        close(h->fd); free(h); return MML_ERR_IO;
    }

    /* ── Access hint ─────────────────────────────────────────────────────── */
#ifdef MADV_SEQUENTIAL
    if (flags & MML_FLAG_SEQUENTIAL)
        madvise(h->data, (size_t)h->size, MADV_SEQUENTIAL);
    else if (flags & MML_FLAG_RANDOM)
        madvise(h->data, (size_t)h->size, MADV_RANDOM);
#endif

    *out = h;
    return MML_OK;
}

void* mml_data(MmlHandle* h) {
    return h ? h->data : NULL;
}

int mml_flush(MmlHandle* h, int64_t offset, int64_t length) {
    if (!h) return MML_ERR_INVALID_ARG;
    if (h->flags & MML_FLAG_READ_ONLY) return MML_OK; /* nothing to flush */
    char* start = (char*)h->data + offset;
    if (msync(start, (size_t)length, MS_SYNC) < 0) return MML_ERR_IO;
    return MML_OK;
}

int mml_close(MmlHandle* h) {
    if (!h) return MML_ERR_INVALID_ARG;
    if (h->data) munmap(h->data, (size_t)h->size);
    if (h->fd >= 0) close(h->fd);
    free(h);
    return MML_OK;
}

int64_t mml_size(MmlHandle* h) {
    return h ? h->size : 0;
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Windows implementation
 * ═══════════════════════════════════════════════════════════════════════════ */
#else  /* _WIN32 */

#include <windows.h>

int mml_open(const char* path, int64_t size, int flags, MmlHandle** out) {
    if (!path || !out) return MML_ERR_INVALID_ARG;

    MmlHandle* h = (MmlHandle*)calloc(1, sizeof(MmlHandle));
    if (!h) return MML_ERR_OOM;

    h->flags = flags;

    DWORD access     = (flags & MML_FLAG_READ_ONLY) ? GENERIC_READ
                                                     : (GENERIC_READ | GENERIC_WRITE);
    DWORD share_mode = FILE_SHARE_READ;
    DWORD create_dis = (flags & MML_FLAG_CREATE) ? CREATE_ALWAYS : OPEN_EXISTING;

    h->file_handle = CreateFileA(path, access, share_mode, NULL, create_dis,
                                 FILE_ATTRIBUTE_NORMAL, NULL);
    if (h->file_handle == INVALID_HANDLE_VALUE) { free(h); return MML_ERR_IO; }

    /* Resize if requested */
    if ((flags & MML_FLAG_CREATE) && size > 0) {
        LARGE_INTEGER li; li.QuadPart = size;
        SetFilePointerEx(h->file_handle, li, NULL, FILE_BEGIN);
        SetEndOfFile(h->file_handle);
    }

    /* Actual file size */
    LARGE_INTEGER fs;
    GetFileSizeEx(h->file_handle, &fs);
    h->size = fs.QuadPart;

    DWORD page_protect = (flags & MML_FLAG_READ_ONLY) ? PAGE_READONLY : PAGE_READWRITE;
    DWORD map_access   = (flags & MML_FLAG_READ_ONLY) ? FILE_MAP_READ : FILE_MAP_ALL_ACCESS;

    h->map_handle = CreateFileMapping(h->file_handle, NULL, page_protect,
                                      (DWORD)(h->size >> 32),
                                      (DWORD)(h->size & 0xFFFFFFFF), NULL);
    if (!h->map_handle) {
        CloseHandle(h->file_handle); free(h); return MML_ERR_IO;
    }

    h->data = MapViewOfFile(h->map_handle, map_access, 0, 0, 0);
    if (!h->data) {
        CloseHandle(h->map_handle); CloseHandle(h->file_handle);
        free(h); return MML_ERR_IO;
    }

    *out = h;
    return MML_OK;
}

void* mml_data(MmlHandle* h)  { return h ? h->data : NULL; }
int64_t mml_size(MmlHandle* h) { return h ? h->size : 0; }

int mml_flush(MmlHandle* h, int64_t offset, int64_t length) {
    if (!h) return MML_ERR_INVALID_ARG;
    if (h->flags & MML_FLAG_READ_ONLY) return MML_OK;
    if (!FlushViewOfFile((char*)h->data + offset, (SIZE_T)length)) return MML_ERR_IO;
    if (!FlushFileBuffers(h->file_handle)) return MML_ERR_IO;
    return MML_OK;
}

int mml_close(MmlHandle* h) {
    if (!h) return MML_ERR_INVALID_ARG;
    if (h->data)       UnmapViewOfFile(h->data);
    if (h->map_handle) CloseHandle(h->map_handle);
    if (h->file_handle != INVALID_HANDLE_VALUE) CloseHandle(h->file_handle);
    free(h);
    return MML_OK;
}

#endif /* _WIN32 */

/* ─── Shared error-string helper ─────────────────────────────────────────── */

const char* mml_error_string(int code) {
    switch (code) {
        case MML_OK:              return "OK";
        case MML_ERR_INVALID_ARG: return "Invalid argument";
        case MML_ERR_IO:          return "I/O error";
        case MML_ERR_OOM:         return "Out of memory";
        case MML_ERR_UNSUPPORTED: return "Unsupported operation";
        default:                  return "Unknown error";
    }
}
