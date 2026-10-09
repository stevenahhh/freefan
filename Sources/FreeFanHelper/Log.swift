import Foundation

/// One timestamped line to stdout, flushed immediately (launchd redirects stdout to a file, which
/// would otherwise be block-buffered). Only called from the daemon queue or before it starts.
/// Callers must never pass raw client input: log counts and verbs, not the bytes a peer sent.
func logLine(_ message: String) {
    var now = time(nil)
    var parts = tm()
    localtime_r(&now, &parts)
    var stamp = [CChar](repeating: 0, count: 32)
    strftime(&stamp, stamp.count, "%Y-%m-%d %H:%M:%S", &parts)
    fputs("\(String(cString: stamp)) freefan-helper: \(message)\n", stdout)
    fflush(stdout)
}
