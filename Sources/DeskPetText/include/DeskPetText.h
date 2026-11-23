// 윈도우판 말풍선 그리기 (DirectWrite + Direct2D). DirectWrite 헤더는 C++ 전용이라 C 함수로 감싸 Swift에서 부름
#ifndef DESKPET_TEXT_H
#define DESKPET_TEXT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 말풍선 한 장의 생김새 (길이는 DIP, 색은 0xAARRGGBB)
typedef struct {
    float bodyWidth;
    float bodyHeight;
    float cornerRadius;
    float tailHeight;
    /// 꼬리 끝의 몸통 왼쪽에서부터 거리
    float tailX;
    float tailHalfWidth;
    float fontSize;
    uint32_t fill;
    uint32_t stroke;
    uint32_t ink;
    /// DIP 하나의 픽셀 수 (화면 배율)
    float scale;
} DPBubbleStyle;

/// 미리 곱한 BGRA 그림 (위쪽 줄부터). dp_image_free로 돌려줌
typedef struct {
    int32_t width;
    int32_t height;
    uint8_t *bgra;
} DPImage;

/// 굵은 글자 한 줄의 크기(DIP)를 잼. 성공하면 1
int32_t dp_text_measure(const uint16_t *text, int32_t length, float fontSize, float *width, float *height);

/// 말풍선(둥근 몸통·꼬리·글자, 컬러 이모지 포함)을 그림. 그림은 몸통 바깥으로 1 DIP씩 여백이 있고 꼬리는 아래쪽.
/// 성공하면 1
int32_t dp_bubble_draw(const uint16_t *text, int32_t length, const DPBubbleStyle *style, DPImage *image);

void dp_image_free(DPImage *image);

#ifdef __cplusplus
}
#endif

#endif
