const std = @import("std");
const builtin = @import("builtin");

pub const SCRaw = struct {
    const pcsc = if (builtin.os.tag == .windows) @import("pcsc/win32.zig") else if (builtin.os.tag == .linux) @import("pcsc/linux.zig") else @panic("Platform not supported.");
    pub const bufferReceiveLengthMax: usize = pcsc.MAX_BUFFER_SIZE;

    const SCRet = enum(pcsc.ulong) {
        SCARD_S_SUCCESS = pcsc.SCARD_S_SUCCESS,
        SCARD_E_NO_READERS_AVAILABLE = pcsc.SCARD_E_NO_READERS_AVAILABLE,
        SCARD_E_NO_SMARTCARD = pcsc.SCARD_E_NO_SMARTCARD,
    };

    const SCProtocol = enum(pcsc.ulong) {
        T0 = pcsc.SCARD_PROTOCOL_T0,
        T1 = pcsc.SCARD_PROTOCOL_T1,
    };

    const Self = @This();
    context: pcsc.ulong,
    reason: pcsc.ulong,

    reader_list_next_offset: usize,
    reader_list_buffer: [1024]u8,
    reader_list_slice: ?[]const u8,
    reader_list_length: usize,

    reader_select: ?[]const u8 = null,

    context_card: ?pcsc.ulong,
    card_protocol: SCProtocol,

    const SCardError = error{
        SCardFailed,
    };

    pub const InitError = error{} || std.mem.Allocator.Error || SCardError;
    pub fn init(alloc: std.mem.Allocator) InitError!*Self {
        var self = try alloc.create(Self);
        errdefer alloc.destroy(self);
        const ret = pcsc.SCardEstablishContext(.USER, null, null, &self.context);
        if (ret != @intFromEnum(SCRet.SCARD_S_SUCCESS)) {
            std.log.err("[SCRaw] SCardEstablishContext failed: reason={X}.", .{ret});
            return InitError.SCardFailed;
        }

        self.context_card = null;

        self.reason = @intFromEnum(Self.SCRet.SCARD_S_SUCCESS);

        self.reader_list_next_offset = 0;
        self.reader_list_length = 0;
        self.reader_list_slice = null;

        self.reader_select = null;

        self.card_protocol = SCProtocol.T0;

        return self;
    }

    pub const DeinitError = error{} || SCardError;
    pub fn deinit(self: *Self, alloc: std.mem.Allocator) DeinitError!void {
        const ret_cancel = pcsc.SCardCancel(self.context);
        if (ret_cancel != @intFromEnum(SCRet.SCARD_S_SUCCESS)) {
            std.log.err("[SCRaw] SCardCancel failed: reason={X}.", .{ret_cancel});
            self.reason = ret_cancel;
            return DeinitError.SCardFailed;
        }
        const ret_release = pcsc.SCardReleaseContext(self.context);
        if (ret_release != @intFromEnum(SCRet.SCARD_S_SUCCESS)) {
            std.log.err("[SCRaw] SCardReleaseContext failed: reason={X}.", .{ret_release});
            self.reason = ret_release;
            return DeinitError.SCardFailed;
        }
        alloc.destroy(self);
    }

    pub const ReaderSearchBeginError = error{
        ReaderListLengthInvalid,
    } || SCardError;
    pub fn readerSearchStart(self: *Self) ReaderSearchBeginError!void {
        const name_list_arg: ?[*:0]u8 = @ptrCast(self.reader_list_buffer[0..]);
        var name_list_length: pcsc.ulong = self.reader_list_buffer.len;
        const name_list_length_arg: ?*pcsc.ulong = &name_list_length;
        const ret = pcsc.SCardListReaders(self.context, null, name_list_arg, name_list_length_arg);
        if (ret == @intFromEnum(SCRet.SCARD_E_NO_READERS_AVAILABLE)) {
            std.log.warn("[SCRaw] SCardListReaders: no readers available.", .{});
            self.reader_list_slice = self.reader_list_buffer[0..0];
            self.reader_list_length = 0;
            self.reader_list_next_offset = 0;
            return;
        } else if (ret != @intFromEnum(SCRet.SCARD_S_SUCCESS)) {
            std.log.err("[SCRaw] SCardListReaders failed: reason={X}.", .{ret});
            self.reason = ret;
            return ReaderSearchBeginError.SCardFailed;
        }
        if (name_list_length > self.reader_list_buffer.len) {
            return ReaderSearchBeginError.ReaderListLengthInvalid;
        }

        // At least one reader available.
        self.reader_list_slice = self.reader_list_buffer[0..name_list_length];
        self.reader_list_length = name_list_length;
        self.reader_list_next_offset = 0;
    }

    pub fn readerSearchEnd(self: *Self) void {
        if (self.reader_list_slice == null) {
            std.log.warn("[SCRaw] Reader search end requested, but the search was never started.", .{});
        }

        self.reader_list_slice = null;
        self.reader_list_next_offset = 0;
        self.reader_list_length = 0;
    }

    pub const ReaderSearchNextError = error{
        ReaderSearchNotStarted,
        ReaderSearchEndOfList,
    };
    pub fn readerSearchNext(self: *Self) ReaderSearchNextError![]const u8 {
        if (self.reader_list_slice == null) {
            return ReaderSearchNextError.ReaderSearchNotStarted;
        }

        if (self.reader_list_next_offset + 1 >= self.reader_list_length) {
            return ReaderSearchNextError.ReaderSearchEndOfList;
        }

        const reader_name_remainder: [*:0]const u8 = @ptrCast(self.reader_list_slice.?[self.reader_list_next_offset..]);
        const reader_name = std.mem.span(reader_name_remainder);
        self.reader_list_next_offset += reader_name.len + 1;
        return reader_name;
    }

    pub fn readerSelect(self: *Self, reader_name: []const u8) void {
        self.reader_select = reader_name;
    }

    const CardConnectError = error{
        ReaderNotSelected,
        CardContextInvalid,
    } || SCardError;
    pub fn cardConnect(self: *Self, protocol: SCProtocol) CardConnectError!void {
        if (self.reader_select == null) {
            return CardConnectError.ReaderNotSelected;
        }

        if (self.context_card == null) {
            std.log.debug("[SCRaw] Card connecting...", .{});
            var context_card: pcsc.ulong = 0;
            const context_card_arg: ?*pcsc.ulong = &context_card;
            var protocol_active: pcsc.ulong = @intFromEnum(SCProtocol.T0);
            const protocol_active_arg: ?*pcsc.ulong = &protocol_active;
            const reader_select_arg: ?[*:0]const u8 = @ptrCast(self.reader_select);
            const ret = pcsc.SCardConnect(self.context, reader_select_arg, pcsc.SCARD_SHARE_SHARED, @intFromEnum(protocol), context_card_arg, protocol_active_arg);
            if (ret != @intFromEnum(SCRet.SCARD_S_SUCCESS)) {
                std.log.err("[SCRaw] SCardConnect failed: reason={X}.", .{ret});
                self.reason = ret;
                return CardConnectError.SCardFailed;
            }
            if (context_card != 0) {
                std.log.info("[SCRaw] Card in reader \"{s}\" selected: active_protocol={s}.", .{ self.reader_select.?, switch (protocol_active) {
                    @intFromEnum(SCProtocol.T0) => "T0",
                    @intFromEnum(SCProtocol.T1) => "T1",
                    else => "unrecognized",
                } });
                self.card_protocol = @as(SCProtocol, @enumFromInt(protocol_active));
                self.context_card = context_card;
            } else {
                std.log.err("[SCRaw] SCardConnect: Card context invalid, context={}.", .{context_card});
                return CardConnectError.CardContextInvalid;
            }
        } else {
            std.log.debug("[SCRaw] Card reconnecting...", .{});
            var protocol_active: pcsc.ulong = @intFromEnum(SCProtocol.T0);
            const protocol_active_arg: ?*pcsc.ulong = &protocol_active;
            const ret = pcsc.SCardReconnect(self.context_card.?, pcsc.SCARD_SHARE_SHARED, @intFromEnum(protocol), pcsc.SCARD_RESET_CARD, protocol_active_arg);
            if (ret != @intFromEnum(SCRet.SCARD_S_SUCCESS)) {
                std.log.err("[SCRaw] SCardReconnect failed: reason={X}.", .{ret});
                self.reason = ret;
                return CardConnectError.SCardFailed;
            }
        }
        std.log.info("[SCRaw] Card connected.", .{});
    }

    const CardDisconnectError = error{} || SCardError;
    pub fn cardDisconnect(self: *Self) CardDisconnectError!void {
        if (self.context_card == null) {
            std.log.warn("[SCRaw] Requested card disconnect, but card is not connected.", .{});
            return;
        }

        const ret = pcsc.SCardDisconnect(self.context_card.?, pcsc.SCARD_LEAVE_CARD);
        if (ret != @intFromEnum(SCRet.SCARD_S_SUCCESS)) {
            std.log.err("[SCRaw] SCardDisconnect failed: reason={X}.", .{ret});
            self.reason = ret;
            return CardDisconnectError.SCardFailed;
        }
        std.log.info("[SCRaw] Card disconnected.", .{});
        self.context_card = null;
    }

    const CardSendReceiveError = error{
        CardContextInvalid,
        CardNotPresent,
        ResponseInvalid,
    } || SCardError;
    pub fn cardSendReceive(self: *Self, buffer_send: []u8, buffer_receive: []u8) CardSendReceiveError![]u8 {
        if (self.context_card == null) {
            // No connected card to send data to.
            std.log.warn("[SCRaw] Tried sending an APDU but a card is not connected.", .{});
            return CardSendReceiveError.CardContextInvalid;
        }

        var pci: pcsc.SCARD_IO_REQUEST = .{
            .dwProtocol = @intFromEnum(self.card_protocol),
            .cbPciLength = @sizeOf(pcsc.SCARD_IO_REQUEST),
        };
        const pci_arg: ?*pcsc.SCARD_IO_REQUEST = &pci;
        std.log.debug("[SCRaw] PCI: protocol={} pci_length={}.", .{ pci.dwProtocol, pci.cbPciLength });

        var response_length: pcsc.ulong = @intCast(buffer_receive.len);
        const response_length_arg: ?*pcsc.ulong = &response_length;
        const buffer_send_arg: [*c]u8 = @ptrCast(buffer_send);
        const buffer_send_length_arg: pcsc.ulong = @intCast(buffer_send.len);
        const buffer_receive_arg: [*c]u8 = @ptrCast(buffer_receive);

        std.log.debug("[SCRaw] Sending {} bytes and receiving at most {} bytes.", .{ buffer_send_length_arg, response_length_arg.?.* });
        const ret = pcsc.SCardTransmit(self.context_card.?, pci_arg, buffer_send_arg, buffer_send_length_arg, null, buffer_receive_arg, response_length_arg);
        if (ret == @intFromEnum(SCRet.SCARD_E_NO_SMARTCARD)) {
            std.log.err("[SCRaw] SCardTransmit failed because the smartcard is no longer inserted into the reader.", .{});
            self.reason = ret;
            return CardSendReceiveError.CardNotPresent;
        } else if (ret != @intFromEnum(SCRet.SCARD_S_SUCCESS)) {
            std.log.err("[SCRaw] SCardTransmit failed: reason={X} response_length={}.", .{ ret, response_length });
            self.reason = ret;
            return CardSendReceiveError.SCardFailed;
        }

        if (response_length > 256 or response_length > buffer_receive.len) {
            //  PC/SC doesn't even support extended TPDUs so this should never happen.
            std.log.err("[SCRaw] Response has length {} but max length or RAPDU is 256 or max length of the receive buffer which is {}.", .{ response_length, buffer_receive.len });
            return CardSendReceiveError.ResponseInvalid;
        }

        return buffer_receive[0..response_length];
    }
};
