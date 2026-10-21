"""Lists the engine files published for Android (names and sizes only, nothing is downloaded)."""
from huggingface_hub import HfApi
from needle.agent import fetch

repo = fetch.engine_repo(3)
print("engine repo:", repo)
for info in HfApi().list_repo_tree(repo, recursive=True):
    if "android" in info.path:
        print(f"{getattr(info, 'size', 0) or 0:>12,}  {info.path}")
