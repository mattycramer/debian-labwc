#!/usr/bin/env python3
import ctypes
import ctypes.util
import json
import re
import sys


STATE_ACTIVE = 1
WORKSPACE_LIMIT = 4
CURRENT_CONTEXT = None


class wl_interface(ctypes.Structure):
    pass


class wl_message(ctypes.Structure):
    _fields_ = [
        ("name", ctypes.c_char_p),
        ("signature", ctypes.c_char_p),
        ("types", ctypes.POINTER(ctypes.POINTER(wl_interface))),
    ]


wl_interface._fields_ = [
    ("name", ctypes.c_char_p),
    ("version", ctypes.c_int),
    ("method_count", ctypes.c_int),
    ("methods", ctypes.POINTER(wl_message)),
    ("event_count", ctypes.c_int),
    ("events", ctypes.POINTER(wl_message)),
]


class wl_array(ctypes.Structure):
    _fields_ = [
        ("size", ctypes.c_size_t),
        ("alloc", ctypes.c_size_t),
        ("data", ctypes.c_void_p),
    ]


def build_protocol():
    wl_output_interface = wl_interface(b"wl_output", 4, 0, None, 0, None)
    ext_workspace_group_handle_v1_interface = wl_interface()
    ext_workspace_handle_v1_interface = wl_interface()
    ext_workspace_manager_v1_interface = wl_interface()
    keepalive = [wl_output_interface]

    assign_types = (ctypes.POINTER(wl_interface) * 1)(
        ctypes.pointer(ext_workspace_group_handle_v1_interface)
    )
    output_enter_types = (ctypes.POINTER(wl_interface) * 1)(ctypes.pointer(wl_output_interface))
    output_leave_types = (ctypes.POINTER(wl_interface) * 1)(ctypes.pointer(wl_output_interface))
    workspace_enter_types = (ctypes.POINTER(wl_interface) * 1)(
        ctypes.pointer(ext_workspace_handle_v1_interface)
    )
    workspace_leave_types = (ctypes.POINTER(wl_interface) * 1)(
        ctypes.pointer(ext_workspace_handle_v1_interface)
    )
    manager_group_types = (ctypes.POINTER(wl_interface) * 1)(
        ctypes.pointer(ext_workspace_group_handle_v1_interface)
    )
    manager_workspace_types = (ctypes.POINTER(wl_interface) * 1)(
        ctypes.pointer(ext_workspace_handle_v1_interface)
    )
    keepalive.extend(
        [
            assign_types,
            output_enter_types,
            output_leave_types,
            workspace_enter_types,
            workspace_leave_types,
            manager_group_types,
            manager_workspace_types,
        ]
    )

    manager_methods = (wl_message * 2)(
        wl_message(b"commit", b"", None),
        wl_message(b"stop", b"", None),
    )
    workspace_group_methods = (wl_message * 2)(
        wl_message(b"destroy", b"", None),
        wl_message(b"create_workspace", b"s", None),
    )
    workspace_methods = (wl_message * 5)(
        wl_message(b"destroy", b"", None),
        wl_message(b"activate", b"", None),
        wl_message(b"deactivate", b"", None),
        wl_message(
            b"assign",
            b"o",
            assign_types,
        ),
        wl_message(b"remove", b"", None),
    )
    workspace_group_events = (wl_message * 6)(
        wl_message(b"capabilities", b"u", None),
        wl_message(b"output_enter", b"o", output_enter_types),
        wl_message(b"output_leave", b"o", output_leave_types),
        wl_message(b"workspace_enter", b"o", workspace_enter_types),
        wl_message(b"workspace_leave", b"o", workspace_leave_types),
        wl_message(b"removed", b"", None),
    )
    workspace_events = (wl_message * 6)(
        wl_message(b"id", b"s", None),
        wl_message(b"name", b"s", None),
        wl_message(b"coordinates", b"a", None),
        wl_message(b"state", b"u", None),
        wl_message(b"capabilities", b"u", None),
        wl_message(b"removed", b"", None),
    )
    manager_events = (wl_message * 4)(
        wl_message(b"workspace_group", b"n", manager_group_types),
        wl_message(b"workspace", b"n", manager_workspace_types),
        wl_message(b"done", b"", None),
        wl_message(b"finished", b"", None),
    )
    keepalive.extend(
        [
            manager_methods,
            workspace_group_methods,
            workspace_methods,
            workspace_group_events,
            workspace_events,
            manager_events,
        ]
    )

    ext_workspace_group_handle_v1_interface.name = b"ext_workspace_group_handle_v1"
    ext_workspace_group_handle_v1_interface.version = 1
    ext_workspace_group_handle_v1_interface.method_count = 2
    ext_workspace_group_handle_v1_interface.methods = workspace_group_methods
    ext_workspace_group_handle_v1_interface.event_count = 6
    ext_workspace_group_handle_v1_interface.events = workspace_group_events

    ext_workspace_handle_v1_interface.name = b"ext_workspace_handle_v1"
    ext_workspace_handle_v1_interface.version = 1
    ext_workspace_handle_v1_interface.method_count = 5
    ext_workspace_handle_v1_interface.methods = workspace_methods
    ext_workspace_handle_v1_interface.event_count = 6
    ext_workspace_handle_v1_interface.events = workspace_events

    ext_workspace_manager_v1_interface.name = b"ext_workspace_manager_v1"
    ext_workspace_manager_v1_interface.version = 1
    ext_workspace_manager_v1_interface.method_count = 2
    ext_workspace_manager_v1_interface.methods = manager_methods
    ext_workspace_manager_v1_interface.event_count = 4
    ext_workspace_manager_v1_interface.events = manager_events

    wl_registry_bind_types = (ctypes.POINTER(wl_interface) * 4)(None, None, None, None)
    wl_registry_methods = (wl_message * 1)(
        wl_message(b"bind", b"usun", wl_registry_bind_types),
    )
    wl_registry_events = (wl_message * 2)(
        wl_message(b"global", b"usu", None),
        wl_message(b"global_remove", b"u", None),
    )
    wl_registry_interface = wl_interface(
        b"wl_registry", 1, 1, wl_registry_methods, 2, wl_registry_events
    )

    keepalive.extend([wl_registry_bind_types, wl_registry_methods, wl_registry_events])

    return {
        "wl_registry": wl_registry_interface,
        "ext_workspace_manager_v1": ext_workspace_manager_v1_interface,
        "ext_workspace_group_handle_v1": ext_workspace_group_handle_v1_interface,
        "ext_workspace_handle_v1": ext_workspace_handle_v1_interface,
        "wl_array": wl_array,
        "_keepalive": keepalive,
    }


PROTOCOL = build_protocol()

LIB = ctypes.CDLL(ctypes.util.find_library("wayland-client"))
LIB.wl_display_connect.restype = ctypes.c_void_p
LIB.wl_display_connect.argtypes = [ctypes.c_char_p]
LIB.wl_display_disconnect.restype = None
LIB.wl_display_disconnect.argtypes = [ctypes.c_void_p]
LIB.wl_display_roundtrip.restype = ctypes.c_int
LIB.wl_display_roundtrip.argtypes = [ctypes.c_void_p]
LIB.wl_proxy_marshal_flags.restype = ctypes.c_void_p
LIB.wl_proxy_add_listener.restype = ctypes.c_int
LIB.wl_proxy_add_listener.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
LIB.wl_proxy_destroy.restype = None
LIB.wl_proxy_destroy.argtypes = [ctypes.c_void_p]
LIB.wl_proxy_get_version.restype = ctypes.c_uint32
LIB.wl_proxy_get_version.argtypes = [ctypes.c_void_p]

REG_GLOBAL = ctypes.CFUNCTYPE(
    None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_char_p, ctypes.c_uint32
)
REG_GLOBAL_REMOVE = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32)
MANAGER_GROUP = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
MANAGER_WORKSPACE = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
MANAGER_DONE = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p)
MANAGER_FINISHED = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p)
GROUP_CAPS = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32)
GROUP_OUTPUT = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
GROUP_WS = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
GROUP_REMOVED = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p)
WS_ID = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p)
WS_NAME = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p)
WS_COORDS = ctypes.CFUNCTYPE(
    None, ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(PROTOCOL["wl_array"])
)
WS_STATE = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32)
WS_CAPS = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32)
WS_REMOVED = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p)


class wl_registry_listener(ctypes.Structure):
    _fields_ = [("global", REG_GLOBAL), ("global_remove", REG_GLOBAL_REMOVE)]


class ext_workspace_manager_v1_listener(ctypes.Structure):
    _fields_ = [
        ("workspace_group", MANAGER_GROUP),
        ("workspace", MANAGER_WORKSPACE),
        ("done", MANAGER_DONE),
        ("finished", MANAGER_FINISHED),
    ]


class ext_workspace_group_handle_v1_listener(ctypes.Structure):
    _fields_ = [
        ("capabilities", GROUP_CAPS),
        ("output_enter", GROUP_OUTPUT),
        ("output_leave", GROUP_OUTPUT),
        ("workspace_enter", GROUP_WS),
        ("workspace_leave", GROUP_WS),
        ("removed", GROUP_REMOVED),
    ]


class ext_workspace_handle_v1_listener(ctypes.Structure):
    _fields_ = [
        ("id", WS_ID),
        ("name", WS_NAME),
        ("coordinates", WS_COORDS),
        ("state", WS_STATE),
        ("capabilities", WS_CAPS),
        ("removed", WS_REMOVED),
    ]


class WorkspaceContext:
    def __init__(self):
        self.display = None
        self.registry = None
        self.manager = None
        self.manager_name = None
        self.manager_version = 0
        self.groups = {}
        self.workspaces = {}
        self.registry_listener = wl_registry_listener(on_global, on_global_remove)
        self.manager_listener = ext_workspace_manager_v1_listener(
            on_manager_group, on_manager_workspace, on_manager_done, on_manager_finished
        )
        self.group_listener = ext_workspace_group_handle_v1_listener(
            on_group_caps,
            on_group_output,
            on_group_output,
            on_group_workspace,
            on_group_workspace,
            on_group_removed,
        )
        self.workspace_listener = ext_workspace_handle_v1_listener(
            on_workspace_id,
            on_workspace_name,
            on_workspace_coordinates,
            on_workspace_state,
            on_workspace_caps,
            on_workspace_removed,
        )

    def connect(self):
        self.display = LIB.wl_display_connect(None)
        if not self.display:
            raise RuntimeError("unable to connect to Wayland display")

        self.registry = LIB.wl_proxy_marshal_flags(
            self.display, 1, ctypes.byref(PROTOCOL["wl_registry"]), 1, 0
        )
        LIB.wl_proxy_add_listener(self.registry, ctypes.byref(self.registry_listener), None)
        self.roundtrip()

        if self.manager_name is None:
            raise RuntimeError("labwc did not expose ext_workspace_manager_v1")

        self.manager = LIB.wl_proxy_marshal_flags(
            self.registry,
            0,
            ctypes.byref(PROTOCOL["ext_workspace_manager_v1"]),
            self.manager_version,
            0,
            self.manager_name,
            PROTOCOL["ext_workspace_manager_v1"].name,
            self.manager_version,
            None,
        )
        LIB.wl_proxy_add_listener(self.manager, ctypes.byref(self.manager_listener), None)
        self.roundtrip()
        self.roundtrip()

    def roundtrip(self):
        rc = LIB.wl_display_roundtrip(self.display)
        if rc < 0:
            raise RuntimeError("Wayland roundtrip failed")
        return rc

    def cleanup(self):
        if self.manager:
            LIB.wl_proxy_destroy(self.manager)
            self.manager = None
        if self.registry:
            LIB.wl_proxy_destroy(self.registry)
            self.registry = None
        if self.display:
            LIB.wl_display_disconnect(self.display)
            self.display = None

    def ordered_workspaces(self):
        return sorted(
            (info for info in self.workspaces.values() if not info.get("removed")),
            key=lambda info: info.get("order", 0),
        )

    def workspace_number(self, info):
        name = info.get("name", "")
        if name.isdigit():
            number = int(name)
            if 1 <= number <= WORKSPACE_LIMIT:
                return number

        match = re.search(r"(\d+)(?!.*\d)", name)
        if match:
            number = int(match.group(1))
            if 1 <= number <= WORKSPACE_LIMIT:
                return number

        coordinates = info.get("coordinates") or []
        if len(coordinates) == 1:
            number = int(coordinates[0]) + 1
            if 1 <= number <= WORKSPACE_LIMIT:
                return number

        order = info.get("order")
        if isinstance(order, int) and 1 <= order <= WORKSPACE_LIMIT:
            return order
        return None

    def active_numbers(self):
        numbers = set()
        for info in self.ordered_workspaces():
            if info.get("state", 0) & STATE_ACTIVE:
                number = self.workspace_number(info)
                if number is not None:
                    numbers.add(number)
        return numbers

    def status_payload(self, workspace):
        classes = ["inactive"]
        if workspace in self.active_numbers():
            classes = ["active"]
        return {"text": str(workspace), "class": classes}

    def matching_workspaces(self, workspace):
        matches = []
        for info in self.ordered_workspaces():
            if self.workspace_number(info) == workspace:
                matches.append(info)
        return matches

    def activate(self, workspace):
        matches = self.matching_workspaces(workspace)
        if not matches:
            return False

        if workspace in self.active_numbers():
            return True

        for info in matches:
            LIB.wl_proxy_marshal_flags(
                info["proxy"],
                1,
                None,
                LIB.wl_proxy_get_version(info["proxy"]),
                0,
            )

        LIB.wl_proxy_marshal_flags(
            self.manager,
            0,
            None,
            LIB.wl_proxy_get_version(self.manager),
            0,
        )

        for _ in range(4):
            self.roundtrip()
            if workspace in self.active_numbers():
                return True

        return workspace in self.active_numbers()


def context():
    return CURRENT_CONTEXT


@REG_GLOBAL
def on_global(_data, _registry, name, interface_name, version):
    if interface_name == b"ext_workspace_manager_v1":
        ctx = context()
        ctx.manager_name = name
        ctx.manager_version = min(version, 1)


@REG_GLOBAL_REMOVE
def on_global_remove(_data, _registry, _name):
    return


@MANAGER_GROUP
def on_manager_group(_data, _manager, group):
    ctx = context()
    ctx.groups.setdefault(group, {"proxy": group})
    LIB.wl_proxy_add_listener(group, ctypes.byref(ctx.group_listener), None)


@MANAGER_WORKSPACE
def on_manager_workspace(_data, _manager, workspace):
    ctx = context()
    info = ctx.workspaces.setdefault(
        workspace, {"proxy": workspace, "order": len(ctx.workspaces) + 1}
    )
    info["proxy"] = workspace
    LIB.wl_proxy_add_listener(workspace, ctypes.byref(ctx.workspace_listener), None)


@MANAGER_DONE
def on_manager_done(_data, _manager):
    return


@MANAGER_FINISHED
def on_manager_finished(_data, _manager):
    return


@GROUP_CAPS
def on_group_caps(_data, group, caps):
    context().groups.setdefault(group, {"proxy": group})["caps"] = caps


@GROUP_OUTPUT
def on_group_output(_data, _group, _output):
    return


@GROUP_WS
def on_group_workspace(_data, group, workspace):
    context().workspaces.setdefault(workspace, {"proxy": workspace})["group"] = group


@GROUP_REMOVED
def on_group_removed(_data, group):
    context().groups.setdefault(group, {"proxy": group})["removed"] = True


@WS_ID
def on_workspace_id(_data, workspace, value):
    context().workspaces.setdefault(workspace, {"proxy": workspace})["id"] = (
        value.decode() if value else ""
    )


@WS_NAME
def on_workspace_name(_data, workspace, value):
    context().workspaces.setdefault(workspace, {"proxy": workspace})["name"] = (
        value.decode() if value else ""
    )


@WS_COORDS
def on_workspace_coordinates(_data, workspace, value):
    coordinates = []
    if value and value.contents.size:
        count = value.contents.size // ctypes.sizeof(ctypes.c_uint32)
        coordinates = list((ctypes.c_uint32 * count).from_address(value.contents.data))
    context().workspaces.setdefault(workspace, {"proxy": workspace})["coordinates"] = coordinates


@WS_STATE
def on_workspace_state(_data, workspace, value):
    context().workspaces.setdefault(workspace, {"proxy": workspace})["state"] = value


@WS_CAPS
def on_workspace_caps(_data, workspace, value):
    context().workspaces.setdefault(workspace, {"proxy": workspace})["caps"] = value


@WS_REMOVED
def on_workspace_removed(_data, workspace):
    context().workspaces.setdefault(workspace, {"proxy": workspace})["removed"] = True


def parse_workspace(value):
    try:
        workspace = int(value)
    except ValueError as exc:
        raise RuntimeError(f"invalid workspace '{value}'") from exc
    if not 1 <= workspace <= WORKSPACE_LIMIT:
        raise RuntimeError(f"workspace must be between 1 and {WORKSPACE_LIMIT}")
    return workspace


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in {"activate", "status"}:
        print("usage: workspacectl.py [activate|status] <workspace>", file=sys.stderr)
        return 2

    workspace = parse_workspace(sys.argv[2])

    global CURRENT_CONTEXT
    CURRENT_CONTEXT = WorkspaceContext()
    try:
        CURRENT_CONTEXT.connect()
        if sys.argv[1] == "status":
            print(json.dumps(CURRENT_CONTEXT.status_payload(workspace), separators=(",", ":")))
            return 0
        if CURRENT_CONTEXT.activate(workspace):
            return 0
        print(f"workspace {workspace} is not available in the current labwc session", file=sys.stderr)
        return 1
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        CURRENT_CONTEXT.cleanup()


if __name__ == "__main__":
    sys.exit(main())
