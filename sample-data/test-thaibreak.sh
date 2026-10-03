#!/usr/bin/env bash
# ==============================================================================
# OpenSearch Thai Best Practices - thaibreak pipeline verification
# ==============================================================================
# ตรวจ 01-analysis-pipeline/06-thaibreak-analyzer.json กับ plugin analysis-thaibreak (v1.4.0+)
# ต้องมี plugin และไฟล์ stopwords ที่ config/analysis/thai-stopwords.txt
# (docker-compose.yml ติดตั้งและ mount ให้แล้ว)
#
#   OPENSEARCH_URL=http://localhost:9200 ./sample-data/test-thaibreak.sh
set -euo pipefail

export OPENSEARCH_URL="${OPENSEARCH_URL:-http://localhost:9200}"
export INDEX_NAME="thai-tb-demo"
cd "$(dirname "$0")/.."

until curl -s "${OPENSEARCH_URL}/_cluster/health" > /dev/null; do
    echo "Waiting for OpenSearch at ${OPENSEARCH_URL}..."
    sleep 3
done
if ! curl -s "${OPENSEARCH_URL}/_cat/plugins?h=component" | grep -q analysis-thaibreak; then
    echo "analysis-thaibreak plugin is not installed on ${OPENSEARCH_URL}" >&2
    exit 2
fi

python3 - <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

URL = os.environ["OPENSEARCH_URL"]
INDEX = os.environ["INDEX_NAME"]
failures = []


def call(method, path, body=None, content_type="application/json"):
    if body is not None and not isinstance(body, bytes):
        body = json.dumps(body).encode()
    req = urllib.request.Request(URL + path, body, {"Content-Type": content_type}, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as err:
        return json.load(err)


def check(label, ok, detail=""):
    print(("PASS: " if ok else "FAIL: ") + label + (f"  {detail}" if detail else ""))
    if not ok:
        failures.append(label)


def search(body, size=20):
    result = call("POST", f"/{INDEX}/_search?size={size}", body)
    if "hits" not in result:
        sys.exit("search failed: " + json.dumps(result, ensure_ascii=False)[:300])
    return [h["_source"]["id"] for h in result["hits"]["hits"]]


def analyze(analyzer, text):
    return [t["token"] for t in call("POST", f"/{INDEX}/_analyze", {"analyzer": analyzer, "text": text})["tokens"]]


# ---------- 1. create index and load data ----------
config = json.load(open("01-analysis-pipeline/06-thaibreak-analyzer.json", encoding="utf-8"))
call("DELETE", f"/{INDEX}")
created = call("PUT", f"/{INDEX}", {"settings": config["settings"], "mappings": config["mappings"]})
if not created.get("acknowledged"):
    sys.exit("index creation failed: " + json.dumps(created, ensure_ascii=False)[:400])
bulk = call("POST", "/_bulk?refresh=true", open("sample-data/bulk-thaibreak.json", "rb").read(),
            "application/x-ndjson")
if bulk.get("errors"):
    sys.exit("bulk indexing failed")
print(f"Index {INDEX} created with 06-thaibreak-analyzer.json and 14 documents loaded\n")

# ---------- 2. normalization ----------
print("=== Test A: spelling variants index to the same term ===")
m = lambda q, field="title", **kw: search({"query": {"match": {field: {"query": q, **kw}}}})
legacy = "นํ้าตาล"          # นํ้าตาล (document 1 is stored like this)
check("น้ำตาล finds the document stored as นํ้าตาล", "1" in m("น้ำตาล"), str(m("น้ำตาล")))
check("นำ้ตาล (tone after ำ) finds it too", "1" in m("นำ้ตาล"), str(m("นำ้ตาล")))
check("นํ้าตาล (legacy) finds น้ำตาล documents", "1" in m(legacy), str(m(legacy)))
check("แมว finds the document stored as เเมว (double Sara E)", "6" in m("แมว"), str(m("แมว")))

# ---------- 3. stopwords ----------
print("\n=== Test B: stopwords with tone marks are removed ===")
tokens = analyze("thai_tb", "บริการส่งอาหารถึงที่ ราคาถูก แต่ ซึ่ง")
print("Tokens:", tokens)
check("ที่, แต่, ซึ่ง removed", not {"ที่", "แต่", "ซึ่ง", "ที", "แต", "ซึง"} & set(tokens))

# ---------- 4. tone handling ----------
print("\n=== Test C: tone marks keep words apart on the main field, .loose is the safety net ===")
check("ข้าว finds only the rice document", m("ข้าว") == ["3"], str(m("ข้าว")))
check("กลอง and กล้อง are different terms", m("กลอง") == ["11"] and m("กล้อง") == ["10"],
      f"{m('กลอง')} / {m('กล้อง')}")
check("title.loose: ขาวหอม (tone dropped) finds the rice document with AND",
      m("ขาวหอม", "title.loose", operator="and") == ["3"], str(m("ขาวหอม", "title.loose", operator="and")))
check("title: ขาวหอม with AND finds nothing", m("ขาวหอม", operator="and") == [])

# ---------- 5. sorting ----------
print("\n=== Test D: thaibreak_collation normalizer sorts in dictionary order ===")
def sorted_names(field):
    result = call("POST", f"/{INDEX}/_search?size=20",
                  {"query": {"match_all": {}}, "sort": [{field: "asc"}], "_source": ["name"]})
    return [h["_source"]["name"] for h in result["hits"]["hits"]]
raw, thai = sorted_names("name"), sorted_names("name.sort")
print("Byte order  :", raw)
print("Thai order  :", thai)
check("ไก่ทอด (leading vowel) is last in byte order but not in Thai order",
      raw[-1] == "ไก่ทอด" and thai[-1] != "ไก่ทอด")
check("กลอง sorts before กล้อง (tone mark is a second-level key)", thai.index("กลอง") < thai.index("กล้อง"))

# ---------- 6. misspellings: fuzzy vs .loose vs .sub ----------
# A typo usually changes how the word is segmented (สนามบิล -> สนาม|บิล), so fuzzy matching on the
# main field has nothing to match. The .sub field also holds the parts of compounds, so a typo that
# still yields a valid part (สนาม, ยนต์, มือ) finds the document.
print("\n=== Test E: misspellings (✓/✗ = intended document found, +n = other documents returned) ===")
cases = [
    ("ขาวหอม", "3", "tone dropped"),
    ("ไก้ทอด", "5", "wrong tone"),
    ("คอมพิวเตอ", "9", "thanthakhat dropped"),
    ("สนามบิล", "7", "wrong final consonant"),
    ("จักยานยนต์", "13", "one letter dropped"),
    ("มือถอ", "8", "tone-bearing letter wrong"),
]
layered = lambda q: {"bool": {"should": [
    {"match": {"title": {"query": q, "boost": 3}}},
    {"match": {"title.loose": {"query": q, "boost": 1}}},
    {"match": {"title.sub": {"query": q, "boost": 0.5}}},
]}}
methods = {
    "exact": lambda q: {"match": {"title": q}},
    "fuzzy AUTO": lambda q: {"match": {"title": {"query": q, "fuzziness": "AUTO"}}},
    "fuzzy 1": lambda q: {"match": {"title": {"query": q, "fuzziness": 1, "prefix_length": 1}}},
    ".loose": lambda q: {"match": {"title.loose": q}},
    ".sub": lambda q: {"match": {"title.sub": q}},
    "layered": layered,
}
print("typo".ljust(14) + "".join(name.ljust(13) for name in methods))
totals = {name: 0 for name in methods}
for typo, intended, _ in cases:
    row = typo.ljust(14)
    for name, build in methods.items():
        ids = search({"query": build(typo)})
        found = intended in ids
        totals[name] += found
        row += (("✓ " if found else "✗ ") + f"+{len(ids) - found}").ljust(13)
    print(row)
print("recall".ljust(14) + "".join(f"{totals[n]}/{len(cases)}".ljust(13) for n in methods))
print("(layered = title x3 + title.loose x1 + title.sub x0.5; คอมพิวเตอ is a known miss: it is segmented"
      " as คอม|พิวเตอ, neither of which is a term of คอมพิวเตอร์)")
for typo, intended, why in cases:
    if typo == "คอมพิวเตอ":
        continue
    ids = search({"query": layered(typo)})
    check(f"layered query returns the intended document in the top 2 for {typo} ({why})",
          intended in ids[:2], str(ids[:4]))

print()
if failures:
    sys.exit(f"{len(failures)} check(s) failed")
print("=== All thaibreak checks passed ===")
PY
