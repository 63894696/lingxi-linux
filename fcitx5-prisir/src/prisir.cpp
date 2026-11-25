// prisir.cpp — 灵犀拼音 fcitx5 输入法引擎 addon。
// 状态模型:per-IC 自管理拼音缓冲(各 InputContext 独立,借鉴 fcitx5-table)。
// 引擎为进程级单例 dlopen(ciku.db 只载一次,各 IC 共享查询)。
#include <fcitx/inputmethodengine.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputcontextproperty.h>
#include <fcitx/inputpanel.h>
#include <fcitx/candidatelist.h>
#include <fcitx/text.h>
#include <fcitx/addonfactory.h>
#include <fcitx/addonmanager.h>
#include <fcitx/inputmethodentry.h>
#include <fcitx/instance.h>
#include <fcitx/action.h>
#include <fcitx/userinterfacemanager.h>
#include <fcitx/statusarea.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <memory>
#include <string>
#include <vector>
#include <cstring>
#include <algorithm>
#include "prisir_engine.h"

namespace {
// 托盘/状态区 helper 路径（与 .deb 安装布局一致）。无 AI 助手。
constexpr const char *kHelperHome = "/usr/lib/fcitx5/prisir";

void launchHelper(const char *name, const char *arg = nullptr) {
    std::string path = std::string(kHelperHome) + "/" + name;
    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        // 语音：带上焦点窗供上屏；daemon 内还会再 resolve。
        if (std::strcmp(name, "prisir_voice") == 0) {
            FILE *fp = popen("xdotool getwindowfocus 2>/dev/null", "r");
            if (fp) {
                char buf[64] = {};
                if (fgets(buf, sizeof(buf), fp)) {
                    for (char *p = buf; *p; ++p) {
                        if (*p == '\n' || *p == '\r') { *p = '\0'; break; }
                    }
                    if (buf[0])
                        setenv("PRISIR_VOICE_TARGET_WID", buf, 1);
                }
                pclose(fp);
            }
        }
        if (arg) {
            execl(path.c_str(), path.c_str(), arg, static_cast<char *>(nullptr));
        } else {
            execl(path.c_str(), path.c_str(), static_cast<char *>(nullptr));
        }
        _exit(127);
    }
}

// 极简 JSON 提取:解析 [{"word":"..","weight":N},..] 取 word 字段。
// 引擎输出格式固定(ffi.rs serde_json),无嵌套/转义除 \" \\。
std::vector<std::string> extractWords(const std::string &json) {
    std::vector<std::string> out;
    const std::string key = "\"word\":\"";
    size_t pos = 0;
    while ((pos = json.find(key, pos)) != std::string::npos) {
        size_t start = pos + key.size();
        std::string w;
        for (size_t i = start; i < json.size(); ++i) {
            char c = json[i];
            if (c == '\\' && i + 1 < json.size()) { w += json[i + 1]; ++i; continue; }
            if (c == '"') { pos = i + 1; break; }
            w += c;
        }
        if (!w.empty()) out.push_back(w);
    }
    return out;
}

// 带 Ctrl/Alt/Super 的组合键不参与标点映射(避免抢 Ctrl+, 等应用快捷键)。
bool hasCommandModifier(const fcitx::Key &key) {
    auto s = key.states();
    return s.test(fcitx::KeyState::Ctrl) || s.test(fcitx::KeyState::Alt) ||
           s.test(fcitx::KeyState::Super);
}

class PrisirState : public fcitx::InputContextProperty {
public:
    std::string buffer;      // 当前拼音输入缓冲
    bool english = false;    // P0:本次输入被判为英文(原样字母上屏)
};

class PrisirEngineAddon;

class PrisirCandidateWord : public fcitx::CandidateWord {
public:
    PrisirCandidateWord(PrisirEngineAddon *engine, std::string word, std::string input)
        : engine_(engine), word_(std::move(word)), input_(std::move(input)) {
        setText(fcitx::Text(word_));
    }
    void select(fcitx::InputContext *ic) const override;

private:
    PrisirEngineAddon *engine_;
    std::string word_;
    std::string input_;
};

class PrisirEngineAddon : public fcitx::InputMethodEngine {
public:
    PrisirEngineAddon(fcitx::Instance *instance) : instance_(instance) {
        // 必须 registerProperty，否则 propertyFor 在 fcitx5 5.1.x 会 assert 崩进程。
        instance_->inputContextManager().registerProperty("prisirState", &factory_);

        // 引擎 .so 与词库路径:addon 安装目录(见 CMake/postinst 布局)。
        const char *base = std::getenv("PRISIR_IME_HOME");
        std::string home = base ? base : "/usr/lib/fcitx5/prisir";
        engine_.open(home + "/libprisir_ime.so", home + "/ciku.db");

        // 状态区菜单（Win 选择性迁移）：词库/造词/符号/语音/简繁/开放API/关于。
        // 不做：AI 助手；手写（安卓同款自研 ONNX，精度远差于 Win 系统 Ink）。
        // 语音：迁移 Win SenseVoice Small + onnxruntime（与 lingxi_voice 同模型）。
        auto &uim = instance_->userInterfaceManager();
        setupAction(uim, actionDict_, "prisir-dict", "词库管理", "prisir_dict");
        setupAction(uim, actionQuickAdd_, "prisir-quick-add", "灵犀造词", "prisir_quick_add");
        setupAction(uim, actionSym_, "prisir-sym", "符号大全", "prisir_symbols");
        // 语音听写：点菜单 = toggle；热键设置在录音浮窗「热键」按钮。
        // 常驻 daemon + 右 Alt 由开机自启 / activate 时 --start 保证。
        setupAction(uim, actionVoice_, "prisir-voice", "语音听写", "prisir_voice");
        setupAction(uim, actionAbout_, "prisir-about", "关于 / 反馈", "prisir_about");
        setupAction(uim, actionOpenApi_, "prisir-openapi", "开放 API", "prisir_openapi_ui");

        // 引擎加载后后台拉起语音 daemon（不 toggle），重启后热键仍可用。
        launchHelper("prisir_voice", "--start");
        // 开放 API：若用户已 enable，则确保 127.0.0.1 监听（未启用则 helper 直接退出）。
        launchHelper("prisir_openapi", "--start");

        actionScript_ = std::make_unique<fcitx::SimpleAction>();
        actionScript_->setShortText("简繁输出");
        actionScript_->connect<fcitx::SimpleAction::Activated>([this](fcitx::InputContext *ic) {
            int mode = engine_.cycleScript();
            actionScript_->setShortText(
                mode == 1 ? "简繁：简→繁" : (mode == 2 ? "简繁：繁→简" : "简繁：不转换"));
            actionScript_->update(ic);
            if (ic) {
                fcitx::Text tip(mode == 1 ? "简→繁" : (mode == 2 ? "繁→简" : "不转换"));
                ic->inputPanel().setPreedit(tip);
                ic->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
                ic->updatePreedit();
            }
        });
        uim.registerAction("prisir-script", actionScript_.get());
    }

    void activate(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &event) override {
        auto *ic = event.inputContext();
        // InputMethod 组在 activate 前会被清空，每次激活重新挂上。
        auto &area = ic->statusArea();
        area.addAction(fcitx::StatusGroup::InputMethod, actionDict_.get());
        area.addAction(fcitx::StatusGroup::InputMethod, actionQuickAdd_.get());
        area.addAction(fcitx::StatusGroup::InputMethod, actionSym_.get());
        area.addAction(fcitx::StatusGroup::InputMethod, actionVoice_.get());
        area.addAction(fcitx::StatusGroup::InputMethod, actionScript_.get());
        area.addAction(fcitx::StatusGroup::InputMethod, actionOpenApi_.get());
        area.addAction(fcitx::StatusGroup::InputMethod, actionAbout_.get());
    }

    void deactivate(const fcitx::InputMethodEntry &entry, fcitx::InputContextEvent &event) override {
        reset(entry, event);
    }

    void reset(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &event) override {
        auto *ic = event.inputContext();
        auto *st = state(ic);
        st->buffer.clear();
        st->english = false;
        engine_.punctReset();
        ic->inputPanel().reset();
        ic->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
        ic->updatePreedit();
    }

    void keyEvent(const fcitx::InputMethodEntry &entry, fcitx::KeyEvent &keyEvent) override {
        FCITX_UNUSED(entry);
        auto *ic = keyEvent.inputContext();
        if (keyEvent.isRelease()) return;
        auto key = keyEvent.key();
        auto *st = state(ic);

        // 带命令修饰键的组合键优先处理，不能被下面的字母分支吃掉。
        // （Ctrl+C/V/A 等在旧实现里会被当成拼音字母吞掉。）
        if (key.states().test(fcitx::KeyState::Ctrl) &&
            key.states().test(fcitx::KeyState::Shift) && key.check(FcitxKey_F)) {
            // P2 简繁切换(2026-11-17):Ctrl+Shift+F 三态循环 原样 → 简→繁 → 繁→简。
            // 键位对齐搜狗；不占用拼音输入字符。
            int mode = engine_.cycleScript();
            fcitx::Text tip = fcitx::Text(
                mode == 1 ? "简→繁" : (mode == 2 ? "繁→简" : "不转换"));
            ic->inputPanel().setPreedit(tip);
            ic->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
            ic->updatePreedit();
            keyEvent.filterAndAccept();
            return;
        }
        // 其余带 Ctrl/Alt/Super 的组合键一律不参与拼音累积（交给应用）。
        if (key.states().test(fcitx::KeyState::Ctrl) || key.states().test(fcitx::KeyState::Alt) ||
            key.states().test(fcitx::KeyState::Super)) {
            if (!st->buffer.empty()) { selectIndex(ic, st, 0); }
            return;
        }
        // Shift 临时英文(2026-11-17,对齐 Windows 行为):按住 Shift 打字母 → 大写英文直接上屏,
        // 不进拼音缓冲。这是习惯动作(打英文单词/缩写),不是设置项。
        // 只在缓冲为空时生效:缓冲非空说明正在打字,Shift+字母按普通逻辑走(先上屏首选再放行)。
        if (st->buffer.empty() && key.isSimple() &&
            key.states().test(fcitx::KeyState::Shift) &&
            !key.states().test(fcitx::KeyState::Ctrl) &&
            !key.states().test(fcitx::KeyState::Alt)) {
            char32_t cp = fcitx::Key::keySymToUnicode(key.sym());
            if ((cp >= U'a' && cp <= U'z') || (cp >= U'A' && cp <= U'Z')) {
                // 只处理 ASCII 字母，直接转 char（不经 utf8 辅助函数，少一个版本依赖）
                char up = static_cast<char>((cp >= U'a') ? (cp - 32) : cp);
                ic->commitString(std::string(1, up));
                keyEvent.filterAndAccept();
                return;
            }
        }
        // a-z:累积拼音
        if (key.isSimple() && key.sym() >= FcitxKey_a && key.sym() <= FcitxKey_z) {
            st->buffer += fcitx::Key::keySymToUTF8(key.sym());
            update(ic, st);
            keyEvent.filterAndAccept();
            return;
        }
        // Backspace:删一个字母;空缓冲不拦截
        if (key.check(FcitxKey_BackSpace)) {
            if (!st->buffer.empty()) {
                st->buffer.pop_back();
                update(ic, st);
                keyEvent.filterAndAccept();
            }
            return;
        }
        // 数字 1-9:选候选。缓冲为空时不拦,让数字正常进应用。
        if (key.isSimple() && key.sym() >= FcitxKey_1 && key.sym() <= FcitxKey_9) {
            if (!st->buffer.empty() && selectIndex(ic, st, key.sym() - FcitxKey_1)) {
                keyEvent.filterAndAccept();
                return;
            }
        }
        // 空格/回车:首选上屏(空格)或原样上屏(回车)
        if (key.check(FcitxKey_space)) {
            if (selectIndex(ic, st, 0)) keyEvent.filterAndAccept();
            return;
        }
        if (key.check(FcitxKey_Return)) {
            if (!st->buffer.empty()) {
                ic->commitString(engine_.toScript(st->buffer));
                resetBuffer(ic, st);
                keyEvent.filterAndAccept();
            }
            return;
        }
        // P0 智能标点(2026-11-16):缓冲区为空时 ASCII → 中文标点。
        // 带命令修饰键的放过,避免抢 Ctrl+, / Alt+. 等应用快捷键。
        if (st->buffer.empty() && key.isSimple() && !hasCommandModifier(key)) {
            char32_t cp = fcitx::Key::keySymToUnicode(key.sym());
            if (cp) {
                std::string mapped = engine_.punct(static_cast<unsigned int>(cp), false);
                if (!mapped.empty()) {
                    ic->commitString(mapped);
                    keyEvent.filterAndAccept();
                    return;
                }
            }
        }
        // 空格翻页(=/- 或 .)仅在缓冲区非空时生效,否则 . 会吞掉句号输入
        // 翻页:+ / . / PageDown 下一页，- / , / PageUp 上一页(2026-11-17 补 PgUp/PgDn,
        // 对齐 Windows 与搜狗习惯;仍然只在有候选时生效,否则 . 会吞掉句号)
        if (!st->buffer.empty() &&
            (key.check(FcitxKey_equal) || key.check(FcitxKey_period) || key.check(FcitxKey_Page_Down))) {
            page(ic, 1); keyEvent.filterAndAccept(); return;
        }
        if (!st->buffer.empty() &&
            (key.check(FcitxKey_minus) || key.check(FcitxKey_comma) || key.check(FcitxKey_Page_Up))) {
            page(ic, -1); keyEvent.filterAndAccept(); return;
        }
        if (key.check(FcitxKey_Escape)) {
            if (!st->buffer.empty()) { resetBuffer(ic, st); keyEvent.filterAndAccept(); }
            return;
        }
        // 其余(标点/大写等):若有缓冲先把首选上屏,再放行该键
        if (!st->buffer.empty()) {
            selectIndex(ic, st, 0);
            // 不 filter,让该键继续传给应用
        }
    }

    // 供 CandidateWord::select 调用
    void commitCandidate(fcitx::InputContext *ic, const std::string &word, const std::string &input) {
        auto *st = state(ic);
        // P0:自动判英文时上屏的就是原样字母,不能当词组学进用户词库。
        bool rawEnglish = st->english && word == input;
        // P2 简繁:上屏前转换(引擎开关关着时原样返回)。
        ic->commitString(engine_.toScript(word));
        if (!rawEnglish) engine_.learn(input, word);
        resetBuffer(ic, st);
    }

private:
    PrisirState *state(fcitx::InputContext *ic) {
        return ic->propertyFor(&factory_);
    }

    void update(fcitx::InputContext *ic, PrisirState *st) {
        if (st->buffer.empty()) { resetBuffer(ic, st); return; }
        auto candList = std::make_unique<fcitx::CommonCandidateList>();
        candList->setPageSize(5);  // 与 selectIndex 的 pageSize 常量一致,显式不依赖默认
        std::vector<std::string> words;
        if (engine_.ok()) {
            // 2026-11-21: 移除整句候选注入。
            // 原实现把 minWords=2 的「多词整句」push 到 words 最前面,于是字拼整句
            // (才但/处来/内荣/而切 —— lattice 把整串切成两个单字再拼接,词库里根本没有
            // 这些词)会占据候选 #1,把词库整词(菜单/出来/内容/而且)挤到 #2。
            // 现在候选一律只来自 queryJson(词库候选),首候选恒为词库最优项。
            for (auto &w : extractWords(engine_.queryJson(st->buffer))) {
                if (std::find(words.begin(), words.end(), w) == words.end()) words.push_back(w);
            }
        }
        // P0 中英文自动判定(2026-11-16):能切音节但词库一条不中 → 当英文原样上屏。
        st->english = false;
        if (!st->buffer.empty() && engine_.classify(st->buffer) == 2) {
            st->english = true;
            words.clear();
            words.push_back(st->buffer);  // 原样字母作为唯一候选
        }
        int idx = 0;
        for (auto &w : words) {
            candList->append(std::make_unique<PrisirCandidateWord>(this, w, st->buffer));
            if (++idx >= 50) break;
        }
        // 预编辑显示原始拼音
        fcitx::Text preedit(st->buffer);
        ic->inputPanel().setPreedit(preedit);
        ic->inputPanel().setCandidateList(std::move(candList));
        ic->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
        ic->updatePreedit();
    }

    bool selectIndex(fcitx::InputContext *ic, PrisirState *st, int idx) {
        auto cl = ic->inputPanel().candidateList();
        if (!cl || cl->size() == 0) {
            if (!st->buffer.empty()) { ic->commitString(engine_.toScript(st->buffer)); resetBuffer(ic, st); }
            return true;
        }
        // 每页候选数:我们 update() 里建的是 CommonCandidateList,默认页大小 5。
        // 基类 CandidateList 无 pageSize(),用固定页大小 + toPageable()->currentPage() 算全局索引。
        const int pageSize = 5;
        int page = 0;
        if (auto *pageable = cl->toPageable()) page = pageable->currentPage();
        if (page < 0) page = 0;
        int global = page * pageSize + idx;
        if (global < 0 || global >= cl->size()) return false;
        const auto &cw = cl->candidate(global);
        commitCandidate(ic, cw.text().toString(), st->buffer);
        return true;
    }

    void page(fcitx::InputContext *ic, int delta) {
        auto cl = ic->inputPanel().candidateList();
        if (!cl) return;
        auto *pageable = cl->toPageable();
        if (!pageable) return;
        if (delta > 0 && pageable->hasNext()) pageable->next();
        else if (delta < 0 && pageable->hasPrev()) pageable->prev();
        ic->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
    }

    void resetBuffer(fcitx::InputContext *ic, PrisirState *st) {
        st->buffer.clear();
        st->english = false;
        engine_.punctReset();  // 一次输入结束,引号配对归位
        ic->inputPanel().reset();
        ic->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
        ic->updatePreedit();
    }

    void setupAction(fcitx::UserInterfaceManager &uim,
                     std::unique_ptr<fcitx::SimpleAction> &slot,
                     const char *id, const char *label, const char *helper,
                     const char *arg = nullptr) {
        slot = std::make_unique<fcitx::SimpleAction>();
        slot->setShortText(label);
        std::string helperName = helper;
        std::string helperArg = arg ? arg : "";
        slot->connect<fcitx::SimpleAction::Activated>(
            [helperName, helperArg](fcitx::InputContext *) {
                launchHelper(helperName.c_str(),
                             helperArg.empty() ? nullptr : helperArg.c_str());
            });
        uim.registerAction(id, slot.get());
    }

    fcitx::Instance *instance_;
    PrisirEngine engine_;
    fcitx::FactoryFor<PrisirState> factory_{
        [](fcitx::InputContext &) { return new PrisirState; }};
    std::unique_ptr<fcitx::SimpleAction> actionDict_;
    std::unique_ptr<fcitx::SimpleAction> actionQuickAdd_;
    std::unique_ptr<fcitx::SimpleAction> actionSym_;
    std::unique_ptr<fcitx::SimpleAction> actionVoice_;
    std::unique_ptr<fcitx::SimpleAction> actionAbout_;
    std::unique_ptr<fcitx::SimpleAction> actionOpenApi_;
    std::unique_ptr<fcitx::SimpleAction> actionScript_;
};

void PrisirCandidateWord::select(fcitx::InputContext *ic) const {
    engine_->commitCandidate(ic, word_, input_);
}

class PrisirFactory : public fcitx::AddonFactory {
public:
    fcitx::AddonInstance *create(fcitx::AddonManager *manager) override {
        FCITX_UNUSED(manager);
        return new PrisirEngineAddon(manager->instance());
    }
};

} // namespace

FCITX_ADDON_FACTORY(PrisirFactory)
