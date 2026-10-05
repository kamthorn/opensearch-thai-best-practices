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
  - [5.5 Pipeline แบบ thaibreak](#55-pipeline-แบบ-thaibreak)
  - [5.6 การค้นหาที่ทนต่อการสะกดผิด (Typo Tolerance)](#56-การค้นหาที่ทนต่อการสะกดผิด-typo-tolerance)
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
(ออกเป็นทั้งประโยค)              ความเสถียรข้ามแพลตฟอร์มสูง        พจนานุกรม 41,272 คำในตัว (v1.5.1)
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
| **Token Filters พิเศษ** | ❌ | ❌ | ❌ | ✅ Normalization, Tone, Soundex, Keyboard, Number, Acronym, Romanization, Collation |

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
│   ├── 05-full-thai-analyzer.json         # Full Production Analyzer Configuration (analysis-icu)
│   └── 06-thaibreak-analyzer.json         # Analyzer แบบ analysis-thaibreak + ฟิลด์ย่อย + normalizer สำหรับ sort
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
    ├── bulk-thaibreak.json                # ข้อมูล 14 เอกสารสำหรับทดสอบ pipeline แบบ thaibreak
    ├── test-queries.sh                    # สคริปต์ทดสอบส่วน 01–03 (ใช้เฉพาะ analysis-icu)
    └── test-thaibreak.sh                  # สคริปต์ทดสอบส่วน 5.5–5.6 (ต้องมี analysis-thaibreak)
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
  https://github.com/kamthorn/opensearch-analysis-thaibreak/releases/download/v1.5.1/analysis-thaibreak-3.9.0.0.zip

# OpenSearch 2.19.0
bin/opensearch-plugin install \
  https://github.com/kamthorn/opensearch-analysis-thaibreak/releases/download/v1.5.1/analysis-thaibreak-2.19.0.0.zip
```

รองรับ: `2.15.0` | `2.17.1` | `2.18.0` | `2.19.0` | `3.8.0` | `3.9.0` — ZIP ติดตั้งได้เฉพาะ OpenSearch รุ่นที่ระบุในชื่อไฟล์ ([ดู Release ทั้งหมด](https://github.com/kamthorn/opensearch-analysis-thaibreak/releases/tag/v1.4.0)) ส่วน `2.11.x`–`2.13.x` ใช้ไม่ได้เพราะ plugin ต้องการ Java 21

ตัวอย่างใน repo นี้ (ส่วน 01–03) ใช้ `icu_tokenizer` และ `icu_collation_keyword` จึงต้องมี **`analysis-icu`** (`bin/opensearch-plugin install analysis-icu`) ส่วน `analysis-thaibreak` ไม่จำเป็น ขั้นตอน `docker-compose up -d` ด้านล่างติดตั้งทั้ง `analysis-icu` และ `analysis-thaibreak` (OpenSearch 2.19.0 ตัวแปร `THAIBREAK_ZIP_URL` เปลี่ยนเวอร์ชันได้) ทดสอบแล้วบน OpenSearch 2.19.0 และ 3.9.0

### ขั้นตอนการรัน
1. **เปิด OpenSearch คลัสเตอร์:**
   ```bash
   docker-compose up -d
   ```

2. **รันการทดสอบและสร้าง Index สาธิต:**
   ```bash
   ./sample-data/test-queries.sh      # ส่วน 01–03 (analysis-icu)
   ./sample-data/test-thaibreak.sh    # ส่วน 5.5–5.6 (analysis-thaibreak)
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
> **ขอบเขตของ regex เหล่านี้:** จัดการ `เเ`, `นํ้า`/`น้ํา`, สระหรือเครื่องหมายซ้ำ และ zero-width ได้ แต่ **ไม่** จัดการ `นำ้` (วรรณยุกต์พิมพ์หลัง `ำ`), สระตามซ้ำ (`ค่าา`), วรรณยุกต์ต่างตัวซ้อนกัน หรือวรรณยุกต์ที่อยู่หน้าสระบน (`ท่ี` → `ที่`) ถ้าต้องครอบคลุมกว่านี้ ให้ใช้ `thaibreak_normalization` ของ plugin [`analysis-thaibreak`](https://github.com/kamthorn/opensearch-analysis-thaibreak) (v1.4.0 ขึ้นไป) หรือ `ThaiCharFilter` / `ThaiNormalizationFilter` ของ Lucene 10.6 (ชื่อ SPI ใน Lucene คือ `thai` และ `thaiNormalization`) ซึ่งยังไม่มีให้ใช้ใน OpenSearch core ([#23151](https://github.com/opensearch-project/OpenSearch/issues/23151)) ส่วน Elasticsearch เพิ่มเข้ามาแล้วในโค้ดที่ยังไม่ปล่อย ([elastic/elasticsearch#160853](https://github.com/elastic/elasticsearch/pull/160853)) โดยใช้ชื่อ char filter `thai` และ token filter `thai_normalization`

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

**ทางเลือกโดยไม่ใช้ ICU:** plugin `analysis-thaibreak` มี filter `thaibreak_collation` ใช้ใน `normalizer` ของฟิลด์ `keyword` ได้ ผลเรียงตรงกับ ICU (วรรณยุกต์เป็นคีย์ระดับรอง จึง `กลอง` มาก่อน `กล้อง`) แต่ไม่ต้องติดตั้ง `analysis-icu` ดูตัวอย่างใน [06-thaibreak-analyzer.json](01-analysis-pipeline/06-thaibreak-analyzer.json) (`name.sort`) และผลทดสอบใน [5.5](#55-pipeline-แบบ-thaibreak)

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

### 5.5 Pipeline แบบ thaibreak

[06-thaibreak-analyzer.json](01-analysis-pipeline/06-thaibreak-analyzer.json) ใช้ tokenizer `thaibreak` (ตัดคำด้วยพจนานุกรมและ TCC) แทน `icu_tokenizer` และไม่ใช้ `icu_folding` ฟิลด์หลักจึงยังแยกคำที่ต่างกันด้วยวรรณยุกต์ (`ข้าว` ≠ `ขาว`, `กลอง` ≠ `กล้อง`):

| ฟิลด์ | analyzer | ใช้ทำอะไร |
|---|---|---|
| `title` | `thai_tb` = `thaibreak` + `thaibreak_normalization` + `lowercase` + `decimal_digit` + stopwords | ค้นหาหลัก แม่นยำ |
| `title.sub` | `thai_tb_sub` (decompound `mixed`, ค้นด้วย `thai_tb`) | ค้นส่วนย่อยของคำประสม (`สนามบิน` → `สนาม`, `บิน`) |
| `title.loose` | `thai_tb_loose` = `thai_tb` + `thaibreak_tone` | ตาข่ายสำรองสำหรับวรรณยุกต์ผิดหรือหาย |
| `name.sort` | `keyword` + normalizer (`thaibreak_normalization` + `thaibreak_collation`) | เรียงตามพจนานุกรม |

```json
"analyzer": {
  "thai_tb": {
    "type": "custom",
    "tokenizer": "thai_tb_words",
    "filter": ["thai_tb_normalization", "lowercase", "decimal_digit", "thai_curated_stopwords"]
  }
}
```

ข้อควรระวัง:
- **analyzer แบบ `custom` ต้องใส่ `thaibreak_normalization` เอง** ไว้ต้น chain ทุกตัว (รวม analyzer ของฟิลด์ย่อย) analyzer สำเร็จรูป `thaibreak` และ `thaibreak_person` ใส่ให้อัตโนมัติตั้งแต่ v1.4.0 ถ้าลืม เอกสารที่พิมพ์ `นํ้าตาล` จะค้นด้วย `น้ำตาล` ไม่เจอ ทั้งที่ตัดคำถูก เพราะ token ยังเป็นรูปเดิมของเอกสาร
- ลำดับ filter: `thaibreak_normalization` มาก่อน `stop` และ `stop` มาก่อน `thaibreak_tone` (เหตุผลเดียวกับ `icu_folding` ใน [5.2](#52-การจัดชุดคำหยุด-curated-stopwords))
- เปลี่ยน analyzer บน index เดิมแล้วต้อง **reindex**

`./sample-data/test-thaibreak.sh` ตรวจพฤติกรรมเหล่านี้กับข้อมูล 14 เอกสาร: `น้ำตาล`, `นำ้ตาล` และ `นํ้าตาล` ค้นเจอเอกสารเดียวกัน, `แมว` เจอเอกสารที่เก็บเป็น `เเมว`, stopwords ที่มีวรรณยุกต์ถูกตัด, `ข้าว` ไม่ชน `ขาว` บนฟิลด์หลัก (ฟิลด์ `.loose` ชน ตามที่ออกแบบ) และ `thaibreak_collation` เรียง `ไก่ทอด` ไว้ใกล้ `ก` แทนที่จะอยู่ท้ายสุด

### 5.6 การค้นหาที่ทนต่อการสะกดผิด (Typo Tolerance)

OpenSearch มี `fuzziness` ในตัว (ระยะ Levenshtein นับเป็นตัวอักษร สลับตำแหน่งสองตัวติดกันนับเป็น 1) แต่ภาษาไทยได้ผลจำกัด:
- **`AUTO` ให้ระยะน้อย:** 0 สำหรับคำ 1–2 ตัวอักษร, 1 สำหรับ 3–5 ตัว, 2 สำหรับ 6 ตัวขึ้นไป คำไทยหลังตัดคำมักสั้น และวรรณยุกต์กับสระนับเป็นตัวอักษรเต็ม
- **การสะกดผิดเปลี่ยนการตัดคำ:** fuzzy ทำกับ term หลังตัดคำ แต่คำที่พิมพ์ผิดมักถูกตัดเป็นคำอื่น เช่น `สนามบิล` → `สนาม|บิล`, `จักยานยนต์` → `จัก|ยาน|ยนต์`, `คอมพิวเตอ` → `คอม|พิวเตอ` ไม่มี term ในฟิลด์หลักที่อยู่ห่างหนึ่งตัวอักษรให้จับคู่

ผลจาก `test-thaibreak.sh` (ข้อมูล 14 เอกสาร ใช้เป็นตัวอย่างประกอบ ไม่ใช่ benchmark; ✓ = เจอเอกสารที่ตั้งใจ, ตัวเลข = จำนวนเอกสารอื่นที่ติดมาด้วย):

| คำที่พิมพ์ผิด | exact | fuzzy AUTO | fuzzy 1 | `.loose` | `.sub` | layered |
|---|---|---|---|---|---|---|
| `ขาวหอม` (วรรณยุกต์หาย) | ✓ +1 | ✓ +1 | ✓ +1 | ✓ +1 | ✓ +2 | ✓ +2 |
| `ไก้ทอด` (วรรณยุกต์ผิด) | ✓ +0 | ✓ +1 | ✓ +1 | ✓ +0 | ✓ +0 | ✓ +0 |
| `คอมพิวเตอ` (การันต์หาย) | ✗ | ✗ +1 | ✗ | ✗ | ✗ | ✗ |
| `สนามบิล` (พยัญชนะท้ายผิด) | ✗ | ✗ | ✗ | ✗ | ✓ +0 | ✓ +0 |
| `จักยานยนต์` (ตกหนึ่งตัวอักษร) | ✗ | ✗ | ✗ | ✗ | ✓ +0 | ✓ +0 |
| `มือถอ` (สระ/ตัวอักษรผิด) | ✗ | ✗ | ✗ | ✗ | ✓ +1 | ✓ +1 |
| **เจอที่ตั้งใจ** | 2/6 | 2/6 | 2/6 | 2/6 | 5/6 | 5/6 |

`layered` = `title` (×3) + `title.loose` (×1) + `title.sub` (×0.5) ในหนึ่ง `bool.should` สิ่งที่ได้ผลคือ `.sub` เพราะมันเก็บส่วนย่อยของคำประสมด้วย การพิมพ์ผิดที่ยังเหลือส่วนย่อยที่ถูก (`สนาม`, `ยนต์`, `มือ`) จึงยังค้นเจอ ส่วน `fuzziness` ไม่เพิ่ม recall ในชุดนี้และดึงเอกสารที่ไม่เกี่ยวมาด้วย (`+1`)

แนวปฏิบัติ:
1. จัดการสะกดต่างรูปแต่หน้าตาเหมือนกันด้วย **normalization** (`นํ้า`, `นำ้`, `เเ`) ไม่ใช่ fuzzy
2. ใช้ฟิลด์ย่อยแยกหน้าที่: `.loose` สำหรับวรรณยุกต์ และ `.sub` สำหรับส่วนย่อยของคำประสม ให้น้ำหนักต่ำกว่าฟิลด์หลักเสมอ เพื่อให้ผลที่ตรงเป๊ะขึ้นก่อน
3. ถ้าจะใช้ `fuzziness` ให้ตั้ง `prefix_length: 1` และ `max_expansions` ให้ต่ำ เพราะขยายหลาย term ช้ากว่า match ปกติ และใช้กับคำที่ยาวพอ
4. ชื่อบุคคลที่ออกเสียงเหมือนกันแต่สะกดต่าง (`ณัฐพล` / `นัฐพล`) ใช้ `thaibreak_soundex` ซึ่ง Levenshtein จับไม่ได้ (ดู README ของ plugin)
5. ถ้าต้องการให้ทนต่อการพิมพ์ผิดแบบกว้างจริงๆ ทางเลือกคือ n-gram (index ใหญ่ขึ้น) ในการทดลองแยกบนข้อมูลชุดเดียวกัน (ฟิลด์ย่อย n-gram 2–3 ตัวอักษร `minimum_should_match: 60%`, ไม่ได้รวมอยู่ในไฟล์ตัวอย่าง) เจอเอกสารที่ตั้งใจครบ 6/6 แต่มีเอกสารอื่นติดมามากกว่า (สูงสุด +6) ต้องวัดกับข้อมูลจริงก่อนนำไปใช้

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

และเมื่อรัน `./sample-data/test-thaibreak.sh` (ต้องมี `analysis-thaibreak`):

```text
=== Test A: spelling variants index to the same term ===
PASS: น้ำตาล finds the document stored as นํ้าตาล  ['1']
PASS: นำ้ตาล (tone after ำ) finds it too  ['1']
PASS: นํ้าตาล (legacy) finds น้ำตาล documents  ['1']
PASS: แมว finds the document stored as เเมว (double Sara E)  ['6']

=== Test B: stopwords with tone marks are removed ===
Tokens: ['บริการ', 'ส่ง', 'อาหาร', 'ถึง', 'ราคา', 'ถูก']
PASS: ที่, แต่, ซึ่ง removed

=== Test C: tone marks keep words apart on the main field, .loose is the safety net ===
PASS: ข้าว finds only the rice document  ['3']
PASS: กลอง and กล้อง are different terms  ['11'] / ['10']
PASS: title.loose: ขาวหอม (tone dropped) finds the rice document with AND  ['3']
PASS: title: ขาวหอม with AND finds nothing

=== Test D: thaibreak_collation normalizer sorts in dictionary order ===
Byte order  : ['กลอง', 'กล้อง', 'ข้าวหอม', 'ครีมผิวขาว', 'คลาวด์', 'คอมพิวเตอร์', 'จักรยานยนต์', 'น้ำตาล', 'น้ำผลไม้', 'มือถือ', 'สนามบิน', 'ส่งอาหาร', 'อาหารแมว', 'ไก่ทอด']
Thai order  : ['กลอง', 'กล้อง', 'ไก่ทอด', 'ข้าวหอม', 'ครีมผิวขาว', 'คลาวด์', 'คอมพิวเตอร์', 'จักรยานยนต์', 'น้ำตาล', 'น้ำผลไม้', 'มือถือ', 'ส่งอาหาร', 'สนามบิน', 'อาหารแมว']
PASS: ไก่ทอด (leading vowel) is last in byte order but not in Thai order
PASS: กลอง sorts before กล้อง (tone mark is a second-level key)
```

(Test E คือตารางใน [5.6](#56-การค้นหาที่ทนต่อการสะกดผิด-typo-tolerance)) ผลเหมือนกันบน OpenSearch 2.19.0 (plugin 2.19.0.0) และ 3.9.0 (plugin 3.9.0.0)

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
