// [[DOC: https://www.freedesktop.org/software/systemd/man/latest/index.html]]
// [[git: https://github.com/systemd/systemd]]

#+build linux
package sdbus

foreign import lib "system:libsystemd.so"

@(default_calling_convention="system", link_prefix="sd_bus_")
foreign lib {
    open_user :: proc(bus: ^Bus) -> i32 ---
    unref :: proc(bus: Bus) -> Bus ---
    flush_close_unref :: proc(bus: Bus) -> Bus ---

    call_method :: proc(
        bus: Bus,
        destination, path, interface, member: cstring,
        ret_error: Error,
        reply: ^Message,
        types: cstring,
        #c_vararg args: ..any
    ) -> i32 ---

    message_read :: proc(m: Message, types: cstring, #c_vararg args: ..any) -> i32 ---
    message_unref :: proc(m: Message) -> Message ---
}
