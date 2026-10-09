import Foundation

// TODO(node-helper-daemon): replace this file with the root daemon. Required behaviour is spelled out in
// the node prompt (socket + getpeereid gate, lease watchdog, 1 s control tick only while controlling,
// Tg-before-md write order, boot-time reset, signal and power handling, monitor-only fallback).
FileHandle.standardError.write(Data("FreeFanHelper scaffold: not implemented yet\n".utf8))
exit(1)
