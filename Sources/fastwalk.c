// Fast recursive file walker used by the dry-run preview.
// Swift's FileManager enumerator costs several seconds for ~400k files; this
// C loop only does opendir/lstat/fprintf and runs in well under a second.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>
#include <sys/stat.h>

static long walk(const char *path, FILE *out, long long *total, long limit) {
    DIR *dir = opendir(path);
    if (!dir) return 0;

    struct dirent *entry;
    long count = 0;

    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;

        size_t need = strlen(path) + strlen(entry->d_name) + 2;
        char *child = malloc(need);
        if (!child) continue;
        snprintf(child, need, "%s/%s", path, entry->d_name);

        struct stat st;
        if (lstat(child, &st) == 0) {
            if (S_ISLNK(st.st_mode)) {
                // never follow symlinks: they could point outside the cache
            } else if (S_ISDIR(st.st_mode)) {
                count += walk(child, out, total, limit);
            } else if (S_ISREG(st.st_mode)) {
                if (count < limit) {
                    long long bytes = (long long)st.st_blocks * 512;
                    fprintf(out, "%lld\t%s\n", bytes, child);
                    *total += bytes;
                }
                count++;
            }
        }
        free(child);
    }

    closedir(dir);
    return count;
}

// Returns the number of regular files found, or -1 when the output file cannot
// be opened. Writes up to `limit` lines of "allocated_bytes<TAB>path".
long cd_scan(const char *root, const char *output_path, long long *total_bytes, long limit) {
    FILE *out = fopen(output_path, "w");
    if (!out) return -1;

    long long total = 0;
    long count = walk(root, out, &total, limit);
    fclose(out);
    if (total_bytes) *total_bytes = total;
    return count;
}

// Recursive delete: unlink files, rmdir directories, never follow symlinks.
static int rmtree_inner(const char *path) {
    struct stat st;
    if (lstat(path, &st) != 0) return -1;
    if (!S_ISDIR(st.st_mode)) return unlink(path);

    DIR *dir = opendir(path);
    if (!dir) return -1;

    struct dirent *entry;
    int rc = 0;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;

        size_t need = strlen(path) + strlen(entry->d_name) + 2;
        char *child = malloc(need);
        if (!child) { rc = -1; continue; }
        snprintf(child, need, "%s/%s", path, entry->d_name);

        struct stat cst;
        if (lstat(child, &cst) == 0) {
            if (S_ISDIR(cst.st_mode)) {
                if (rmtree_inner(child) != 0) rc = -1;
            } else {
                if (unlink(child) != 0) rc = -1;
            }
        }
        free(child);
    }
    closedir(dir);
    if (rmdir(path) != 0) rc = -1;
    return rc;
}

int cd_rmtree(const char *path) {
    return rmtree_inner(path);
}
