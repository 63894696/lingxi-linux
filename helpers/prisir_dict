#!/usr/bin/env python3
# 灵犀拼音 词库管理 (GTK, 对齐 Win 端 userdict_window.rs)
# 单搜索框统一搜主库(phrase+pinyin 合并, 拼音/词条同搜), 编辑行回填, 保存=upsert 主库,
# 删除选中(主库+五笔均可, 确认弹窗), 灵犀式翻页。
# 确保本进程 GTK 输入走 fcitx5: 会话可能把变量设成空串, setdefault 不会覆盖, 故空才赋值。
import os
for _k, _v in (("GTK_IM_MODULE","fcitx"),("QT_IM_MODULE","fcitx"),("XMODIFIERS","@im=fcitx")):
    if not os.environ.get(_k):
        os.environ[_k] = _v
import sqlite3, traceback
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Pango
Gtk.init_check([])  # import 后立即初始化, 让 gtk-im-module 在首个 IM context 前解析为 fcitx

DB = "/usr/lib/fcitx5/prisir/ciku.db"
PAGE = 20

class DictWin(Gtk.Window):
    def __init__(self):
        Gtk.Window.__init__(self, title="Prisir 灵犀拼音词库管理")
        self.set_default_size(800, 560)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.connect("destroy", Gtk.main_quit)
        self.page = 0
        self.total = 0
        self.term = ""
        self.rows = []  # (key, value, weight, source)

        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        v.set_border_width(10)
        self.add(v)

        # ① 顶部统一搜索行
        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        v.pack_start(top, False, False, 0)
        top.pack_start(Gtk.Label(label="输入:"), False, False, 0)
        self.search = Gtk.SearchEntry()
        self.search.connect("activate", self.on_search)
        top.pack_start(self.search, True, True, 0)
        sb = Gtk.Button(label="搜索")
        sb.connect("clicked", self.on_search)
        top.pack_start(sb, False, False, 0)

        # ② 编辑行(词/拼音/词频 + 保存/删除)
        edit = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        v.pack_start(edit, False, False, 0)
        edit.pack_start(Gtk.Label(label="词语:"), False, False, 0)
        self.e_word = Gtk.Entry(); edit.pack_start(self.e_word, True, True, 0)
        edit.pack_start(Gtk.Label(label="拼音:"), False, False, 0)
        self.e_py = Gtk.Entry(); edit.pack_start(self.e_py, True, True, 0)
        edit.pack_start(Gtk.Label(label="词频:"), False, False, 0)
        self.e_wt = Gtk.Entry(); self.e_wt.set_width_chars(8); edit.pack_start(self.e_wt, False, False, 0)
        saveb = Gtk.Button(label="保存"); saveb.connect("clicked", self.on_save); edit.pack_start(saveb, False, False, 0)
        delb = Gtk.Button(label="删除"); delb.connect("clicked", self.on_delete); edit.pack_start(delb, False, False, 0)

        # ③ 词条表格(拼音/词语/词频/来源)
        self.store = Gtk.ListStore(str, str, str, str)
        self.view = Gtk.TreeView(model=self.store)
        for i, (t, w) in enumerate([("拼音", 140), ("词语", 260), ("词频", 100), ("来源", 90)]):
            r = Gtk.CellRendererText(); r.set_property("ellipsize", Pango.EllipsizeMode.END)
            col = Gtk.TreeViewColumn(t, r, text=i); col.set_resizable(True); col.set_min_width(w)
            self.view.append_column(col)
        self.view.get_selection().connect("changed", self.on_row_sel)
        sc = Gtk.ScrolledWindow(); sc.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        sc.add(self.view)
        v.pack_start(sc, True, True, 0)

        # ④ 底部翻页 + 状态
        bot = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        v.pack_start(bot, False, False, 0)
        pb = Gtk.Button(label="< 上一页"); pb.connect("clicked", lambda *a: self.turn(-1)); bot.pack_start(pb, False, False, 0)
        nb = Gtk.Button(label="下一页 >"); nb.connect("clicked", lambda *a: self.turn(1)); bot.pack_start(nb, False, False, 0)
        self.status = Gtk.Label(label="", xalign=0); self.status.set_ellipsize(Pango.EllipsizeMode.END)
        bot.pack_start(self.status, True, True, 0)

        self.load()

    def conn(self, ro=True):
        if ro:
            return sqlite3.connect("file:%s?mode=ro" % DB, uri=True)
        return sqlite3.connect(DB)

    def load(self):
        """统一搜索: term 同时按 词条(value) 和 拼音(key) 搜 phrase+pinyin, 合并去重, weight 排序。"""
        self.store.clear(); self.rows = []
        if not os.path.exists(DB):
            self.status.set_text("词库文件不存在: " + DB); return
        try:
            c = self.conn(True)
            off = self.page * PAGE
            term = self.term
            # 合并查询: phrase 与 pinyin 同构 (jp,key,value,weight)
            if term:
                like = "%" + term + "%"
                base = "FROM phrase WHERE value LIKE ? OR key LIKE ?"
                cnt = "SELECT count(*) " + base
                q = ("SELECT key,value,weight,'phrase' " + base +
                     " UNION ALL SELECT key,value,weight,'pinyin' FROM pinyin WHERE value LIKE ? OR key LIKE ?" +
                     " ORDER BY weight DESC LIMIT ? OFFSET ?")
                cnt_args = [like, like]
                args = [like, like, like, like, PAGE, off]
                # 总数 = phrase 匹配 + pinyin 匹配
                tot = c.execute("SELECT count(*) FROM phrase WHERE value LIKE ? OR key LIKE ?", [like, like]).fetchone()[0]
                tot += c.execute("SELECT count(*) FROM pinyin WHERE value LIKE ? OR key LIKE ?", [like, like]).fetchone()[0]
            else:
                q = ("SELECT key,value,weight,'phrase' FROM phrase"
                     " UNION ALL SELECT key,value,weight,'pinyin' FROM pinyin"
                     " ORDER BY weight DESC LIMIT ? OFFSET ?")
                args = [PAGE, off]
                tot = c.execute("SELECT count(*) FROM phrase").fetchone()[0]
                tot += c.execute("SELECT count(*) FROM pinyin").fetchone()[0]
            for row in c.execute(q, args):
                k, val, wt, src = row
                self.rows.append((k, val, wt, src))
                self.store.append([str(k), str(val), str(wt), str(src)])
            c.close()
            self.total = tot
            maxp = max(0, (self.total - 1) // PAGE)
            label = ("「%s」 共 %d 条 · 第 %d/%d 页" % (self.term, self.total, self.page + 1, maxp + 1)) if self.term else \
                    ("全库共 %d 条 · 第 %d/%d 页" % (self.total, self.page + 1, maxp + 1))
            if not self.rows:
                label = "词库为空" if not self.term else "无匹配结果 — 换个拼音/词再搜"
            self.status.set_text(label)
            self._dbg(label)
        except Exception:
            self.status.set_text("查询出错: " + traceback.format_exc().splitlines()[-1])

    def _dbg(self, label):
        try:
            with open("/tmp/dict_status.txt", "w", encoding="utf-8") as f:
                f.write("status=" + label + "\nentry_text=" + self.search.get_text() + "\nterm=" + self.term + "\n")
        except Exception:
            pass

    def on_search(self, *a):
        self.term = self.search.get_text().strip()
        self.page = 0
        self.load()

    def turn(self, d):
        maxp = max(0, (self.total - 1) // PAGE)
        np = min(max(self.page + d, 0), maxp)
        if np != self.page:
            self.page = np; self.load()

    def on_row_sel(self, sel):
        m, it = sel.get_selected()
        if not it: return
        self.e_word.set_text(m[it][1])
        self.e_py.set_text(m[it][0])
        self.e_wt.set_text(m[it][2])

    def on_save(self, *a):
        w = self.e_word.get_text().strip()
        p = self.e_py.get_text().strip().lower()
        if not w or not p:
            self.status.set_text("词语和拼音都要填"); return
        try:
            wt = int(self.e_wt.get_text().strip() or "0")
            if wt < 0: raise ValueError()
        except ValueError:
            self.status.set_text("词频须为非负整数"); return
        try:
            c = self.conn(False)
            # upsert 主库 phrase(词条) 与 pinyin(拼音)
            for t in ("phrase", "pinyin"):
                ex = c.execute("SELECT weight FROM %s WHERE key=? AND value=?" % t, (p, w)).fetchone()
                if ex:
                    c.execute("UPDATE %s SET weight=? WHERE key=? AND value=?" % t, (wt, p, w))
                else:
                    c.execute("INSERT INTO %s(jp,key,value,weight) VALUES(?,?,?,?)" % t, (p, p, w, wt))
            c.commit(); c.close()
            self.status.set_text("已保存: %s (%s)" % (w, p))
            self.load()
        except Exception:
            self.status.set_text("保存出错: " + traceback.format_exc().splitlines()[-1])

    def on_delete(self, *a):
        m, it = self.view.get_selection().get_selected()
        if not it:
            self.status.set_text("先选中一行"); return
        key, val = m[it][0], m[it][1]
        src = m[it][3]
        dlg = Gtk.MessageDialog(parent=self, flags=Gtk.DialogFlags.MODAL,
                                message_type=Gtk.MessageType.WARNING,
                                buttons=Gtk.ButtonsType.OK_CANCEL,
                                text="删除主库词条")
        dlg.format_secondary_text("确定从 %s 删除「%s」(%s)?此操作直接改主库文件。" % (src, val, key))
        r = dlg.run(); dlg.destroy()
        if r != Gtk.ResponseType.OK: return
        try:
            c = self.conn(False)
            n = 0
            for t in ("phrase", "pinyin", "wubi86"):
                n += c.execute("DELETE FROM %s WHERE key=? AND value=?" % t, (key, val)).rowcount
            c.commit(); c.close()
            # 删空本页且非第0页则回退
            if self.page > 0 and len(self.rows) <= 1: self.page -= 1
            self.status.set_text("已删除: %s (%s), %d 行" % (val, key, n))
            self.load()
        except Exception:
            self.status.set_text("删除出错: " + traceback.format_exc().splitlines()[-1])

win = DictWin()
win.show_all()
Gtk.main()
