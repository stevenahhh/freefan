import Foundation

// FreeFanHelper: the only process that writes to the SMC. Runs as root under launchd.
// The daemon itself lives in HelperDaemon.swift, the socket front end in SocketServer.swift.

let options = HelperOptions.parse(CommandLine.arguments)
let allowed = options.allowedUIDs.sorted().map(String.init).joined(separator: ",")
logLine("starting (euid \(geteuid()), socket \(options.socketPath), tick \(options.tick) s, allowed uids \(allowed))")
if geteuid() != 0 {
    logLine("WARNING: not running as root; every SMC write will fail with notPrivileged and the helper will fall back to monitor mode")
}

signal(SIGPIPE, SIG_IGN)

let daemon = HelperDaemon.make(options: options)
do {
    try daemon.start()
} catch {
    logLine("fatal: \(error)")
    exit(1)
}
dispatchMain()
