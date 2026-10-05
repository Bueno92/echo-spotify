#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <sys/fsuid.h>
#include <sys/types.h>
#include <unistd.h>

/*
 * Run a command with fsgid == real gid.
 *
 * echo-dot-assist launches hassmic with:
 *   real gid = NET_GID (3990)
 *   effective gid = aipc
 * and its firewall owner rule allows sockets tagged with gid 3990.
 *
 * For librespot we keep fsgid=3990 for the lifetime of the process so all
 * sockets created deep inside Rust/tokio inherit the allowed socket owner.
 * spotify-mixplay restores fsgid to egid before opening Amazon mixer paths.
 */
int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: spotify-netexec COMMAND [ARGS...]\n");
        return 2;
    }

    gid_t rgid = getgid();
    gid_t egid = getegid();
    gid_t old = setfsgid(rgid);
    gid_t now = setfsgid((gid_t)-1);

    if (now != rgid) {
        fprintf(stderr,
                "spotify-netexec: setfsgid failed: rgid=%u egid=%u old=%u now=%u\n",
                (unsigned)rgid, (unsigned)egid, (unsigned)old, (unsigned)now);
        return 1;
    }

    fprintf(stderr,
            "spotify-netexec: rgid=%u egid=%u fsgid=%u; exec %s\n",
            (unsigned)rgid, (unsigned)egid, (unsigned)now, argv[1]);

    execvp(argv[1], &argv[1]);
    perror("spotify-netexec: execvp");
    return 127;
}
