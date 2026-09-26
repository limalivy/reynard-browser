#include "VideoRemux.h"
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc == 3 && strcmp(argv[1], "contains") == 0) return ReynardVideoDuration(argv[2]) > 0 ? 0 : 1;
    if (argc != 3) return 2;
    int result = ReynardRemuxVideo(argv[1], argv[2]);
    fprintf(stderr, "remux result: %d\n", result);
    return result < 0 ? 1 : 0;
}
