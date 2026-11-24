"""python3 tests/test_claudito.py"""
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True   # new files in the plugin folder reload the shell

import tempfile
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import activity  # noqa: E402
import seasons  # noqa: E402

HOOK = os.path.join(ROOT, "claudito-hook")
NOW = 1_000_000.0
MARKUP = "/usr/share/omarchy/shell/plugins/notifications/Markup.js"
BASH = {"tool_name": "Bash", "tool_input": {"command": "make", "description": "Build"}}
GREP = {"tool_name": "Grep", "tool_input": {"pattern": "x"}}


class Hook(unittest.TestCase):
    """Runs the real hook in a process of its own, in an empty folder."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = tmp.name
        self.env = {**os.environ, "XDG_RUNTIME_DIR": self.dir}

    def send(self, event, **fields):
        ev = {"hook_event_name": event, "session_id": "s", "cwd": "/x/proj", **fields}
        self.run_hook(json.dumps(ev).encode())
        return self.state()

    def run_hook(self, data):
        r = subprocess.run([sys.executable, HOOK], input=data, env=self.env, capture_output=True, timeout=20)
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, b"", b""))

    def state(self):
        try:
            with open(os.path.join(self.dir, "claudito", "state.json"), encoding="utf-8") as f:
                return json.load(f)["sessions"]["s"]
        except FileNotFoundError:
            return {}

    def test_idle_notification_is_not_waiting(self):
        self.send("Stop")
        s = self.send("Notification", notification_type="idle_prompt", message="Claude is waiting for your input")
        self.assertEqual(s["mode"], "done")

    def test_idle_notification_without_type(self):
        self.send("Stop")
        self.assertEqual(self.send("Notification", message="Claude is waiting for your input")["mode"], "done")
        self.assertEqual(self.send("Notification", message="Claude needs your permission")["mode"], "waiting")

    def test_informative_notifications(self):
        self.send("UserPromptSubmit")
        for kind in ("auth_success", "agent_completed", "something_new"):
            self.assertEqual(self.send("Notification", notification_type=kind)["mode"], "thinking")

    def test_permission(self):
        self.send("PreToolUse", **BASH)
        s = self.send("PermissionRequest", **BASH)
        self.assertEqual((s["mode"], s["tool"], s["detail"], s["resume"]), ("waiting", "Bash", "Build", "terminal"))
        again = self.send("Notification", notification_type="permission_prompt", message="Claude needs permission")
        self.assertEqual(again, s)   # the reminder changes nothing
        self.assertEqual(self.send("PostToolUse", **BASH)["mode"], "thinking")

    def test_late_pretooluse_does_not_hide_permission(self):
        self.send("PermissionRequest", **BASH)
        self.assertEqual(self.send("PreToolUse", **BASH)["mode"], "waiting")

    def test_parallel_tool_does_not_hide_permission(self):
        self.send("PermissionRequest", **BASH)
        self.assertEqual(self.send("PostToolUse", **GREP)["mode"], "waiting")

    def test_subagent_does_not_hide_permission(self):
        self.send("PermissionRequest", **BASH)
        self.assertEqual(self.send("PreToolUse", agent_id="a1", **GREP)["mode"], "waiting")
        self.assertEqual(self.send("PreToolUse", **GREP)["mode"], "search")   # you said no; it went on

    def test_stop_and_prompt_always_win(self):
        self.send("PermissionRequest", agent_id="a1", **BASH)
        self.assertEqual(self.send("UserPromptSubmit")["mode"], "thinking")
        self.send("PermissionRequest", agent_id="a1", **BASH)
        self.assertEqual(self.send("Stop")["mode"], "done")

    def test_answered_question(self):
        q = {"tool_name": "AskUserQuestion", "tool_input": {"questions": []}}
        self.assertEqual(self.send("PreToolUse", **q)["mode"], "waiting")
        self.assertEqual(self.send("PostToolUse", **q)["mode"], "thinking")

    def test_turn_is_kept(self):
        turn = self.send("UserPromptSubmit")["turn"]
        self.send("PreToolUse", **GREP)
        self.assertEqual(self.send("Stop")["turn"], turn)


    def project(self, cwd, root=None):
        self.env.pop("CLAUDE_PROJECT_DIR", None)
        if root:
            self.env["CLAUDE_PROJECT_DIR"] = root
        return self.send("PreToolUse", **{**GREP, "cwd": cwd})["project"]

    def test_project_is_where_the_session_started(self):
        a = os.path.join(self.dir, "proj")
        os.makedirs(os.path.join(a, "src", "deep"))
        self.assertEqual(self.project(a, root=a), "proj")
        self.assertEqual(self.project(os.path.join(a, "src", "deep"), root=a), "proj")
        self.assertEqual(self.project(a + os.sep), "proj")   # older Claude Code: no variable

    def test_project_of_a_session_started_at_home(self):
        home = os.path.join(self.dir, "someone")
        repo, other = os.path.join(home, "src", "repo"), os.path.join(home, "notes")
        os.makedirs(os.path.join(repo, ".git"))
        os.makedirs(os.path.join(repo, "sub"))
        os.makedirs(other)
        os.makedirs(os.path.join(home, ".git"))   # dotfiles in git: not a project
        self.env.update(HOME=home)
        self.assertEqual(self.project(home, root=home), "someone")
        self.assertEqual(self.project(os.path.join(repo, "sub"), root=home), "repo")
        self.assertEqual(self.project(other, root=home), "repo")   # it stays
        self.assertEqual(self.project(home, root=home), "repo")

    def log(self):
        try:
            with open(os.path.join(self.dir, "claudito", "hook.log"), encoding="utf-8") as f:
                return f.read()
        except FileNotFoundError:
            return ""

    def test_errors_are_logged_without_the_event(self):
        self.send("Stop")
        self.assertEqual(self.log(), "")
        self.run_hook(b'{"secret-thing": ')
        self.run_hook(b'["secret-thing"]')
        self.assertIn("JSONDecodeError", self.log())
        self.assertIn("AttributeError", self.log())
        self.assertNotIn("secret-thing", self.log())


class StatusLine(unittest.TestCase):
    def test_many_at_once(self):
        with tempfile.TemporaryDirectory() as d:
            folder = os.path.join(d, "claudito")
            os.makedirs(folder)
            stale = os.path.join(folder, ".statusline-old.tmp")
            open(stale, "w").close()
            os.utime(stale, (time.time() - 600,) * 2)
            env = {**os.environ, "XDG_RUNTIME_DIR": d}
            script = os.path.join(ROOT, "claudito-statusline")
            running = [subprocess.Popen([sys.executable, script], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, env=env) for _ in range(12)]
            for i, p in enumerate(running):
                p.stdin.write(json.dumps({"session_id": str(i), "model": {"display_name": "M"}, "pad": "x" * 50_000}).encode())
                p.stdin.close()
            for p in running:
                self.assertEqual((p.stdout.read().strip(), p.stderr.read(), p.wait(20)), (b"M", b"", 0))
                p.stdout.close()
                p.stderr.close()
            self.assertEqual(os.listdir(folder), ["statusline.json"])
            with open(os.path.join(folder, "statusline.json"), encoding="utf-8") as f:
                self.assertEqual(len(json.load(f)["pad"]), 50_000)


class Watch(unittest.TestCase):
    def test_follows_and_cleans_up(self):
        with tempfile.TemporaryDirectory() as d:
            folder = os.path.join(d, "claudito")
            env = {**os.environ, "XDG_RUNTIME_DIR": d, "CLAUDE_CONFIG_DIR": os.path.join(d, "none")}
            view = os.path.join(folder, "view.json")
            p = subprocess.Popen([sys.executable, os.path.join(ROOT, "claudito-watch")], env=env,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                def wait(mode):
                    for _ in range(50):
                        try:
                            with open(view, encoding="utf-8") as f:
                                v = json.load(f)
                            if v["mode"] == mode:
                                return v
                        except FileNotFoundError:
                            pass
                        time.sleep(0.1)
                    self.fail("never " + mode)

                self.assertIn(wait("sleep")["season"], seasons.SEASONS)
                subprocess.run([sys.executable, HOOK], env=env, check=True, input=json.dumps(
                    {"hook_event_name": "PreToolUse", "session_id": "s", "cwd": "/x/proj", **BASH}).encode())
                v = wait("terminal")
                self.assertEqual((v["detail"], v["project"]), ("Build", "proj"))
            finally:
                p.terminate()
                out, err = p.communicate(timeout=10)
            self.assertEqual((p.returncode, out, err), (0, b"", b""))
            self.assertFalse(os.path.exists(view))


class SessionMode(unittest.TestCase):
    def mode(self, mode, age, status=None, since=None, **kw):
        live = {"status": status, "since": NOW - since} if status else None
        extra = {k: kw.pop(k) for k in ("resume",) if k in kw}
        return activity.session_mode({"mode": mode, "ts": NOW - age, **extra}, NOW, live, **kw)

    def test_accepted_permission(self):
        self.assertEqual(self.mode("waiting", 20, "waiting", 19.9, resume="terminal"), "waiting")
        self.assertEqual(self.mode("waiting", 20, "busy", 5, resume="terminal"), "terminal")

    def test_stale_busy_is_not_an_answer(self):
        self.assertEqual(self.mode("waiting", 5, "busy", 60), "waiting")

    def test_rejected_or_escaped(self):
        self.assertEqual(self.mode("waiting", 20, "idle", 5), "idle")
        self.assertEqual(self.mode("thinking", 20, "idle", 5), "idle")
        self.assertEqual(self.mode("terminal", 900, "idle", 700), "sleep")

    def test_idle_just_before_stop_does_not_flicker(self):
        self.assertEqual(self.mode("thinking", 3, "idle", 0.5), "thinking")
        self.assertEqual(self.mode("waiting", 3, "idle", 0.5), "waiting")
        self.assertEqual(self.mode("thinking", 3, "idle", 1.6), "idle")

    def test_waiting_expires(self):
        self.assertEqual(self.mode("waiting", 1700), "waiting")
        self.assertEqual(self.mode("waiting", 1900), "sleep")
        self.assertEqual(self.mode("waiting", 9000, "waiting", 9000), "waiting")   # still there
        self.assertEqual(self.mode("waiting", 5, gone=True), "sleep")

    def test_long_tool(self):
        self.assertEqual(self.mode("terminal", 2000), "sleep")
        self.assertEqual(self.mode("terminal", 2000, "busy", 2100), "terminal")

    def test_ages(self):
        for mode, age, want in (("done", 3, "done"), ("done", 60, "idle"), ("done", 700, "sleep"),
                                ("wake", 1, "wake"), ("wake", 60, "idle"),
                                ("oops", 1, "oops"), ("oops", 10, "thinking"), ("sleep", 0, "sleep")):
            self.assertEqual(self.mode(mode, age), want, (mode, age))


class Tracker(unittest.TestCase):
    def show(self, t, now=NOW, registry=None, **sessions):
        return t.update(json.dumps({"sessions": sessions}), registry, now)[0]

    def test_desktop_session(self):
        s = {"mode": "waiting", "ts": NOW}
        live = {"status": "waiting", "since": NOW}
        self.assertTrue(self.show(activity.Tracker(), registry={"a": {**live, "desktop": True}}, a=s)["desktop"])
        self.assertFalse(self.show(activity.Tracker(), registry={"a": live}, a=s)["desktop"])
        self.assertFalse(self.show(activity.Tracker(), a=s)["desktop"])

    def test_waiting_beats_newer_work(self):
        v = self.show(activity.Tracker(), a={"mode": "waiting", "ts": NOW - 60, "project": "p"},
                      b={"mode": "build", "ts": NOW})
        self.assertEqual((v["mode"], v["project"]), ("waiting", "p"))

    def test_work_beats_idle(self):
        v = self.show(activity.Tracker(), a={"mode": "build", "ts": NOW - 60}, b={"mode": "done", "ts": NOW - 30})
        self.assertEqual(v["mode"], "build")

    def test_hat_gap(self):
        t = activity.Tracker()
        self.show(t, a={"mode": "build", "detail": "f", "ts": NOW - 1})
        self.assertEqual(self.show(t, a={"mode": "thinking", "ts": NOW})["mode"], "build")
        self.assertEqual(self.show(t, now=NOW + 2, a={"mode": "thinking", "ts": NOW})["mode"], "thinking")

    def test_closed_terminal(self):
        t = activity.Tracker()
        live = {"a": {"status": "waiting", "since": NOW}}
        s = {"mode": "waiting", "ts": NOW}
        self.assertEqual(self.show(t, registry=live, a=s)["mode"], "waiting")
        self.assertEqual(self.show(t, now=NOW + 1, registry={}, a=s)["mode"], "waiting")   # a blip
        self.assertEqual(self.show(t, now=NOW + 6, registry={}, a=s)["mode"], "sleep")

    def test_never_registered_is_not_closed(self):
        v = self.show(activity.Tracker(), registry={}, a={"mode": "build", "ts": NOW})
        self.assertEqual(v["mode"], "build")

    def test_bad_files(self):
        t = activity.Tracker()
        self.show(t, a={"mode": "build", "ts": NOW})
        self.assertEqual(t.update('{"sess', None, NOW)[0]["mode"], "build")
        self.assertEqual(t.update("[]", None, NOW)[0]["mode"], "build")
        self.assertEqual(t.update("", None, NOW)[0]["mode"], "sleep")
        self.assertEqual(t.update('{"sessions": {"a": 3, "b": {"ts": "x"}}}', None, NOW)[0]["mode"], "sleep")


class Registry(unittest.TestCase):
    def test_read(self):
        with tempfile.TemporaryDirectory() as d:
            def put(name, text):
                with open(os.path.join(d, name), "w", encoding="utf-8") as f:
                    f.write(text)
            put("1.json", json.dumps({"sessionId": "a", "status": "busy", "statusUpdatedAt": 5000}))
            put("2.json", json.dumps({"sessionId": "dead", "status": "busy"}))
            put("3.json", "{half")
            put("4.json", "[]")
            put("5.secret.key", "x")
            got = activity.read_registry(d, alive=lambda pid, started: pid != 2)
            self.assertEqual(got, {"a": {"status": "busy", "since": 5.0, "desktop": False}})
            put("1.json", json.dumps({"sessionId": "a", "entrypoint": "claude-desktop"}))
            self.assertTrue(activity.read_registry(d, alive=lambda pid, started: pid == 1)["a"]["desktop"])
        self.assertIsNone(activity.read_registry(os.path.join(d, "nope")))

    def test_process_alive(self):
        self.assertTrue(activity.process_alive(os.getpid()))
        p = subprocess.Popen([sys.executable, "-c", ""])
        p.wait()
        self.assertFalse(activity.process_alive(p.pid))
        self.assertFalse(activity.process_alive(os.getpid(), "1"))   # reused pid
        with open("/proc/self/stat") as f:
            started = f.read().rpartition(")")[2].split()[19]
        self.assertTrue(activity.process_alive(os.getpid(), started))

    def test_other_machine(self):
        ns = os.readlink("/proc/self/ns/pid")
        self.assertFalse(activity.other_machine("linux:abc:" + ns))
        self.assertTrue(activity.other_machine("linux:abc:pid:[1]"))
        self.assertFalse(activity.other_machine(None))


class Notify(unittest.TestCase):
    def view(self, mode, ts, turn=0):
        return {"s": {"mode": mode, "ts": ts, "turn": turn, "tool": "", "detail": "", "project": ""}}

    def test_waiting_once_after_a_while(self):
        n = activity.Notifier(NOW)
        v = self.view("waiting", NOW + 1)
        self.assertEqual(n.update(v, NOW + 1), [])
        self.assertEqual(n.update(v, NOW + 5), [])
        self.assertEqual([x[0] for x in n.update(v, NOW + 6)], ["waiting"])
        self.assertEqual(n.update(v, NOW + 60), [])

    def test_desktop_app_permissions(self):
        """The app has its own notifications for permissions, not for the rest."""
        for desktop, tool, told in ((True, "PowerShell", False), (True, "AskUserQuestion", True),
                                    (True, "ExitPlanMode", True), (True, "", True), (False, "PowerShell", True)):
            n = activity.Notifier(NOW)
            v = self.view("waiting", NOW + 1)
            v["s"].update(desktop=desktop, tool=tool)
            n.update(v, NOW + 1)
            self.assertEqual(bool(n.update(v, NOW + 9)), told, (desktop, tool))
        n = activity.Notifier(NOW)
        v = self.view("done", NOW + 200, NOW + 100)
        v["s"]["desktop"] = True
        self.assertEqual(len(n.update(v, NOW + 200)), 1)

    def test_answered_at_once(self):
        n = activity.Notifier(NOW)
        n.update(self.view("waiting", NOW + 1), NOW + 1)
        n.update(self.view("terminal", NOW + 1), NOW + 3)
        self.assertEqual(n.update(self.view("terminal", NOW + 1), NOW + 9), [])

    def test_nothing_about_the_past(self):
        n = activity.Notifier(NOW)
        n.update(self.view("waiting", NOW - 100), NOW)
        self.assertEqual(n.update(self.view("waiting", NOW - 100), NOW + 30), [])
        self.assertEqual(n.update(self.view("done", NOW - 2, NOW - 900), NOW), [])

    def test_only_long_tasks(self):
        n = activity.Notifier(NOW)
        self.assertEqual(n.update(self.view("done", NOW + 30, NOW + 1), NOW + 30), [])
        got = n.update(self.view("done", NOW + 200, NOW + 100), NOW + 200)
        self.assertEqual([(k, s) for k, _, s in got], [("done", 100)])
        self.assertEqual(n.update(self.view("done", NOW + 200, NOW + 100), NOW + 201), [])


@unittest.skipUnless(shutil.which("node") and os.path.exists(MARKUP), "needs node and Omarchy")
class NotificationText(unittest.TestCase):
    def test_no_markup_survives(self):
        """Through Omarchy's own rendering of notification bodies."""
        script = '''
          const fs = require("fs"), vm = require("vm");
          const load = f => fs.readFileSync(f, "utf8").replace(/^\\.(pragma|import).*$/gm, "");
          const ctx = {Security: {}};
          vm.createContext(ctx);
          vm.createContext(ctx.Security);
          vm.runInContext(load(process.argv[1].replace("Markup", "Security")), ctx.Security);
          vm.runInContext(load(process.argv[1]), ctx);
          vm.runInContext(load(process.argv[2]), ctx);
          const bad = ["<b>x</b>", "&lt;b&gt;x", "&amp;lt;b&amp;gt;x", "<br/>", "<u>x</u>"];
          console.log(JSON.stringify(bad.map(t => [ctx.render(t), ctx.render(ctx.plain(t))])));
        '''
        r = subprocess.run(["node", "-e", script, MARKUP, os.path.join(ROOT, "code", "plain.js")],
                           capture_output=True, text=True)
        self.assertEqual(r.stderr, "")
        tag = re.compile(r"<\w")
        for raw, plain in json.loads(r.stdout):
            self.assertRegex(raw, tag)   # or this test proves nothing
            self.assertNotRegex(plain, tag)


class Seasons(unittest.TestCase):
    def test_dates(self):
        for month, day, want in ((1, 1, "winter"), (3, 19, "winter"), (3, 20, "spring"), (6, 20, "spring"),
                                 (6, 21, "summer"), (9, 21, "summer"), (9, 22, "autumn"), (11, 23, "autumn"),
                                 (12, 20, "autumn"), (12, 21, "winter"), (12, 31, "winter"), (2, 29, "winter")):
            self.assertEqual(seasons.season_on(dt.date(2028, month, day)), want, (month, day))

    def test_south(self):
        self.assertEqual(seasons.season_on(dt.date(2026, 11, 23), southern=True), "spring")
        self.assertEqual(seasons.season_on(dt.date(2026, 1, 1), southern=True), "summer")
        self.assertIn("AR", seasons.SOUTHERN)
        self.assertNotIn("MX", seasons.SOUTHERN)

    def test_country(self):
        self.assertEqual(seasons.country("America/Mexico_City"), "MX")
        self.assertEqual(seasons.country("Australia/Sydney"), "AU")
        old = {k: os.environ.pop(k, None) for k in ("LC_ALL", "LC_TIME", "LANG")}
        try:
            os.environ["LANG"] = "es_CL.UTF-8"
            self.assertEqual(seasons.country("UTC"), "CL")
            self.assertEqual(seasons.country("", "/nonexistent"), "CL")
            os.environ["LANG"] = "C"
            self.assertEqual(seasons.country(""), "")
        finally:
            os.environ.pop("LANG")
            os.environ.update({k: v for k, v in old.items() if v is not None})

    def test_mini_sprites(self):
        """The same for the bar icon, 16 wide and ending on the right row."""
        with open(os.path.join(ROOT, "code", "mini.js"), encoding="utf-8") as f:
            hats, outfits = f.read().split("var OUTFITS")
        for part, top, last in ((hats, -3, 0), (outfits, 8, 10)):
            for season in seasons.SEASONS:
                m = re.search(r"\n  %s: \{(.*?)\n  \}" % season, part, re.S)
                self.assertTrue(m, season)
                colors = set(re.findall(r"(\w): \"#", m[1]))
                rows = re.findall(r'^ +"([^"]+)",?$', m[1], re.M)
                self.assertEqual({len(r) for r in rows}, {16}, season)
                self.assertEqual(top + len(rows) - 1, last, season)
                self.assertLessEqual(set("".join(rows)) - {"."}, colors, season)

    def test_sprites(self):
        """Every season has a hat and an outfit, with even rows and known colors."""
        path = os.path.join(ROOT, "code", "sprites.js")
        with open(path, encoding="utf-8") as f:
            text = f.read()
        hats, outfits = text.split("var OUTFITS")
        for part in (hats, outfits.split("\n}\n")[0]):
            for season in seasons.SEASONS:
                m = re.search(r"\n  %s: \{(.*?)\n  \}" % season, part, re.S)
                self.assertTrue(m, season)
                colors = set(re.findall(r"(\w): \"#", m[1].split("palette", 1)[1]))
                rows = re.findall(r'^ +"([^"]+)",?$', m[1], re.M)
                self.assertTrue(rows)
                self.assertEqual({len(r) for r in rows}, {26}, season)
                self.assertLessEqual(set("".join(rows)) - {"."}, colors, season)


if __name__ == "__main__":
    unittest.main()
