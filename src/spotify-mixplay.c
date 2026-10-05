#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <sys/fsuid.h>
#include <sys/types.h>
#include <unistd.h>

/*
 * Restore fsgid to the effective mixer group before exec'ing mixplay.
 * This keeps librespot's network sockets on NET_GID 3990 while avoiding
 * accidental denial when mixplay opens files/devices checked with fsgid.
 */
int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: spotify-mixplay MIXPLAY [ARGS...]\n");
        return 2;
    }

    gid_t egid = getegid();
    gid_t old = setfsgid(egid);
    gid_t now = setfsgid((gid_t)-1);

    if (now != egid) {
        fprintf(stderr,
                "spotify-mixplay: setfsgid failed: egid=%u old=%u now=%u\n",
                (unsigned)egid, (unsigned)old, (unsigned)now);
        return 1;
    }

    execvp(argv[1], &argv[1]);
    perror("spotify-mixplay: execvp");
    return 127;
}
