#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <reshade.hpp>

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <mutex>
#include <string>

namespace
{
HMODULE g_module = nullptr;
std::atomic<reshade::api::effect_runtime *> g_runtime = nullptr;
std::atomic<HWND> g_game_hwnd = nullptr;
std::atomic<bool> g_overlay_open = false;
std::atomic<bool> g_toggle_requested = false;
std::atomic<bool> g_worker_started = false;
std::atomic<bool> g_stop = false;
std::atomic<DWORD> g_worker_thread_id = 0;
UINT g_handshake_msg = 0;
UINT g_ui_active_msg = 0;
std::mutex g_log_mutex;

std::wstring module_directory()
{
    wchar_t path[MAX_PATH] = {};
    GetModuleFileNameW(g_module, path, MAX_PATH);
    std::wstring s(path);
    const size_t slash = s.find_last_of(L"\\/");
    return slash == std::wstring::npos ? L"." : s.substr(0, slash);
}

void log_line(const char *text)
{
    std::lock_guard<std::mutex> lock(g_log_mutex);

    const std::wstring path = module_directory() + L"\\bridge-input.log";
    HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return;

    SYSTEMTIME st = {};
    GetLocalTime(&st);

    char line[1024] = {};
    const int n = std::snprintf(line, sizeof(line),
        "%02u:%02u:%02u.%03u  %s\r\n",
        st.wHour, st.wMinute, st.wSecond, st.wMilliseconds, text);

    if (n > 0)
    {
        DWORD written = 0;
        WriteFile(file, line, static_cast<DWORD>(n), &written, nullptr);
    }
    CloseHandle(file);
}

void logf(const char *fmt, uintptr_t a = 0, uintptr_t b = 0, uintptr_t c = 0)
{
    char buf[768] = {};
    std::snprintf(buf, sizeof(buf), fmt,
        static_cast<unsigned long long>(a),
        static_cast<unsigned long long>(b),
        static_cast<unsigned long long>(c));
    log_line(buf);
}

const char *message_name(UINT msg)
{
    switch (msg)
    {
    case WM_KEYDOWN: return "WM_KEYDOWN";
    case WM_KEYUP: return "WM_KEYUP";
    case WM_SYSKEYDOWN: return "WM_SYSKEYDOWN";
    case WM_SYSKEYUP: return "WM_SYSKEYUP";
    case WM_CHAR: return "WM_CHAR";
    case WM_MOUSEMOVE: return "WM_MOUSEMOVE";
    case WM_LBUTTONDOWN: return "WM_LBUTTONDOWN";
    case WM_LBUTTONUP: return "WM_LBUTTONUP";
    case WM_RBUTTONDOWN: return "WM_RBUTTONDOWN";
    case WM_RBUTTONUP: return "WM_RBUTTONUP";
    case WM_MBUTTONDOWN: return "WM_MBUTTONDOWN";
    case WM_MBUTTONUP: return "WM_MBUTTONUP";
    case WM_MOUSEWHEEL: return "WM_MOUSEWHEEL";
    default: return nullptr;
    }
}

DWORD WINAPI input_worker(LPVOID)
{
    g_worker_thread_id.store(GetCurrentThreadId());

    MSG msg = {};
    PeekMessageW(&msg, nullptr, WM_USER, WM_USER, PM_NOREMOVE);

    g_handshake_msg = RegisterWindowMessageA("UWM_REMIX_BRIDGE_REGISTER_THREADPROC_MSG");
    g_ui_active_msg = RegisterWindowMessageA("UWM_REMIX_UIACTIVE_MSG");

    logf("worker started tid=%llu handshakeMsg=0x%llX uiMsg=0x%llX",
        GetCurrentThreadId(), g_handshake_msg, g_ui_active_msg);

    bool connected = false;
    while (!g_stop.load() && !connected)
    {
        const HWND hwnd = g_game_hwnd.load();
        if (hwnd != nullptr && IsWindow(hwnd) && g_handshake_msg != 0)
        {
            DWORD_PTR receiver_result = 0;
            const LRESULT ok = SendMessageTimeoutW(
                hwnd,
                g_handshake_msg,
                static_cast<WPARAM>(GetCurrentThreadId()),
                0,
                SMTO_ABORTIFHUNG | SMTO_BLOCK,
                1000,
                &receiver_result);

            if (ok != 0)
            {
                connected = true;
                logf("HANDSHAKE OK hwnd=0x%llX tid=%llu result=0x%llX",
                    reinterpret_cast<uintptr_t>(hwnd), GetCurrentThreadId(), receiver_result);
                if (g_ui_active_msg != 0)
                    PostMessageW(hwnd, g_ui_active_msg, 0, 0);
                break;
            }
        }

        Sleep(500);
    }

    if (!connected)
    {
        log_line("HANDSHAKE FAILED / worker stopping");
        return 0;
    }

    bool home_down = false;
    uint32_t mouse_move_counter = 0;

    while (!g_stop.load() && GetMessageW(&msg, nullptr, 0, 0) > 0)
    {
        if (msg.message == WM_KEYDOWN || msg.message == WM_SYSKEYDOWN)
        {
            if (msg.wParam == VK_HOME)
            {
                if (!home_down)
                {
                    home_down = true;
                    g_toggle_requested.store(true);
                    log_line("HOME DOWN -> queued ReShade overlay toggle");
                }
            }
        }
        else if (msg.message == WM_KEYUP || msg.message == WM_SYSKEYUP)
        {
            if (msg.wParam == VK_HOME)
                home_down = false;
        }

        if (const char *name = message_name(msg.message))
        {
            if (msg.message != WM_MOUSEMOVE || (++mouse_move_counter % 30) == 0)
            {
                char buf[512] = {};
                std::snprintf(buf, sizeof(buf), "%s wParam=0x%llX lParam=0x%llX",
                    name,
                    static_cast<unsigned long long>(msg.wParam),
                    static_cast<unsigned long long>(msg.lParam));
                log_line(buf);
            }
        }
    }

    log_line("worker exited");
    return 0;
}

void ensure_worker_started()
{
    bool expected = false;
    if (!g_worker_started.compare_exchange_strong(expected, true))
        return;

    HANDLE thread = CreateThread(nullptr, 0, input_worker, nullptr, 0, nullptr);
    if (thread == nullptr)
    {
        g_worker_started.store(false);
        logf("CreateThread failed error=%llu", GetLastError());
        return;
    }
    CloseHandle(thread);
}

void on_init_effect_runtime(reshade::api::effect_runtime *runtime)
{
    g_runtime.store(runtime);

    const HWND hwnd = static_cast<HWND>(runtime->get_hwnd());
    g_game_hwnd.store(hwnd);

    logf("effect runtime init runtime=0x%llX hwnd=0x%llX",
        reinterpret_cast<uintptr_t>(runtime), reinterpret_cast<uintptr_t>(hwnd));

    ensure_worker_started();
}

void on_destroy_effect_runtime(reshade::api::effect_runtime *runtime)
{
    reshade::api::effect_runtime *expected = runtime;
    g_runtime.compare_exchange_strong(expected, nullptr);
    logf("effect runtime destroy runtime=0x%llX", reinterpret_cast<uintptr_t>(runtime));
}

void on_reshade_present(reshade::api::effect_runtime *runtime)
{
    if (!g_toggle_requested.exchange(false))
        return;

    const bool desired = !g_overlay_open.load();
    const bool changed = runtime->open_overlay(desired, reshade::api::input_source::keyboard);

    if (changed)
    {
        g_overlay_open.store(desired);
        const HWND hwnd = g_game_hwnd.load();
        if (hwnd != nullptr && g_ui_active_msg != 0)
            PostMessageW(hwnd, g_ui_active_msg, desired ? 1 : 0, 0);
    }

    logf("open_overlay requested=%llu changed=%llu currentTracked=%llu",
        desired ? 1u : 0u, changed ? 1u : 0u, g_overlay_open.load() ? 1u : 0u);
}

bool on_reshade_open_overlay(
    reshade::api::effect_runtime *,
    bool open,
    reshade::api::input_source)
{
    g_overlay_open.store(open);

    const HWND hwnd = g_game_hwnd.load();
    if (hwnd != nullptr && g_ui_active_msg != 0)
        PostMessageW(hwnd, g_ui_active_msg, open ? 1 : 0, 0);

    logf("ReShade overlay state -> %llu (posted UWM_REMIX_UIACTIVE_MSG)", open ? 1u : 0u);

    return false;
}
} // namespace

extern "C" __declspec(dllexport) const char *NAME = "b-bridge Input POC";
extern "C" __declspec(dllexport) const char *DESCRIPTION =
    "Restores the dormant RTX Remix input message channel in b-bridge and proves GTA -> x86 bridge -> x64 ReShade input forwarding.";

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID reserved)
{
    switch (reason)
    {
    case DLL_PROCESS_ATTACH:
        g_module = hModule;
        DisableThreadLibraryCalls(hModule);
        if (!reshade::register_addon(hModule))
            return FALSE;

        reshade::register_event<reshade::addon_event::init_effect_runtime>(on_init_effect_runtime);
        reshade::register_event<reshade::addon_event::destroy_effect_runtime>(on_destroy_effect_runtime);
        reshade::register_event<reshade::addon_event::reshade_present>(on_reshade_present);
        reshade::register_event<reshade::addon_event::reshade_open_overlay>(on_reshade_open_overlay);
        break;

    case DLL_PROCESS_DETACH:
        g_stop.store(true);
        if (const DWORD tid = g_worker_thread_id.load(); tid != 0)
            PostThreadMessageW(tid, WM_QUIT, 0, 0);

        reshade::unregister_addon(hModule);
        break;
    }

    return TRUE;
}
