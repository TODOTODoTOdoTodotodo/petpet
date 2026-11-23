// This object is responsible for telling, on Windows, whether any app is using a microphone right now (a call or
// meeting in progress), the way the macOS build reads the input device's running state: it walks the active capture
// endpoints with WASAPI and looks for an active audio session on any of them. It never opens a stream or reads audio,
// so no microphone permission is needed. The audio headers are C++ only, so this file wraps them in one C function.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmdeviceapi.h>
#include <audiopolicy.h>
#include "DeskPetAudio.h"

#pragma comment(lib, "ole32.lib")

namespace {

template <class T> void release(T *&object) {
    if (object) {
        object->Release();
        object = nullptr;
    }
}

/// 한 녹음 장치에 활성 세션이 있는지
bool hasActiveSession(IMMDevice *device) {
    IAudioSessionManager2 *manager = nullptr;
    IAudioSessionEnumerator *sessions = nullptr;
    bool active = false;
    if (SUCCEEDED(device->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL, nullptr, reinterpret_cast<void **>(&manager)))
        && SUCCEEDED(manager->GetSessionEnumerator(&sessions))) {
        int count = 0;
        sessions->GetCount(&count);
        for (int index = 0; index < count && !active; index++) {
            IAudioSessionControl *session = nullptr;
            if (FAILED(sessions->GetSession(index, &session))) continue;
            AudioSessionState state = AudioSessionStateInactive;
            if (SUCCEEDED(session->GetState(&state)) && state == AudioSessionStateActive) active = true;
            release(session);
        }
    }
    release(sessions);
    release(manager);
    return active;
}

}  // namespace

extern "C" int32_t dp_microphone_in_use(int32_t *devices) {
    // 이미 다른 모드로 초기화돼 있어도 그대로 씀
    (void)CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    IMMDeviceEnumerator *enumerator = nullptr;
    IMMDeviceCollection *endpoints = nullptr;
    int32_t result = -1;
    UINT count = 0;
    if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                   reinterpret_cast<void **>(&enumerator)))
        && SUCCEEDED(enumerator->EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE, &endpoints))
        && SUCCEEDED(endpoints->GetCount(&count))) {
        result = 0;
        for (UINT index = 0; index < count && result == 0; index++) {
            IMMDevice *device = nullptr;
            if (FAILED(endpoints->Item(index, &device))) continue;
            if (hasActiveSession(device)) result = 1;
            release(device);
        }
    }
    if (devices) *devices = static_cast<int32_t>(count);
    release(endpoints);
    release(enumerator);
    return result;
}
