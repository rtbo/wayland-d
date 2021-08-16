// Copyright © 2017-2021 Rémi Thebault
module wayland.client;

public import wayland.client.core;
public import wayland.client.protocol;

version(WlDynamic)
{
    import wayland.native.client;
    import wayland.native.util;

    import derelict.util.loader : SharedLibLoader;

    private class WlClientLoader : SharedLibLoader
    {
        this()
        {
            super("libwayland-client.so");
        }

        protected override void loadSymbols()
        {
            bindFunc( cast( void** )&wl_event_queue_destroy, "wl_event_queue_destroy" );
            bindFunc( cast( void** )&wl_proxy_marshal, "wl_proxy_marshal" );
            bindFunc( cast( void** )&wl_proxy_marshal_array, "wl_proxy_marshal_array" );
            bindFunc( cast( void** )&wl_proxy_create, "wl_proxy_create" );
            bindFunc( cast( void** )&wl_proxy_create_wrapper, "wl_proxy_create_wrapper" );
            bindFunc( cast( void** )&wl_proxy_wrapper_destroy, "wl_proxy_wrapper_destroy" );
            bindFunc( cast( void** )&wl_proxy_marshal_constructor, "wl_proxy_marshal_constructor" );
            bindFunc( cast( void** )&wl_proxy_marshal_constructor_versioned, "wl_proxy_marshal_constructor_versioned" );
            bindFunc( cast( void** )&wl_proxy_marshal_array_constructor, "wl_proxy_marshal_array_constructor" );
            bindFunc( cast( void** )&wl_proxy_marshal_array_constructor_versioned, "wl_proxy_marshal_array_constructor_versioned" );
            bindFunc( cast( void** )&wl_proxy_destroy, "wl_proxy_destroy" );
            bindFunc( cast( void** )&wl_proxy_add_listener, "wl_proxy_add_listener" );
            bindFunc( cast( void** )&wl_proxy_get_listener, "wl_proxy_get_listener" );
            bindFunc( cast( void** )&wl_proxy_add_dispatcher, "wl_proxy_add_dispatcher" );
            bindFunc( cast( void** )&wl_proxy_set_user_data, "wl_proxy_set_user_data" );
            bindFunc( cast( void** )&wl_proxy_get_user_data, "wl_proxy_get_user_data" );
            bindFunc( cast( void** )&wl_proxy_get_version, "wl_proxy_get_version" );
            bindFunc( cast( void** )&wl_proxy_get_id, "wl_proxy_get_id" );
            bindFunc( cast( void** )&wl_proxy_get_class, "wl_proxy_get_class" );
            bindFunc( cast( void** )&wl_proxy_set_queue, "wl_proxy_set_queue" );
            bindFunc( cast( void** )&wl_display_connect, "wl_display_connect" );
            bindFunc( cast( void** )&wl_display_connect_to_fd, "wl_display_connect_to_fd" );
            bindFunc( cast( void** )&wl_display_disconnect, "wl_display_disconnect" );
            bindFunc( cast( void** )&wl_display_get_fd, "wl_display_get_fd" );
            bindFunc( cast( void** )&wl_display_dispatch, "wl_display_dispatch" );
            bindFunc( cast( void** )&wl_display_dispatch_queue, "wl_display_dispatch_queue" );
            bindFunc( cast( void** )&wl_display_dispatch_queue_pending, "wl_display_dispatch_queue_pending" );
            bindFunc( cast( void** )&wl_display_dispatch_pending, "wl_display_dispatch_pending" );
            bindFunc( cast( void** )&wl_display_get_error, "wl_display_get_error" );
            bindFunc( cast( void** )&wl_display_get_protocol_error, "wl_display_get_protocol_error" );
            bindFunc( cast( void** )&wl_display_flush, "wl_display_flush" );
            bindFunc( cast( void** )&wl_display_roundtrip_queue, "wl_display_roundtrip_queue" );
            bindFunc( cast( void** )&wl_display_roundtrip, "wl_display_roundtrip" );
            bindFunc( cast( void** )&wl_display_create_queue, "wl_display_create_queue" );
            bindFunc( cast( void** )&wl_display_prepare_read_queue, "wl_display_prepare_read_queue" );
            bindFunc( cast( void** )&wl_display_prepare_read, "wl_display_prepare_read" );
            bindFunc( cast( void** )&wl_display_cancel_read, "wl_display_cancel_read" );
            bindFunc( cast( void** )&wl_display_read_events, "wl_display_read_events" );
            bindFunc( cast( void** )&wl_log_set_handler_client, "wl_log_set_handler_client" );

            bindFunc( cast( void** )&wl_list_init, "wl_list_init" );
            bindFunc( cast( void** )&wl_list_insert, "wl_list_insert" );
            bindFunc( cast( void** )&wl_list_remove, "wl_list_remove" );
            bindFunc( cast( void** )&wl_list_length, "wl_list_length" );
            bindFunc( cast( void** )&wl_list_empty, "wl_list_empty" );
            bindFunc( cast( void** )&wl_list_insert_list, "wl_list_insert_list" );
            bindFunc( cast( void** )&wl_array_init, "wl_array_init" );
            bindFunc( cast( void** )&wl_array_release, "wl_array_release" );
            bindFunc( cast( void** )&wl_array_add, "wl_array_add" );
            bindFunc( cast( void** )&wl_array_copy, "wl_array_copy" );
        }
    }

    private __gshared WlClientLoader _loader;

    shared static this()
    {
        _loader = new WlClientLoader;
    }

    public @property SharedLibLoader wlClientDynLib()
    {
        return _loader;
    }
}

