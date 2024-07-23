#ifndef HOOK_H
#define HOOK_H

#ifdef __cplusplus
extern "C" {
#endif

#include <windows.h>

extern HHOOK hKeyboardHook;
extern HHOOK hMouseHook;

extern HOOKPROC GoKeyboardProcPtr;
extern HOOKPROC GoMouseProcPtr;

__declspec(dllexport) LRESULT CALLBACK GoKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam);
__declspec(dllexport) LRESULT CALLBACK GoMouseProc(int nCode, WPARAM wParam, LPARAM lParam);

__declspec(dllexport) LRESULT callNextHookEx(int nCode, WPARAM wParam, LPARAM lParam);
__declspec(dllexport) HINSTANCE getModuleHandle();
__declspec(dllexport) void setGoKeyboardProc(HOOKPROC goKeyboardProc);
__declspec(dllexport) void setGoMouseProc(HOOKPROC goMouseProc);
__declspec(dllexport) void setKeyboardHook(HINSTANCE hInstance);
__declspec(dllexport) void setMouseHook(HINSTANCE hInstance);
__declspec(dllexport) void removeHook();
__declspec(dllexport) void setHook(int hookType, HOOKPROC hookProc, HINSTANCE hInstance, DWORD threadId);

#ifdef __cplusplus
}
#endif

#endif // HOOK_H
