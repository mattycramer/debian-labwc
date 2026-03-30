#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

struct wl_interface;
struct wl_message;
struct wl_array;
struct wl_display;
struct wl_registry;
struct wl_proxy;
struct wl_output;

struct wl_message {
  const char *name;
  const char *signature;
  const struct wl_interface **types;
};

struct wl_interface {
  const char *name;
  int version;
  int method_count;
  const struct wl_message *methods;
  int event_count;
  const struct wl_message *events;
};

struct wl_array {
  size_t size;
  size_t alloc;
  void *data;
};

struct wl_registry_listener {
  void (*global)(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version);
  void (*global_remove)(void *data, struct wl_registry *registry, uint32_t name);
};

struct zwlr_foreign_toplevel_manager_v1_listener {
  void (*toplevel)(void *data, void *manager, void *toplevel);
  void (*finished)(void *data, void *manager);
};

struct zwlr_foreign_toplevel_handle_v1_listener {
  void (*title)(void *data, void *handle, const char *title);
  void (*app_id)(void *data, void *handle, const char *app_id);
  void (*output_enter)(void *data, void *handle, void *output);
  void (*output_leave)(void *data, void *handle, void *output);
  void (*state)(void *data, void *handle, struct wl_array *state);
  void (*done)(void *data, void *handle);
  void (*closed)(void *data, void *handle);
};

struct handle_node {
  void *proxy;
  struct handle_node *next;
};

struct daemon_context {
  struct wl_display *display;
  struct wl_registry *registry;
  void *manager;
  uint32_t manager_name;
  uint32_t manager_version;
  volatile sig_atomic_t running;
  volatile sig_atomic_t refresh_queued;
  bool bootstrapped;
  char helper_path[PATH_MAX];
  struct handle_node *handles;
};

static struct daemon_context GLOBAL_CONTEXT = {
    .display = NULL,
    .registry = NULL,
    .manager = NULL,
    .manager_name = 0,
    .manager_version = 0,
    .running = 1,
    .refresh_queued = 0,
    .bootstrapped = false,
    .helper_path = {0},
    .handles = NULL,
};

static struct wl_interface wl_output_interface = {
    .name = "wl_output",
    .version = 4,
    .method_count = 0,
    .methods = NULL,
    .event_count = 0,
    .events = NULL,
};

static struct wl_interface zwlr_foreign_toplevel_manager_v1_interface;
static struct wl_interface zwlr_foreign_toplevel_handle_v1_interface;

static const struct wl_interface *wl_registry_bind_types[] = {NULL, NULL, NULL, NULL};
static const struct wl_message wl_registry_methods[] = {
    {"bind", "usun", wl_registry_bind_types},
};
static const struct wl_message wl_registry_events[] = {
    {"global", "usu", NULL},
    {"global_remove", "u", NULL},
};
static struct wl_interface wl_registry_interface = {
    .name = "wl_registry",
    .version = 1,
    .method_count = 1,
    .methods = wl_registry_methods,
    .event_count = 2,
    .events = wl_registry_events,
};

static const struct wl_interface *manager_toplevel_types[] = {
    &zwlr_foreign_toplevel_handle_v1_interface,
};
static const struct wl_message manager_events[] = {
    {"toplevel", "n", manager_toplevel_types},
    {"finished", "", NULL},
};

static const struct wl_interface *handle_output_types[] = {
    &wl_output_interface,
};
static const struct wl_message handle_events[] = {
    {"title", "s", NULL},
    {"app_id", "s", NULL},
    {"output_enter", "o", handle_output_types},
    {"output_leave", "o", handle_output_types},
    {"state", "a", NULL},
    {"done", "", NULL},
    {"closed", "", NULL},
};

static struct wl_interface zwlr_foreign_toplevel_manager_v1_interface = {
    .name = "zwlr_foreign_toplevel_manager_v1",
    .version = 2,
    .method_count = 0,
    .methods = NULL,
    .event_count = 2,
    .events = manager_events,
};

static struct wl_interface zwlr_foreign_toplevel_handle_v1_interface = {
    .name = "zwlr_foreign_toplevel_handle_v1",
    .version = 2,
    .method_count = 0,
    .methods = NULL,
    .event_count = 7,
    .events = handle_events,
};

extern struct wl_display *wl_display_connect(const char *name);
extern void wl_display_disconnect(struct wl_display *display);
extern int wl_display_roundtrip(struct wl_display *display);
extern int wl_display_dispatch(struct wl_display *display);
extern void *wl_proxy_marshal_flags(void *proxy, uint32_t opcode, const struct wl_interface *interface,
                                    uint32_t version, uint32_t flags, ...);
extern int wl_proxy_add_listener(void *proxy, void (**implementation)(void), void *data);
extern void wl_proxy_destroy(void *proxy);
extern uint32_t wl_proxy_get_version(void *proxy);

static struct daemon_context *context(void) {
  return &GLOBAL_CONTEXT;
}

static void queue_refresh(void) {
  context()->refresh_queued = 1;
}

static void discard_stdio(void) {
  int fd = open("/dev/null", O_RDWR);
  if (fd < 0) {
    _exit(127);
  }
  (void)dup2(fd, STDIN_FILENO);
  (void)dup2(fd, STDOUT_FILENO);
  (void)dup2(fd, STDERR_FILENO);
  if (fd > STDERR_FILENO) {
    close(fd);
  }
}

static bool run_refresh(void) {
  pid_t pid = fork();
  if (pid < 0) {
    return false;
  }
  if (pid == 0) {
    discard_stdio();
    execl(context()->helper_path, context()->helper_path, "refresh", (char *)NULL);
    _exit(127);
  }

  int status = 0;
  while (waitpid(pid, &status, 0) < 0) {
    if (errno == EINTR) {
      continue;
    }
    return false;
  }
  return true;
}

static void service_refresh_queue(void) {
  if (!context()->refresh_queued) {
    return;
  }

  context()->refresh_queued = 0;
  (void)run_refresh();
}

static void remove_handle_node(struct handle_node *node) {
  struct daemon_context *ctx = context();
  struct handle_node **cursor = &ctx->handles;

  while (*cursor != NULL) {
    if (*cursor == node) {
      *cursor = node->next;
      return;
    }
    cursor = &(*cursor)->next;
  }
}

static void signal_handler(int signo) {
  (void)signo;
  context()->running = 0;
}

static void on_registry_global(void *data, struct wl_registry *registry, uint32_t name,
                               const char *interface_name, uint32_t version) {
  (void)data;
  (void)registry;
  if (strcmp(interface_name, "zwlr_foreign_toplevel_manager_v1") == 0) {
    struct daemon_context *ctx = context();
    ctx->manager_name = name;
    ctx->manager_version = version < 2 ? version : 2;
  }
}

static void on_registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
  (void)data;
  (void)registry;
  (void)name;
}

static void on_handle_title(void *data, void *handle, const char *title) {
  (void)data;
  (void)handle;
  (void)title;
}

static void on_handle_app_id(void *data, void *handle, const char *app_id) {
  (void)data;
  (void)handle;
  (void)app_id;
}

static void on_handle_output_enter(void *data, void *handle, void *output) {
  (void)data;
  (void)handle;
  (void)output;
}

static void on_handle_output_leave(void *data, void *handle, void *output) {
  (void)data;
  (void)handle;
  (void)output;
}

static void on_handle_state(void *data, void *handle, struct wl_array *state) {
  (void)data;
  (void)handle;
  (void)state;
}

static void on_handle_done(void *data, void *handle) {
  (void)data;
  (void)handle;
  if (context()->bootstrapped) {
    queue_refresh();
  }
}

static void on_handle_closed(void *data, void *handle) {
  struct handle_node *node = data;
  if (context()->bootstrapped) {
    queue_refresh();
  }
  if (node != NULL) {
    remove_handle_node(node);
    free(node);
  }
  if (handle != NULL) {
    wl_proxy_destroy(handle);
  }
}

static const struct zwlr_foreign_toplevel_handle_v1_listener handle_listener = {
    .title = on_handle_title,
    .app_id = on_handle_app_id,
    .output_enter = on_handle_output_enter,
    .output_leave = on_handle_output_leave,
    .state = on_handle_state,
    .done = on_handle_done,
    .closed = on_handle_closed,
};

static void on_manager_toplevel(void *data, void *manager, void *handle) {
  (void)data;
  (void)manager;

  struct handle_node *node = calloc(1, sizeof(*node));
  if (node == NULL) {
    queue_refresh();
    return;
  }

  node->proxy = handle;
  node->next = context()->handles;
  context()->handles = node;

  (void)wl_proxy_add_listener(handle, (void (**)(void))&handle_listener, node);
}

static void on_manager_finished(void *data, void *manager) {
  (void)data;
  (void)manager;
  context()->running = 0;
}

static const struct zwlr_foreign_toplevel_manager_v1_listener manager_listener = {
    .toplevel = on_manager_toplevel,
    .finished = on_manager_finished,
};

static const struct wl_registry_listener registry_listener = {
    .global = on_registry_global,
    .global_remove = on_registry_global_remove,
};

static bool init_helper_path(void) {
  const char *home = getenv("HOME");
  if (home == NULL || home[0] == '\0') {
    return false;
  }

  int written = snprintf(context()->helper_path, sizeof(context()->helper_path),
                         "%s/.config/waybar/scripts/grouped-taskbar.py", home);
  return written > 0 && (size_t)written < sizeof(context()->helper_path);
}

static bool connect_wayland(void) {
  struct daemon_context *ctx = context();

  ctx->display = wl_display_connect(NULL);
  if (ctx->display == NULL) {
    return false;
  }

  ctx->registry = wl_proxy_marshal_flags(ctx->display, 1, &wl_registry_interface, 1, 0);
  if (ctx->registry == NULL) {
    return false;
  }

  (void)wl_proxy_add_listener(ctx->registry, (void (**)(void))&registry_listener, NULL);
  if (wl_display_roundtrip(ctx->display) < 0) {
    return false;
  }

  if (ctx->manager_name == 0 || ctx->manager_version == 0) {
    return false;
  }

  ctx->manager = wl_proxy_marshal_flags(ctx->registry, 0, &zwlr_foreign_toplevel_manager_v1_interface,
                                        ctx->manager_version, 0, ctx->manager_name,
                                        zwlr_foreign_toplevel_manager_v1_interface.name, ctx->manager_version, NULL);
  if (ctx->manager == NULL) {
    return false;
  }

  (void)wl_proxy_add_listener(ctx->manager, (void (**)(void))&manager_listener, NULL);
  if (wl_display_roundtrip(ctx->display) < 0) {
    return false;
  }
  if (wl_display_roundtrip(ctx->display) < 0) {
    return false;
  }

  ctx->bootstrapped = true;
  return true;
}

static void cleanup(void) {
  struct daemon_context *ctx = context();
  struct handle_node *node = ctx->handles;
  while (node != NULL) {
    struct handle_node *next = node->next;
    if (node->proxy != NULL) {
      wl_proxy_destroy(node->proxy);
    }
    free(node);
    node = next;
  }
  ctx->handles = NULL;

  if (ctx->manager != NULL) {
    wl_proxy_destroy(ctx->manager);
    ctx->manager = NULL;
  }
  if (ctx->registry != NULL) {
    wl_proxy_destroy(ctx->registry);
    ctx->registry = NULL;
  }
  if (ctx->display != NULL) {
    wl_display_disconnect(ctx->display);
    ctx->display = NULL;
  }
}

int main(void) {
  struct sigaction action = {0};
  action.sa_handler = signal_handler;
  sigemptyset(&action.sa_mask);
  (void)sigaction(SIGINT, &action, NULL);
  (void)sigaction(SIGTERM, &action, NULL);

  if (!init_helper_path()) {
    return 1;
  }

  if (!connect_wayland()) {
    cleanup();
    return 1;
  }

  while (context()->running) {
    int rc = wl_display_dispatch(context()->display);
    service_refresh_queue();
    if (rc < 0) {
      break;
    }
  }

  cleanup();
  return 0;
}
