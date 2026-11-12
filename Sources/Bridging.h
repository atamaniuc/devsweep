#ifndef CLEANDISK_BRIDGING_H
#define CLEANDISK_BRIDGING_H

long cd_scan(const char *root, const char *output_path, long long *total_bytes, long limit);
int cd_rmtree(const char *path);

#endif
