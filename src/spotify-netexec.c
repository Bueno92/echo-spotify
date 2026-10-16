#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>

/*
 * Run a command with the real group (NET_GID 3990) as its real, effective
 * and saved group.
 *
 * echo-dot-assist launches hassmic with:
 *   real gid = NET_GID (3990)
 *   effective gid = aipc
 * and its firewall owner rule (--gid-owner 3990) reads the file system group
 * a socket was created with.  hassmic switches it with setfsgid() around each
 * socket; that does not survive an exec: execve sets the file system group to
 * the effective one.  The first version did setfsgid() and then exec'd
 * librespot, which therefore ran with fsgid = aipc and was held to local
 * addresses (checked on a PC: Gid "3990 1000 1000 1000" after the exec).
 * With 3990 effective, exec keeps fsgid = 3990 for librespot's whole life.
 * librespot needs no mixer: its sound goes through a pipe to mixplay, which
 * runs with aipc (start-spotify.sh), or to hassmic.
 */
int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: spotify-netexec COMMAND [ARGS...]\n");
        return 2;
    }

    gid_t rgid = getgid();
    if (setresgid(rgid, rgid, rgid)) {
        perror("spotify-netexec: setresgid");
        return 1;
    }
    fprintf(stderr, "spotify-netexec: gid %u (real, effective, saved, file system); exec %s\n",
            (unsigned)rgid, argv[1]);

    execvp(argv[1], &argv[1]);
    perror("spotify-netexec: execvp");
    return 127;
}
