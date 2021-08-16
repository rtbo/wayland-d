// Copyright © 2017-2021 Rémi Thebault
/// bindings to wayland-server-core.h
module wayland.native.server;

// Wayland server-core copyright:
/*
 * Copyright © 2008 Kristian Høgsberg
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice (including the
 * next paragraph) shall be included in all copies or substantial
 * portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import wayland.native.util;
import core.sys.posix.sys.types;

extern(C)
{
    struct wl_display;
    struct wl_event_loop;
    struct wl_event_source;
    struct wl_client;
    struct wl_global;
    struct wl_resource;
    struct wl_shm_buffer;
    struct wl_shm_pool;
    struct wl_protocol_logger;

    struct wl_protocol_logger_message {
        wl_resource* resource;
        int message_opcode;
        const(wl_message)* message;
        int arguments_count;
        const(wl_argument)* arguments;
    }

    struct wl_listener {
        wl_list link;
        wl_notify_func_t notify;
    }

    struct wl_signal {
        wl_list listener_list;
    }

    enum {
        WL_EVENT_READABLE = 0x01,
        WL_EVENT_WRITABLE = 0x02,
        WL_EVENT_HANGUP   = 0x04,
        WL_EVENT_ERROR    = 0x08
    }

    enum wl_protocol_logger_type {
        WL_PROTOCOL_LOGGER_REQUEST,
        WL_PROTOCOL_LOGGER_EVENT,
    }


    alias wl_event_loop_fd_func_t = int function (int fd, uint mask, void* data);
    alias wl_event_loop_timer_func_t = int function (void* data);
    alias wl_event_loop_signal_func_t = int function (int signal_number, void* data);
    alias wl_event_loop_idle_func_t = void function (void* data);

    alias wl_notify_func_t = void function (wl_listener* listener, void* data);
    alias wl_global_bind_func_t = void function (wl_client* client, void* data, uint ver, uint id);
    alias wl_client_for_each_resource_iterator_func_t = wl_iterator_result function (wl_resource* resource, void* user_data);

    alias wl_display_global_filter_func_t = bool function (const(wl_client)* client, const(wl_global)* global, void* data);

    alias wl_resource_destroy_func_t = void function (wl_resource* resource);

    alias wl_protocol_logger_func_t = void function (void* user_data, wl_protocol_logger_type direction, const(wl_protocol_logger_message)* message);
}


/** Iterate over a list of clients. */
auto wlClientForEach(wl_list* list)
{
    struct WlClientRange
    {
        wl_list* list;
        wl_client* client;

        this(wl_list* list)
        {
            this.list = list;
            this.client = wl_client_from_link(list.next);
        }

        @property wl_client* front()
        {
            return client;
        }

        @property bool empty()
        {
            return wl_client_get_link(client) == list;
        }

        void popFront()
        {
            client = wl_client_from_link(wl_client_get_link(client).next);
        }
    }

    return WlClientRange(list);
}


/** Initialize a new \ref wl_signal for use.
 *
 * \param signal The signal that will be initialized
 *
 * \memberof wl_signal
 */
void
wl_signal_init(wl_signal* signal)
{
	wl_list_init(&signal.listener_list);
}

/** Add the specified listener to this signal.
 *
 * \param signal The signal that will emit events to the listener
 * \param listener The listener to add
 *
 * \memberof wl_signal
 */
void
wl_signal_add(wl_signal* signal, wl_listener* listener)
{
	wl_list_insert(signal.listener_list.prev, &listener.link);
}

/** Gets the listener for the specified callback.
 *
 * \param signal The signal that contains the specified listener
 * \param notify The listener that is the target of this search
 * \return the list item that corresponds to the specified listener, or NULL
 * if none was found
 *
 * \memberof wl_signal
 */
wl_listener*
wl_signal_get(wl_signal* signal, wl_notify_func_t notify)
{
    foreach(l; wl_range!(wl_listener.link)(&signal.listener_list))
    {
        if (l.notify == notify) return l;
    }
    return null;
}

/** Emits this signal, notifying all registered listeners.
 *
 * \param signal The signal object that will emit the signal
 * \param data The data that will be emitted with the signal
 *
 * \memberof wl_signal
 */
void
wl_signal_emit(wl_signal* signal, void* data)
{
    foreach(l; wl_range!(wl_listener.link)(&signal.listener_list))
    {
        l.notify(l, data);
    }
}

// #define wl_resource_for_each(resource, list)					\
//     for (resource = 0, resource = wl_resource_from_link((list)->next);	\
//         wl_resource_get_link(resource) != (list);				\
//         resource = wl_resource_from_link(wl_resource_get_link(resource)->next))

// #define wl_resource_for_each_safe(resource, tmp, list)					\
//     for (resource = 0, tmp = 0,							\
//         resource = wl_resource_from_link((list)->next),	\
//         tmp = wl_resource_from_link((list)->next->next);	\
//         wl_resource_get_link(resource) != (list);				\
//         resource = tmp,							\
//         tmp = wl_resource_from_link(wl_resource_get_link(resource)->next))


version(WlDynamic)
{
    extern(C) nothrow
    {
        alias da_wl_event_loop_create = wl_event_loop* function ();

        alias da_wl_event_loop_destroy = void function (wl_event_loop* loop);

        alias da_wl_event_loop_add_fd = wl_event_source* function (wl_event_loop* loop, int fd, uint mask, wl_event_loop_fd_func_t func, void* data);

        alias da_wl_event_source_fd_update = int function (wl_event_source* source, uint mask);

        alias da_wl_event_loop_add_timer = wl_event_source* function (wl_event_loop* loop, wl_event_loop_timer_func_t func, void* data);

        alias da_wl_event_loop_add_signal = wl_event_source* function (wl_event_loop* loop, int signal_number, wl_event_loop_signal_func_t func, void* data);

        alias da_wl_event_source_timer_update = int function (wl_event_source* source, int ms_delay);

        alias da_wl_event_source_remove = int function (wl_event_source* source);

        alias da_wl_event_source_check = void function (wl_event_source* source);

        alias da_wl_event_loop_dispatch = int function (wl_event_loop* loop, int timeout);

        alias da_wl_event_loop_dispatch_idle = void function (wl_event_loop* loop);

        alias da_wl_event_loop_add_idle = wl_event_source* function (wl_event_loop* loop, wl_event_loop_idle_func_t func, void* data);

        alias da_wl_event_loop_get_fd = int function (wl_event_loop* loop);

        alias da_wl_event_loop_add_destroy_listener = void function (wl_event_loop* loop, wl_listener* listener);

        alias da_wl_event_loop_get_destroy_listener = wl_listener* function (wl_event_loop* loop, wl_notify_func_t notify);

        alias da_wl_display_create = wl_display* function ();

        alias da_wl_display_destroy = void function (wl_display* display);

        alias da_wl_display_get_event_loop = wl_event_loop* function (wl_display* display);

        alias da_wl_display_add_socket = int function (wl_display* display, const(char)* name);

        alias da_wl_display_add_socket_auto = const(char)* function (wl_display* display);

        alias da_wl_display_add_socket_fd = int function (wl_display* display, int sock_fd);

        alias da_wl_display_terminate = void function (wl_display* display);

        alias da_wl_display_run = void function (wl_display* display);

        alias da_wl_display_flush_clients = void function (wl_display* display);

        alias da_wl_display_get_serial = uint function (wl_display* display);

        alias da_wl_display_next_serial = uint function (wl_display* display);

        alias da_wl_display_add_destroy_listener = void function (wl_display* display, wl_listener* listener);

        alias da_wl_display_add_client_created_listener = void function (wl_display* display, wl_listener* listener);

        alias da_wl_display_get_destroy_listener = wl_listener* function (wl_display* display, wl_notify_func_t notify);

        alias da_wl_global_create = wl_global* function (wl_display* display, const(wl_interface)* iface, int ver, void* data, wl_global_bind_func_t bind);

        alias da_wl_global_destroy = void function (wl_global* global);

        alias da_wl_display_set_global_filter = void function (wl_display* display, wl_display_global_filter_func_t filter, void* data);

        alias da_wl_global_get_interface = const(wl_interface)* function (const(wl_global)* global);

        alias da_wl_global_get_user_data = void* function (const(wl_global)* global);

        alias da_wl_client_create = wl_client* function (wl_display* display, int fd);

        alias da_wl_display_get_client_list = wl_list* function (wl_display* display);

        alias da_wl_client_get_link = wl_list* function (wl_client* client);

        alias da_wl_client_from_link = wl_client* function (wl_list* link);

        alias da_wl_client_destroy = void function (wl_client* client);

        alias da_wl_client_flush = void function (wl_client* client);

        alias da_wl_client_get_credentials = void function (wl_client* client, pid_t* pid, uid_t* uid, gid_t* gid);

        alias da_wl_client_get_fd = int function (wl_client* client);

        alias da_wl_client_add_destroy_listener = void function (wl_client* client, wl_listener* listener);

        alias da_wl_client_get_destroy_listener = wl_listener* function (wl_client* client, wl_notify_func_t notify);

        alias da_wl_client_get_object = wl_resource* function (wl_client* client, uint id);

        alias da_wl_client_post_no_memory = void function (wl_client* client);

        alias da_wl_client_add_resource_created_listener = void function (wl_client* client, wl_listener* listener);

        alias da_wl_client_for_each_resource = void function (wl_client* client, wl_client_for_each_resource_iterator_func_t iterator, void* user_data);

        alias da_wl_resource_post_event = void function (wl_resource* resource, uint opcode, ...);

        alias da_wl_resource_post_event_array = void function (wl_resource* resource, uint opcode, wl_argument* args);

        alias da_wl_resource_queue_event = void function (wl_resource* resource, uint opcode, ...);

        alias da_wl_resource_queue_event_array = void function (wl_resource* resource, uint opcode, wl_argument* args);

        alias da_wl_resource_post_error = void function (wl_resource* resource, uint code, const(char)* msg, ...);

        alias da_wl_resource_post_no_memory = void function (wl_resource* resource);

        alias da_wl_client_get_display = wl_display* function (wl_client* client);

        alias da_wl_resource_create = wl_resource* function (wl_client* client, const(wl_interface)* iface, int ver, uint id);

        alias da_wl_resource_set_implementation = void function (wl_resource* resource, const(void)* impl, void* data, wl_resource_destroy_func_t destroy);

        alias da_wl_resource_set_dispatcher = void function (wl_resource* resource, wl_dispatcher_func_t dispatcher, const(void)* impl, void* data, wl_resource_destroy_func_t destroy);

        alias da_wl_resource_destroy = void function (wl_resource* resource);

        alias da_wl_resource_get_id = uint function (wl_resource* resource);

        alias da_wl_resource_get_link = wl_list* function (wl_resource* resource);

        alias da_wl_resource_from_link = wl_resource* function (wl_list* resource);

        alias da_wl_resource_find_for_client = wl_resource* function (wl_list* list, wl_client* client);

        alias da_wl_resource_get_client = wl_client* function (wl_resource* resource);

        alias da_wl_resource_set_user_data = void function (wl_resource* resource, void* data);

        alias da_wl_resource_get_user_data = void* function (wl_resource* resource);

        alias da_wl_resource_get_version = int function (wl_resource* resource);

        alias da_wl_resource_set_destructor = void function (wl_resource* resource, wl_resource_destroy_func_t destroy);

        alias da_wl_resource_instance_of = int function (wl_resource* resource, const(wl_interface)* iface, const(void)* impl);

        alias da_wl_resource_get_class = const(char)* function (wl_resource* resource);

        alias da_wl_resource_add_destroy_listener = void function (wl_resource* resource, wl_listener* listener);

        alias da_wl_resource_get_destroy_listener = wl_listener* function (wl_resource* resource, wl_notify_func_t notify);

        alias da_wl_shm_buffer_get = wl_shm_buffer* function (wl_resource* resource);

        alias da_wl_shm_buffer_begin_access = void function (wl_shm_buffer* buffer);

        alias da_wl_shm_buffer_end_access = void function (wl_shm_buffer* buffer);

        alias da_wl_shm_buffer_get_data = void* function (wl_shm_buffer* buffer);

        alias da_wl_shm_buffer_get_stride = int function (wl_shm_buffer* buffer);

        alias da_wl_shm_buffer_get_format = uint function (wl_shm_buffer* buffer);

        alias da_wl_shm_buffer_get_width = int function (wl_shm_buffer* buffer);

        alias da_wl_shm_buffer_get_height = int function (wl_shm_buffer* buffer);

        alias da_wl_shm_buffer_ref_pool = wl_shm_pool* function (wl_shm_buffer* buffer);

        alias da_wl_shm_pool_unref = void function (wl_shm_pool* pool);

        alias da_wl_display_init_shm = int function (wl_display* display);

        alias da_wl_display_add_shm_format = uint* function (wl_display* display, uint format);

        alias da_wl_log_set_handler_server = void function (wl_log_func_t handler);

        alias da_wl_display_add_protocol_logger = wl_protocol_logger* function (wl_display* display, wl_protocol_logger_func_t, void* user_data);

        alias da_wl_protocol_logger_destroy = void function (wl_protocol_logger* logger);
    }

    __gshared
    {
        da_wl_event_loop_create wl_event_loop_create;
        da_wl_event_loop_destroy wl_event_loop_destroy;
        da_wl_event_loop_add_fd wl_event_loop_add_fd;
        da_wl_event_source_fd_update wl_event_source_fd_update;
        da_wl_event_loop_add_timer wl_event_loop_add_timer;
        da_wl_event_loop_add_signal wl_event_loop_add_signal;
        da_wl_event_source_timer_update wl_event_source_timer_update;
        da_wl_event_source_remove wl_event_source_remove;
        da_wl_event_source_check wl_event_source_check;
        da_wl_event_loop_dispatch wl_event_loop_dispatch;
        da_wl_event_loop_dispatch_idle wl_event_loop_dispatch_idle;
        da_wl_event_loop_add_idle wl_event_loop_add_idle;
        da_wl_event_loop_get_fd wl_event_loop_get_fd;
        da_wl_event_loop_add_destroy_listener wl_event_loop_add_destroy_listener;
        da_wl_event_loop_get_destroy_listener wl_event_loop_get_destroy_listener;
        da_wl_display_create wl_display_create;
        da_wl_display_destroy wl_display_destroy;
        da_wl_display_get_event_loop wl_display_get_event_loop;
        da_wl_display_add_socket wl_display_add_socket;
        da_wl_display_add_socket_auto wl_display_add_socket_auto;
        da_wl_display_add_socket_fd wl_display_add_socket_fd;
        da_wl_display_terminate wl_display_terminate;
        da_wl_display_run wl_display_run;
        da_wl_display_flush_clients wl_display_flush_clients;
        da_wl_display_get_serial wl_display_get_serial;
        da_wl_display_next_serial wl_display_next_serial;
        da_wl_display_add_destroy_listener wl_display_add_destroy_listener;
        da_wl_display_add_client_created_listener wl_display_add_client_created_listener;
        da_wl_display_get_destroy_listener wl_display_get_destroy_listener;
        da_wl_global_create wl_global_create;
        da_wl_global_destroy wl_global_destroy;
        da_wl_display_set_global_filter wl_display_set_global_filter;
        da_wl_global_get_interface wl_global_get_interface;
        da_wl_global_get_user_data wl_global_get_user_data;
        da_wl_client_create wl_client_create;
        da_wl_display_get_client_list wl_display_get_client_list;
        da_wl_client_get_link wl_client_get_link;
        da_wl_client_from_link wl_client_from_link;
        da_wl_client_destroy wl_client_destroy;
        da_wl_client_flush wl_client_flush;
        da_wl_client_get_credentials wl_client_get_credentials;
        da_wl_client_get_fd wl_client_get_fd;
        da_wl_client_add_destroy_listener wl_client_add_destroy_listener;
        da_wl_client_get_destroy_listener wl_client_get_destroy_listener;
        da_wl_client_get_object wl_client_get_object;
        da_wl_client_post_no_memory wl_client_post_no_memory;
        da_wl_client_add_resource_created_listener wl_client_add_resource_created_listener;
        da_wl_client_for_each_resource wl_client_for_each_resource;
        da_wl_resource_post_event wl_resource_post_event;
        da_wl_resource_post_event_array wl_resource_post_event_array;
        da_wl_resource_queue_event wl_resource_queue_event;
        da_wl_resource_queue_event_array wl_resource_queue_event_array;
        da_wl_resource_post_error wl_resource_post_error;
        da_wl_resource_post_no_memory wl_resource_post_no_memory;
        da_wl_client_get_display wl_client_get_display;
        da_wl_resource_create wl_resource_create;
        da_wl_resource_set_implementation wl_resource_set_implementation;
        da_wl_resource_set_dispatcher wl_resource_set_dispatcher;
        da_wl_resource_destroy wl_resource_destroy;
        da_wl_resource_get_id wl_resource_get_id;
        da_wl_resource_get_link wl_resource_get_link;
        da_wl_resource_from_link wl_resource_from_link;
        da_wl_resource_find_for_client wl_resource_find_for_client;
        da_wl_resource_get_client wl_resource_get_client;
        da_wl_resource_set_user_data wl_resource_set_user_data;
        da_wl_resource_get_user_data wl_resource_get_user_data;
        da_wl_resource_get_version wl_resource_get_version;
        da_wl_resource_set_destructor wl_resource_set_destructor;
        da_wl_resource_instance_of wl_resource_instance_of;
        da_wl_resource_get_class wl_resource_get_class;
        da_wl_resource_add_destroy_listener wl_resource_add_destroy_listener;
        da_wl_resource_get_destroy_listener wl_resource_get_destroy_listener;
        da_wl_shm_buffer_get wl_shm_buffer_get;
        da_wl_shm_buffer_begin_access wl_shm_buffer_begin_access;
        da_wl_shm_buffer_end_access wl_shm_buffer_end_access;
        da_wl_shm_buffer_get_data wl_shm_buffer_get_data;
        da_wl_shm_buffer_get_stride wl_shm_buffer_get_stride;
        da_wl_shm_buffer_get_format wl_shm_buffer_get_format;
        da_wl_shm_buffer_get_width wl_shm_buffer_get_width;
        da_wl_shm_buffer_get_height wl_shm_buffer_get_height;
        da_wl_shm_buffer_ref_pool wl_shm_buffer_ref_pool;
        da_wl_shm_pool_unref wl_shm_pool_unref;
        da_wl_display_init_shm wl_display_init_shm;
        da_wl_display_add_shm_format wl_display_add_shm_format;
        da_wl_log_set_handler_server wl_log_set_handler_server;
        da_wl_display_add_protocol_logger wl_display_add_protocol_logger;
        da_wl_protocol_logger_destroy wl_protocol_logger_destroy;
    }
}

version(WlStatic)
{
    extern(C) nothrow
    {
        wl_event_loop* wl_event_loop_create();

        void wl_event_loop_destroy(wl_event_loop* loop);

        wl_event_source* wl_event_loop_add_fd(wl_event_loop* loop, int fd, uint mask, wl_event_loop_fd_func_t func, void* data);

        int wl_event_source_fd_update(wl_event_source* source, uint mask);

        wl_event_source* wl_event_loop_add_timer(wl_event_loop* loop, wl_event_loop_timer_func_t func, void* data);

        wl_event_source* wl_event_loop_add_signal(wl_event_loop* loop, int signal_number, wl_event_loop_signal_func_t func, void* data);

        int wl_event_source_timer_update(wl_event_source* source, int ms_delay);

        int wl_event_source_remove(wl_event_source* source);

        void wl_event_source_check(wl_event_source* source);

        int wl_event_loop_dispatch(wl_event_loop* loop, int timeout);

        void wl_event_loop_dispatch_idle(wl_event_loop* loop);

        wl_event_source* wl_event_loop_add_idle(wl_event_loop* loop, wl_event_loop_idle_func_t func, void* data);

        int wl_event_loop_get_fd(wl_event_loop* loop);

        void wl_event_loop_add_destroy_listener(wl_event_loop* loop, wl_listener* listener);

        wl_listener* wl_event_loop_get_destroy_listener(wl_event_loop* loop, wl_notify_func_t notify);

        wl_display* wl_display_create();

        void wl_display_destroy(wl_display* display);

        wl_event_loop* wl_display_get_event_loop(wl_display* display);

        int wl_display_add_socket(wl_display* display, const(char)* name);

        const(char)* wl_display_add_socket_auto(wl_display* display);

        int wl_display_add_socket_fd(wl_display* display, int sock_fd);

        void wl_display_terminate(wl_display* display);

        void wl_display_run(wl_display* display);

        void wl_display_flush_clients(wl_display* display);

        uint wl_display_get_serial(wl_display* display);

        uint wl_display_next_serial(wl_display* display);

        void wl_display_add_destroy_listener(wl_display* display, wl_listener* listener);

        void wl_display_add_client_created_listener(wl_display* display, wl_listener* listener);

        wl_listener* wl_display_get_destroy_listener(wl_display* display, wl_notify_func_t notify);

        wl_global* wl_global_create(wl_display* display, const(wl_interface)* iface, int ver, void* data, wl_global_bind_func_t bind);

        void wl_global_destroy(wl_global* global);

        void wl_display_set_global_filter(wl_display* display, wl_display_global_filter_func_t filter, void* data);

        const(wl_interface)* wl_global_get_interface(const(wl_global)* global);

        void* wl_global_get_user_data(const(wl_global)* global);

        wl_client* wl_client_create(wl_display* display, int fd);

        wl_list* wl_display_get_client_list(wl_display* display);

        wl_list* wl_client_get_link(wl_client* client);

        wl_client* wl_client_from_link(wl_list* link);

        void wl_client_destroy(wl_client* client);

        void wl_client_flush(wl_client* client);

        void wl_client_get_credentials(wl_client* client, pid_t* pid, uid_t* uid, gid_t* gid);

        int wl_client_get_fd(wl_client* client);

        void wl_client_add_destroy_listener(wl_client* client, wl_listener* listener);

        wl_listener* wl_client_get_destroy_listener(wl_client* client, wl_notify_func_t notify);

        wl_resource* wl_client_get_object(wl_client* client, uint id);

        void wl_client_post_no_memory(wl_client* client);

        void wl_client_add_resource_created_listener(wl_client* client, wl_listener* listener);

        void wl_client_for_each_resource(wl_client* client, wl_client_for_each_resource_iterator_func_t iterator, void* user_data);

        void wl_resource_post_event(wl_resource* resource, uint opcode, ...);

        void wl_resource_post_event_array(wl_resource* resource, uint opcode, wl_argument* args);

        void wl_resource_queue_event(wl_resource* resource, uint opcode, ...);

        void wl_resource_queue_event_array(wl_resource* resource, uint opcode, wl_argument* args);

        /* msg is a printf format string, variable args are its args. */
        void wl_resource_post_error(wl_resource* resource, uint code, const(char)* msg, ...);

        void wl_resource_post_no_memory(wl_resource* resource);

        wl_display* wl_client_get_display(wl_client* client);

        wl_resource* wl_resource_create(wl_client* client, const(wl_interface)* iface, int ver, uint id);

        void wl_resource_set_implementation(wl_resource* resource, const(void)* impl, void* data, wl_resource_destroy_func_t destroy);

        void wl_resource_set_dispatcher(wl_resource* resource, wl_dispatcher_func_t dispatcher, const(void)* impl, void* data, wl_resource_destroy_func_t destroy);

        void wl_resource_destroy(wl_resource* resource);

        uint wl_resource_get_id(wl_resource* resource);

        wl_list* wl_resource_get_link(wl_resource* resource);

        wl_resource* wl_resource_from_link(wl_list* resource);

        wl_resource* wl_resource_find_for_client(wl_list* list, wl_client* client);

        wl_client* wl_resource_get_client(wl_resource* resource);

        void wl_resource_set_user_data(wl_resource* resource, void* data);

        void* wl_resource_get_user_data(wl_resource* resource);

        int wl_resource_get_version(wl_resource* resource);

        void wl_resource_set_destructor(wl_resource* resource, wl_resource_destroy_func_t destroy);

        int wl_resource_instance_of(wl_resource* resource, const(wl_interface)* iface, const(void)* impl);

        const(char)* wl_resource_get_class(wl_resource* resource);

        void wl_resource_add_destroy_listener(wl_resource* resource, wl_listener* listener);

        wl_listener* wl_resource_get_destroy_listener(wl_resource* resource, wl_notify_func_t notify);

        wl_shm_buffer* wl_shm_buffer_get(wl_resource* resource);

        void wl_shm_buffer_begin_access(wl_shm_buffer* buffer);

        void wl_shm_buffer_end_access(wl_shm_buffer* buffer);

        void* wl_shm_buffer_get_data(wl_shm_buffer* buffer);

        int wl_shm_buffer_get_stride(wl_shm_buffer* buffer);

        uint wl_shm_buffer_get_format(wl_shm_buffer* buffer);

        int wl_shm_buffer_get_width(wl_shm_buffer* buffer);

        int wl_shm_buffer_get_height(wl_shm_buffer* buffer);

        wl_shm_pool* wl_shm_buffer_ref_pool(wl_shm_buffer* buffer);

        void wl_shm_pool_unref(wl_shm_pool* pool);

        int wl_display_init_shm(wl_display* display);

        uint* wl_display_add_shm_format(wl_display* display, uint format);

        void wl_log_set_handler_server(wl_log_func_t handler);

        wl_protocol_logger* wl_display_add_protocol_logger(wl_display* display, wl_protocol_logger_func_t, void* user_data);

        void wl_protocol_logger_destroy(wl_protocol_logger* logger);
    }
}

