"""Build deployment files without modifying tracked lab sources."""
import json
import os
from pathlib import Path
import re
import shutil
import stat

ROOT = Path(__file__).resolve().parents[1]


def prepare(root, config):
    source = root / "modules/module-1/resources"
    build = root / ".build"
    build.mkdir(exist_ok=True)
    # Only reset our own generated directories, never source files or state.
    for name in ("backend", "frontend", "assets", "cosmosdb"):
        target = build / name
        if target.exists():
            if target.resolve().parent != build.resolve():
                raise ValueError("Build directory must not resolve outside .build")
            def clear_readonly(function, path, _exc):
                os.chmod(path, stat.S_IWRITE | stat.S_IREAD | stat.S_IEXEC)
                function(path)
            shutil.rmtree(target, onerror=clear_readonly)
    ignore = shutil.ignore_patterns(".python_packages", "__pycache__", "*.pyc", "*.zip")
    shutil.copytree(source / "azure_function/data", build / "backend", ignore=ignore)
    shutil.copytree(source / "azure_function/react", build / "frontend", ignore=ignore)
    shutil.copytree(source / "storage_account", build / "assets")
    shutil.copytree(source / "cosmosdb", build / "cosmosdb", ignore=shutil.ignore_patterns("*.py", "__pycache__"))

    values = {
        "FUNCTIONS_WORKER_RUNTIME": "python",
        "AzureWebJobsStorage": config["connection_string"],
        "JWT_SECRET": "T2BYL6#]zc>Byuzu",
        "AZ_DB_ENDPOINT": config["cosmos_endpoint"],
        "AZ_DB_PRIMARYKEY": config["cosmos_key"],
        "CON_STR": config["connection_string"],
        "CONTAINER_NAME": config["container_name"],
    }
    # Intentional source-package disclosure is part of this isolated security lab.
    (build / "backend/local.settings.json").write_text(json.dumps({"IsEncrypted": False, "Values": values}, indent=2), encoding="utf-8")
    asset_url = config["asset_url"].rstrip("/")
    web_url = asset_url + "/webfiles/build"
    for html in (build / "frontend/webapp/index.html", build / "assets/webfiles/build/index.html"):
        text = html.read_text(encoding="utf-8")
        text = re.sub(r'''((?:src|href)=["'])/''', lambda m: m.group(1) + web_url + "/", text)
        html.write_text(text, encoding="utf-8")
    for js in (build / "assets/webfiles/build/static/js").glob("*.js"):
        text = js.read_text(encoding="utf-8")
        text = text.replace("AZURE_FUNCTION_URL", config["backend_url"])
        text = text.replace('"/static', '"' + web_url + '/static')
        text = text.replace('n.p+"static', '"' + web_url + '/static')
        js.write_text(text, encoding="utf-8")
    posts = build / "cosmosdb/blog-posts.json"
    posts.write_text(posts.read_text(encoding="utf-8").replace("AZURE_FUNCTION_URL", asset_url.removeprefix("https://")), encoding="utf-8")
    ssh_config = build / "assets/shared/files/.ssh/config.txt"
    text = ssh_config.read_text(encoding="utf-8")
    text = text.replace("Host VM_IP_ADDR\n  HostName justin", "Host developer-vm\n  HostName " + config["vm_ip"])
    ssh_config.write_text(text, encoding="utf-8")
    print("Prepared backend, frontend, assets and database fixtures in .build (credentials not logged).")


if __name__ == "__main__":
    prepare(ROOT, json.loads(os.environ["AZUREGOAT_CONFIG"]))
