package notify

import "../dbus"
import "core:fmt"

Notify :: struct {
    message_id: u32,
    dbus_connection: ^dbus.DBusConnection,
}

init :: proc() {
    dbus_err : dbus.DBusError
    args, array, dict, entry, variant : dbus.DBusMessageIter
    pending : ^dbus.DBusPendingCall
    id : u32

    dbus.error_init(&dbus_err)
    defer dbus.error_free(&dbus_err)

    conn := dbus.bus_get(.DBUS_BUS_SESSION, &dbus_err)
    defer dbus.connection_unref(conn)

    if dbus.error_is_set(&dbus_err) == 1 {
        fmt.println("Connection error")
        return
    }

    dbus_message := dbus.message_new_method_call(
        "org.freedesktop.Notifications",
        "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications",
        "Notify"
    )

    if dbus_message == nil {
        fmt.println("Dbus message is nil")
        return
    }
    defer dbus.message_unref(dbus_message)

    dbus.message_iter_init_append(dbus_message, &args)

    app : cstring = "music_player"
    replace : u32 = 0
    icon : cstring = "dialog-information"
    summary : cstring = "this is summary"
    body : cstring = "body"

    dbus.message_iter_append_basic(&args, dbus.DBUS_TYPE_STRING, &app)
    dbus.message_iter_append_basic(&args, dbus.DBUS_TYPE_UINT32, &replace)
    dbus.message_iter_append_basic(&args, dbus.DBUS_TYPE_STRING, &icon)
    dbus.message_iter_append_basic(&args, dbus.DBUS_TYPE_STRING, &summary)
    dbus.message_iter_append_basic(&args, dbus.DBUS_TYPE_STRING, &body)

    dbus.message_iter_open_container(&args, dbus.DBUS_TYPE_ARRAY, "s", &array)
    dbus.message_iter_close_container(&args, &array)

    dbus.message_iter_open_container(&args, dbus.DBUS_TYPE_ARRAY, "{sv}", &dict)
    dbus.message_iter_open_container(&dict, dbus.DBUS_TYPE_DICT_ENTRY, nil, &entry)

    hint_key : cstring = "urgency"
    dbus.message_iter_append_basic(&entry, dbus.DBUS_TYPE_STRING, &hint_key)

    dbus.message_iter_open_container(&entry, dbus.DBUS_TYPE_VARIANT, "y", &variant)

    urgency := 1
    dbus.message_iter_append_basic(&variant, dbus.DBUS_TYPE_BYTE, &urgency)

    dbus.message_iter_close_container(&entry, &variant)
    dbus.message_iter_close_container(&dict, &entry)
    dbus.message_iter_close_container(&args, &dict)

    timeout : i32 = 5000
    dbus.message_iter_append_basic(&args, dbus.DBUS_TYPE_INT32, &timeout)

    ret := dbus.connection_send_with_reply(conn, dbus_message, &pending, -1)
    if ret == 0 || pending == nil {
        fmt.println("sending failed")
        return
    }

    dbus.connection_flush(conn)
    dbus.pending_call_block(pending)


}

