// mob_beam.m — Mob BEAM launcher for iOS.
// Extracted from the per-app beam_main.m stub so app code stays minimal.
// mob_set_startup_phase/error are implemented in mob_nif.m (which imports the
// Swift-generated header) so this file stays free of app-specific includes.

#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include "mob_beam.h"

// EPMD compiled into the binary (epmd.c / epmd_srv.c / epmd_cli.c compiled
// with -Dmain=epmd_ios_main). Only present in device builds; the simulator
// connects to the Mac's EPMD via the shared network stack.
#ifdef MOB_BUNDLE_OTP
extern int epmd_ios_main(int argc, char **argv);
static void* epmd_thread(void *arg) {
    char *args[] = {"epmd", NULL};
    epmd_ios_main(1, args);  // runs the EPMD event loop (does not return)
    return NULL;
}
#endif

// Compile-time defaults (simulator). Override via -D flags for device builds.
#ifndef OTP_ROOT
#define OTP_ROOT   "/tmp/otp-ios-sim"
#endif
#ifndef ERTS_VSN
#define ERTS_VSN   "erts-16.3"
#endif
#ifndef OTP_RELEASE
#define OTP_RELEASE "29"
#endif

void mob_init_ui(void) {
    // SwiftUI: the UI is driven by MobViewModel (Swift ObservableObject).
    // No UIViewController reference needed here; the hosting controller is
    // created by MobUIFactory in AppDelegate.m.
    NSLog(@"[MobBeam] mob_init_ui: SwiftUI mode ready");
}

static void mob_write_diag(const char *docs_dir, const char *name, const char *info) {
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", docs_dir, name);
    FILE *f = fopen(path, "w");
    if (f) { fprintf(f, "%s\n", info); fclose(f); }
}

// Find the device's own USB link-local (169.254.x.x) IP by walking ifaddrs.
// On simulator there is no such interface; returns NULL so callers fall back to 127.0.0.1.
static const char *find_link_local_ip(char *buf, size_t len) {
    struct ifaddrs *ifa_list;
    if (getifaddrs(&ifa_list) != 0) return NULL;
    const char *found = NULL;
    for (struct ifaddrs *ifa = ifa_list; ifa && !found; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) continue;
        struct sockaddr_in *sa = (struct sockaddr_in *)ifa->ifa_addr;
        uint32_t addr = ntohl(sa->sin_addr.s_addr);
        if ((addr >> 16) == 0xA9FE) {  // 169.254.0.0/16
            inet_ntop(AF_INET, &sa->sin_addr, buf, (socklen_t)len);
            found = buf;
        }
    }
    freeifaddrs(ifa_list);
    return found;
}

void mob_start_beam(const char* app_module) {
    mob_set_startup_phase("Setting up BEAM environment…");

    // Resolve Documents dir early for diagnostics.
    NSArray *dp = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs_ns = [dp firstObject];
    const char *docs_dir = docs_ns ? [docs_ns UTF8String] : "/tmp";
    mob_write_diag(docs_dir, "mob_diag_a_entered.txt", "mob_start_beam entered");

    // On simulator OTP_ROOT is a fixed /tmp path shared with the Mac.
    // On physical device the OTP runtime is bundled inside the .app — resolve
    // the path at runtime so it works regardless of where iOS installs the app.
#ifdef MOB_BUNDLE_OTP
    NSString *bundle_otp = [[[NSBundle mainBundle] bundlePath]
                             stringByAppendingPathComponent:@"otp"];
    const char *otp_root = [bundle_otp UTF8String];
    const char *erts_vsn = ERTS_VSN;
    const char *otp_release = OTP_RELEASE;
#else
    const char *otp_root = OTP_ROOT;
    const char *erts_vsn = ERTS_VSN;
    const char *otp_release = OTP_RELEASE;
#endif

    mob_write_diag(docs_dir, "mob_diag_b_otp_root.txt", otp_root);

    // Compose dynamic paths that depend on otp_root.
    static char bindir[512], elixir_dir[512], logger_dir[512], boot_path[512];
    snprintf(bindir,      sizeof(bindir),      "%s/%s/bin",              otp_root, erts_vsn);
    snprintf(elixir_dir,  sizeof(elixir_dir),  "%s/lib/elixir/ebin",    otp_root);
    snprintf(logger_dir,  sizeof(logger_dir),  "%s/lib/logger/ebin",    otp_root);
    snprintf(boot_path,   sizeof(boot_path),   "%s/releases/%s/start_clean", otp_root, otp_release);

    mob_write_diag(docs_dir, "mob_diag_c_paths.txt", bindir);
    NSLog(@"[MobBeam] otp_root=%s erts=%s release=%s", otp_root, erts_vsn, otp_release);

    setenv("BINDIR",   bindir, 1);
    setenv("ROOTDIR",  otp_root, 1);
    setenv("PROGNAME", "erl", 1);
    setenv("EMU",      "beam", 1);
    setenv("HOME",     "/tmp", 1);
    // Set MOB_DATA_DIR to the app's Documents directory — persistent storage
    // accessible to the app and backed up by iCloud. Used by the generated Repo
    // module to determine where to place the SQLite database file.
    // Falls back to /tmp when the documents path is unavailable (e.g. on simulator
    // when the sandbox isn't fully resolved at BEAM launch time).
    setenv("MOB_DATA_DIR", docs_dir, 1);

    // Write crash dump to app's Documents so it survives the crash and can be retrieved.
    static char crash_dump[512];
    snprintf(crash_dump, sizeof(crash_dump), "%s/mob_erl_crash.dump", docs_dir);
    setenv("ERL_CRASH_DUMP", crash_dump, 1);
    setenv("ERL_CRASH_DUMP_SECONDS", "30", 1);

    // Dist port: read from MOB_DIST_PORT env var (simulator via SIMCTL_CHILD_ prefix),
    // default to 9101 for standalone/physical launch.
    const char *env_port = getenv("MOB_DIST_PORT");
    static char dist_port_min[16], dist_port_max[16];
    snprintf(dist_port_min, sizeof(dist_port_min), "%s", env_port ? env_port : "9101");
    snprintf(dist_port_max, sizeof(dist_port_max), "%s", env_port ? env_port : "9101");

    // Determine node hostname:
    //   MOB_BUNDLE_OTP = physical device build (OTP bundled in .app).
    //   On device: find the USB link-local (169.254.x.x) interface via getifaddrs().
    //   The device's in-process EPMD binds 0.0.0.0:4369 so Mac can query it
    //   directly over USB; the dist port is also directly reachable. No iproxy needed.
    //
    //   Without MOB_BUNDLE_OTP = simulator build. Simulator shares the Mac's network
    //   stack, including Mac's USB link-local interfaces, so find_link_local_ip()
    //   would return the Mac's USB IP (wrong). Always use 127.0.0.1 on simulator.
#ifdef MOB_BUNDLE_OTP
    // Physical device: find USB link-local IP; node name is <app>_ios@<device-ip>
    static char link_local_buf[64];
    const char *ll_ip = find_link_local_ip(link_local_buf, sizeof(link_local_buf));
    const char *host_ip = ll_ip ? ll_ip : "127.0.0.1";
    static char eval_expr[280], node_name[128], beams_dir[512];
    snprintf(eval_expr, sizeof(eval_expr), "%s:start().", app_module);
    snprintf(node_name, sizeof(node_name), "%s_ios@%s", app_module, host_ip);
#else
    // Simulator: use 127.0.0.1 but include a short UDID suffix so concurrent
    // simulators get unique node names and don't conflict in Mac's EPMD.
    // SIMULATOR_UDID is set automatically by the iOS simulator runtime.
    const char *host_ip = "127.0.0.1";
    const char *sim_udid = getenv("SIMULATOR_UDID");
    static char sim_short[9];
    sim_short[0] = '\0';
    if (sim_udid) {
        int n = 0;
        for (int i = 0; sim_udid[i] && n < 8; i++) {
            unsigned char c = (unsigned char)sim_udid[i];
            if ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f')) {
                sim_short[n++] = (char)tolower(c);
            }
        }
        sim_short[n] = '\0';
    }
    static char eval_expr[280], node_name[128], beams_dir[512];
    snprintf(eval_expr, sizeof(eval_expr), "%s:start().", app_module);
    if (sim_short[0]) {
        snprintf(node_name, sizeof(node_name), "%s_ios_%s@%s", app_module, sim_short, host_ip);
    } else {
        snprintf(node_name, sizeof(node_name), "%s_ios@%s", app_module, host_ip);
    }
#endif
    mob_write_diag(docs_dir, "mob_diag_host_ip.txt", host_ip);
    snprintf(beams_dir, sizeof(beams_dir), "%s/%s", otp_root, app_module);

#ifdef MOB_BUNDLE_OTP
    // On physical device, the bundle BEAMs are read-only (code-signed).
    // deployer.ex can push updated BEAMs to Documents/otp/<app>/ via
    // `xcrun devicectl device copy to --domain-type appDataContainer`.
    // If that directory exists, prefer it over the in-bundle copy.
    static char docs_beams[512];
    snprintf(docs_beams, sizeof(docs_beams), "%s/otp/%s", docs_dir, app_module);
    if ([[NSFileManager defaultManager] fileExistsAtPath:@(docs_beams)])  {
        strlcpy(beams_dir, docs_beams, sizeof(beams_dir));
    }
    mob_write_diag(docs_dir, "mob_diag_beams_dir.txt", beams_dir);
#endif

    // MOB_BEAMS_DIR — the directory where app BEAMs (and priv/) are deployed.
    //
    // Ecto.Migrator uses :code.priv_dir(app) to locate migration .exs files, but
    // that requires an OTP lib structure ($OTP_ROOT/lib/APP-VERSION/ebin/). Mob
    // apps use a flat -pa directory, so :code.priv_dir/1 returns {error, bad_name}
    // and Ecto silently reports "Migrations already up" without running anything.
    //
    // Fix: deployer.ex copies priv/ into beams_dir/priv/. App code reads this
    // env var and passes the explicit path to Ecto.Migrator.run/4. See also the
    // corresponding comment in mob_beam.c for the Android side.
    setenv("MOB_BEAMS_DIR", beams_dir, 1);

    const char* args[] = {
        "beam",
        "-S", "1:1", "-SDcpu", "1:1", "-SDio", "1", "-A", "1", "-sbwt", "none",
        // Cap the BEAM's memory super carrier to 10MB on physical iOS devices.
        // The default 1GB virtual reservation is rejected by iOS on real hardware
        // (not on simulator where the Mac's VM handles it). Without this the BEAM
        // crashes immediately during startup on any physical iOS device.
#ifdef MOB_BUNDLE_OTP
        "-MIscs", "10",
#endif
        "--",
        "-root",     otp_root,
        "-bindir",   bindir,
        "-progname", "erl",
        "--",
        "-name",     node_name,
        "-setcookie", "mob_secret",
        "-kernel", "inet_dist_listen_min", dist_port_min,
        "-kernel", "inet_dist_listen_max", dist_port_max,
        "-noshell", "-noinput",
        "-boot",   boot_path,
        "-pa",     elixir_dir,
        "-pa",     logger_dir,
        "-pa",     beams_dir,
        "-eval",   eval_expr,
        NULL
    };
    int ac = 0;
    while (args[ac]) ac++;
    NSLog(@"[MobBeam] mob_start_beam: starting BEAM module=%s argc=%d", app_module, ac);
    mob_set_startup_phase("Starting BEAM…");
    mob_write_diag(docs_dir, "mob_diag_d_erl_start.txt", "calling erl_start");

    // Redirect stdout/stderr to a log file so BEAM error output is captured.
    char beam_log_path[512];
    snprintf(beam_log_path, sizeof(beam_log_path), "%s/beam_stdout.log", docs_dir);
    int log_fd = open(beam_log_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (log_fd >= 0) {
        dup2(log_fd, STDOUT_FILENO);
        dup2(log_fd, STDERR_FILENO);
        close(log_fd);
    }

#ifdef MOB_BUNDLE_OTP
    // Start EPMD as a thread so the BEAM can register for distribution.
    // On simulator the Mac's EPMD is reachable via the shared network stack;
    // on device there is no host EPMD, so we run our own in-process.
    pthread_t epmd_t;
    pthread_create(&epmd_t, NULL, epmd_thread, NULL);
    pthread_detach(epmd_t);
    usleep(300000);  // 300ms — give EPMD time to bind port 4369
#endif

    void erl_start(int, char**);
    erl_start(ac, (char**)args);
    mob_write_diag(docs_dir, "mob_diag_e_erl_exited.txt", "erl_start returned");
    mob_set_startup_error("BEAM exited unexpectedly — check Documents/mob_erl_crash.dump");
    NSLog(@"[MobBeam] mob_start_beam: erl_start returned (unexpected)");
}
