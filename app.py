#!/usr/bin/env python3
"""Private local backend for the GitHub SSH menu-bar app."""

import argparse
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid
from datetime import datetime
from pathlib import Path


SSH_DIR = Path.home() / ".ssh"
PROFILES_DIR = SSH_DIR / "github-accounts"
BACKUPS_DIR = PROFILES_DIR / ".backups"
ACTIVE_PRIVATE = SSH_DIR / "id_rsa"
ACTIVE_PUBLIC = SSH_DIR / "id_rsa.pub"
ASKPASS = Path(__file__).with_name("askpass.sh")


def tr(english):
    if not os.environ.get("GITHUB_KEY_SWITCHER_LANGUAGE", "en").startswith("zh"):
        return english
    try:
        catalog = json.loads(Path(__file__).with_name("locales.json").read_text(encoding="utf-8"))
        return catalog.get("zh", {}).get(english, english)
    except (OSError, ValueError, TypeError):
        return english


def safe_name(value):
    name = value.strip()
    if (not name or name in (".", "..") or name.startswith(".") or len(name) > 64
            or any(ord(c) < 32 or c in "/\\:" for c in name)):
        raise ValueError(tr("Name must be 1–64 characters, cannot start with a dot, and cannot contain path separators."))
    return name


def public_identity(data):
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return None
    for line in text.splitlines():
        fields = line.split()
        for i, field in enumerate(fields[:-1]):
            if field.startswith(("ssh-", "ecdsa-", "sk-")):
                return field + " " + fields[i + 1]
    return None


def public_email(data):
    try:
        lines = data.decode("utf-8").splitlines()
    except UnicodeDecodeError:
        return ""
    for line in lines:
        fields = line.split()
        if len(fields) < 3 or not fields[0].startswith(("ssh-", "ecdsa-", "sk-")):
            continue
        comment = " ".join(fields[2:])
        if re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", comment):
            return comment
    return ""


def verify_pair(private, public_data):
    env = os.environ.copy()
    env["SSH_ASKPASS"] = str(ASKPASS)
    env["SSH_ASKPASS_REQUIRE"] = "force"
    env.setdefault("DISPLAY", ":0")
    try:
        result = subprocess.run(
            ["/usr/bin/ssh-keygen", "-y", "-f", str(private)], stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=120, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError(f"{tr('Could not run ssh-keygen to validate the key')}: {exc}") from exc
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", "replace").strip()
        raise RuntimeError(tr("Could not read the private key, or its passphrase was incorrect.") + (f"\n{detail}" if detail else ""))
    if public_identity(result.stdout) != public_identity(public_data) or not public_identity(public_data):
        raise RuntimeError(tr("The public and private keys do not match; nothing was imported or switched."))


def github_username(private):
    env = os.environ.copy()
    env["SSH_ASKPASS"] = str(ASKPASS)
    env["SSH_ASKPASS_REQUIRE"] = "force"
    env.setdefault("DISPLAY", ":0")
    try:
        result = subprocess.run(
            ["/usr/bin/ssh", "-T", "-i", str(private), "-o", "IdentitiesOnly=yes",
             "-o", "StrictHostKeyChecking=yes", "git@github.com"],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env=env, timeout=45, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError(f"{tr('Could not contact GitHub over SSH')}: {exc}") from exc
    output = (result.stdout + result.stderr).decode("utf-8", "replace")
    match = re.search(r"(?:^|\n)Hi ([^!\r\n]+)! You've successfully authenticated", output)
    if match:
        return match.group(1).strip()
    detail = output.strip()
    if "Host key verification failed" in detail or "No ED25519 host key is known" in detail:
        raise RuntimeError(tr("GitHub's SSH host key is not trusted yet. Run `ssh -T git@github.com` in Terminal, verify its fingerprint, then try again."))
    raise RuntimeError(tr("GitHub did not identify an account for this key. Make sure the key is added to GitHub.\n") +
                        (detail[-1200:] if detail else tr("SSH returned no authentication message.")))


def secure_write(path, data, mode):
    fd, temp_name = tempfile.mkstemp(prefix="." + path.name + ".", dir=str(path.parent))
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, path)
    except Exception:
        try:
            os.unlink(temp_name)
        except OSError:
            pass
        raise


def import_pair(name, private, public):
    name = safe_name(name)
    private_data, public_data = Path(private).read_bytes(), Path(public).read_bytes()
    verify_pair(Path(private), public_data)
    PROFILES_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(PROFILES_DIR, 0o700)
    target = PROFILES_DIR / name
    if target.exists():
        raise RuntimeError(tr("An account named '{name}' already exists. Choose another name.").format(name=name))
    target.mkdir(mode=0o700)
    try:
        secure_write(target / "id_rsa", private_data, 0o600)
        secure_write(target / "id_rsa.pub", public_data, 0o644)
    except Exception:
        shutil.rmtree(target, ignore_errors=True)
        raise


def read_global_identity():
    values = {}
    for key in ("user.name", "user.email"):
        result = subprocess.run(["git", "config", "--global", "--get", key],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
        values[key.rsplit(".", 1)[1]] = result.stdout.decode("utf-8", "replace").strip() if result.returncode == 0 else ""
    return values


def profile_identity(profile):
    try:
        data = json.loads((profile / "git-identity.json").read_text(encoding="utf-8"))
        return {"name": str(data.get("name", "")), "email": str(data.get("email", "")),
                "verified": bool(data.get("github_verified", False))}
    except (OSError, ValueError, TypeError):
        return None


def save_profile_identity(profile, name, email):
    name, email = name.strip(), email.strip()
    if not name:
        raise RuntimeError(tr("GitHub username cannot be empty."))
    secure_write(profile / "git-identity.json",
                 json.dumps({"name": name, "email": email, "github_verified": True}, ensure_ascii=False).encode("utf-8"), 0o600)


def set_global_identity(name, email):
    old = read_global_identity()
    changes = [("user.name", name, "name")]
    if email:
        changes.append(("user.email", email, "email"))
    try:
        for key, value, _ in changes:
            result = subprocess.run(["git", "config", "--global", key, value],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
            if result.returncode:
                detail = result.stderr.decode("utf-8", "replace").strip()
                raise RuntimeError(detail or tr("Could not update global {key}.").format(key=key))
    except Exception:
        for key, _, field in changes:
            subprocess.run(["git", "config", "--global", "--unset-all", key],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            if old[field]:
                subprocess.run(["git", "config", "--global", key, old[field]],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        raise


def profiles():
    if not PROFILES_DIR.is_dir():
        return []
    return sorted((p for p in PROFILES_DIR.iterdir() if not p.name.startswith(".") and p.is_dir()
                   and (p / "id_rsa").is_file() and (p / "id_rsa.pub").is_file()),
                  key=lambda p: p.name.casefold())


def active_name():
    try:
        current = public_identity(ACTIVE_PUBLIC.read_bytes())
        for profile in profiles():
            if current and public_identity((profile / "id_rsa.pub").read_bytes()) == current:
                return profile.name
    except OSError:
        pass
    return None


def reject_symlink(path):
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        return
    if stat.S_ISLNK(mode):
        raise RuntimeError(tr("{path} is a symbolic link. Resolve it manually to avoid overwriting its target.").format(path=path))
    if not stat.S_ISREG(mode):
        raise RuntimeError(tr("{path} is not a regular file; switching was stopped.").format(path=path))


def restore(destination, backup, existed):
    if existed and backup:
        staged = SSH_DIR / (".restore-" + uuid.uuid4().hex + ".tmp")
        shutil.copyfile(backup, staged)
        os.chmod(staged, 0o600 if destination == ACTIVE_PRIVATE else 0o644)
        os.replace(staged, destination)
    else:
        destination.unlink(missing_ok=True)


def activate_profile(profile):
    private, public = profile / "id_rsa", profile / "id_rsa.pub"
    private_data, public_data = private.read_bytes(), public.read_bytes()
    verify_pair(private, public_data)
    identity = profile_identity(profile) or {}
    if identity.get("verified") and identity.get("name"):
        username = identity["name"]
        email = identity.get("email", "").strip()
    else:
        username = github_username(private)
        email = public_email(public_data) or identity.get("email", "").strip()
        save_profile_identity(profile, username, email)
    SSH_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    reject_symlink(ACTIVE_PRIVATE)
    reject_symlink(ACTIVE_PUBLIC)
    had_private, had_public = ACTIVE_PRIVATE.exists(), ACTIVE_PUBLIC.exists()
    backup = None
    if had_private or had_public:
        BACKUPS_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(PROFILES_DIR, 0o700)
        backup = BACKUPS_DIR / (datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
        backup.mkdir(mode=0o700)
        try:
            if had_private:
                shutil.copyfile(ACTIVE_PRIVATE, backup / "id_rsa")
                os.chmod(backup / "id_rsa", 0o600)
            if had_public:
                shutil.copyfile(ACTIVE_PUBLIC, backup / "id_rsa.pub")
                os.chmod(backup / "id_rsa.pub", 0o644)
        except Exception:
            shutil.rmtree(backup, ignore_errors=True)
            raise
    token = uuid.uuid4().hex
    staged_private, staged_public = SSH_DIR / (".id_rsa-" + token + ".tmp"), SSH_DIR / (".id_rsa.pub-" + token + ".tmp")
    try:
        secure_write(staged_private, private_data, 0o600)
        secure_write(staged_public, public_data, 0o644)
        os.replace(staged_private, ACTIVE_PRIVATE)
        try:
            os.replace(staged_public, ACTIVE_PUBLIC)
        except Exception:
            restore(ACTIVE_PRIVATE, backup / "id_rsa" if backup and had_private else None, had_private)
            restore(ACTIVE_PUBLIC, backup / "id_rsa.pub" if backup and had_public else None, had_public)
            raise
    except Exception as exc:
        staged_private.unlink(missing_ok=True)
        staged_public.unlink(missing_ok=True)
        where = f"\n{tr('Original key backup remains at: ')}{backup}" if backup else ""
        raise RuntimeError(f"{tr('Switch failed; rollback was attempted.')}{where}\n{exc}") from exc
    try:
        set_global_identity(username, email)
    except Exception as exc:
        restore(ACTIVE_PRIVATE, backup / "id_rsa" if backup and had_private else None, had_private)
        restore(ACTIVE_PUBLIC, backup / "id_rsa.pub" if backup and had_public else None, had_public)
        raise RuntimeError(f"{tr('Could not update the global Git identity; the SSH keys were rolled back:')}\n{exc}") from exc
    return str(backup) if backup else ""


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list")
    save = commands.add_parser("save-current")
    save.add_argument("name")
    imp = commands.add_parser("import")
    imp.add_argument("name")
    imp.add_argument("private")
    imp.add_argument("public")
    use = commands.add_parser("activate")
    use.add_argument("name")
    email = commands.add_parser("set-email")
    email.add_argument("name")
    email.add_argument("git_email")
    args = parser.parse_args()
    try:
        if args.command == "list":
            items = profiles()
            print(json.dumps({"profiles": [p.name for p in items], "active": active_name(),
                              "identities": {p.name: profile_identity(p) for p in items},
                              "global_identity": read_global_identity()}, ensure_ascii=False))
        elif args.command == "save-current":
            if not ACTIVE_PRIVATE.is_file() or not ACTIVE_PUBLIC.is_file():
                raise RuntimeError(tr("Both ~/.ssh/id_rsa and ~/.ssh/id_rsa.pub must exist."))
            import_pair(args.name, ACTIVE_PRIVATE, ACTIVE_PUBLIC)
            try:
                profile = PROFILES_DIR / safe_name(args.name)
                username = github_username(profile / "id_rsa")
                email = public_email((profile / "id_rsa.pub").read_bytes())
                save_profile_identity(profile, username, email)
            except Exception:
                shutil.rmtree(PROFILES_DIR / safe_name(args.name), ignore_errors=True)
                raise
            print(json.dumps({"ok": True, "name": safe_name(args.name), "github_username": username,
                              "email": email}, ensure_ascii=False))
        elif args.command == "import":
            import_pair(args.name, args.private, args.public)
            try:
                profile = PROFILES_DIR / safe_name(args.name)
                username = github_username(profile / "id_rsa")
                email = public_email((profile / "id_rsa.pub").read_bytes())
                save_profile_identity(profile, username, email)
            except Exception:
                shutil.rmtree(PROFILES_DIR / safe_name(args.name), ignore_errors=True)
                raise
            print(json.dumps({"ok": True, "name": safe_name(args.name), "github_username": username,
                              "email": email}, ensure_ascii=False))
        elif args.command == "set-email":
            if not (PROFILES_DIR / safe_name(args.name)).is_dir():
                raise RuntimeError(tr("Account profile not found."))
            if not args.git_email.strip():
                raise RuntimeError(tr("Git email cannot be empty."))
            profile = PROFILES_DIR / safe_name(args.name)
            username = github_username(profile / "id_rsa")
            save_profile_identity(profile, username, args.git_email)
            print(json.dumps({"ok": True, "name": safe_name(args.name), "github_username": username}, ensure_ascii=False))
        else:
            backup = activate_profile(PROFILES_DIR / safe_name(args.name))
            identity = profile_identity(PROFILES_DIR / safe_name(args.name)) or {}
            email = identity.get("email", "") or read_global_identity()["email"]
            print(json.dumps({"ok": True, "name": args.name, "backup": backup,
                              "github_username": identity.get("name", ""),
                              "email": email}, ensure_ascii=False))
    except Exception as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
