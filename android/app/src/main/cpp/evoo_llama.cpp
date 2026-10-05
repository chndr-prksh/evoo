// A thin bridge between Kotlin (LlamaNative) and llama.cpp: load a GGUF model, then complete a prompt given as
// a fixed prefix (instructions + examples, evaluated once and kept) and a per-dictation suffix. Mirrors the Mac
// app's LlamaRefiner.swift.
#include <jni.h>
#include <android/log.h>
#include <string>
#include <vector>
#include "llama.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "EvooLlama", __VA_ARGS__)

namespace {

struct Engine {
    llama_model *model = nullptr;
    llama_context *ctx = nullptr;
    const llama_vocab *vocab = nullptr;
    llama_sampler *sampler = nullptr;
    std::vector<llama_token> cachedPrefix;
};

const uint32_t kContext = 4096;

std::vector<llama_token> tokenize(const llama_vocab *vocab, const std::string &text, bool addSpecial) {
    std::vector<llama_token> tokens(text.size() + 8);
    int n = llama_tokenize(vocab, text.c_str(), (int32_t) text.size(), tokens.data(), (int32_t) tokens.size(), addSpecial, true);
    if (n < 0) {
        tokens.resize(-n);
        n = llama_tokenize(vocab, text.c_str(), (int32_t) text.size(), tokens.data(), (int32_t) tokens.size(), addSpecial, true);
    }
    tokens.resize(n < 0 ? 0 : n);
    return tokens;
}

bool decode(llama_context *ctx, std::vector<llama_token> &tokens) {
    if (tokens.empty()) return true;
    return llama_decode(ctx, llama_batch_get_one(tokens.data(), (int32_t) tokens.size())) == 0;
}

// Text crosses the bridge as UTF-8 bytes: Java's own string encoding mangles emoji.
std::string fromJava(JNIEnv *env, jbyteArray bytes) {
    jsize n = env->GetArrayLength(bytes);
    std::string out((size_t) n, '\0');
    if (n > 0) env->GetByteArrayRegion(bytes, 0, n, (jbyte *) out.data());
    return out;
}

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_app_evoo_android_LlamaNative_load(JNIEnv *env, jobject, jbyteArray jpath, jint threads) {
    static bool initialized = false;
    if (!initialized) {
        llama_log_set([](enum ggml_log_level, const char *, void *) {}, nullptr);
        llama_backend_init();
        initialized = true;
    }
    std::string path = fromJava(env, jpath);
    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 0;  // CPU: works on every phone
    llama_model *model = llama_model_load_from_file(path.c_str(), mparams);
    if (!model) return 0;

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = kContext;
    cparams.n_batch = kContext;
    cparams.n_threads = threads;
    cparams.n_threads_batch = threads;
    llama_context *ctx = llama_init_from_model(model, cparams);
    if (!ctx) {
        llama_model_free(model);
        return 0;
    }
    auto *engine = new Engine();
    engine->model = model;
    engine->ctx = ctx;
    engine->vocab = llama_model_get_vocab(model);
    engine->sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(engine->sampler, llama_sampler_init_greedy());  // deterministic output
    LOGI("model loaded, %d threads", threads);
    return (jlong) engine;
}

// Returns the completion as UTF-8 bytes (null on failure). `prefix` is evaluated once and reused while it stays
// the same; pass an empty suffix to just warm it up.
JNIEXPORT jbyteArray JNICALL
Java_app_evoo_android_LlamaNative_complete(JNIEnv *env, jobject, jlong handle, jbyteArray jprefix, jbyteArray jsuffix, jint maxTokens, jbyteArray jstate) {
    auto *engine = (Engine *) handle;
    if (!engine) return nullptr;
    std::string prefixText = fromJava(env, jprefix), suffixText = fromJava(env, jsuffix);
    llama_memory_t memory = llama_get_memory(engine->ctx);

    std::vector<llama_token> prefix = tokenize(engine->vocab, prefixText, true);
    if (prefix == engine->cachedPrefix) {
        llama_memory_seq_rm(memory, 0, (llama_pos) prefix.size(), -1);  // drop the previous dictation
    } else {
        // Reading the instructions takes the model tens of seconds on a phone, so the result is kept on disk:
        // the next time the keyboard starts, it is loaded back in well under a second.
        std::string statePath = fromJava(env, jstate);
        llama_memory_clear(memory, true);
        engine->cachedPrefix.clear();
        bool restored = false;
        if (!statePath.empty()) {
            std::vector<llama_token> saved(prefix.size() + 16);
            size_t count = 0;
            if (llama_state_load_file(engine->ctx, statePath.c_str(), saved.data(), saved.size(), &count)) {
                saved.resize(count);
                restored = saved == prefix;
            }
            if (!restored) llama_memory_clear(memory, true);
        }
        if (!restored) {
            if (!decode(engine->ctx, prefix)) return nullptr;
            if (!statePath.empty()) {
                bool ok = llama_state_save_file(engine->ctx, statePath.c_str(), prefix.data(), prefix.size());
                LOGI("instructions evaluated, %s", ok ? "saved" : "not saved");
            }
        } else {
            LOGI("instructions restored from disk");
        }
        engine->cachedPrefix = prefix;
    }

    std::string out;
    if (!suffixText.empty()) {
        llama_sampler_reset(engine->sampler);
        std::vector<llama_token> suffix = tokenize(engine->vocab, suffixText, false);
        if (prefix.size() + suffix.size() + (size_t) maxTokens >= kContext) return nullptr;  // too long for the model
        if (!decode(engine->ctx, suffix)) return nullptr;
        char piece[256];
        for (int i = 0; i < maxTokens; i++) {
            llama_token token = llama_sampler_sample(engine->sampler, engine->ctx, -1);
            if (llama_vocab_is_eog(engine->vocab, token)) break;
            int n = llama_token_to_piece(engine->vocab, token, piece, sizeof(piece), 0, false);
            if (n > 0) out.append(piece, n);
            if (out.find("<|im_end|>") != std::string::npos) break;
            if (llama_decode(engine->ctx, llama_batch_get_one(&token, 1)) != 0) break;
        }
    }
    jbyteArray bytes = env->NewByteArray((jsize) out.size());
    env->SetByteArrayRegion(bytes, 0, (jsize) out.size(), (const jbyte *) out.data());
    return bytes;
}

JNIEXPORT void JNICALL
Java_app_evoo_android_LlamaNative_free(JNIEnv *, jobject, jlong handle) {
    auto *engine = (Engine *) handle;
    if (!engine) return;
    llama_sampler_free(engine->sampler);
    llama_free(engine->ctx);
    llama_model_free(engine->model);
    delete engine;
}

}  // extern "C"
