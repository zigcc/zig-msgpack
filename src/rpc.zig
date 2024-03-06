const std = @import("std");
const msgpack = @import("msgpack");

// we try to use the zig fifo
const FifoType = std.fifo.LinearFifo(msgpack.Payload, .Dynamic);
