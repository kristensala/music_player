// Doc: https://dbus.freedesktop.org/doc/api/html/group__DBus.html
package dbus

import "core:c"

foreign import lib {
    "system:dbus-1"
}

DBUS_TYPE_STRING :: c.int('s')
DBUS_TYPE_BYTE :: c.int('y')
DBUS_TYPE_UINT32 :: c.int('u')
DBUS_TYPE_INT32 :: c.int('i')
DBUS_TYPE_ARRAY :: c.int('a')
DBUS_TYPE_DICT_ENTRY :: c.int('e')
DBUS_TYPE_VARIANT :: c.int('v')

DBusError :: struct {
    name: cstring,
    message: cstring,
    _bitfield: u32,
    padding1: rawptr
}

DBusConnection :: struct {}
DBusMessage :: struct {}
DBusPendingCall :: struct {}

DBusMessageIter :: struct {
    dummy1: rawptr,
    dummy2: rawptr,
    dummy3: u32,
    dummy4: c.int,
    dummy5: c.int,
    dummy6: c.int,
    dummy7: c.int,
    dummy8: c.int,
    dummy9: c.int,
    dummy10: c.int,
    dummy11: c.int,
    pad1: c.int,
    pad2: rawptr,
    pad3: rawptr
}

DBusBusType :: enum {
    DBUS_BUS_SESSION,
    DBUS_BUS_SYSTEM,
    DBUS_BUS_STARTER
}
    
@(default_calling_convention="c", link_prefix="dbus_")
foreign lib {
    error_init     :: proc(error: ^DBusError) ---
    error_is_set   :: proc(error: ^DBusError) -> c.uint ---
    error_free     :: proc(error: ^DBusError) ---

    bus_get        :: proc(type: DBusBusType, error: ^DBusError) -> ^DBusConnection ---

    message_iter_init :: proc(message: ^DBusMessage, iter: ^DBusMessageIter) -> c.uint ---
    message_new_method_call :: proc(destination: cstring, path: cstring, iface: cstring, method: cstring) -> ^DBusMessage ---
    message_iter_init_append :: proc(message: ^DBusMessage, iter: ^DBusMessageIter) ---
    message_iter_append_basic :: proc(iter: ^DBusMessageIter, type: c.int, value: rawptr) -> c.uint ---

    message_iter_get_arg_type :: proc(iter: ^DBusMessageIter) -> c.int ---
    message_iter_get_basic :: proc(iter: ^DBusMessageIter, value: rawptr) ---

    message_iter_open_container :: proc(iter: ^DBusMessageIter, type: c.int, contained_signature: cstring, sub: ^DBusMessageIter) -> c.uint ---
    message_iter_close_container :: proc(iter: ^DBusMessageIter, sub: ^DBusMessageIter) -> c.uint ---

    connection_send_with_reply :: proc(connection: ^DBusConnection, message: ^DBusMessage, pending_return: ^^DBusPendingCall, timeout_seconds: c.int) -> c.uint ---
    connection_send_with_reply_and_block :: proc(connection: ^DBusConnection, message: DBusMessage, timeout_milliseconds: c.int, error: ^DBusError) ---

    message_unref :: proc(message: ^DBusMessage) ---

    connection_flush :: proc(connection: ^DBusConnection) --- // Blocks until the outgoing message queue is empty.
    connection_unref :: proc(connection: ^DBusConnection) ---

    pending_call_block :: proc(pending: ^DBusPendingCall) ---
    pending_call_steal_reply :: proc(pending: ^DBusPendingCall) -> ^DBusMessage ---
    pending_call_unref :: proc(pending: ^DBusPendingCall) ---

    // request_bus_name
    //connection_register_object_path
    // dbus_message_append_args

}
