pub const ulong = u64;
pub const ilong = i64;

pub const SCARD_SCOPE = enum(ulong) {
    USER = 0,
    SYSTEM = 2,
};

pub const SCARD_IO_REQUEST = extern struct {
    dwProtocol: ulong,
    cbPciLength: ulong,
};

pub const SCARD_AUTOALLOCATE: ulong = @bitCast(@as(ilong, -1));
pub const SCARD_S_SUCCESS: ulong = 0;
pub const SCARD_E_NO_READERS_AVAILABLE: ulong = 0x8010002E;
pub const SCARD_E_NO_SMARTCARD: ulong = 0x8010000C;
pub const SCARD_PROTOCOL_T0: u16 = 0x0001;
pub const SCARD_PROTOCOL_T1: u16 = 0x0002;
pub const SCARD_SHARE_SHARED: u16 = 0x0002;
pub const SCARD_LEAVE_CARD: u16 = 0x0000;
pub const SCARD_RESET_CARD: u16 = 0x0001;
pub const MAX_BUFFER_SIZE: ulong = 264;
pub const MAX_BUFFER_SIZE_EXTENDED: ulong = (4 + 3 + (1 << 16) + 3 + 2);

pub extern "pcsclite" fn SCardEstablishContext(
    dwScope: SCARD_SCOPE,
    pvReserved1: ?*const anyopaque,
    pvReserved2: ?*const anyopaque,
    phContext: ?*ulong,
) callconv(.C) ulong;

pub extern "pcsclite" fn SCardReleaseContext(
    hContext: ulong,
) callconv(.C) ulong;

pub extern "pcsclite" fn SCardIsValidContext(
    hContext: ulong,
) callconv(.C) ulong;

pub extern "pcsclite" fn SCardListReaders(
    hContext: ulong,
    mszGroups: ?[*:0]const u8,
    mszReaders: ?[*:0]u8,
    pcchReaders: ?*ulong,
) callconv(.C) ulong;

pub extern "pcsclite" fn SCardCancel(
    hContext: ulong,
) callconv(.C) ulong;

pub extern "pcsclite" fn SCardConnect(
    hContext: ulong,
    szReader: ?[*:0]const u8,
    dwShareMode: ulong,
    dwPreferredProtocols: ulong,
    phCard: ?*ulong,
    pdwActiveProtocol: ?*ulong,
) callconv(.C) ulong;

pub extern "pcsclite" fn SCardReconnect(
    hCard: ulong,
    dwShareMode: ulong,
    dwPreferredProtocols: ulong,
    dwInitialization: ulong,
    pdwActiveProtocol: ?*ulong,
) callconv(.C) ulong;

pub extern "pcsclite" fn SCardDisconnect(
    hCard: ulong,
    dwDisposition: ulong,
) callconv(.C) ulong;

pub extern "pcsclite" fn SCardTransmit(
    hCard: ulong,
    pioSendPci: ?*SCARD_IO_REQUEST,
    pbSendBuffer: ?[*]u8,
    cbSendLength: ulong,
    pioRecvPci: ?*SCARD_IO_REQUEST,
    pbRecvBuffer: ?[*]u8,
    pcbRecvLength: ?*ulong,
) callconv(.C) ulong;
