const std = @import("std");
const SCRaw = @import("scraw").SCRaw;

pub fn usage(arg0: [:0]const u8) void {
    std.log.info("Usage: {s} <pcsc_reader_name>\n-You can get the reader name by running `pcsc_scan`.", .{arg0});
}

const MainError = error{
    ArgCountInvalid,
};
pub fn main() !void {
    var alloc_gp = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = alloc_gp.allocator();

    const arg = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, arg);
    if (arg.len != 2) {
        std.log.err("Expected 2 arguments, got {}.", .{arg.len});
        usage(arg[0]);
        return MainError.ArgCountInvalid;
    }

    std.log.info("Desired reader: \"{s}\".", .{arg[1]});

    const scraw = try SCRaw.init(alloc);
    defer scraw.deinit(alloc) catch {};

    try scraw.readerSearchStart();
    var reader_found: bool = false;
    while (true) {
        const reader_name: []const u8 = scraw.readerSearchNext() catch |err| {
            if (err == SCRaw.ReaderSearchNextError.ReaderSearchEndOfList) {
                break;
            } else {
                return err;
            }
        };
        std.log.info("Next reader: \"{s}\".", .{reader_name});
        if (std.mem.eql(u8, reader_name, arg[1])) {
            std.log.info("Found reader.", .{});
            scraw.readerSelect(reader_name);
            scraw.readerSearchEnd();
            reader_found = true;
            break;
        }
    }
    if (!reader_found) {
        std.log.err("Could not find the desired reader.", .{});
        return;
    }

    std.log.info("Trying to connect to card.", .{});
    try scraw.cardConnect(.T0);
    defer scraw.cardDisconnect() catch {
        std.log.err("Card disconnect failed.", .{});
    };

    var capdu0 = [_]u8{ 0x00, 0xA4, 0x00, 0x04, 0x02, 0x3F, 0x00 };
    var rapdu_buffer = std.mem.zeroes([SCRaw.bufferReceiveLengthMax]u8);
    var rapdu = try scraw.cardSendReceive(capdu0[0..], rapdu_buffer[0..]);
    std.log.info("CAPDU={} RAPDU={}.", .{ std.fmt.fmtSliceHexUpper(capdu0[0..]), std.fmt.fmtSliceHexUpper(rapdu[0..]) });

    var capdu1 = [_]u8{ 0x00, 0xC0, 0x00, 0x00, rapdu[1] };
    rapdu = try scraw.cardSendReceive(capdu1[0..], rapdu_buffer[0..]);
    std.log.info("CAPDU={} RAPDU={}.", .{ std.fmt.fmtSliceHexUpper(capdu1[0..]), std.fmt.fmtSliceHexUpper(rapdu[0..]) });
}
