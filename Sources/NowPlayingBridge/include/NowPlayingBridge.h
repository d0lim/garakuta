#ifndef NOW_PLAYING_BRIDGE_H
#define NOW_PLAYING_BRIDGE_H

/// Helper library that talks to the system's now-playing service on behalf of the app.
///
/// Since macOS 15.4 that service only answers processes Apple signed, so the app cannot call it directly. It instead
/// launches the system perl interpreter, which loads this library; the library's constructor runs the requested
/// mode and never returns while streaming. The app reads records from the helper's standard output.
///
/// Environment:
///   GARAKUTA_NOW_PLAYING_MODE     "stream" (default): emit a record on every change until the parent exits.
///                                 "once": emit one record and exit.
///                                 "command": send GARAKUTA_NOW_PLAYING_COMMAND (a number, see below) and exit.
///   GARAKUTA_NOW_PLAYING_COMMAND  0 play, 1 pause, 2 toggle play/pause, 3 stop, 4 next track, 5 previous track.
///
/// Record format: one line per record, the base64 encoding of a binary property list dictionary with keys
///   "info"    dictionary as returned by the service (title, artist, artwork, elapsed time, ...),
///   "playing" boolean,
///   "pid"     integer process id of the app that owns the now-playing item (0 when unknown).
void NowPlayingBridgeMain(void);

#endif
