#include "PrivateAPIs.h"
#include <dlfcn.h>
#include <stddef.h>
#include <string.h>
#include <string.h>
#include <stdio.h>

typedef CGSConnectionID (*MainConnectionIDFn)(void);
typedef CGSSpaceID (*GetActiveSpaceFn)(CGSConnectionID);
typedef CGSSpaceID (*ManagedDisplayGetCurrentSpaceFn)(CGSConnectionID, CFStringRef);
typedef CFArrayRef (*CopyManagedDisplaySpacesFn)(CGSConnectionID);
typedef int (*SpaceGetTypeFn)(CGSConnectionID, CGSSpaceID);
typedef CFArrayRef (*CopySpacesForWindowsFn)(CGSConnectionID, int, CFArrayRef);
typedef CFArrayRef (*CopyWindowsWithOptionsAndTagsFn)(CGSConnectionID, uint32_t, CFArrayRef, uint32_t, uint64_t *, uint64_t *);
typedef CGError (*GetWindowLevelFn)(CGSConnectionID, CGWindowID, CGWindowLevel *);
typedef CGError (*GetWindowBoundsFn)(CGSConnectionID, CGWindowID, CGRect *);
typedef CGError (*GetWindowOwnerFn)(CGSConnectionID, CGWindowID, CGSConnectionID *);
typedef CGError (*GetConnectionPSNFn)(CGSConnectionID, ProcessSerialNumber *);
typedef CGError (*SetFrontProcessWithOptionsFn)(ProcessSerialNumber *, uint32_t, uint32_t);
typedef CGError (*PostEventRecordToFn)(ProcessSerialNumber *, uint8_t *);
typedef AXError (*AXUIElementGetWindowFn)(AXUIElementRef, CGWindowID *);
typedef OSStatus (*GetProcessForPIDFn)(pid_t, ProcessSerialNumber *);
typedef OSStatus (*GetProcessPIDFn)(const ProcessSerialNumber *, pid_t *);

static bool gLoaded = false;
static char gMissing[512];

static MainConnectionIDFn gMainConnectionID;
static GetActiveSpaceFn gGetActiveSpace;
static ManagedDisplayGetCurrentSpaceFn gManagedDisplayGetCurrentSpace;
static CopyManagedDisplaySpacesFn gCopyManagedDisplaySpaces;
static SpaceGetTypeFn gSpaceGetType;
static CopySpacesForWindowsFn gCopySpacesForWindows;
static CopyWindowsWithOptionsAndTagsFn gCopyWindowsWithOptionsAndTags;
static GetWindowLevelFn gGetWindowLevel;
static GetWindowBoundsFn gGetWindowBounds;
static GetWindowOwnerFn gGetWindowOwner;
static GetConnectionPSNFn gGetConnectionPSN;
static SetFrontProcessWithOptionsFn gSetFrontProcessWithOptions;
static PostEventRecordToFn gPostEventRecordTo;
static AXUIElementGetWindowFn gAXUIElementGetWindow;
static GetProcessForPIDFn gGetProcessForPID;
static GetProcessPIDFn gGetProcessPID;

static void *resolve(void *handle, const char *name) {
    void *p = dlsym(handle, name);
    if (!p) {
        if (gMissing[0]) strlcat(gMissing, ",", sizeof gMissing);
        strlcat(gMissing, name, sizeof gMissing);
    }
    return p;
}

bool GKPrivateAPIsLoad(void) {
    if (gLoaded) return true;
    gMissing[0] = 0;
    void *sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    void *his = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY);
    if (!sky || !his) {
        strlcpy(gMissing, sky ? "HIServices" : "SkyLight", sizeof gMissing);
        return false;
    }
    gMainConnectionID = (MainConnectionIDFn)resolve(sky, "CGSMainConnectionID");
    gGetActiveSpace = (GetActiveSpaceFn)resolve(sky, "CGSGetActiveSpace");
    gManagedDisplayGetCurrentSpace = (ManagedDisplayGetCurrentSpaceFn)resolve(sky, "CGSManagedDisplayGetCurrentSpace");
    gCopyManagedDisplaySpaces = (CopyManagedDisplaySpacesFn)resolve(sky, "CGSCopyManagedDisplaySpaces");
    gSpaceGetType = (SpaceGetTypeFn)resolve(sky, "CGSSpaceGetType");
    gCopySpacesForWindows = (CopySpacesForWindowsFn)resolve(sky, "CGSCopySpacesForWindows");
    gCopyWindowsWithOptionsAndTags = (CopyWindowsWithOptionsAndTagsFn)resolve(sky, "CGSCopyWindowsWithOptionsAndTags");
    gGetWindowLevel = (GetWindowLevelFn)resolve(sky, "CGSGetWindowLevel");
    gGetWindowBounds = (GetWindowBoundsFn)resolve(sky, "CGSGetWindowBounds");
    gGetWindowOwner = (GetWindowOwnerFn)resolve(sky, "CGSGetWindowOwner");
    gGetConnectionPSN = (GetConnectionPSNFn)resolve(sky, "CGSGetConnectionPSN");
    gSetFrontProcessWithOptions = (SetFrontProcessWithOptionsFn)resolve(sky, "_SLPSSetFrontProcessWithOptions");
    gPostEventRecordTo = (PostEventRecordToFn)resolve(sky, "SLPSPostEventRecordTo");
    gAXUIElementGetWindow = (AXUIElementGetWindowFn)resolve(his, "_AXUIElementGetWindow");
    gGetProcessForPID = (GetProcessForPIDFn)resolve(his, "GetProcessForPID");
    gGetProcessPID = (GetProcessPIDFn)resolve(his, "GetProcessPID");
    gLoaded = gMissing[0] == 0;
    return gLoaded;
}

bool GKPrivateAPIsAvailable(void) { return gLoaded; }
const char *GKPrivateAPIsMissingSymbols(void) { return gMissing; }

CGSConnectionID GKMainConnectionID(void) { return gLoaded ? gMainConnectionID() : 0; }
CGSSpaceID GKGetActiveSpace(CGSConnectionID cid) { return gLoaded ? gGetActiveSpace(cid) : 0; }
CGSSpaceID GKManagedDisplayGetCurrentSpace(CGSConnectionID cid, CFStringRef d) { return gLoaded ? gManagedDisplayGetCurrentSpace(cid, d) : 0; }
CFArrayRef GKCopyManagedDisplaySpaces(CGSConnectionID cid) { return gLoaded ? gCopyManagedDisplaySpaces(cid) : NULL; }
int GKSpaceGetType(CGSConnectionID cid, CGSSpaceID sid) { return gLoaded ? gSpaceGetType(cid, sid) : -1; }
CFArrayRef GKCopySpacesForWindows(CGSConnectionID cid, int mask, CFArrayRef w) { return gLoaded ? gCopySpacesForWindows(cid, mask, w) : NULL; }
CFArrayRef GKCopyWindowsWithOptionsAndTags(CGSConnectionID cid, uint32_t owner, CFArrayRef spaces, uint32_t options, uint64_t *set, uint64_t *clear) {
    return gLoaded ? gCopyWindowsWithOptionsAndTags(cid, owner, spaces, options, set, clear) : NULL;
}
CGError GKGetWindowLevel(CGSConnectionID cid, CGWindowID wid, CGWindowLevel *out) { return gLoaded ? gGetWindowLevel(cid, wid, out) : kCGErrorFailure; }
CGError GKGetWindowBounds(CGSConnectionID cid, CGWindowID wid, CGRect *out) { return gLoaded ? gGetWindowBounds(cid, wid, out) : kCGErrorFailure; }
CGError GKGetWindowOwner(CGSConnectionID cid, CGWindowID wid, CGSConnectionID *out) { return gLoaded ? gGetWindowOwner(cid, wid, out) : kCGErrorFailure; }
CGError GKGetConnectionPSN(CGSConnectionID cid, ProcessSerialNumber *out) { return gLoaded ? gGetConnectionPSN(cid, out) : kCGErrorFailure; }

bool GKProcessSerialNumberForPID(pid_t pid, ProcessSerialNumber *out) {
    if (!gLoaded || !out) return false;
    return gGetProcessForPID(pid, out) == noErr;
}

bool GKPIDForProcessSerialNumber(ProcessSerialNumber *psn, pid_t *out) {
    if (!gLoaded || !psn || !out) return false;
    return gGetProcessPID(psn, out) == noErr;
}

CGError GKSetFrontProcessWithOptions(ProcessSerialNumber *psn, CGWindowID wid, uint32_t mode) {
    return gLoaded ? gSetFrontProcessWithOptions(psn, wid, mode) : kCGErrorFailure;
}

/// The 0xf8-byte record SLPSPostEventRecordTo expects. Only the fields the window server reads for a
/// key-window change are named; everything else stays zero. Offsets are checked at compile time.
typedef struct __attribute__((packed)) {
    uint8_t  header[4];
    uint32_t length;          // total record length, always 0xf8
    uint32_t phase;           // 1 = activate, 2 = deactivate
    uint8_t  reserved0[0x14];
    uint8_t  target[16];      // all 0xff: not addressed to a specific element
    uint8_t  reserved1[0x0a];
    uint16_t kind;            // 0x10 = key window change
    uint32_t windowID;
    uint8_t  reserved2[0xf8 - 0x40];
} GKKeyWindowRecord;

_Static_assert(sizeof(GKKeyWindowRecord) == 0xf8, "record must be 0xf8 bytes");
_Static_assert(offsetof(GKKeyWindowRecord, length) == 0x04, "length offset");
_Static_assert(offsetof(GKKeyWindowRecord, phase) == 0x08, "phase offset");
_Static_assert(offsetof(GKKeyWindowRecord, target) == 0x20, "target offset");
_Static_assert(offsetof(GKKeyWindowRecord, kind) == 0x3a, "kind offset");
_Static_assert(offsetof(GKKeyWindowRecord, windowID) == 0x3c, "windowID offset");

static void GKPostKeyWindowRecord(ProcessSerialNumber *psn, CGWindowID wid, uint32_t phase) {
    GKKeyWindowRecord record = {0};
    record.length = sizeof record;
    record.phase = phase;
    memset(record.target, 0xff, sizeof record.target);
    record.kind = 0x10;
    record.windowID = wid;
    gPostEventRecordTo(psn, (uint8_t *)&record);
}

void GKMakeKeyWindow(ProcessSerialNumber *psn, CGWindowID wid) {
    if (!gLoaded) return;
    GKPostKeyWindowRecord(psn, wid, 1);
    GKPostKeyWindowRecord(psn, wid, 2);
}

bool GKAXUIElementGetWindow(AXUIElementRef element, CGWindowID *out) {
    if (!gLoaded || !element || !out) return false;
    return gAXUIElementGetWindow(element, out) == kAXErrorSuccess;
}
