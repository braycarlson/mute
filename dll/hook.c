#include "hook.h"

HHOOK hKeyboardHook = NULL;
HHOOK hMouseHook = NULL;

HOOKPROC GoKeyboardProcPtr = NULL;
HOOKPROC GoMouseProcPtr = NULL;

__declspec(dllexport) LRESULT callNextHookEx(int nCode, WPARAM wParam, LPARAM lParam) {
    return CallNextHookEx(NULL, nCode, wParam, lParam);
}

__declspec(dllexport) HINSTANCE getModuleHandle() {
    return GetModuleHandle(NULL);
}

void setGoKeyboardProc(HOOKPROC goKeyboardProc) {
    GoKeyboardProcPtr = goKeyboardProc;
}

void setGoMouseProc(HOOKPROC goMouseProc) {
    GoMouseProcPtr = goMouseProc;
}

__declspec(dllexport) void setKeyboardHook(HINSTANCE hInstance) {
    setHook(WH_KEYBOARD_LL, GoKeyboardProcPtr, hInstance, 0);
}

__declspec(dllexport) void setMouseHook(HINSTANCE hInstance) {
    setHook(WH_MOUSE_LL, GoMouseProcPtr, hInstance, 0);
}

__declspec(dllexport) void removeHook() {
    if (hKeyboardHook != NULL) {
        UnhookWindowsHookEx(hKeyboardHook);
        hKeyboardHook = NULL;
    }

    if (hMouseHook != NULL) {
        UnhookWindowsHookEx(hMouseHook);
        hMouseHook = NULL;
    }
}

__declspec(dllexport) void setHook(int hookType, HOOKPROC hookProc, HINSTANCE hInstance, DWORD threadId) {
    if (hookType == WH_KEYBOARD_LL && hKeyboardHook == NULL) {
        hKeyboardHook = SetWindowsHookEx(hookType, hookProc, hInstance, threadId);
    }

    if (hookType == WH_MOUSE_LL && hMouseHook == NULL) {
        hMouseHook = SetWindowsHookEx(hookType, hookProc, hInstance, threadId);
    }
}
