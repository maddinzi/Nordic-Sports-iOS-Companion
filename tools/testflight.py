"""Start the iOS TestFlight workflow and read its result from Windows, without the gh CLI.

    python -X utf8 tools/testflight.py start     start a run on main (uploads a TestFlight build: about 120 macOS minutes)
    python -X utf8 tools/testflight.py status    the newest runs: number, state, result, commit
    python -X utf8 tools/testflight.py wait      wait for the newest run, then print its result (and errors on failure)
    python -X utf8 tools/testflight.py errors [run_id]   the error lines of a failed run (default: the newest)

The GitHub login comes from git's credential manager (`git credential fill`, the same login `git push` uses). The
token only goes into the request header; it is never printed or written to a file. Start a run only when a device
test on the iPhone follows (docs/testflight-ci.md, "Actions budget"); the build number is the run number.
"""
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

REPO = "maddinzi/Nordic-Sports-iOS-Companion"
WORKFLOW = "ios-testflight.yml"
API = f"https://api.github.com/repos/{REPO}"


def token() -> str:
    out = subprocess.run(
        ["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n",
        capture_output=True, text=True, check=True,
    ).stdout
    for line in out.splitlines():
        if line.startswith("password="):
            return line[len("password="):]
    sys.exit("No GitHub login in git's credential manager (a git push to GitHub stores one).")


def request(path: str, method: str = "GET", body: dict | None = None, raw: bool = False):
    req = urllib.request.Request(
        f"{API}/{path}", method=method, data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {token()}", "Accept": "application/vnd.github+json"},
    )
    try:
        with urllib.request.urlopen(req) as resp:
            data = resp.read()
            if raw:
                return data.decode("utf-8", errors="replace")
            return json.loads(data) if data else resp.status
    except urllib.error.HTTPError as e:
        sys.exit(f"GitHub answered {e.code} for {method} {path}")


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def job_log(job_id: int) -> str:
    """A job's log: GitHub answers with a redirect to a short-lived storage link, fetched without the token (the
    storage refuses a request that carries it)."""
    req = urllib.request.Request(
        f"{API}/actions/jobs/{job_id}/logs",
        headers={"Authorization": f"Bearer {token()}", "Accept": "application/vnd.github+json"},
    )
    try:
        urllib.request.build_opener(_NoRedirect).open(req)
        sys.exit("GitHub sent no log link")
    except urllib.error.HTTPError as e:
        if e.code not in (301, 302, 303, 307, 308):
            sys.exit(f"GitHub answered {e.code} for the log of job {job_id}")
        link = e.headers["Location"]
    with urllib.request.urlopen(link) as resp:
        return resp.read().decode("utf-8", errors="replace")


def runs(count: int = 1) -> list:
    return request(f"actions/workflows/{WORKFLOW}/runs?per_page={count}")["workflow_runs"]


def line(r: dict) -> str:
    return f"run {r['run_number']} (id {r['id']}): {r['status']}, {r['conclusion'] or '-'}, {r['head_sha'][:7]}, {r['created_at']}"


def errors(run_id: int) -> None:
    jobs = request(f"actions/runs/{run_id}/jobs")["jobs"]
    failed = [j for j in jobs if j["conclusion"] == "failure"]
    if not failed:
        print("No failed job.")
        return
    for job in failed:
        steps = [s["name"] for s in job["steps"] if s["conclusion"] == "failure"]
        print(f"job {job['name']}: failed in {', '.join(steps) or '?'}")
        log = job_log(job["id"])
        found = sorted({re.sub(r"^\S+Z ", "", l).strip() for l in log.splitlines() if "error:" in l})
        if found:
            print("\n".join(found[:40]))
        else:
            print("No 'error:' lines; the last lines of the log:")
            print("\n".join(log.splitlines()[-40:]))


def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "start":
        status = request(f"actions/workflows/{WORKFLOW}/dispatches", "POST", {"ref": "main"})
        print("started" if status == 204 else f"unexpected answer {status}")
    elif cmd == "status":
        for r in runs(3):
            print(line(r))
    elif cmd == "wait":
        time.sleep(20)  # a run just started shows up after a few seconds
        while True:
            r = runs()[0]
            if r["status"] == "completed":
                print(line(r))
                if r["conclusion"] != "success":
                    errors(r["id"])
                return
            time.sleep(60)
    elif cmd == "errors":
        errors(int(sys.argv[2]) if len(sys.argv) > 2 else runs()[0]["id"])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
