# OpenSearch Thai Best Practices 🇹🇭

[![Plugin Release](https://img.shields.io/github/v/release/kamthorn/opensearch-analysis-thaibreak?label=opensearch-plugin&color=blue)](https://github.com/kamthorn/opensearch-analysis-thaibreak/releases)

คู่มือและคลังตัวอย่างมาตรฐานการประมวลผลและสืบค้นภาษาไทยบน **OpenSearch** ระดับ Production ครอบคลุมครบทั้ง 4 เสาหลัก:
1. **Text Normalization:** การชำระอักขรวิธี, สระซ้ำ, สระลอย, สระหน้า, Zero-width
2. **Curated Stopwords & Synonyms:** การคัดกรองคำหยุดอย่างถูกต้อง ไม่ทำลายคำสำคัญ (Over-filtering) และคำพ้องคำทับศัพท์
3. **Thai Collation Sorting:** การเรียงลำดับ ก-ฮ ตามพจนานุกรมฉบับราชบัณฑิตยสถาน (แก้ปัญหาสระหน้า `เ`, `แ`, `โ`, `ใ`, `ไ`)
4. **Thai Hybrid Search:** การผสานผลลัพธ์ระหว่าง Lexical Search (BM25) และ Neural/Dense Vector (k-NN) ด้วย **Reciprocal Rank Fusion (RRF)**

---

## สารบัญ

- [1. ปัญหาคลาสสิกของภาษาไทยบน OpenSearch](#1-ปัญหาคลาสสิกของภาษาไทยบน-opensearch)
- [2. เปรียบเทียบ Tokenizer สำหรับภาษาไทย](#2-เปรียบเทียบ-tokenizer-สำหรับภาษาไทย)
- [3. โครงสร้างโปรเจกต์](#3-โครงสร้างโปรเจกต์)
- [4. เริ่มต้นใช้งานแบบด่วน (Quick Start)](#4-เริ่มต้นใช้งานแบบด่วน-quick-start)
- [5. รายละเอียดแต่ละโมดูล](#5-รายละเอียดแต่ละโมดูล)
  - [5.1 การ Normalization ชำระอักขรวิธีก่อนตัดคำ](#51-การ-normalization-ชำระอักขรวิธีก่อนตัดคำ)
  - [5.2 การจัดชุดคำหยุด (Curated Stopwords)](#52-การจัดชุดคำหยุด-curated-stopwords)
  - [5.3 การจัดเรียงตามพจนานุกรมไทย (Collation Sorting)](#53-การจัดเรียงตามพจนานุกรมไทย-collation-sorting)
  - [5.4 การค้นหาแบบลูกผสม (Thai Hybrid Search)](#54-การค้นหาแบบลูกผสม-thai-hybrid-search)
- [6. ผลการทดสอบ (Verification & Test Results)](#6-ผลการทดสอบ-verification--test-results)
- [7. โปรเจกต์ที่เกี่ยวข้อง](#7-โปรเจกต์ที่เกี่ยวข้อง)
- [8. สิทธิ์การใช้งาน (License)](#8-สิทธิ์การใช้งาน-license)

---

## 1. ปัญหาคลาสสิกของภาษาไทยบน OpenSearch

การตั้งค่า OpenSearch โดยใช้ Analyzer เริ่มต้น (`standard` หรือ `thai`) มักพบปัญหาสำคัญ 4 ประการ:

| ปัญหา | พฤติกรรมเดิมที่ผิดพลาด | ผลกระทบต่อระบบค้นหา | แนวทางแก้ไขใน Best Practices |
|---|---|---|---|
| **1. อักขรวิธีและสระซ้ำ** | `เเมว` (สระเอ 2 ตัว), `นํ้า` (นิคหิต+สระอา), `ดีี` (สระอีซ้ำ) | ค้นหา `แมว` หรือ `น้ำ` ไม่พบ | ใช้ `pattern_replace` char filters จัดรูปก่อนตัดคำ (หรือ `thaibreak_normalization` ถ้าติดตั้ง plugin) |
| **2. Over-filtering Stopwords** | ชุด `stopwords.txt` ดั้งเดิมของ Lucene ตัดคำกริยา/คำนาม เช่น `ผล`, `เปิด`, `ส่ง`, `ทาง` | ค้นหา `"ผลไม้"` กลายเป็นค้นหาคำว่า `"ไม้"` คำเดียว | ใช้ [Curated Stopwords](01-analysis-pipeline/03-curated-stopwords.txt) ที่ตัดเฉพาะคำไวยากรณ์ |
| **3. การเรียงลำดับเพี้ยน (Sort)** | Byte-order ปกติมองว่าสระหน้า (`เ-ไ`) มีรหัส Unicode สูงกว่า `ฮ` | คำว่า `"เกาะ"`, `"ไก่"` ถูกเรียงไปอยู่หลัง `"ฮูก"` | ใช้ `icu_collation_keyword` (Language: `th`) จัดเรียงตามพยัญชนะต้น |
| **4. คำค้นไม่ตรงรูป (Lexical Gap)** | ผู้ใช้พิมพ์คำค้นกำกวม, คำทับศัพท์ หรือคำถามภาษาธรรมชาติ | BM25 อย่างเดียวให้ Recall ต่ำ | ทำ **Hybrid Search** ผสาน BM25 เข้ากับ Dense Vector ด้วย RRF |

---

## 2. เปรียบเทียบ Tokenizer สำหรับภาษาไทย

```
                                  ข้อความภาษาไทย
                                        │
             ┌──────────────────────────┼──────────────────────────┐
             ▼                          ▼                          ▼
      [ standard ]               [ icu_tokenizer ]          [ thaibreak ]
    (UAX#29 พื้นฐาน)             (analysis-icu)        (opensearch-analysis-thaibreak)
             │                          │                          │
   ไม่ตัดคำภาษาไทย              RuleBasedBreakIterator         Viterbi DAG + TCC 30 Rules
(ออกเป็นทั้งประโยค)              ความเสถียรข้ามแพลตฟอร์มสูง        พจนานุกรม 51,347 คำในตัว (v1.4.0)
                                                           รองรับ User Dict แบบ Plaintext
```

| คุณสมบัติ | `standard` | `thai` (Built-in) | `icu_tokenizer` | `thaibreak` (Plugin) |
|---|---|---|---|---|
| **การรองรับภาษาไทย** | ❌ ไม่ตัดคำ | ⚠️ พื้นฐาน | ✅ ดีมาก | 🌟 แนะนำระดับสูง |
| **อัลกอริทึม** | Whitespace/Punctuation | JDK `BreakIterator` | ICU4J Dictionary-based | Viterbi Shortest Path + TCC |
| **ความเสถียรข้าม JVM** | คงที่ | ❌ ต่างตามเวอร์ชัน Java | ✅ สม่ำเสมอ | ✅ 100% Deterministic |
| **User Dictionary** | ❌ | ❌ (รอ upstream Lucene) | ⚠️ ต้อง compile `.dict` | ✅ โหลดผ่าน Plaintext TSV ได้ทันที |
| **การป้องกันพยางค์แตก** | ❌ | ❌ | ⚠️ บางคำ | ✅ ควบคุมด้วย TCC Rules |
| **Compound Word Modes** | ❌ | ❌ | ❌ | ✅ NONE / DISCARD / MIXED (Graph Token) |
| **Token Filters พิเศษ** | ❌ | ❌ | ❌ | ✅ Tone, Soundex, Keyboard, Number |

---

## 3. โครงสร้างโปรเจกต์

```
opensearch-thai-best-practices/
├── docker-compose.yml                     # สภาพแวดล้อม OpenSearch + Dashboards
├── 01-analysis-pipeline/
│   ├── 01-char-filters.json               # กฎ Pattern Replace ชำระอักขรวิธี
│   ├── 02-tokenizers-comparison.json      # การเปรียบเทียบเชิงลึกของแต่ละ Tokenizer
│   ├── 03-curated-stopwords.txt           # รายการ Stopwords ภาษาไทยฉบับปรับปรุง
│   ├── 04-synonyms.txt                    # คำพ้อง/คำทับศัพท์สำหรับระบบค้นหา
│   └── 05-full-thai-analyzer.json         # Full Production Analyzer Configuration
├── 02-collation-sorting/
│   ├── thai-sort-mapping.json             # การตั้งค่า icu_collation_keyword
│   └── test-sort-query.json               # คำสั่ง Query เปรียบเทียบผลลัพธ์การเรียง
├── 03-hybrid-search/
│   ├── knn-index-mapping.json             # Mappings รองรับทั้ง Text และ k-NN Vector
│   ├── search-pipeline-rrf.json           # OpenSearch Pipeline ใช้ RRF ผสานคะแนน
│   ├── search-pipeline-minmax.json        # Alternative Pipeline ใช้ Min-Max Normalization
│   └── hybrid-search-query.json           # ตัวอย่าง Hybrid Search Query
└── sample-data/
    ├── bulk-products.json                 # ข้อมูลตัวอย่างสินค้าภาษาไทย
    └── test-queries.sh                    # สคริปต์รันทดสอบอัตโนมัติครบทุกฟีเจอร์
```

> ไฟล์ `.json` ในโฟลเดอร์ `01`–`03` มีคีย์อธิบาย (`description`, `explanation`, `test_cases`) ที่ OpenSearch ไม่รู้จัก ส่งไฟล์ตรงๆ ให้ `PUT /<index>` ไม่ได้ ให้ส่งเฉพาะ `settings` และ `mappings` เช่น `jq '{settings, mappings}' 01-analysis-pipeline/05-full-thai-analyzer.json` ส่วน `test-queries.sh` สร้าง index ด้วยชุดค่าเดียวกันให้แล้ว

---

## 4. เริ่มต้นใช้งานแบบด่วน (Quick Start)

### ข้อกำหนดระบบ
- Docker และ Docker Compose
- `curl` และ `python3` (สำหรับรันชุดทดสอบ)

### ทางเลือกที่ 1: รันผ่าน Pre-built Docker Image (มี plugin `analysis-thaibreak` ติดตั้งแล้ว)

```bash
docker run -d -p 9200:9200 -p 9600:9600 \
  -e "discovery.type=single-node" \
  -e "DISABLE_SECURITY_PLUGIN=true" \
  -e "DISABLE_INSTALL_DEMO_CONFIG=true" \
  --name opensearch-thaibreak \
  ghcr.io/kamthorn/opensearch-thaibreak:3.9.0
```

image มีให้สำหรับ `2.18.0`, `2.19.0`, `3.8.0` และ `3.9.0` (`latest` ชี้ไปที่ 2.18.0) และมีเฉพาะ `analysis-thaibreak` ไม่มี `analysis-icu`

### ทางเลือกที่ 2: ติดตั้ง Plugin ใน OpenSearch เดิม

```bash
# OpenSearch 3.9.0
bin/opensearch-plugin install \
  https://github.com/kamthorn/opensearch-analysis-thaibreak/releases/download/v1.4.0/analysis-thaibreak-3.9.0.0.zip

# OpenSearch 2.19.0
bin/opensearch-plugin install \
  https://github.com/kamthorn/opensearch-analysis-thaibreak/releases/download/v1.4.0/analysis-thaibreak-2.19.0.0.zip
```

รองรับ: `2.15.0` | `2.17.1` | `2.18.0` | `2.19.0` | `3.8.0` | `3.9.0` — ZIP ติดตั้งได้เฉพาะ OpenSearch รุ่นที่ระบุในชื่อไฟล์ ([ดู Release ทั้งหมด](https://github.com/kamthorn/opensearch-analysis-thaibreak/releases/tag/v1.4.0)) ส่วน `2.11.x`–`2.13.x` ใช้ไม่ได้เพราะ plugin ต้องการ Java 21

ตัวอย่างใน repo นี้ (ส่วน 01–03) ใช้ `icu_tokenizer` และ `icu_collation_keyword` จึงต้องมี **`analysis-icu`** (`bin/opensearch-plugin install analysis-icu`) ส่วน `analysis-thaibreak` ไม่จำเป็น ขั้นตอน `docker-compose up -d` ด้านล่างติดตั้ง `analysis-icu` ให้อัตโนมัติ ทดสอบแล้วบน OpenSearch 2.19.0 และ 3.9.0

### ขั้นตอนการรัน
1. **เปิด OpenSearch คลัสเตอร์:**
   ```bash
   docker-compose up -d
   ```

2. **รันการทดสอบและสร้าง Index สาธิต:**
   ```bash
   ./sample-data/test-queries.sh
   ```

3. **เข้าใช้งาน OpenSearch Dashboards:**
   เปิดเบราว์เซอร์ไปที่ [http://localhost:5601](http://localhost:5601)

---

## 5. รายละเอียดแต่ละโมดูล

### 5.1 การ Normalization ชำระอักขรวิธีก่อนตัดคำ

ภาษาไทยมักมีปัญหาจากการพิมพ์ผิดรูปแบบแต่แสดงผลบนหน้าจอคล้ายกัน ซึ่งทำให้การจับคู่คำในระบบค้นหาล้มเหลว:

```json
"char_filter": {
  "thai_zero_width": {
    "type": "pattern_replace",
    "pattern": "[\\u200B\\u200C\\u200D\\uFEFF]",
    "replacement": ""
  },
  "thai_double_sara_e": {
    "type": "pattern_replace",
    "pattern": "\\u0E40\\u0E40",
    "replacement": "\u0E41"
  },
  "thai_sara_am": {
    "type": "pattern_replace",
    "pattern": "\\u0E4D([\\u0E48-\\u0E4B])?\\u0E32",
    "replacement": "$1\u0E33"
  },
  "thai_duplicate_diacritics": {
    "type": "pattern_replace",
    "pattern": "([\\u0E31\\u0E34-\\u0E3A\\u0E47-\\u0E4E])\\1+",
    "replacement": "$1"
  }
}
```

> **ข้อควรระวังในการเขียน `replacement`:** ใน JSON ให้เขียน `"\u0E41"` (backslash เดียว เพื่อให้ JSON แปลงเป็นอักขระจริง) ส่วน `pattern` เขียน `"\\u0E40\\u0E40"` (สอง backslash ให้ regex ตีความ) ถ้าเขียน `replacement` เป็น `"\\u0E41"` Java จะถือ `\` เป็น escape แล้วได้ข้อความ `u0E41` ติดเข้าไปใน token (`เเมว` กลายเป็น `u0E41มว`) และ filter จะทำให้ข้อมูลเสียแทนที่จะแก้
>
> **ขอบเขตของ regex เหล่านี้:** จัดการ `เเ`, `นํ้า`/`น้ํา`, สระหรือเครื่องหมายซ้ำ และ zero-width ได้ แต่ **ไม่** จัดการ `นำ้` (วรรณยุกต์พิมพ์หลัง `ำ`), สระตามซ้ำ (`ค่าา`), วรรณยุกต์ต่างตัวซ้อนกัน หรือวรรณยุกต์ที่อยู่หน้าสระบน (`ท่ี` → `ที่`) ถ้าต้องครอบคลุมกว่านี้ ให้ใช้ `thaibreak_normalization` ของ plugin [`analysis-thaibreak`](https://github.com/kamthorn/opensearch-analysis-thaibreak) (v1.4.0 ขึ้นไป) หรือ `thai_char_filter` / `thai_normalization` ของ Lucene 10.6 ซึ่ง OpenSearch core ยังไม่ได้ปล่อย ([#23151](https://github.com/opensearch-project/OpenSearch/issues/23151))

### 5.2 การจัดชุดคำหยุด (Curated Stopwords)

ในเอกสารเดิมของ Apache Lucene / OpenSearch รายการ Stopwords ได้รับอิทธิพลจากงานวิจัยบทความข่าวการเมือง ทำให้มีคำกริยาและคำนามทั่วไปปะปนอยู่ เช่น `"ผล"`, `"เปิด"`, `"ส่ง"`, `"ทาง"`

ใน Best Practices นี้ เราใช้รายการ [03-curated-stopwords.txt](01-analysis-pipeline/03-curated-stopwords.txt) ซึ่งคัดเฉพาะ:
- **คำเชื่อม:** `ที่`, `ซึ่ง`, `อัน`, `และ`, `หรือ`, `แต่`, `ดังนั้น`, `สำหรับ`
- **คำบุพบท:** `ใน`, `บน`, `ใต้`, `แห่ง`, `ของ`, `โดย`, `เพื่อ`, `ต่อ`
- **คำลงท้าย:** `ครับ`, `ค่ะ`, `คะ`, `นะ`, `จ๊ะ`, `เลย`

**ลำดับของ filter สำคัญ:** `stop` เทียบ token กับไฟล์ตามตัวอักษรตรงๆ โดยไม่ผ่าน analyzer ดังนั้นต้องวางไว้ **ก่อน** `icu_folding` เพราะ `icu_folding` ตัดวรรณยุกต์ออกตามที่ออกแบบไว้ (`ที่` → `ที`, `ข้าว` → `ขาว`) ถ้า `icu_folding` มาก่อน stopwords ที่มีวรรณยุกต์ (33 จาก 67 คำในรายการนี้ เช่น `ที่`, `ซึ่ง`, `แล้ว`, `ค่ะ`) จะไม่ถูกตัดเลย analyzer ในตัวอย่างจึงเรียงเป็น `decimal_digit` → `thai_curated_stopwords` → (`thai_synonyms`) → `icu_folding` และ `test-queries.sh` มี Test Case 2b ตรวจเรื่องนี้

`icu_folding` ทำให้คำที่ต่างกันด้วยวรรณยุกต์ซ้ำกันใน index (`ไก่`/`ไก`, `ใหม่`/`ใหม`) ซึ่งเป็นข้อแลกเปลี่ยน: ได้ recall เพิ่มเมื่อผู้ใช้พิมพ์วรรณยุกต์ผิด แต่เสีย precision ถ้าต้องการแยกคำเหล่านี้ ให้เอา `icu_folding` ออกจากฟิลด์หลัก แล้วทำฟิลด์ย่อยแบบ loose (เช่น `thaibreak_tone`) ที่ให้น้ำหนักต่ำกว่า

### 5.3 การจัดเรียงตามพจนานุกรมไทย (Collation Sorting)

การใช้ Field แบบ `keyword` ปกติจะเรียงตามรหัสไบต์ UTF-8:
- พยัญชนะ: `ก` (0x0E01) ถึง `ฮ` (0x0E2E)
- สระหน้า: `เ` (0x0E40), `แ` (0x0E41), `โ` (0x0E42), `ใ` (0x0E43), `ไ` (0x0E44)

เนื่องจาก `0x0E40 > 0x0E2E` ทำให้คำว่า `"เกาะ"` หรือ `"ไก่"` ถูกจัดไปอยู่หลัง `"ฮูก"` ทันที

**แนวทางแก้ไข:** ใช้ `icu_collation_keyword`:
```json
"name": {
  "type": "text",
  "fields": {
    "thai_sort": {
      "type": "icu_collation_keyword",
      "language": "th",
      "country": "TH"
    }
  }
}
```
อัลกอริทึม ICU จะทำ Vowel Reordering นำพยัญชนะต้นขึ้นมาพิจารณาก่อนสระหน้าเสมอ ได้ผลลัพธ์ที่ถูกต้องตามพจนานุกรม:
`กบ` ➔ `เกาะ` ➔ `ไก่` ➔ `ขวด` ➔ `ฮูก`

### 5.4 การค้นหาแบบลูกผสม (Thai Hybrid Search)

การค้นหาภาษาไทยที่มีประสิทธิภาพสูงสุดในยุคปัจจุบัน คือการผสานข้อดีของ 2 โลก:
- **BM25 Lexical Search:** แม่นยำกับชื่อเฉพาะ, รหัสสินค้า, ศัพท์เทคนิคที่ตรงตัว
- **k-NN Vector Search:** เข้าใจความหมาย บริบท คำใกล้เคียง และคำแสลง

```json
{
  "query": {
    "hybrid": {
      "queries": [
        {
          "match": {
            "content": {
              "query": "การวิเคราะห์ข้อมูลบนคลาวด์",
              "boost": 0.4
            }
          }
        },
        {
          "knn": {
            "content_vector": {
              "vector": [0.25, 0.55, 0.12, 0.88],
              "k": 10,
              "boost": 0.6
            }
          }
        }
      ]
    }
  }
}
```

และผสานคะแนนผ่าน Search Pipeline ด้วย **Reciprocal Rank Fusion (RRF)**:
$$\text{RRF Score} = \sum_{m \in M} \frac{1}{k + r_m(d)}$$

โดย `k` คือ `rank_constant` (ค่าเริ่มต้น 60) และ `r_m(d)` คืออันดับของเอกสาร `d` ในผลของ query ที่ `m` pipeline ใช้ `score-ranker-processor` ซึ่งมีให้ตั้งแต่ OpenSearch 2.19 (`normalization-processor` ไม่รองรับ `rrf` ใน 3.9.0) RRF ใช้เฉพาะอันดับ ค่า `boost` ใน query จึงไม่มีผลต่อคะแนนรวม ถ้าต้องการถ่วงน้ำหนักระหว่าง BM25 กับ k-NN ให้ใช้ pipeline แบบ min-max ([search-pipeline-minmax.json](03-hybrid-search/search-pipeline-minmax.json)) ตัวอย่าง mapping ใช้ k-NN engine `lucene` เพราะ `nmslib` สร้าง index ใหม่ไม่ได้ตั้งแต่ OpenSearch 3.0

---

## 6. ผลการทดสอบ (Verification & Test Results)

เมื่อรัน `./sample-data/test-queries.sh` ระบบจะสาธิตผลลัพธ์จริง (ผลเหมือนกันบน OpenSearch 2.19.0 และ 3.9.0):

```text
=== 5. Test Case 1: Normalization & Typo Tolerance ===
Testing search for 'แมว' against document indexed with double-E 'เเมว':
Hits: 1 ['อาหารแมวเกรดพรีเมียม สูตรบำรุงขนและผิวหนัง']

=== 6. Test Case 2: Curated Stopwords (No Over-filtering) ===
Testing search for 'ผลไม้' (previously over-filtered in Lucene when 'ผล' was removed):
Hits: 1 ['น้ำผลไม้แท้ 100% รสส้มเขียวหวาน']

=== 6b. Test Case 2b: Stopwords That Carry Tone Marks Are Removed ===
Analyzing 'ฉันกินข้าวที่ร้านแต่ไม่อร่อย' (ที่ and แต่ are stopwords; icu_folding must run AFTER the stop filter):
Tokens: ['ฉัน', 'กิน', 'ขาว', 'ราน', 'ไม', 'อรอย']
PASS: tone-marked stopwords removed

=== 7. Test Case 3: Thai Collation Sorting Comparison ===
[Flawed Default Byte Sort] (สระนำหน้า เ, ไ ไปอยู่หลังสุด):
['กบ', 'ขวด', 'ฮูก', 'เกาะ', 'ไก่']
[Correct Thai Collation Sort] (ตามพจนานุกรมราชบัณฑิตยสถาน):
['กบ', 'เกาะ', 'ไก่', 'ขวด', 'ฮูก']

=== 8. Test Case 4: Thai Hybrid Search (BM25 + k-NN with RRF) ===
Hybrid Results:
 - Score: 0.032786883 | Title: เปิดตัวสินค้าใหม่ แพลตฟอร์มคลาวด์สำหรับองค์กร
 - Score: 0.016129032 | Title: หนังสือคู่มือปัญญาประดิษฐ์และการประยุกต์ใช้ AI
 - Score: 0.015873017 | Title: อาหารแมวเกรดพรีเมียม สูตรบำรุงขนและผิวหนัง
 - Score: 0.015625 | Title: น้ำผลไม้แท้ 100% รสส้มเขียวหวาน
 - Score: 0.015384615 | Title: บริการคนขับรถผู้บริหารมืออาชีพ
```

---

## 7. โปรเจกต์ที่เกี่ยวข้อง

| โปรเจกต์ | คำอธิบาย | ลิงก์ |
|---|---|---|
| **opensearch-analysis-thaibreak** | OpenSearch Plugin ตัดคำภาษาไทย พร้อม Filters ครบชุด | [GitHub](https://github.com/kamthorn/opensearch-analysis-thaibreak) · [v1.4.0](https://github.com/kamthorn/opensearch-analysis-thaibreak/releases/tag/v1.4.0) |
| **thai-break** | Multi-language Thai Segmenter (PHP/Go/Rust/TypeScript/Python) | [GitHub](https://github.com/kamthorn/thai-break) |
| **Apache Lucene Upstream** | PR #16717, #16718, #16720, #16722, #16727 (🟣 All 5 Merged!) | [#16717](https://github.com/apache/lucene/pull/16717) · [#16718](https://github.com/apache/lucene/pull/16718) · [#16720](https://github.com/apache/lucene/pull/16720) · [#16722](https://github.com/apache/lucene/pull/16722) · [#16727](https://github.com/apache/lucene/pull/16727) |
| **OpenSearch Core Upstream** | RFC Issue #23151 — Modernize Thai Language Analysis in OpenSearch Core | [#23151](https://github.com/opensearch-project/OpenSearch/issues/23151) |

---

## 8. สิทธิ์การใช้งาน (License)

Apache License 2.0 — ดูรายละเอียดที่ [LICENSE.txt](LICENSE.txt)
สามารถนำไปประยุกต์ใช้ในระบบเชิงพาณิชย์และโปรเจกต์ภายในองค์กรได้อย่างอิสระ
