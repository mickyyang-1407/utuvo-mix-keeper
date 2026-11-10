#!/usr/bin/env python3
"""安裝／移除混音守門員的 hook。只增刪自己的項目，其他設定逐字保留。

用法：hooks.py install | uninstall | status
"""
import json, os, shutil, sys, tempfile, time

SETTINGS = os.path.expanduser("~/.claude/settings.json")
SCRIPT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "hooks/send-event.sh")
MARK = "hooks/send-event.sh"
EVENTS = {"Stop": "stop", "Notification": "notification", "PermissionRequest": "permission",
          "UserPromptSubmit": "submit", "SessionEnd": "end"}


def ours(cmd):
    # 認得「這份腳本的實際路徑」，或任何 mix-keeper 資料夾裡的同名腳本（換過資料夾也清得掉舊的）。
    # 也認得 App 自己裝的（~/Library/Application Support/MixKeeper/send-event.sh），兩邊才不會重複裝。
    return isinstance(cmd, str) and (SCRIPT in cmd or ("send-event.sh" in cmd and ("mix-keeper" in cmd.lower() or "MixKeeper" in cmd)))


def strip(hooks):
    removed = 0
    for event in list(hooks):
        kept_groups = []
        for group in hooks[event]:
            cmds = group.get("hooks", [])
            kept = [c for c in cmds if not ours(c.get("command"))]
            removed += len(cmds) - len(kept)
            if kept:
                kept_groups.append({**group, "hooks": kept})
        if kept_groups:
            hooks[event] = kept_groups
        else:
            del hooks[event]
    return removed


def write(settings, before):
    after = json.dumps(settings, ensure_ascii=False, indent=2) + "\n"
    if after == before:
        return False
    target = os.path.realpath(SETTINGS)
    backup = f"{target}.bak-mix-keeper-{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(target, backup)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(target))
    with os.fdopen(fd, "w") as f:
        f.write(after)
    os.chmod(tmp, os.stat(target).st_mode & 0o777)
    os.replace(tmp, target)
    print("backup:", backup)
    return True


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    before = open(SETTINGS, encoding="utf-8").read()
    settings = json.loads(before)
    hooks = settings.setdefault("hooks", {})
    if action == "status":
        print({e: sum(ours(c.get("command")) for g in v for c in g.get("hooks", [])) for e, v in hooks.items()})
        return
    removed = strip(hooks)
    if action == "install":
        for event, kind in EVENTS.items():
            command = f"/bin/sh '{SCRIPT}' {kind}"
            hooks.setdefault(event, []).append({"hooks": [{"type": "command", "command": command, "timeout": 5}]})
    elif action != "uninstall":
        sys.exit("用法：hooks.py install|uninstall|status")
    print(action, "removed", removed, "changed", write(settings, before))


if __name__ == "__main__":
    main()
