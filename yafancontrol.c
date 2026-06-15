/* yafancontrol — in-process ThinkPad fan controller.
 *
 * C reimplementation of the original yafancontrol.sh, kept fully drop-in: same
 * thresholds, same /etc/yafancontrol/yafancontrol.cfg, same closed-loop control
 * (drive the EC's measured fan RPM toward a temperature-derived setpoint by
 * toggling between "level 7" and "level disengaged"). The bash version spawned
 * cat/cat/grep/awk/sleep five times every second — a 1 Hz CPU spike. This reads
 * temp/fan with pread() and sleeps with nanosleep(): one poll is ~3 syscalls and
 * microseconds of CPU, and it forks nothing.
 *
 * Two deliberate differences from the bash original:
 *   - No startup calibration sweep. The bash script spun the fan to "disengaged"
 *     for ~60 s on every start to discover min/max RPM. Those bounds are now the
 *     config keys fan_speed_min / fan_speed_max; run `yafancontrol --calibrate`
 *     once to measure them for your machine.
 *   - Arms the thinkpad_acpi EC fan watchdog (120 s): if the daemon dies
 *     uncleanly the firmware resumes safe fan control within 120 s. On a clean
 *     SIGTERM/SIGINT it restores "level auto" immediately, like the bash trap.
 *
 * Build:  cc -O2 -Wall -Wextra -o yafancontrol yafancontrol.c
 *
 * Copyright (c) 2023-2026 Thomas Hartwig. Licensed under the Apache License 2.0.
 * Provided "as is" without warranty of any kind; use at your own risk.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <time.h>
#include <errno.h>

/* ---- configuration (defaults mirror yafancontrol.cfg; millidegrees C) ---- */
static long temp_raise    = 86000;   /* above -> ramp setpoint up            */
static long temp_lower    = 84000;   /* below -> ramp setpoint down          */
static long temp_kick_in  = 84000;   /* above -> engage active control       */
static long temp_kick_off = 74000;   /* below -> release back to "auto"      */
static int  verbosity     = 7;
static long interval_ms   = 1000;    /* poll period                          */
static long fan_speed_min = 3500;    /* ~RPM at "level 7"    (run --calibrate)*/
static long fan_speed_max = 5000;    /* ~RPM at "disengaged" (run --calibrate)*/
static char temp_file[256] = "/sys/devices/virtual/thermal/thermal_zone0/temp";
static char fan_file[256]  = "/proc/acpi/ibm/fan";

static const char *L_AUTO = "level auto";
static const char *L_HIGH = "level 7";
static const char *L_FULL = "level disengaged";

static volatile sig_atomic_t g_stop = 0;
static void on_sig(int s) { (void)s; g_stop = 1; }

/* trim trailing ws/quotes, then strip leading ws/quotes, in place */
static void unquote(char *s) {
    size_t n = strlen(s);
    while (n && (s[n-1]=='\n'||s[n-1]=='\r'||s[n-1]==' '||s[n-1]=='\t'||s[n-1]=='"'))
        s[--n] = 0;
    char *p = s;
    while (*p==' '||*p=='\t'||*p=='"') p++;
    if (p != s) memmove(s, p, strlen(p)+1);
}

static void load_config(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return;                       /* defaults stand if no file */
    char line[512];
    while (fgets(line, sizeof line, f)) {
        char *h = line; while (*h==' '||*h=='\t') h++;
        if (*h=='#' || *h=='\n' || *h==0) continue;
        char *eq = strchr(h, '=');
        if (!eq) continue;
        *eq = 0;
        for (int i=(int)strlen(h)-1; i>=0 && (h[i]==' '||h[i]=='\t'); i--) h[i]=0;
        char *val = eq+1; unquote(val);
        if      (!strcmp(h,"temp_raise"))    temp_raise    = atol(val);
        else if (!strcmp(h,"temp_lower"))    temp_lower    = atol(val);
        else if (!strcmp(h,"temp_kick_in"))  temp_kick_in  = atol(val);
        else if (!strcmp(h,"temp_kick_off")) temp_kick_off = atol(val);
        else if (!strcmp(h,"verbosity"))     verbosity     = atoi(val);
        else if (!strcmp(h,"interval_ms"))   interval_ms   = atol(val);
        else if (!strcmp(h,"fan_speed_min")) fan_speed_min = atol(val);
        else if (!strcmp(h,"fan_speed_max")) fan_speed_max = atol(val);
        else if (!strcmp(h,"temp_file"))     snprintf(temp_file,sizeof temp_file,"%s",val);
        else if (!strcmp(h,"fan_file"))      snprintf(fan_file, sizeof fan_file, "%s",val);
    }
    fclose(f);
}

/* fresh read at offset 0 (sysfs/procfs regenerate the buffer at pos 0) */
static long read_temp(int fd) {
    char b[32];
    ssize_t n = pread(fd, b, sizeof b - 1, 0);
    if (n <= 0) return -1;
    b[n] = 0;
    return atol(b);
}

/* parse the "speed:\t<rpm>" line of /proc/acpi/ibm/fan */
static long read_fan_rpm(int fd) {
    char b[512];
    ssize_t n = pread(fd, b, sizeof b - 1, 0);
    if (n <= 0) return -1;
    b[n] = 0;
    char *p = strstr(b, "speed:");
    if (!p) return -1;
    p += 6;
    while (*p==' '||*p=='\t') p++;
    return atol(p);
}

static void fan_write(int fd, const char *cmd) {
    char line[48];
    int n = snprintf(line, sizeof line, "%s\n", cmd);
    if (write(fd, line, (size_t)n) < 0 && verbosity >= 1)
        fprintf(stderr, "yafancontrol: write '%s' failed: %s\n", cmd, strerror(errno));
}

static void sleep_ms(long ms) {
    struct timespec ts = { ms/1000, (ms%1000)*1000000L };
    nanosleep(&ts, NULL);
}

/* --calibrate: measure level-7 and disengaged RPM, print cfg lines, restore */
static int calibrate(void) {
    int ffd = open(fan_file, O_WRONLY);
    int rfd = open(fan_file, O_RDONLY);
    if (ffd < 0 || rfd < 0) { perror("open fan_file"); return 1; }
    fan_write(ffd, "watchdog 120");
    fprintf(stderr, "calibrating — spins the fan up for ~30s...\n");
    fan_write(ffd, L_HIGH); sleep_ms(15000);
    long lo = read_fan_rpm(rfd);
    fan_write(ffd, L_FULL); sleep_ms(15000);
    long hi = read_fan_rpm(rfd);
    fan_write(ffd, L_AUTO);
    printf("fan_speed_min=%ld\nfan_speed_max=%ld\n", lo, hi);
    return 0;
}

int main(int argc, char **argv) {
    load_config("/etc/yafancontrol/yafancontrol.cfg");

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--calibrate")) return calibrate();
        else if (!strcmp(argv[i], "-v") && i+1 < argc) verbosity = atoi(argv[++i]);
        else { fprintf(stderr, "usage: yafancontrol [--calibrate] [-v N]\n"); return 2; }
    }

    if (temp_raise < temp_lower || temp_kick_in < temp_kick_off) {
        fprintf(stderr, "yafancontrol: invalid thresholds in config\n");
        return 1;
    }

    struct sigaction sa; memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_sig;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT,  &sa, NULL);

    int tfd = open(temp_file, O_RDONLY);
    int rfd = open(fan_file,  O_RDONLY);
    int ffd = open(fan_file,  O_WRONLY);
    if (tfd < 0 || rfd < 0 || ffd < 0) {
        fprintf(stderr, "yafancontrol: open failed: %s\n", strerror(errno));
        return 1;
    }

    fan_write(ffd, "watchdog 120");       /* EC fail-safe if we crash */

    bool kicked = false;
    long current = fan_speed_max;         /* RPM setpoint, clamped [min,max]  */
    const char *level = L_AUTO;           /* last commanded level             */
    fan_write(ffd, L_AUTO);

    if (verbosity >= 5)
        fprintf(stderr, "yafancontrol: started (kick_in=%ld kick_off=%ld raise=%ld "
                "lower=%ld min=%ld max=%ld interval=%ldms)\n",
                temp_kick_in, temp_kick_off, temp_raise, temp_lower,
                fan_speed_min, fan_speed_max, interval_ms);

    while (!g_stop) {
        long temp = read_temp(tfd);
        long fan  = read_fan_rpm(rfd);
        if (temp < 0) { sleep_ms(interval_ms); continue; }

        if (temp > temp_kick_in && !kicked) {
            kicked = true;
            if (verbosity >= 7) fprintf(stderr, "yafancontrol: kick in @ %ld°C\n", temp/1000);
        }
        if (temp < temp_kick_off && kicked) {
            kicked = false;
            if (verbosity >= 7) fprintf(stderr, "yafancontrol: kick out @ %ld°C\n", temp/1000);
        }

        const char *want = level;
        if (kicked) {
            if (temp > temp_raise) {
                current += 200;
                if (current > fan_speed_max) current = fan_speed_max;
            }
            if (temp < temp_lower) {
                current -= 200;
                if (current < fan_speed_min) current = fan_speed_min;
            }
            if      (fan >= 0 && fan < current - current/40) want = L_FULL;
            else if (fan >= 0 && fan > current)              want = L_HIGH;
            /* else: within the deadband — hold the current level */
        } else {
            want = L_AUTO;
        }

        if (want != level) {
            fan_write(ffd, want);
            level = want;
            if (verbosity >= 7)
                fprintf(stderr, "yafancontrol: %ld°C fan=%ld set=%ld -> %s\n",
                        temp/1000, fan, current, want);
        } else {
            fan_write(ffd, want);         /* re-assert: keeps the EC watchdog fed */
            if (verbosity >= 8)
                fprintf(stderr, "yafancontrol: %ld°C fan=%ld (%s)\n", temp/1000, fan, want);
        }

        sleep_ms(interval_ms);
    }

    fan_write(ffd, L_AUTO);
    if (verbosity >= 5) fprintf(stderr, "yafancontrol: stopped, fan restored to auto\n");
    return 0;
}
