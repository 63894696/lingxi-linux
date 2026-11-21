// prisir_engine.h — 引擎 cdylib(libprisir_ime.so)的 dlopen 封装。
// 与 Windows ffi.rs 同一套 C ABI:load/query/learn/free_string/free。
// fcitx5 addon 不直接 link 引擎(引擎独立 .so,运行期 dlopen),
// 便于引擎单独升级而不重编 addon。
#pragma once
#include <dlfcn.h>
#include <string>
#include <vector>

struct PrisirCandidate {
    std::string word;
    long weight;
};

class PrisirEngine {
public:
    PrisirEngine() = default;
    ~PrisirEngine() { close(); }

    bool open(const std::string &so_path, const std::string &db_path) {
        close();
        handle_lib_ = dlopen(so_path.c_str(), RTLD_NOW | RTLD_LOCAL);
        if (!handle_lib_) return false;
        p_load = (LoadFn)dlsym(handle_lib_, "prisir_ime_load");
        p_query = (QueryFn)dlsym(handle_lib_, "prisir_ime_query");
        p_learn = (LearnFn)dlsym(handle_lib_, "prisir_ime_learn");
        p_free_str = (FreeStrFn)dlsym(handle_lib_, "prisir_ime_free_string");
        p_free = (FreeFn)dlsym(handle_lib_, "prisir_ime_free");
        // P0(2026-11-16):可选符号。旧引擎 .so 没有也不影响 addon 启动,
        // 只是中英文自动判定 / 智能标点不生效(退回纯拼音行为)。
        p_classify = (ClassifyFn)dlsym(handle_lib_, "prisir_ime_classify");
        p_classify_with = (ClassifyWithFn)dlsym(handle_lib_, "prisir_ime_classify_with");
        p_punct = (PunctFn)dlsym(handle_lib_, "prisir_ime_punct");
        p_punct_reset = (PunctResetFn)dlsym(handle_lib_, "prisir_ime_punct_reset");
        // P2(2026-11-16/17):简繁转换与模式切换，可选符号。
        // 新引擎用 to_script（按模式转换）；旧引擎只有 to_trad（只做简→繁）。
        p_to_script = (ToScriptFn)dlsym(handle_lib_, "prisir_ime_to_script");
        if (!p_to_script) p_to_script = (ToScriptFn)dlsym(handle_lib_, "prisir_ime_to_trad");
        p_script = (ScriptFn)dlsym(handle_lib_, "prisir_ime_script");
        p_set_script = (SetScriptFn)dlsym(handle_lib_, "prisir_ime_set_script");
        p_cycle_script = (CycleScriptFn)dlsym(handle_lib_, "prisir_ime_cycle_script");
        if (!p_load || !p_query || !p_learn || !p_free_str || !p_free) {
            close();
            return false;
        }
        engine_ = p_load(db_path.c_str(), 0);
        if (!engine_) { close(); return false; }
        return true;
    }

    void close() {
        if (engine_ && p_free) { p_free(engine_); engine_ = nullptr; }
        if (handle_lib_) { dlclose(handle_lib_); handle_lib_ = nullptr; }
        p_load = nullptr; p_query = nullptr; p_learn = nullptr;
        p_free_str = nullptr; p_free = nullptr;
        p_classify = nullptr; p_classify_with = nullptr;
        p_punct = nullptr; p_punct_reset = nullptr;
        p_to_script = nullptr;
        p_script = nullptr;
        p_set_script = nullptr;
        p_cycle_script = nullptr;
    }

    bool ok() const { return engine_ != nullptr; }

    // 查询,返回 JSON 数组字符串(调用方负责解析)。失败返回空串。
    std::string queryJson(const std::string &input) {
        if (!engine_) return {};
        char *r = p_query(engine_, input.c_str());
        if (!r) return {};
        std::string out(r);
        p_free_str(r);
        return out;
    }

    void learn(const std::string &input, const std::string &selected) {
        if (engine_) p_learn(engine_, input.c_str(), selected.c_str());
    }

    // P0 中英文自动判定:返回 0=空 1=拼音 2=英文 3=单字母存疑。
    // exactFlag 传 -1 表示让引擎自己判断词库精确命中(推荐)。
    // 注意:不能传候选数——query() 有模糊音/贪心兼底,候选数恒 >0,会全判成拼音。
    // 旧 .so 无此符号时返回 1(拼音,行为不变)。
    int classify(const std::string &input, int exactFlag = -1) {
        if (!engine_) return 1;
        if (p_classify_with) return p_classify_with(engine_, input.c_str(), exactFlag);
        if (p_classify) return p_classify(engine_, input.c_str());
        return 1;
    }

    // P0 智能标点:ASCII → 中文标点。无映射/旧 .so 时返回空串(调用方按原键处理)。
    std::string punct(unsigned int ch, bool reset) {
        if (!engine_ || !p_punct) return {};
        char *r = p_punct(engine_, ch, reset ? 1 : 0);
        if (!r) return {};
        std::string out(r);
        p_free_str(r);
        return out;
    }

    // P2 简繁:上屏前按当前模式转换。原样模式/旧 .so 无符号 → 原样返回。
    std::string toScript(const std::string &text) {
        if (!engine_ || !p_to_script || text.empty()) return text;
        char *r = p_to_script(engine_, text.c_str());
        if (!r) return text;
        std::string out(r);
        p_free_str(r);
        return out.empty() ? text : out;
    }

    // P2 简繁:当前模式 0=原样 1=简→繁 2=繁→简。
    int scriptMode() {
        if (!engine_ || !p_script) return 0;
        return p_script(engine_);
    }

    // P2 简繁:三态循环，返回新模式（供快捷键）。
    int cycleScript() {
        if (!engine_) return 0;
        if (p_cycle_script) return p_cycle_script(engine_);
        // 回退：本侧自己算不了引擎状态，直接不动。
        return scriptMode();
    }

    // 归位引号配对状态(换输入框/上屏/回车)。
    void punctReset() {
        if (!engine_) return;
        if (p_punct_reset) { p_punct_reset(engine_); return; }
        // 回退路径:传一个不可映射的码点 + reset=1,只做归位。
        if (p_punct) { char *r = p_punct(engine_, 0, 1); if (r) p_free_str(r); }
    }

private:
    using LoadFn = void *(*)(const char *, int);
    using QueryFn = char *(*)(void *, const char *);
    using LearnFn = void (*)(void *, const char *, const char *);
    using FreeStrFn = void (*)(char *);
    using FreeFn = void (*)(void *);
    using ClassifyFn = int (*)(void *, const char *);
    using ClassifyWithFn = int (*)(void *, const char *, int);
    using PunctFn = char *(*)(void *, unsigned int, int);
    using PunctResetFn = void (*)(void *);
        using ToScriptFn = char *(*)(void *, const char *);
    using ScriptFn = int (*)(void *);
    using SetScriptFn = void (*)(void *, int);
    using CycleScriptFn = int (*)(void *);

    void *handle_lib_ = nullptr;
    void *engine_ = nullptr;
    LoadFn p_load = nullptr;
    QueryFn p_query = nullptr;
    LearnFn p_learn = nullptr;
    FreeStrFn p_free_str = nullptr;
    FreeFn p_free = nullptr;
    ClassifyFn p_classify = nullptr;
    ClassifyWithFn p_classify_with = nullptr;
    PunctFn p_punct = nullptr;
    PunctResetFn p_punct_reset = nullptr;
        ToScriptFn p_to_script = nullptr;
    ScriptFn p_script = nullptr;
    SetScriptFn p_set_script = nullptr;
    CycleScriptFn p_cycle_script = nullptr;
};
