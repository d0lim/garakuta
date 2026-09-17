#ifndef PRIVATE_APIS_H
#define PRIVATE_APIS_H

#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>
#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>

/// Private SkyLight (CGS/SLS) and HIServices symbols used by the window switcher (W01).
/// Every symbol is resolved at runtime with dlsym so a missing one degrades a feature instead of failing to launch.
/// All functions below return a failure value when GKPrivateAPIsLoad() has not succeeded.

typedef int CGSConnectionID;
typedef uint64_t CGSSpaceID;

/// CGSCopySpacesForWindows mask values.
enum {
    GKSpaceMaskCurrent = 5,
    GKSpaceMaskOther = 6,
    GKSpaceMaskAll = 7,
};

/// CGSSpaceGetType results.
enum {
    GKSpaceTypeUser = 0,
    GKSpaceTypeSystem = 2,
    GKSpaceTypeFullscreen = 4,
};

/// Loads SkyLight + HIServices and resolves every symbol. Returns false if any required symbol is missing.
bool GKPrivateAPIsLoad(void);
/// True after a successful GKPrivateAPIsLoad.
bool GKPrivateAPIsAvailable(void);
/// Names of symbols that failed to resolve on the last GKPrivateAPIsLoad, comma separated (static buffer).
const char *GKPrivateAPIsMissingSymbols(void);

// Connection / spaces
CGSConnectionID GKMainConnectionID(void);
CGSSpaceID GKGetActiveSpace(CGSConnectionID cid);
CGSSpaceID GKManagedDisplayGetCurrentSpace(CGSConnectionID cid, CFStringRef displayIdentifier);
/// Array of dictionaries, one per display: "Display Identifier", "Current Space" {id64, ManagedSpaceID, type}, "Spaces" [...].
CFArrayRef GKCopyManagedDisplaySpaces(CGSConnectionID cid);
int GKSpaceGetType(CGSConnectionID cid, CGSSpaceID sid);
/// Array of CFNumber space ids the given windows (array of CFNumber CGWindowID) belong to.
CFArrayRef GKCopySpacesForWindows(CGSConnectionID cid, int mask, CFArrayRef windowIDs);
/// Array of CFNumber window ids in the given spaces. options 0x2 = visible windows, 0x7 = include invisible.
CFArrayRef GKCopyWindowsWithOptionsAndTags(CGSConnectionID cid, uint32_t owner, CFArrayRef spaces, uint32_t options,
                                           uint64_t *setTags, uint64_t *clearTags);

// Windows
CGError GKGetWindowLevel(CGSConnectionID cid, CGWindowID wid, CGWindowLevel *outLevel);
CGError GKGetWindowBounds(CGSConnectionID cid, CGWindowID wid, CGRect *outBounds);
CGError GKGetWindowOwner(CGSConnectionID cid, CGWindowID wid, CGSConnectionID *outOwner);
CGError GKGetConnectionPSN(CGSConnectionID cid, ProcessSerialNumber *outPSN);

// Focus
/// Process serial number for a pid (Carbon GetProcessForPID). Returns false on failure.
bool GKProcessSerialNumberForPID(pid_t pid, ProcessSerialNumber *outPSN);
/// pid for a process serial number (Carbon GetProcessPID). Returns false on failure.
bool GKPIDForProcessSerialNumber(ProcessSerialNumber *psn, pid_t *outPID);
/// Brings a process and one of its windows to the front without raising the app's other windows.
/// mode: 0x200 = user generated (kCPSUserGenerated).
CGError GKSetFrontProcessWithOptions(ProcessSerialNumber *psn, CGWindowID wid, uint32_t mode);
/// Posts the synthetic activate/deactivate event pair that makes `wid` the key window of `psn` (publicly documented record layout).
void GKMakeKeyWindow(ProcessSerialNumber *psn, CGWindowID wid);

// Accessibility
/// CGWindowID backing an AXUIElement window (HIServices _AXUIElementGetWindow). Returns false on failure.
bool GKAXUIElementGetWindow(AXUIElementRef element, CGWindowID *outWindowID);

#endif
