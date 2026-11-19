"""Check the deployed UI, assets, seeded data, registration and login.

Creates one clearly named smoke-test user in the isolated lab. Does not print
passwords, JWTs, connection strings or account keys.
"""
import argparse
from datetime import datetime, timezone
from html.parser import HTMLParser
import json
import secrets
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen


def fetch(url, payload=None, method="GET"):
    data = None if method == "GET" else (b"" if payload is None else json.dumps(payload).encode())
    request = Request(url, data=data, method=method, headers={"Content-Type": "application/json", "User-Agent": "AzureGoat-deployment-check"})
    with urlopen(request, timeout=60) as response:
        return response.status, response.read(12 * 1024 * 1024)


class Assets(HTMLParser):
    def __init__(self):
        super().__init__()
        self.urls = []

    def handle_starttag(self, tag, attributes):
        attributes = dict(attributes)
        if tag == "script" and attributes.get("src"):
            self.urls.append(attributes["src"])
        if tag == "link" and attributes.get("rel") == "stylesheet":
            self.urls.append(attributes.get("href", ""))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--frontend", required=True)
    parser.add_argument("--api", required=True)
    args = parser.parse_args()
    _, html = fetch(args.frontend)
    assert b'id="root"' in html, "Frontend did not return the React application"
    print("PASS frontend HTML")
    assets = Assets()
    assets.feed(html.decode())
    checked = 0
    for address in assets.urls:
        url = urljoin(args.frontend, address)
        host = urlparse(url).hostname
        if host != urlparse(args.frontend).hostname and not host.endswith(".blob.core.windows.net"):
            continue
        _, content = fetch(url)
        assert content, "Empty application asset"
        if urlparse(url).path.endswith(".js"):
            assert b"AZURE_FUNCTION_URL" not in content, "Unrendered API placeholder"
            assert args.api.rstrip("/").encode() in content, "Bundle points to a different API"
        checked += 1
    assert checked >= 2, "Expected application JS and CSS assets"
    print(f"PASS application assets ({checked})")
    _, response = fetch(args.api.rstrip("/") + "/list-posts", method="POST")
    posts = json.loads(response)["body"]
    assert isinstance(posts, list) and posts, "No seeded posts"
    print(f"PASS seeded blog API ({len(posts)} posts)")
    image = posts[0].get("getRequestImageData")
    if image:
        _, content = fetch(image)
        assert content, "Seeded post image is empty"
        print("PASS seeded image")
    suffix = secrets.token_hex(6)
    user = {
        "email": f"deployment-check-{suffix}@example.invalid",
        "username": f"deploymentcheck{suffix}",
        "password": secrets.token_urlsafe(24),
        "name": "Deployment smoke test", "country": "KR", "address": "Lab",
        "phone": "0000000000", "secretQuestion": "Lab check", "secretAnswer": suffix,
        "creationDate": datetime.now(timezone.utc).isoformat(),
    }
    fetch(args.api.rstrip("/") + "/register", user, "POST")
    _, response = fetch(args.api.rstrip("/") + "/login", {"email": user["email"], "password": user["password"]}, "POST")
    result = json.loads(response)["body"]
    assert result.get("token") and result["user"]["email"] == user["email"], "Registration/login failed"
    print("PASS registration and login (token redacted)")
    print("RESULT all application smoke checks passed")


if __name__ == "__main__":
    main()
