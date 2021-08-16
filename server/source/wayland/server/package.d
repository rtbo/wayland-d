// Copyright © 2017-2021 Rémi Thebault
/// bindings to wayland-server-core.h
module wayland.server;

public import wayland.server.core;
public import wayland.server.protocol;
public import wayland.server.eventloop;

version(WlDynamic)
{
    import wayland.native.server;
    import wayland.native.util;

    import derelict.util.loader : SharedLibLoader;

    private class WlServerLoader : SharedLibLoader
    {
        this()
        {
            super("libwayland-server.so");
        }

        protected override void loadSymbols()
        {
            bindFunc( cast( void** )&wl_event_loop_create, "wl_event_loop_create" );
            bindFunc( cast( void** )&wl_event_loop_destroy, "wl_event_loop_destroy" );
            bindFunc( cast( void** )&wl_event_loop_add_fd, "wl_event_loop_add_fd" );
            bindFunc( cast( void** )&wl_event_source_fd_update, "wl_event_source_fd_update" );
            bindFunc( cast( void** )&wl_event_loop_add_timer, "wl_event_loop_add_timer" );
            bindFunc( cast( void** )&wl_event_loop_add_signal, "wl_event_loop_add_signal" );
            bindFunc( cast( void** )&wl_event_source_timer_update, "wl_event_source_timer_update" );
            bindFunc( cast( void** )&wl_event_source_remove, "wl_event_source_remove" );
            bindFunc( cast( void** )&wl_event_source_check, "wl_event_source_check" );
            bindFunc( cast( void** )&wl_event_loop_dispatch, "wl_event_loop_dispatch" );
            bindFunc( cast( void** )&wl_event_loop_dispatch_idle, "wl_event_loop_dispatch_idle" );
            bindFunc( cast( void** )&wl_event_loop_add_idle, "wl_event_loop_add_idle" );
            bindFunc( cast( void** )&wl_event_loop_get_fd, "wl_event_loop_get_fd" );
            bindFunc( cast( void** )&wl_event_loop_add_destroy_listener, "wl_event_loop_add_destroy_listener" );
            bindFunc( cast( void** )&wl_event_loop_get_destroy_listener, "wl_event_loop_get_destroy_listener" );
            bindFunc( cast( void** )&wl_display_create, "wl_display_create" );
            bindFunc( cast( void** )&wl_display_destroy, "wl_display_destroy" );
            bindFunc( cast( void** )&wl_display_get_event_loop, "wl_display_get_event_loop" );
            bindFunc( cast( void** )&wl_display_add_socket, "wl_display_add_socket" );
            bindFunc( cast( void** )&wl_display_add_socket_auto, "wl_display_add_socket_auto" );
            bindFunc( cast( void** )&wl_display_add_socket_fd, "wl_display_add_socket_fd" );
            bindFunc( cast( void** )&wl_display_terminate, "wl_display_terminate" );
            bindFunc( cast( void** )&wl_display_run, "wl_display_run" );
            bindFunc( cast( void** )&wl_display_flush_clients, "wl_display_flush_clients" );
            bindFunc( cast( void** )&wl_display_get_serial, "wl_display_get_serial" );
            bindFunc( cast( void** )&wl_display_next_serial, "wl_display_next_serial" );
            bindFunc( cast( void** )&wl_display_add_destroy_listener, "wl_display_add_destroy_listener" );
            bindFunc( cast( void** )&wl_display_add_client_created_listener, "wl_display_add_client_created_listener" );
            bindFunc( cast( void** )&wl_display_get_destroy_listener, "wl_display_get_destroy_listener" );
            bindFunc( cast( void** )&wl_global_create, "wl_global_create" );
            bindFunc( cast( void** )&wl_global_destroy, "wl_global_destroy" );
            bindFunc( cast( void** )&wl_display_set_global_filter, "wl_display_set_global_filter" );
            bindFunc( cast( void** )&wl_global_get_interface, "wl_global_get_interface" );
            bindFunc( cast( void** )&wl_global_get_user_data, "wl_global_get_user_data" );
            bindFunc( cast( void** )&wl_client_create, "wl_client_create" );
            bindFunc( cast( void** )&wl_display_get_client_list, "wl_display_get_client_list" );
            bindFunc( cast( void** )&wl_client_get_link, "wl_client_get_link" );
            bindFunc( cast( void** )&wl_client_from_link, "wl_client_from_link" );
            bindFunc( cast( void** )&wl_client_destroy, "wl_client_destroy" );
            bindFunc( cast( void** )&wl_client_flush, "wl_client_flush" );
            bindFunc( cast( void** )&wl_client_get_credentials, "wl_client_get_credentials" );
            bindFunc( cast( void** )&wl_client_get_fd, "wl_client_get_fd" );
            bindFunc( cast( void** )&wl_client_add_destroy_listener, "wl_client_add_destroy_listener" );
            bindFunc( cast( void** )&wl_client_get_destroy_listener, "wl_client_get_destroy_listener" );
            bindFunc( cast( void** )&wl_client_get_object, "wl_client_get_object" );
            bindFunc( cast( void** )&wl_client_post_no_memory, "wl_client_post_no_memory" );
            bindFunc( cast( void** )&wl_client_add_resource_created_listener, "wl_client_add_resource_created_listener" );
            bindFunc( cast( void** )&wl_client_for_each_resource, "wl_client_for_each_resource" );
            bindFunc( cast( void** )&wl_resource_post_event, "wl_resource_post_event" );
            bindFunc( cast( void** )&wl_resource_post_event_array, "wl_resource_post_event_array" );
            bindFunc( cast( void** )&wl_resource_queue_event, "wl_resource_queue_event" );
            bindFunc( cast( void** )&wl_resource_queue_event_array, "wl_resource_queue_event_array" );
            bindFunc( cast( void** )&wl_resource_post_error, "wl_resource_post_error" );
            bindFunc( cast( void** )&wl_resource_post_no_memory, "wl_resource_post_no_memory" );
            bindFunc( cast( void** )&wl_client_get_display, "wl_client_get_display" );
            bindFunc( cast( void** )&wl_resource_create, "wl_resource_create" );
            bindFunc( cast( void** )&wl_resource_set_implementation, "wl_resource_set_implementation" );
            bindFunc( cast( void** )&wl_resource_set_dispatcher, "wl_resource_set_dispatcher" );
            bindFunc( cast( void** )&wl_resource_destroy, "wl_resource_destroy" );
            bindFunc( cast( void** )&wl_resource_get_id, "wl_resource_get_id" );
            bindFunc( cast( void** )&wl_resource_get_link, "wl_resource_get_link" );
            bindFunc( cast( void** )&wl_resource_from_link, "wl_resource_from_link" );
            bindFunc( cast( void** )&wl_resource_find_for_client, "wl_resource_find_for_client" );
            bindFunc( cast( void** )&wl_resource_get_client, "wl_resource_get_client" );
            bindFunc( cast( void** )&wl_resource_set_user_data, "wl_resource_set_user_data" );
            bindFunc( cast( void** )&wl_resource_get_user_data, "wl_resource_get_user_data" );
            bindFunc( cast( void** )&wl_resource_get_version, "wl_resource_get_version" );
            bindFunc( cast( void** )&wl_resource_set_destructor, "wl_resource_set_destructor" );
            bindFunc( cast( void** )&wl_resource_instance_of, "wl_resource_instance_of" );
            bindFunc( cast( void** )&wl_resource_get_class, "wl_resource_get_class" );
            bindFunc( cast( void** )&wl_resource_add_destroy_listener, "wl_resource_add_destroy_listener" );
            bindFunc( cast( void** )&wl_resource_get_destroy_listener, "wl_resource_get_destroy_listener" );
            bindFunc( cast( void** )&wl_shm_buffer_get, "wl_shm_buffer_get" );
            bindFunc( cast( void** )&wl_shm_buffer_begin_access, "wl_shm_buffer_begin_access" );
            bindFunc( cast( void** )&wl_shm_buffer_end_access, "wl_shm_buffer_end_access" );
            bindFunc( cast( void** )&wl_shm_buffer_get_data, "wl_shm_buffer_get_data" );
            bindFunc( cast( void** )&wl_shm_buffer_get_stride, "wl_shm_buffer_get_stride" );
            bindFunc( cast( void** )&wl_shm_buffer_get_format, "wl_shm_buffer_get_format" );
            bindFunc( cast( void** )&wl_shm_buffer_get_width, "wl_shm_buffer_get_width" );
            bindFunc( cast( void** )&wl_shm_buffer_get_height, "wl_shm_buffer_get_height" );
            bindFunc( cast( void** )&wl_shm_buffer_ref_pool, "wl_shm_buffer_ref_pool" );
            bindFunc( cast( void** )&wl_shm_pool_unref, "wl_shm_pool_unref" );
            bindFunc( cast( void** )&wl_display_init_shm, "wl_display_init_shm" );
            bindFunc( cast( void** )&wl_display_add_shm_format, "wl_display_add_shm_format" );
            bindFunc( cast( void** )&wl_log_set_handler_server, "wl_log_set_handler_server" );
            bindFunc( cast( void** )&wl_display_add_protocol_logger, "wl_display_add_protocol_logger" );
            bindFunc( cast( void** )&wl_protocol_logger_destroy, "wl_protocol_logger_destroy" );

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

    private __gshared WlServerLoader _loader;

    shared static this()
    {
        _loader = new WlServerLoader;
    }

    public @property SharedLibLoader wlServerDynLib()
    {
        return _loader;
    }
}

