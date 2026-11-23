// This object is responsible for drawing DeskPet's speech bubbles on Windows with DirectWrite and Direct2D:
// measuring a line of bold text (Korean and color emoji through the system font fallback) and painting the
// rounded body, the tail and the text into a premultiplied BGRA picture the Swift stage composites itself.
// DirectWrite has only C++ headers, so this file wraps it in a small C API (DeskPetText.h).
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d2d1.h>
#include <dwrite.h>
#include <wincodec.h>
#include <math.h>
#include <stdlib.h>
#include "DeskPetText.h"

#pragma comment(lib, "d2d1.lib")
#pragma comment(lib, "dwrite.lib")
#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "ole32.lib")

namespace {

template <class T> void release(T *&object) {
    if (object) {
        object->Release();
        object = nullptr;
    }
}

/// 한 번 만든 팩토리를 계속 씀 (앱 수명 동안)
struct Factories {
    ID2D1Factory *d2d = nullptr;
    IDWriteFactory *write = nullptr;
    IWICImagingFactory *wic = nullptr;
    bool ready = false;
    bool tried = false;
};

Factories &factories() {
    static Factories shared;
    if (!shared.tried) {
        shared.tried = true;
        // 이미 다른 모드로 초기화돼 있어도 그대로 씀
        (void)CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        shared.ready = SUCCEEDED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &shared.d2d))
            && SUCCEEDED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                                             reinterpret_cast<IUnknown **>(&shared.write)))
            && SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&shared.wic)));
    }
    return shared;
}

/// 글자 크기별 굵은 글꼴 (말풍선은 두 크기뿐)
IDWriteTextFormat *format(float size) {
    static float sizes[4] = {};
    static IDWriteTextFormat *formats[4] = {};
    for (int index = 0; index < 4; index++) {
        if (formats[index] && sizes[index] == size) return formats[index];
    }
    Factories &shared = factories();
    if (!shared.ready) return nullptr;
    IDWriteTextFormat *made = nullptr;
    if (FAILED(shared.write->CreateTextFormat(L"Segoe UI", nullptr, DWRITE_FONT_WEIGHT_BOLD, DWRITE_FONT_STYLE_NORMAL,
                                              DWRITE_FONT_STRETCH_NORMAL, size, L"", &made))) {
        return nullptr;
    }
    made->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
    for (int index = 0; index < 4; index++) {
        if (!formats[index]) {
            sizes[index] = size;
            formats[index] = made;
            return made;
        }
    }
    // 자리가 다 찼으면 첫 자리를 바꿈
    release(formats[0]);
    sizes[0] = size;
    formats[0] = made;
    return made;
}

IDWriteTextLayout *layout(const uint16_t *text, int32_t length, float size, float width, float height) {
    IDWriteTextFormat *textFormat = format(size);
    if (!textFormat || length < 0) return nullptr;
    IDWriteTextLayout *made = nullptr;
    if (FAILED(factories().write->CreateTextLayout(reinterpret_cast<const WCHAR *>(text), static_cast<UINT32>(length),
                                                   textFormat, width, height, &made))) {
        return nullptr;
    }
    return made;
}

D2D1_COLOR_F color(uint32_t argb) {
    return D2D1::ColorF(((argb >> 16) & 0xFF) / 255.0f, ((argb >> 8) & 0xFF) / 255.0f, (argb & 0xFF) / 255.0f,
                        ((argb >> 24) & 0xFF) / 255.0f);
}

/// 꼬리 모양 (closed면 채울 삼각형, 아니면 테두리 두 변)
ID2D1PathGeometry *tailPath(D2D1_POINT_2F left, D2D1_POINT_2F tip, D2D1_POINT_2F right, bool closed) {
    ID2D1PathGeometry *path = nullptr;
    ID2D1GeometrySink *sink = nullptr;
    if (FAILED(factories().d2d->CreatePathGeometry(&path)) || FAILED(path->Open(&sink))) {
        release(path);
        return nullptr;
    }
    sink->BeginFigure(left, closed ? D2D1_FIGURE_BEGIN_FILLED : D2D1_FIGURE_BEGIN_HOLLOW);
    sink->AddLine(tip);
    sink->AddLine(right);
    sink->EndFigure(closed ? D2D1_FIGURE_END_CLOSED : D2D1_FIGURE_END_OPEN);
    sink->Close();
    release(sink);
    return path;
}

}  // namespace

extern "C" int32_t dp_text_measure(const uint16_t *text, int32_t length, float fontSize, float *width, float *height) {
    IDWriteTextLayout *line = layout(text, length, fontSize, 4096, 4096);
    if (!line) return 0;
    DWRITE_TEXT_METRICS metrics = {};
    HRESULT result = line->GetMetrics(&metrics);
    release(line);
    if (FAILED(result)) return 0;
    *width = metrics.widthIncludingTrailingWhitespace;
    *height = metrics.height;
    return 1;
}

extern "C" int32_t dp_bubble_draw(const uint16_t *text, int32_t length, const DPBubbleStyle *style, DPImage *image) {
    Factories &shared = factories();
    if (!shared.ready || !style || !image || style->scale <= 0) return 0;
    const float margin = 1;
    const UINT width = static_cast<UINT>(ceilf((style->bodyWidth + margin * 2) * style->scale));
    const UINT height = static_cast<UINT>(ceilf((style->bodyHeight + style->tailHeight + margin * 2) * style->scale));
    if (width == 0 || height == 0 || width > 4096 || height > 1024) return 0;

    IWICBitmap *bitmap = nullptr;
    ID2D1RenderTarget *target = nullptr;
    ID2D1SolidColorBrush *fill = nullptr, *stroke = nullptr, *ink = nullptr;
    ID2D1PathGeometry *tailFill = nullptr, *tailEdge = nullptr;
    IDWriteTextLayout *words = nullptr;
    bool drawn = false;

    const D2D1_RENDER_TARGET_PROPERTIES properties = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_DEFAULT, D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED),
        96 * style->scale, 96 * style->scale);
    if (SUCCEEDED(shared.wic->CreateBitmap(width, height, GUID_WICPixelFormat32bppPBGRA, WICBitmapCacheOnDemand, &bitmap))
        && SUCCEEDED(shared.d2d->CreateWicBitmapRenderTarget(bitmap, properties, &target))
        && SUCCEEDED(target->CreateSolidColorBrush(color(style->fill), &fill))
        && SUCCEEDED(target->CreateSolidColorBrush(color(style->stroke), &stroke))
        && SUCCEEDED(target->CreateSolidColorBrush(color(style->ink), &ink))) {
        const float bottom = margin + style->bodyHeight;
        const float tip = margin + style->tailX;
        const float half = style->tailHalfWidth;
        // 맥 말풍선과 같은 자리: 채운 꼬리는 몸통 테두리를 덮고, 꼬리 테두리 두 변은 따로 그림
        tailFill = tailPath(D2D1::Point2F(tip - half, bottom - 2), D2D1::Point2F(tip, bottom + style->tailHeight - 0.5f),
                            D2D1::Point2F(tip + half, bottom - 2), true);
        tailEdge = tailPath(D2D1::Point2F(tip - half, bottom - 0.5f), D2D1::Point2F(tip, bottom + style->tailHeight - 0.5f),
                            D2D1::Point2F(tip + half, bottom - 0.5f), false);
        words = layout(text, length, style->fontSize, style->bodyWidth, style->bodyHeight);
        if (words) {
            words->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER);
            words->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
        }

        // 투명 바탕이라 ClearType 대신 회색조 글자
        target->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
        target->BeginDraw();
        target->Clear(D2D1::ColorF(0, 0, 0, 0));
        const D2D1_ROUNDED_RECT body = {D2D1::RectF(margin, margin, margin + style->bodyWidth, bottom), style->cornerRadius,
                                        style->cornerRadius};
        target->FillRoundedRectangle(body, fill);
        target->DrawRoundedRectangle(body, stroke, 1.0f);
        if (tailFill) target->FillGeometry(tailFill, fill);
        if (tailEdge) target->DrawGeometry(tailEdge, stroke, 1.0f);
        // 4 = D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT (윈도우 8.1부터): 이모지를 컬러로
        if (words) target->DrawTextLayout(D2D1::Point2F(margin, margin), words, ink, static_cast<D2D1_DRAW_TEXT_OPTIONS>(4));
        drawn = SUCCEEDED(target->EndDraw());
    }

    if (drawn) {
        const UINT stride = width * 4;
        uint8_t *pixels = static_cast<uint8_t *>(malloc(static_cast<size_t>(stride) * height));
        if (pixels && SUCCEEDED(bitmap->CopyPixels(nullptr, stride, stride * height, pixels))) {
            image->width = static_cast<int32_t>(width);
            image->height = static_cast<int32_t>(height);
            image->bgra = pixels;
        } else {
            free(pixels);
            drawn = false;
        }
    }
    release(words);
    release(tailEdge);
    release(tailFill);
    release(ink);
    release(stroke);
    release(fill);
    release(target);
    release(bitmap);
    return drawn ? 1 : 0;
}

extern "C" void dp_image_free(DPImage *image) {
    if (!image) return;
    free(image->bgra);
    image->bgra = nullptr;
    image->width = 0;
    image->height = 0;
}
