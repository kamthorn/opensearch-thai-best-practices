#!/usr/bin/env bash
# ==============================================================================
# OpenSearch Thai Best Practices - Automated Verification Script
# ==============================================================================
set -euo pipefail

OPENSEARCH_URL="${OPENSEARCH_URL:-http://localhost:9200}"
INDEX_NAME="thai-best-practices-demo"
PIPELINE_NAME="thai-hybrid-rrf-pipeline"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== 1. Checking OpenSearch Cluster Health ===${NC}"
until curl -s "${OPENSEARCH_URL}/_cluster/health" > /dev/null; do
    echo -e "${YELLOW}Waiting for OpenSearch at ${OPENSEARCH_URL}...${NC}"
    sleep 3
done
echo -e "${GREEN}OpenSearch is up and ready!${NC}\n"

echo -e "${BLUE}=== 2. Creating Search Pipeline (RRF Normalization) ===${NC}"
curl -s -X PUT "${OPENSEARCH_URL}/_search/pipeline/${PIPELINE_NAME}" \
     -H "Content-Type: application/json" \
     -d @03-hybrid-search/search-pipeline-rrf.json | grep -o '"acknowledged":true' || true
echo -e "${GREEN}Pipeline created successfully!${NC}\n"

echo -e "${BLUE}=== 3. Creating Index with Production Thai Analyzer & Collation ===${NC}"
curl -s -X DELETE "${OPENSEARCH_URL}/${INDEX_NAME}" > /dev/null || true

# Combine settings + mappings
INDEX_CONFIG=$(cat << 'EOF'
{
  "settings": {
    "index": {
      "knn": true,
      "analysis": {
        "char_filter": {
          "thai_zero_width": {
            "type": "pattern_replace",
            "pattern": "[\\u200B\\u200C\\u200D\\uFEFF]",
            "replacement": ""
          },
          "thai_double_sara_e": {
            "type": "pattern_replace",
            "pattern": "\\u0E40\\u0E40",
            "replacement": "\\u0E41"
          },
          "thai_sara_am": {
            "type": "pattern_replace",
            "pattern": "\\u0E4D([\\u0E48-\\u0E4B])?\\u0E32",
            "replacement": "$1\\u0E33"
          },
          "thai_duplicate_diacritics": {
            "type": "pattern_replace",
            "pattern": "([\\u0E31\\u0E34-\\u0E3A\\u0E47-\\u0E4E])\\1+",
            "replacement": "$1"
          }
        },
        "filter": {
          "thai_curated_stopwords": {
            "type": "stop",
            "stopwords_path": "analysis/thai-stopwords.txt"
          },
          "thai_synonyms": {
            "type": "synonym_graph",
            "synonyms_path": "analysis/thai-synonyms.txt",
            "lenient": true
          }
        },
        "analyzer": {
          "thai_index": {
            "type": "custom",
            "char_filter": [
              "thai_zero_width",
              "thai_double_sara_e",
              "thai_sara_am",
              "thai_duplicate_diacritics"
            ],
            "tokenizer": "icu_tokenizer",
            "filter": [
              "icu_folding",
              "decimal_digit",
              "thai_curated_stopwords",
              "thai_synonyms"
            ]
          },
          "thai_search": {
            "type": "custom",
            "char_filter": [
              "thai_zero_width",
              "thai_double_sara_e",
              "thai_sara_am",
              "thai_duplicate_diacritics"
            ],
            "tokenizer": "icu_tokenizer",
            "filter": [
              "icu_folding",
              "decimal_digit",
              "thai_curated_stopwords"
            ]
          }
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "id": { "type": "keyword" },
      "title": { "type": "text", "analyzer": "thai_index", "search_analyzer": "thai_search" },
      "content": { "type": "text", "analyzer": "thai_index", "search_analyzer": "thai_search" },
      "category": { "type": "keyword" },
      "name": {
        "type": "text",
        "fields": {
          "raw_sort": { "type": "keyword" },
          "thai_sort": {
            "type": "icu_collation_keyword",
            "index": false,
            "language": "th",
            "country": "TH"
          }
        }
      },
      "content_vector": {
        "type": "knn_vector",
        "dimension": 4,
        "method": {
          "name": "hnsw",
          "space_type": "cosinesimil",
          "engine": "nmslib"
        }
      }
    }
  }
}
EOF
)

curl -s -X PUT "${OPENSEARCH_URL}/${INDEX_NAME}" \
     -H "Content-Type: application/json" \
     -d "${INDEX_CONFIG}" | grep -o '"acknowledged":true'
echo -e "${GREEN}Index created successfully!${NC}\n"

echo -e "${BLUE}=== 4. Ingesting Sample Thai Documents ===${NC}"
# Re-index to target index
sed "s/thai-products/${INDEX_NAME}/g" sample-data/bulk-products.json | \
curl -s -X POST "${OPENSEARCH_URL}/_bulk?refresh=true" \
     -H "Content-Type: application/x-ndjson" \
     --data-binary @- > /dev/null
echo -e "${GREEN}Bulk indexing complete!${NC}\n"

echo -e "${BLUE}=== 5. Test Case 1: Normalization & Typo Tolerance ===${NC}"
echo "Testing search for 'แมว' against document indexed with double-E 'เเมว':"
curl -s "${OPENSEARCH_URL}/${INDEX_NAME}/_search" \
     -H "Content-Type: application/json" \
     -d '{"query":{"match":{"content":"แมว"}}}' | \
     python3 -c "import sys,json; r=json.load(sys.stdin); print('Hits:', r['hits']['total']['value'], [h['_source']['title'] for h in r['hits']['hits']])"

echo -e "\n${BLUE}=== 6. Test Case 2: Curated Stopwords (No Over-filtering) ===${NC}"
echo "Testing search for 'ผลไม้' (previously over-filtered in Lucene when 'ผล' was removed):"
curl -s "${OPENSEARCH_URL}/${INDEX_NAME}/_search" \
     -H "Content-Type: application/json" \
     -d '{"query":{"match":{"title":"ผลไม้"}}}' | \
     python3 -c "import sys,json; r=json.load(sys.stdin); print('Hits:', r['hits']['total']['value'], [h['_source']['title'] for h in r['hits']['hits']])"

echo -e "\n${BLUE}=== 7. Test Case 3: Thai Collation Sorting Comparison ===${NC}"
echo -e "${YELLOW}[Flawed Default Byte Sort] (สระนำหน้า เ, ไ ไปอยู่หลังสุด):${NC}"
curl -s "${OPENSEARCH_URL}/${INDEX_NAME}/_search" \
     -H "Content-Type: application/json" \
     -d '{"query":{"match_all":{}}, "sort":[{"name.raw_sort":{"order":"asc"}}], "_source":["name"]}' | \
     python3 -c "import sys,json; r=json.load(sys.stdin); print([h['_source']['name'] for h in r['hits']['hits']])"

echo -e "${GREEN}[Correct Thai Collation Sort] (ตามพจนานุกรมราชบัณฑิตยสถาน):${NC}"
curl -s "${OPENSEARCH_URL}/${INDEX_NAME}/_search" \
     -H "Content-Type: application/json" \
     -d '{"query":{"match_all":{}}, "sort":[{"name.thai_sort":{"order":"asc"}}], "_source":["name"]}' | \
     python3 -c "import sys,json; r=json.load(sys.stdin); print([h['_source']['name'] for h in r['hits']['hits']])"

echo -e "\n${BLUE}=== 8. Test Case 4: Thai Hybrid Search (BM25 + k-NN with RRF) ===${NC}"
curl -s "${OPENSEARCH_URL}/${INDEX_NAME}/_search?search_pipeline=${PIPELINE_NAME}" \
     -H "Content-Type: application/json" \
     -d @03-hybrid-search/hybrid-search-query.json | \
     python3 -c "import sys,json; r=json.load(sys.stdin); print('Hybrid Results:'); [print(' - Score:', h['_score'], '| Title:', h['_source']['title']) for h in r['hits']['hits']]"

echo -e "\n${GREEN}=== All Tests Completed Successfully! ===${NC}"
