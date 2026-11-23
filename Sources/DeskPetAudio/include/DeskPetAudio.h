// 윈도우판 통화 중 확인 (WASAPI). 오디오 헤더가 C++ 전용이라 C 함수로 감싸 Swift에서 부름
#ifndef DESKPET_AUDIO_H
#define DESKPET_AUDIO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 녹음 장치(마이크)를 쓰는 중인 앱이 있으면 1, 없으면 0, 확인하지 못하면 -1. 소리는 읽지 않음.
/// devices에는 살펴본 활성 녹음 장치 수를 넣음 (NULL이면 넣지 않음)
int32_t dp_microphone_in_use(int32_t *devices);

#ifdef __cplusplus
}
#endif

#endif
