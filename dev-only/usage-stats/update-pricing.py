#!/usr/bin/env python3
"""從 LiteLLM 的公開價格表產生 AspaceI 內建的模型價格（只取 Claude 與 GPT）。

用法：python3 dev-only/usage-stats/update-pricing.py
輸出：Sources/AspaceI/Resources/Pricing/model-prices.json
價格單位：每個 token 的美元。說明見 dev-only/usage-stats/overview.md「費用」。
"""
import datetime
import json
import os
import re
import urllib.request

SOURCE = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
OUTPUT = os.path.join(os.path.dirname(__file__), "../../Sources/AspaceI/Resources/Pricing/model-prices.json")


def price(entry):
    result = {}
    for key, name in [
        ("input_cost_per_token", "input"),
        ("output_cost_per_token", "output"),
        ("cache_read_input_token_cost", "cacheRead"),
        ("cache_creation_input_token_cost", "cacheWrite"),
        ("cache_creation_input_token_cost_above_1hr", "cacheWrite1h"),
    ]:
        if isinstance(entry.get(key), (int, float)):
            result[name] = entry[key]
    # 長上下文：整個請求超過門檻就全部改用較高的價格（Codex 為 272k）。
    for key in entry:
        match = re.fullmatch(r"input_cost_per_token_above_(\d+)k_tokens", key)
        if match:
            threshold = match.group(1)
            result["threshold"] = int(threshold) * 1000
            for field, name in [("input_cost_per_token", "inputAbove"), ("output_cost_per_token", "outputAbove"),
                                ("cache_read_input_token_cost", "cacheReadAbove"), ("cache_creation_input_token_cost", "cacheWriteAbove")]:
                value = entry.get(f"{field}_above_{threshold}k_tokens")
                if isinstance(value, (int, float)):
                    result[name] = value
    return result if "input" in result and "output" in result else None


def main():
    with urllib.request.urlopen(SOURCE, timeout=30) as response:
        data = json.load(response)
    models = {}
    for key, entry in data.items():
        if not isinstance(entry, dict):
            continue
        name = key.removeprefix("chatgpt/")
        if "/" in name or not (name.startswith("claude-") or name.startswith("gpt-")):
            continue
        # 沒有前綴的版本優先；只有 chatgpt/ 版本的（例如 gpt-5.3-codex-spark）才用它。
        if name in models and key.startswith("chatgpt/"):
            continue
        value = price(entry)
        if value:
            models[name] = value
    table = {
        "source": SOURCE,
        "fetchedAt": datetime.date.today().isoformat(),
        "models": dict(sorted(models.items())),
    }
    with open(OUTPUT, "w") as file:
        json.dump(table, file, indent=1, sort_keys=False)
        file.write("\n")
    print(f"{len(models)} 個模型 → {os.path.normpath(OUTPUT)}")


if __name__ == "__main__":
    main()
