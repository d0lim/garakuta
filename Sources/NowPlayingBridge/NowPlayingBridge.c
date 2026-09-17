#include "NowPlayingBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef void (*GetNowPlayingInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetApplicationPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*RegisterForNotificationsFn)(dispatch_queue_t);
typedef Boolean (*SendCommandFn)(unsigned int, CFDictionaryRef);

static GetNowPlayingInfoFn gGetInfo;
static GetIsPlayingFn gGetIsPlaying;
static GetApplicationPIDFn gGetPID;
static RegisterForNotificationsFn gRegister;
static SendCommandFn gSendCommand;
/// Three queues, kept apart on purpose. The service is registered with gNotificationQueue and delivers its
/// notifications there; it also hops onto that queue internally while answering queries, so nothing may block it
/// and no query may be issued from it. Queries are issued and records emitted on gQueue; their callbacks land on
/// gCallbackQueue.
static dispatch_queue_t gNotificationQueue;
static dispatch_queue_t gQueue;
static dispatch_queue_t gCallbackQueue;
static CFDataRef gLastRecord;
/// Metadata from the last successful info query and the app it belonged to; playback-state notifications reuse
/// it. gQueue only.
static CFDictionaryRef gLastInfo;
static int gLastInfoPID;

static bool loadService(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!handle) return false;
    gGetInfo = (GetNowPlayingInfoFn)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
    gGetIsPlaying = (GetIsPlayingFn)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    gGetPID = (GetApplicationPIDFn)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID");
    gRegister = (RegisterForNotificationsFn)dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
    gSendCommand = (SendCommandFn)dlsym(handle, "MRMediaRemoteSendCommand");
    return gGetInfo && gGetIsPlaying && gGetPID && gRegister && gSendCommand;
}

// MARK: Output

static const char kBase64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static void writeBase64Line(const uint8_t *bytes, size_t length) {
    char out[4096];
    size_t used = 0;
    for (size_t i = 0; i < length; i += 3) {
        uint32_t chunk = (uint32_t)bytes[i] << 16;
        if (i + 1 < length) chunk |= (uint32_t)bytes[i + 1] << 8;
        if (i + 2 < length) chunk |= bytes[i + 2];
        out[used++] = kBase64[(chunk >> 18) & 63];
        out[used++] = kBase64[(chunk >> 12) & 63];
        out[used++] = i + 1 < length ? kBase64[(chunk >> 6) & 63] : '=';
        out[used++] = i + 2 < length ? kBase64[chunk & 63] : '=';
        if (used > sizeof out - 8) { fwrite(out, 1, used, stdout); used = 0; }
    }
    out[used++] = '\n';
    fwrite(out, 1, used, stdout);
    fflush(stdout);
}

/// Only property-list values survive; anything else the service might hand over is dropped instead of failing the record.
static bool isPlistValue(CFTypeRef value) {
    CFTypeID type = CFGetTypeID(value);
    return type == CFStringGetTypeID() || type == CFNumberGetTypeID() || type == CFBooleanGetTypeID()
        || type == CFDateGetTypeID() || type == CFDataGetTypeID();
}

static void copyPlistEntries(const void *key, const void *value, void *context) {
    if (CFGetTypeID(key) == CFStringGetTypeID() && isPlistValue(value)) {
        CFDictionarySetValue((CFMutableDictionaryRef)context, key, value);
    }
}

static void emit(CFDictionaryRef info, Boolean playing, int pid) {
    if (getenv("GARAKUTA_NOW_PLAYING_DEBUG")) fprintf(stderr, "emit: info %s (%ld keys) playing %d pid %d\n", info ? "present" : "NULL", info ? (long)CFDictionaryGetCount(info) : 0L, playing, pid);
    CFMutableDictionaryRef record = CFDictionaryCreateMutable(NULL, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFMutableDictionaryRef cleanInfo = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (info) CFDictionaryApplyFunction(info, copyPlistEntries, cleanInfo);
    CFDictionarySetValue(record, CFSTR("info"), cleanInfo);
    CFDictionarySetValue(record, CFSTR("playing"), playing ? kCFBooleanTrue : kCFBooleanFalse);
    CFNumberRef pidNumber = CFNumberCreate(NULL, kCFNumberIntType, &pid);
    CFDictionarySetValue(record, CFSTR("pid"), pidNumber);
    CFDataRef data = CFPropertyListCreateData(NULL, record, kCFPropertyListBinaryFormat_v1_0, 0, NULL);
    if (data) {
        // Notifications arrive in bursts; identical consecutive records are not worth a line.
        bool same = gLastRecord && CFEqual(gLastRecord, data);
        if (!same) {
            writeBase64Line(CFDataGetBytePtr(data), (size_t)CFDataGetLength(data));
            if (gLastRecord) CFRelease(gLastRecord);
            gLastRecord = CFRetain(data);
        }
        CFRelease(data);
    }
    CFRelease(pidNumber);
    CFRelease(cleanInfo);
    CFRelease(record);
}

/// Owner of the now-playing item as of the last complete snapshot. gQueue only.
static int gLastPID;

/// Asks the service for the three pieces of state at once and emits them together on gQueue.
///
/// `queryInfo` false asks only for playback state and owner and reuses the last metadata, provided it came from
/// the same app. When a piece has not arrived after two seconds the snapshot either reports what it has
/// (`emitPartial`) or is dropped. Browsers never answer the metadata query on macOS 26 (the app reads their tab
/// titles instead); the abandoned request does no harm beyond the wait.
static void snapshot(bool queryInfo, bool emitPartial, void (^completion)(void)) {
    dispatch_group_t group = dispatch_group_create();
    __block CFDictionaryRef info = NULL;
    __block Boolean playing = false;
    __block int pid = 0;
    __block bool finished = false;
    if (queryInfo) {
        dispatch_group_enter(group);
        gGetInfo(gCallbackQueue, ^(CFDictionaryRef value) { info = value ? CFRetain(value) : NULL; dispatch_group_leave(group); });
    }
    dispatch_group_enter(group);
    gGetIsPlaying(gCallbackQueue, ^(Boolean value) { playing = value; dispatch_group_leave(group); });
    dispatch_group_enter(group);
    gGetPID(gCallbackQueue, ^(int value) { pid = value; dispatch_group_leave(group); });
    void (^finish)(bool complete) = ^(bool complete) {
        if (finished) return;
        finished = true;
        bool fresh = queryInfo && complete;
        if (fresh) {
            if (gLastInfo) CFRelease(gLastInfo);
            gLastInfo = info ? CFRetain(info) : NULL;
            gLastInfoPID = pid;
        }
        CFDictionaryRef effective = fresh ? info : (pid != 0 && pid == gLastInfoPID ? gLastInfo : NULL);
        if (complete) gLastPID = pid;
        if (complete || emitPartial) emit(effective, playing, pid);
        else if (getenv("GARAKUTA_NOW_PLAYING_DEBUG")) fprintf(stderr, "query timed out; skipped\n");
        if (completion) completion();
    };
    dispatch_group_notify(group, gQueue, ^{
        finish(true);
        if (info) CFRelease(info);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), gQueue, ^{ finish(false); });
}

// MARK: Modes

static void notificationReceived(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
    // Only the "info did change" notification refreshes metadata; the others carry playback state.
    bool infoChanged = CFStringCompare(name, CFSTR("kMRMediaRemoteNowPlayingInfoDidChangeNotification"), 0) == kCFCompareEqualTo;
    if (getenv("GARAKUTA_NOW_PLAYING_DEBUG")) {
        char buffer[160];
        CFStringGetCString(name, buffer, sizeof buffer, kCFStringEncodingUTF8);
        fprintf(stderr, "notification %s\n", buffer);
    }
    dispatch_async(gQueue, ^{ snapshot(infoChanged, true, NULL); });
}

static void observe(const char *name) {
    CFStringRef cfName = CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8);
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL, notificationReceived, cfName, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFRelease(cfName);
}

static void stream(void) {
    gRegister(gNotificationQueue);
    observe("kMRMediaRemoteNowPlayingInfoDidChangeNotification");
    observe("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification");
    observe("kMRMediaRemoteNowPlayingApplicationDidChangeNotification");
    observe("kMRMediaRemoteNowPlayingApplicationClientStateDidChange");
    observe("kMRMediaRemoteNowPlayingPlayerStateDidChange");
    dispatch_async(gQueue, ^{ snapshot(true, true, NULL); });
    // Some players update elapsed time without posting a change; a slow poll keeps the progress honest, and
    // exiting once the parent is gone keeps helpers from piling up.
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
    dispatch_source_set_event_handler(timer, ^{
        if (getppid() == 1) exit(0);
        snapshot(gLastPID != 0, false, NULL);
    });
    dispatch_resume(timer);
    CFRunLoopRun();
}

static void once(void) {
    gRegister(gNotificationQueue);
    // Give the connection to the service a moment to come up before asking.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), gQueue, ^{ snapshot(true, true, ^{ exit(0); }); });
    CFRunLoopRun();
}

static void command(void) {
    const char *value = getenv("GARAKUTA_NOW_PLAYING_COMMAND");
    unsigned int cmd = value ? (unsigned int)strtoul(value, NULL, 10) : 2;
    Boolean ok = gSendCommand(cmd, NULL);
    // Give the service a moment to deliver before the process disappears.
    usleep(150000);
    exit(ok ? 0 : 3);
}

void NowPlayingBridgeMain(void) {
    signal(SIGPIPE, SIG_DFL);  // die when the parent closes the pipe
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (!loadService()) {
        fprintf(stderr, "now-playing service unavailable\n");
        exit(2);
    }
    gNotificationQueue = dispatch_queue_create("com.d0lim.garakuta.nowplaying.notifications", DISPATCH_QUEUE_SERIAL);
    gQueue = dispatch_queue_create("com.d0lim.garakuta.nowplaying", DISPATCH_QUEUE_SERIAL);
    gCallbackQueue = dispatch_queue_create("com.d0lim.garakuta.nowplaying.callbacks", DISPATCH_QUEUE_SERIAL);
    const char *mode = getenv("GARAKUTA_NOW_PLAYING_MODE");
    if (mode && strcmp(mode, "command") == 0) command();
    else if (mode && strcmp(mode, "once") == 0) once();
    else stream();
    exit(0);
}

/// The host interpreter only loads the library; the constructor does the rest.
__attribute__((constructor)) static void start(void) {
    NowPlayingBridgeMain();
}
