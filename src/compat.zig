// In-memory stream adapter for the callback-based Pack API on Zig 0.16+.
pub const BufferStream = struct {
    buffer: []u8,
    pos: usize,

    const Self = @This();

    pub const WriteError = error{NoSpaceLeft};
    pub const ReadError = error{EndOfStream};

    pub fn init(buffer: []u8) Self {
        return .{
            .buffer = buffer,
            .pos = 0,
        };
    }

    pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
        const available = self.buffer.len - self.pos;
        if (bytes.len > available) return error.NoSpaceLeft;
        @memcpy(self.buffer[self.pos..][0..bytes.len], bytes);
        self.pos += bytes.len;
        return bytes.len;
    }

    pub fn read(self: *Self, dest: []u8) ReadError!usize {
        // Read from current position in buffer
        const available = self.buffer.len - self.pos;
        if (available == 0) return 0;

        const to_read = @min(dest.len, available);
        @memcpy(dest[0..to_read], self.buffer[self.pos..][0..to_read]);
        self.pos += to_read;
        return to_read;
    }

    pub fn reset(self: *Self) void {
        self.pos = 0;
    }

    pub fn seekTo(self: *Self, pos: usize) !void {
        if (pos > self.buffer.len) {
            return error.OutOfBounds;
        }
        self.pos = pos;
    }

    pub fn getPos(self: Self) usize {
        return self.pos;
    }

    pub fn getEndPos(self: Self) usize {
        return self.buffer.len;
    }
};

pub const fixedBufferStream = BufferStream.init;
