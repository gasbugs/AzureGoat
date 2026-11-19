"""Seed only missing lab records. Re-applying must not reset learner changes."""
import json
import os
from pathlib import Path
import time


def main():
    from azure.cosmos import CosmosClient
    from azure.cosmos.exceptions import CosmosResourceExistsError, CosmosHttpResponseError
    client = CosmosClient(os.environ["COSMOS_ENDPOINT"], os.environ["COSMOS_KEY"])
    db = client.get_database_client("ine-cosmos-sql-db")
    source = Path(__file__).resolve().parents[1] / ".build/cosmosdb"
    for name in ("blog-users", "blog-posts"):
        container = db.get_container_client(name)
        added = 0
        records = json.loads((source / (name + ".json")).read_text(encoding="utf-8"))
        for record in records:
            for attempt in range(12):
                try:
                    container.create_item(record)
                    added += 1
                    break
                except CosmosResourceExistsError:
                    break
                except CosmosHttpResponseError as exc:
                    if exc.status_code not in (403, 404, 429, 503) or attempt == 11:
                        raise
                    time.sleep(5)
        print(f"{name}: added {added} records; preserved existing records")


if __name__ == "__main__":
    main()
