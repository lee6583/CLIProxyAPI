#!/usr/bin/env python3
import argparse
import json
import sys
import urllib.request
import urllib.error


def _request(url: str, method: str = "GET", headers=None, payload=None, timeout=20):
    req = urllib.request.Request(url=url, method=method)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, data=data, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return resp.status, body
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace") if e.fp else ""
        return e.code, body


def main() -> int:
    ap = argparse.ArgumentParser(description="Verify CLIProxyAPI account and model availability")
    ap.add_argument("--base-url", required=True, help="CLIProxyAPI base url, e.g. https://cliproxyapi-hbg5.onrender.com")
    ap.add_argument("--management-key", required=True, help="management key for /v0/management")
    ap.add_argument("--api-key", required=True, help="client api key for /v1/*")
    ap.add_argument("--model", default="gpt-5.3-codex", help="model to verify")
    ap.add_argument("--timeout", type=int, default=20)
    args = ap.parse_args()

    base = args.base_url.rstrip("/")

    st, body = _request(
        f"{base}/v0/management/auth-files?is_webui=1",
        headers={"Authorization": f"Bearer {args.management_key}"},
        timeout=args.timeout,
    )
    if st != 200:
        print(f"[FAIL] auth-files status={st} body={body[:300]}")
        return 1
    try:
        files = json.loads(body).get("files", [])
    except Exception as e:
        print(f"[FAIL] auth-files json parse error: {e}")
        return 1
    print(f"[OK] auth-files count={len(files)}")

    st, body = _request(
        f"{base}/v1/models",
        headers={"Authorization": f"Bearer {args.api_key}"},
        timeout=args.timeout,
    )
    if st != 200:
        print(f"[FAIL] /v1/models status={st} body={body[:300]}")
        return 1

    model_ids = []
    try:
        model_ids = [m.get("id", "") for m in json.loads(body).get("data", []) if isinstance(m, dict)]
    except Exception as e:
        print(f"[FAIL] /v1/models json parse error: {e}")
        return 1

    if args.model not in model_ids:
        print(f"[FAIL] model not found: {args.model}")
        print(f"[INFO] first models: {model_ids[:20]}")
        return 1
    print(f"[OK] model exists: {args.model}")

    st, body = _request(
        f"{base}/v1/responses",
        method="POST",
        headers={"Authorization": f"Bearer {args.api_key}"},
        payload={"model": args.model, "input": "Reply with OK only."},
        timeout=args.timeout,
    )
    if st != 200:
        print(f"[FAIL] /v1/responses status={st} body={body[:300]}")
        return 1

    try:
        data = json.loads(body)
    except Exception as e:
        print(f"[FAIL] /v1/responses json parse error: {e}")
        return 1

    status = data.get("status", "")
    if status != "completed":
        print(f"[FAIL] /v1/responses unexpected status={status} body={body[:300]}")
        return 1

    print(f"[OK] /v1/responses completed model={args.model}")
    print("[DONE] verification passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
