#+build !linux
package sdbus

open_user :: proc(bus: ^Bus) -> i32 {
    return -1
}

unref :: proc(bus: Bus) -> Bus {
    return nil
}

flush_close_unref :: proc(bus: Bus) -> Bus {
    return nil
}

call_method :: proc(
    bus: Bus,
    destination, path, interface, member: cstring,
    ret_error: Error,
    reply: ^Message,
    types: cstring,
    args: ..any
) -> i32 {
    return -1
}

message_read :: proc(m: Message, types: cstring, args: ..any) -> i32 {
    return -1
}

message_unref :: proc(m: Message) -> Message {
    return nil
}
