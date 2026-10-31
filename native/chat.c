#include <lean/lean.h>
#include <libwebsockets.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define HISTORY 50
#define QUEUE 64
#define CHAT_MAX_INPUT 8192
#define MAX_CLIENTS 64

struct packet {
    size_t size;
    unsigned char data[];
};

struct peer {
    struct lws *wsi;
    struct peer *next;
    unsigned char input[CHAT_MAX_INPUT];
    size_t used;
    struct packet *queue[QUEUE];
    size_t head, count;
    int overflow;
};

struct chat {
    struct lws_context *context;
    lean_object *handler;
    struct peer *peers;
    size_t clients;
    uint64_t id;
    uint16_t http_port;
    struct packet *history[HISTORY];
    size_t history_head, history_count;
};

static lean_obj_res fail(const char *message) {
    return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string(message)));
}

static struct packet *packet_new(const void *data, size_t size) {
    struct packet *packet = malloc(sizeof(*packet) + LWS_PRE + size);
    if (!packet) return NULL;
    packet->size = size;
    memcpy(packet->data + LWS_PRE, data, size);
    return packet;
}

static void enqueue(struct peer *peer, const void *data, size_t size) {
    if (peer->overflow) return;
    if (peer->count == QUEUE) {
        fprintf(stderr, "Chat: closing a slow client (send queue full)\n");
        peer->overflow = 1;
    } else {
        struct packet *packet = packet_new(data, size);
        if (!packet) {
            fprintf(stderr, "Chat: send queue allocation failed\n");
            peer->overflow = 1;
        } else {
            peer->queue[(peer->head + peer->count++) % QUEUE] = packet;
        }
    }
    lws_callback_on_writable(peer->wsi);
}

static int close_with(struct lws *wsi, enum lws_close_status code, const char *reason) {
    fprintf(stderr, "Chat: closing connection: %s\n", reason);
    lws_close_reason(wsi, code, (unsigned char *)reason, strlen(reason));
    return -1;
}

static int valid_origin(struct lws *wsi, struct chat *chat) {
    char origin[256], expected[80];
    if (lws_hdr_copy(wsi, origin, sizeof(origin), WSI_TOKEN_ORIGIN) <= 0)
        return 0;
    const char *hosts[] = {"127.0.0.1", "localhost"};
    for (size_t i = 0; i < 2; ++i) {
        snprintf(expected, sizeof(expected), "http://%s:%u", hosts[i], chat->http_port);
        if (!strcmp(origin, expected)) return 1;
    }
    return 0;
}

static int callback(struct lws *wsi, enum lws_callback_reasons reason,
                    void *user, void *in, size_t len) {
    struct chat *chat = lws_context_user(lws_get_context(wsi));
    struct peer *peer = user;
    switch (reason) {
    case LWS_CALLBACK_FILTER_PROTOCOL_CONNECTION: {
        char path[128], protocol[128];
        if (lws_hdr_copy(wsi, path, sizeof(path), WSI_TOKEN_GET_URI) <= 0 ||
            lws_hdr_copy(wsi, protocol, sizeof(protocol), WSI_TOKEN_PROTOCOL) <= 0 ||
            strcmp(protocol, "leanwebstudy-chat") ||
            strcmp(path, "/chat/socket") || !valid_origin(wsi, chat) ||
            chat->clients >= MAX_CLIENTS) {
            fprintf(stderr, "Chat: rejected path, subprotocol, origin, or connection limit\n");
            return 1;
        }
        break;
    }
    case LWS_CALLBACK_ESTABLISHED: {
        peer->wsi = wsi;
        peer->next = chat->peers;
        chat->peers = peer;
        chat->clients++;
        size_t size = 32;
        for (size_t i = 0; i < chat->history_count; ++i)
            size += chat->history[(chat->history_head + i) % HISTORY]->size + 1;
        char *history = malloc(size);
        if (!history) return close_with(wsi, LWS_CLOSE_STATUS_UNEXPECTED_CONDITION, "history allocation");
        size_t used = (size_t)sprintf(history, "{\"type\":\"history\",\"messages\":[");
        for (size_t i = 0; i < chat->history_count; ++i) {
            struct packet *packet = chat->history[(chat->history_head + i) % HISTORY];
            if (i) history[used++] = ',';
            memcpy(history + used, packet->data + LWS_PRE, packet->size);
            used += packet->size;
        }
        memcpy(history + used, "]}", 2);
        enqueue(peer, history, used + 2);
        free(history);
        break;
    }
    case LWS_CALLBACK_RECEIVE: {
        if (lws_frame_is_binary(wsi))
            return close_with(wsi, LWS_CLOSE_STATUS_UNACCEPTABLE_OPCODE, "text only");
        if (len > CHAT_MAX_INPUT - peer->used)
            return close_with(wsi, LWS_CLOSE_STATUS_MESSAGE_TOO_LARGE, "message exceeds 8192 bytes");
        memcpy(peer->input + peer->used, in, len);
        peer->used += len;
        if (!lws_is_final_fragment(wsi) || lws_remaining_packet_payload(wsi)) break;
        lean_object *bytes = lean_alloc_sarray(1, peer->used, peer->used);
        memcpy(lean_sarray_cptr(bytes), peer->input, peer->used);
        lean_inc(chat->handler);
        lean_object *result = lean_apply_2(chat->handler, lean_box_uint64(chat->id + 1), bytes);
        int accepted = lean_unbox(lean_ctor_get(result, 0));
        lean_object *text = lean_ctor_get(result, 1);
        const char *data = lean_string_cstr(text);
        size_t size = lean_string_size(text) - 1;
        peer->used = 0;
        if (accepted) {
            struct packet *packet = packet_new(data, size);
            if (!packet) {
                lean_dec(result);
                return close_with(wsi, LWS_CLOSE_STATUS_UNEXPECTED_CONDITION, "history allocation");
            }
            chat->id++;
            if (chat->history_count == HISTORY) {
                free(chat->history[chat->history_head]);
                chat->history_head = (chat->history_head + 1) % HISTORY;
                chat->history_count--;
            }
            chat->history[(chat->history_head + chat->history_count++) % HISTORY] = packet;
            for (struct peer *target = chat->peers; target; target = target->next)
                enqueue(target, data, size);
        } else {
            fprintf(stderr, "Chat: invalid message rejected\n");
            enqueue(peer, data, size);
        }
        lean_dec(result);
        break;
    }
    case LWS_CALLBACK_SERVER_WRITEABLE: {
        if (peer->overflow)
            return close_with(wsi, LWS_CLOSE_STATUS_POLICY_VIOLATION, "send queue full");
        if (!peer->count) break;
        struct packet *packet = peer->queue[peer->head];
        int written = lws_write(wsi, packet->data + LWS_PRE, packet->size, LWS_WRITE_TEXT);
        if (written < 0 || (size_t)written != packet->size)
            return close_with(wsi, LWS_CLOSE_STATUS_UNEXPECTED_CONDITION, "send failed");
        free(packet);
        peer->head = (peer->head + 1) % QUEUE;
        peer->count--;
        if (peer->count) lws_callback_on_writable(wsi);
        break;
    }
    case LWS_CALLBACK_CLOSED: {
        struct peer **position = &chat->peers;
        while (*position && *position != peer) position = &(*position)->next;
        if (*position) {
            *position = peer->next;
            chat->clients--;
        }
        for (size_t i = 0; i < peer->count; ++i)
            free(peer->queue[(peer->head + i) % QUEUE]);
        break;
    }
    case LWS_CALLBACK_HTTP:
        return lws_return_http_status(wsi, HTTP_STATUS_NOT_FOUND, NULL);
    default:
        break;
    }
    return 0;
}

static const struct lws_protocols protocols[] = {
    {.name = "leanwebstudy-chat", .callback = callback,
     .per_session_data_size = sizeof(struct peer), .rx_buffer_size = 4096},
    {0}
};

static const lws_retry_bo_t idle_policy = {
    .secs_since_valid_ping = 20,
    .secs_since_valid_hangup = 30,
};

static void finalize_chat(void *data) {
    struct chat *chat = data;
    lws_context_destroy(chat->context);
    for (size_t i = 0; i < chat->history_count; ++i)
        free(chat->history[(chat->history_head + i) % HISTORY]);
    lean_dec(chat->handler);
    free(chat);
}

static void foreach_chat(void *data, b_lean_obj_arg visitor) {
    struct chat *chat = data;
    lean_inc(visitor);
    lean_inc(chat->handler);
    lean_dec(lean_apply_1(visitor, chat->handler));
}

static lean_external_class *chat_class;
static pthread_once_t class_once = PTHREAD_ONCE_INIT;

static void initialize_class(void) {
    chat_class = lean_register_external_class(finalize_chat, foreach_chat);
}

LEAN_EXPORT lean_obj_res leanwebstudy_chat_open(uint16_t http_port, lean_obj_arg handler) {
    if (pthread_once(&class_once, initialize_class) != 0) {
        lean_dec(handler);
        return fail("Could not initialize WebSocket server class");
    }
    struct chat *chat = calloc(1, sizeof(*chat));
    if (!chat) {
        lean_dec(handler);
        return fail("Could not allocate WebSocket server");
    }
    chat->http_port = http_port;
    chat->handler = handler;
    struct lws_context_creation_info info = {0};
    info.port = 0;
    info.iface = "127.0.0.1";
    info.protocols = protocols;
    info.user = chat;
    info.gid = -1;
    info.uid = -1;
    info.options = LWS_SERVER_OPTION_VALIDATE_UTF8;
    info.max_http_header_data = 4096;
    info.max_http_header_pool = MAX_CLIENTS;
    info.fd_limit_per_thread = MAX_CLIENTS + 8;
    info.timeout_secs = 10;
    info.retry_and_idle_policy = &idle_policy;
    chat->context = lws_create_context(&info);
    if (!chat->context) {
        lean_dec(handler);
        free(chat);
        return fail("Could not start loopback WebSocket server");
    }
    return lean_io_result_mk_ok(lean_alloc_external(chat_class, chat));
}

LEAN_EXPORT lean_obj_res leanwebstudy_chat_port(b_lean_obj_arg server) {
    struct chat *chat = lean_get_external_data(server);
    struct lws_vhost *vhost = lws_get_vhost_by_name(chat->context, "default");
    if (!vhost) return fail("WebSocket listener not found");
    int port = lws_get_vhost_listen_port(vhost);
    if (port <= 0 || port > UINT16_MAX) return fail("Invalid WebSocket listener port");
    return lean_io_result_mk_ok(lean_box(port));
}

LEAN_EXPORT lean_obj_res leanwebstudy_chat_service(b_lean_obj_arg server) {
    struct chat *chat = lean_get_external_data(server);
    if (lws_service(chat->context, 100) < 0)
        return fail("WebSocket service loop failed");
    return lean_io_result_mk_ok(lean_box(0));
}
