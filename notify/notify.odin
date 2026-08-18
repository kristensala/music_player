package notify

import "../dbus"
import "core:fmt"
import "core:unicode/utf8"

Notify_Error :: enum {
    Not_Valid_Utf8_String,
    Failed_To_Create_Message,
    Failed_To_Send_Message,
    No_Content
}

Error :: union {
    dbus.DBusError,
    Notify_Error
}

// Persist the last_notification_id
// @todo: show album art and album name in the notification (can I use html in body?)
send_notification :: proc(connection: ^dbus.DBusConnection, summary: cstring, body: cstring, icon: cstring, last_notification_id: u32) -> (n: u32, err: Error) {
    assert(connection != nil)

    // nothing to show, so do not trigger the notification
    if (summary == nil && body == nil) || (len(summary) == 0 && len(body) == 0) {
        return last_notification_id, .No_Content
    }

    is_summary_valid_utf8 := utf8.valid_string(string(summary))
    is_body_valid_utf8 := utf8.valid_string(string(body))
    if !is_summary_valid_utf8 || !is_body_valid_utf8 {
        return last_notification_id, .Not_Valid_Utf8_String
    }


    args, array, dict, entry, variant : dbus.DBusMessageIter
    pending : ^dbus.DBusPendingCall

    dbus_message := dbus.message_new_method_call(
        "org.freedesktop.Notifications",
        "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications",
        "Notify"
    )

    if dbus_message == nil {
        fmt.println("Dbus message is nil")
        return last_notification_id, .Failed_To_Create_Message
    }
    defer dbus.message_unref(dbus_message)

    dbus.message_iter_init_append(dbus_message, &args)

    app : cstring = "music_player"
    replace : u32 = last_notification_id
    _icon : cstring = "audio-headphones" // @fix: does nothing; needs some daemon running to get these icons

    is_icon_valid_utf8 := utf8.valid_string(string(icon))
    if is_icon_valid_utf8 && icon != nil {
        _icon = icon
    }

    _summary := summary
    _body := body

    dbus.message_iter_append_basic(&args, dbus.DBUS_TYPE_STRING, &app)
    dbus.message_iter_append_basic(&args, dbus.DBUS_TYPE_UINT32, &replace)
    dbus.message_iter_append_basic(&args, dbus.DBUS_TYPE_STRING, &_icon)
    dbus.message_iter_append_basic(&args, dbus.DBUS_TYPE_STRING, &_summary)
    dbus.message_iter_append_basic(&args, dbus.DBUS_TYPE_STRING, &_body)

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

    // Queues the message, but does not quarantee it hits the socket immediately.
    // Thats why we flush the connection (below) before blocking the calling thread,
    // because it forces the write to the transport now
    ret := dbus.connection_send_with_reply(connection, dbus_message, &pending, -1)
    if ret == 0 || pending == nil {
        return last_notification_id, .Failed_To_Send_Message
    }

    dbus.connection_flush(connection) // in synchronous blocking code required to avoid deadlock
    dbus.pending_call_block(pending) // block calling thread until reply message arrives or connection fails

    reply := dbus.pending_call_steal_reply(pending)
    dbus.pending_call_unref(pending)

    notification_id := last_notification_id
    if reply != nil {
        dbus.message_iter_init(reply, &args)
        if dbus.DBUS_TYPE_UINT32 == dbus.message_iter_get_arg_type(&args) {
            dbus.message_iter_get_basic(&args, &notification_id)
            fmt.println("notification ID: ", notification_id)
            dbus.message_unref(reply)
        }

    }

    return notification_id, nil
}

