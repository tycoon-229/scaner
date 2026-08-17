#include <jni.h>

#include "BarcodeFormat.h"
#include "ImageView.h"
#include "ReadBarcode.h"
#include "ReaderOptions.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <string>
#include <unordered_set>
#include <vector>

using namespace ZXing;
using std::chrono::steady_clock;

namespace {

constexpr int FORMAT_CODE128 = 1 << 4;
constexpr int FORMAT_DATABAR = 1 << 5;
constexpr int FORMAT_DATABAR_EXPANDED = 1 << 6;
constexpr int FORMAT_EAN8 = 1 << 8;
constexpr int FORMAT_EAN13 = 1 << 9;
constexpr int FORMAT_PDF417 = 1 << 12;
constexpr int FORMAT_UPCA = 1 << 14;
constexpr int FORMAT_UPCE = 1 << 15;
constexpr int FORMAT_DATABAR_LIMITED = 1 << 19;
constexpr int FORMAT_MICRO_PDF417 = 1 << 20;

struct DecodePass {
    int left;
    int top;
    int width;
    int height;
    const char* name;
};

struct NativeCode {
    std::string text;
    int format = 0;
    int imageWidth = 0;
    int imageHeight = 0;
    int topLeftX = 0;
    int topLeftY = 0;
    int topRightX = 0;
    int topRightY = 0;
    int bottomLeftX = 0;
    int bottomLeftY = 0;
    int bottomRightX = 0;
    int bottomRightY = 0;
    bool isInverted = false;
    bool isMirrored = false;
    std::string passName;
};

int elapsedMs(const steady_clock::time_point& start)
{
    return static_cast<int>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                steady_clock::now() - start)
                                .count());
}

ReaderOptions compositeReaderOptions()
{
    return ReaderOptions()
        .setFormats(
            BarcodeFormat::Code128 |
            BarcodeFormat::DataBar |
            BarcodeFormat::DataBarOmni |
            BarcodeFormat::DataBarStk |
            BarcodeFormat::DataBarStkOmni |
            BarcodeFormat::DataBarLtd |
            BarcodeFormat::DataBarExp |
            BarcodeFormat::DataBarExpStk |
            BarcodeFormat::EAN8 |
            BarcodeFormat::EAN13 |
            BarcodeFormat::PDF417 |
            BarcodeFormat::CompactPDF417 |
            BarcodeFormat::MicroPDF417 |
            BarcodeFormat::UPCA |
            BarcodeFormat::UPCE)
        .setTryHarder(true)
        .setTryRotate(true)
        .setTryInvert(true)
        .setTryDownscale(true)
        .setMaxNumberOfSymbols(8)
        .setReturnErrors(false);
}

std::vector<DecodePass> buildPasses(int width, int height)
{
    const int upperHeight = std::max(1, static_cast<int>(height * 0.62f));
    const int lowerTop = std::max(0, static_cast<int>(height * 0.34f));
    const int lowerHeight = std::max(1, height - lowerTop);
    const int middleTop = std::max(0, static_cast<int>(height * 0.18f));
    const int middleHeight = std::max(1, static_cast<int>(height * 0.68f));
    const int centerLeft = std::max(0, static_cast<int>(width * 0.08f));
    const int centerWidth = std::max(1, static_cast<int>(width * 0.84f));

    return {
        {0, 0, width, height, "full"},
        {0, 0, width, upperHeight, "upper"},
        {0, lowerTop, width, lowerHeight, "lower"},
        {0, middleTop, width, std::min(height - middleTop, middleHeight), "middle"},
        {centerLeft, 0, std::min(width - centerLeft, centerWidth), height, "center"},
    };
}

int detectedFormat(BarcodeFormat format)
{
    switch (format) {
    case BarcodeFormat::Code128:
        return FORMAT_CODE128;
    case BarcodeFormat::DataBar:
    case BarcodeFormat::DataBarOmni:
    case BarcodeFormat::DataBarStk:
    case BarcodeFormat::DataBarStkOmni:
        return FORMAT_DATABAR;
    case BarcodeFormat::DataBarExp:
    case BarcodeFormat::DataBarExpStk:
        return FORMAT_DATABAR_EXPANDED;
    case BarcodeFormat::DataBarLtd:
        return FORMAT_DATABAR_LIMITED;
    case BarcodeFormat::EAN8:
        return FORMAT_EAN8;
    case BarcodeFormat::EAN13:
        return FORMAT_EAN13;
    case BarcodeFormat::PDF417:
    case BarcodeFormat::CompactPDF417:
        return FORMAT_PDF417;
    case BarcodeFormat::MicroPDF417:
        return FORMAT_MICRO_PDF417;
    case BarcodeFormat::UPCA:
        return FORMAT_UPCA;
    case BarcodeFormat::UPCE:
        return FORMAT_UPCE;
    default:
        return 0;
    }
}

std::string dedupeKey(const NativeCode& code)
{
    return std::to_string(code.format) + "|" + code.text;
}

NativeCode nativeCodeFromResult(const Barcode& result, const DecodePass& pass, int imageWidth, int imageHeight)
{
    auto pos = result.position();
    auto tl = pos.topLeft();
    auto tr = pos.topRight();
    auto bl = pos.bottomLeft();
    auto br = pos.bottomRight();

    NativeCode code;
    code.text = result.text();
    code.format = detectedFormat(result.format());
    code.imageWidth = imageWidth;
    code.imageHeight = imageHeight;
    code.topLeftX = tl.x + pass.left;
    code.topLeftY = tl.y + pass.top;
    code.topRightX = tr.x + pass.left;
    code.topRightY = tr.y + pass.top;
    code.bottomLeftX = bl.x + pass.left;
    code.bottomLeftY = bl.y + pass.top;
    code.bottomRightX = br.x + pass.left;
    code.bottomRightY = br.y + pass.top;
    code.isInverted = result.isInverted();
    code.isMirrored = result.isMirrored();
    code.passName = pass.name;
    return code;
}

std::vector<NativeCode> decodeLuminance(
    const uint8_t* data,
    int size,
    int width,
    int height,
    int rowStride,
    int* durationMs)
{
    auto startedAt = steady_clock::now();
    std::vector<NativeCode> output;
    std::unordered_set<std::string> seen;
    auto options = compositeReaderOptions();

    ImageView image(data, size, width, height, ImageFormat::Lum, rowStride);
    for (const DecodePass& pass : buildPasses(width, height)) {
        ImageView cropped = image.cropped(pass.left, pass.top, pass.width, pass.height);
        Barcodes results = ReadBarcodes(cropped, options);
        for (const Barcode& result : results) {
            if (!result.isValid() || result.text().empty()) {
                continue;
            }

            NativeCode code = nativeCodeFromResult(result, pass, width, height);
            std::string key = dedupeKey(code);
            if (seen.insert(key).second) {
                output.push_back(std::move(code));
            }
        }
    }

    *durationMs = elapsedMs(startedAt);
    return output;
}

jobject newHashMap(JNIEnv* env)
{
    jclass mapClass = env->FindClass("java/util/HashMap");
    jmethodID constructor = env->GetMethodID(mapClass, "<init>", "()V");
    return env->NewObject(mapClass, constructor);
}

void putObject(JNIEnv* env, jobject map, const char* key, jobject value)
{
    jclass mapClass = env->FindClass("java/util/HashMap");
    jmethodID put = env->GetMethodID(
        mapClass,
        "put",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
    jstring jKey = env->NewStringUTF(key);
    env->CallObjectMethod(map, put, jKey, value);
    env->DeleteLocalRef(jKey);
}

void putString(JNIEnv* env, jobject map, const char* key, const std::string& value)
{
    jstring jValue = env->NewStringUTF(value.c_str());
    putObject(env, map, key, jValue);
    env->DeleteLocalRef(jValue);
}

void putInt(JNIEnv* env, jobject map, const char* key, int value)
{
    jclass integerClass = env->FindClass("java/lang/Integer");
    jmethodID valueOf = env->GetStaticMethodID(integerClass, "valueOf", "(I)Ljava/lang/Integer;");
    jobject jValue = env->CallStaticObjectMethod(integerClass, valueOf, value);
    putObject(env, map, key, jValue);
    env->DeleteLocalRef(jValue);
}

void putBool(JNIEnv* env, jobject map, const char* key, bool value)
{
    jclass booleanClass = env->FindClass("java/lang/Boolean");
    jmethodID valueOf = env->GetStaticMethodID(booleanClass, "valueOf", "(Z)Ljava/lang/Boolean;");
    jobject jValue = env->CallStaticObjectMethod(booleanClass, valueOf, value);
    putObject(env, map, key, jValue);
    env->DeleteLocalRef(jValue);
}

jobject codeToMap(JNIEnv* env, const NativeCode& code)
{
    jobject map = newHashMap(env);
    putString(env, map, "text", code.text);
    putInt(env, map, "format", code.format);
    putInt(env, map, "imageWidth", code.imageWidth);
    putInt(env, map, "imageHeight", code.imageHeight);
    putInt(env, map, "topLeftX", code.topLeftX);
    putInt(env, map, "topLeftY", code.topLeftY);
    putInt(env, map, "topRightX", code.topRightX);
    putInt(env, map, "topRightY", code.topRightY);
    putInt(env, map, "bottomLeftX", code.bottomLeftX);
    putInt(env, map, "bottomLeftY", code.bottomLeftY);
    putInt(env, map, "bottomRightX", code.bottomRightX);
    putInt(env, map, "bottomRightY", code.bottomRightY);
    putBool(env, map, "isInverted", code.isInverted);
    putBool(env, map, "isMirrored", code.isMirrored);
    putString(env, map, "pass", code.passName);
    return map;
}

jobject codesToMap(JNIEnv* env, const std::vector<NativeCode>& codes, int durationMs)
{
    jobject root = newHashMap(env);
    putInt(env, root, "durationMs", durationMs);

    jclass arrayListClass = env->FindClass("java/util/ArrayList");
    jmethodID constructor = env->GetMethodID(arrayListClass, "<init>", "()V");
    jmethodID add = env->GetMethodID(arrayListClass, "add", "(Ljava/lang/Object;)Z");
    jobject list = env->NewObject(arrayListClass, constructor);

    for (const NativeCode& code : codes) {
        jobject codeMap = codeToMap(env, code);
        env->CallBooleanMethod(list, add, codeMap);
        env->DeleteLocalRef(codeMap);
    }

    putObject(env, root, "codes", list);
    env->DeleteLocalRef(list);
    return root;
}

} // namespace

extern "C" JNIEXPORT jobject JNICALL
Java_com_fpt_yuyama_scanner_gs1_Gs1CompositeNativeDecoder_decodeYuvNative(
    JNIEnv* env,
    jobject,
    jbyteArray imageBytes,
    jint width,
    jint height,
    jint rowStride)
{
    if (imageBytes == nullptr || width <= 0 || height <= 0 || rowStride <= 0) {
        return codesToMap(env, {}, 0);
    }

    jsize size = env->GetArrayLength(imageBytes);
    jbyte* bytes = env->GetByteArrayElements(imageBytes, nullptr);
    int durationMs = 0;
    std::vector<NativeCode> codes;

    try {
        codes = decodeLuminance(
            reinterpret_cast<const uint8_t*>(bytes),
            size,
            width,
            height,
            rowStride,
            &durationMs);
    } catch (...) {
        durationMs = 0;
    }

    env->ReleaseByteArrayElements(imageBytes, bytes, JNI_ABORT);
    return codesToMap(env, codes, durationMs);
}
