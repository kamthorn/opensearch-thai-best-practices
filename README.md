# OpenSearch Thai Best Practices 🇹🇭

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
- [7. สิทธิ์การใช้งาน (License)](#7-สิทธิ์การใช้งาน-license)

---

## 1. ปัญหาคลาสสิกของภาษาไทยบน OpenSearch

การตั้งค่า OpenSearch โดยใช้ Analyzer เริ่มต้น (`standard` หรือ `thai`) มักพบปัญหาสำคัญ 4 ประการ:

| ปัญหา | พฤติกรรมเดิมที่ผิดพลาด | ผลกระทบต่อระบบค้นหา | แนวทางแก้ไขใน Best Practices |
|---|---|---|---|
| **1. อักขรวิธีและสระซ้ำ** | `เเมว` (สระเอ 2 ตัว), `นํ้า` (นิคหิต+สระอา), `ดีี` (สระอีซ้ำ) | ค้นหา `แมว` หรือ `น้ำ` ไม่พบ | ใช้ `pattern_replace` char filters กวาดและจัดรูป NFC ก่อนตัดคำ |
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
(ออกเป็นทั้งประโยค)              ความเสถียรข้ามแพลตฟอร์มสูง        พจนานุกรม 25,907 คำในตัว
                                                           รองรับ User Dict แบบ Plaintext
```

| คุณสมบัติ | `standard` | `thai` (Built-in) | `icu_tokenizer` | `thaibreak` (Plugin) |
|---|---|---|---|---|
| **การรองรับภาษาไทย** | ❌ ไม่ตัดคำ | ⚠️ พื้นฐาน | ✅ ดีมาก | 🌟 แนะนำระดับสูง |
| **อัลกอริทึม** | Whitespace/Punctuation | JDK `BreakIterator` | ICU4J Dictionary-based | Viterbi Shortest Path + TCC |
| **ความเสถียรข้าม JVM** | คงที่ | ❌ ต่างตามเวอร์ชัน Java | ✅ สม่ำเสมอ | ✅ 100% Deterministic |
| **User Dictionary** | ❌ | ❌ (รอ upstream Lucene) | ⚠️ ต้อง compile `.dict` | ✅ โหลดผ่าน Plaintext TSV ได้ทันที |
| **การป้องกันพยางค์แตก** | ❌ | ❌ | ⚠️ บางคำ | ✅ ควบคุมด้วย TCC Rules |

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

---

## 4. เริ่มต้นใช้งานแบบด่วน (Quick Start)

### ข้อกำหนดระบบ
- Docker และ Docker Compose
- `curl` และ `python3` (สำหรับรันชุดทดสอบ)

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
}
```

### 5.2 การจัดชุดคำหยุด (Curated Stopwords)

ในเอกสารเดิมของ Apache Lucene / OpenSearch รายการ Stopwords ได้รับอิทธิพลจากงานวิจัยบทความข่าวการเมือง ทำให้มีคำกริยาและคำนามทั่วไปปะปนอยู่ เช่น `"ผล"`, `"เปิด"`, `"ส่ง"`, `"ทาง"`

ใน Best Practices นี้ เราใช้รายการ [03-curated-stopwords.txt](01-analysis-pipeline/03-curated-stopwords.txt) ซึ่งคัดเฉพาะ:
- **คำเชื่อม:** `ที่`, `ซึ่ง`, `อัน`, `และ`, `หรือ`, `แต่`, `ดังนั้น`, `สำหรับ`
- **คำบุพบท:** `ใน`, `บน`, `ใต้`, `แห่ง`, `ของ`, `โดย`, `เพื่อ`, `ต่อ`
- **คำลงท้าย:** `ครับ`, `ค่ะ`, `คะ`, `นะ`, `จ๊ะ`, `เลย`

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
      "index": false,
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
$$\text{RRF Score} = \sum_{m \in M} \frac{w_m}{k + r_m(d)}$$

---

## 6. ผลการทดสอบ (Verification & Test Results)

เมื่อรัน `./sample-data/test-queries.sh` ระบบจะสาธิตผลลัพธ์จริง:

```text
=== 5. Test Case 1: Normalization & Typo Tolerance ===
Testing search for 'แมว' against document indexed with double-E 'เเมว':
Hits: 1 ['อาหารแมวเกรดพรีเมียม สูตรบำรุงขนและผิวหนัง']

=== 6. Test Case 2: Curated Stopwords (No Over-filtering) ===
Testing search for 'ผลไม้' (previously over-filtered in Lucene when 'ผล' was removed):
Hits: 1 ['น้ำผลไม้แท้ 100% รสส้มเขียวหวาน']

=== 7. Test Case 3: Thai Collation Sorting Comparison ===
[Flawed Default Byte Sort] (สระนำหน้า เ, ไ ไปอยู่หลังสุด):
['กบ', 'ขวด', 'ฮูก', 'เกาะ', 'ไก่']

[Correct Thai Collation Sort] (ตามพจนานุกรมราชบัณฑิตยสถาน):
['กบ', 'เกาะ', 'ไก่', 'ขวด', 'ฮูก']

=== 8. Test Case 4: Thai Hybrid Search (BM25 + k-NN with RRF) ===
Hybrid Results:
 - Score: 0.032786883 | Title: เปิดตัวสินค้าใหม่ แพลตฟอร์มคลาวด์สำหรับองค์กร
 - Score: 0.032258064 | Title: หนังสือคู่มือปัญญาประดิษฐ์และการประยุกต์ใช้ AI
```

---

## 7. สิทธิ์การใช้งาน (License)

Apache License 2.0 — ดูรายละเอียดที่ [LICENSE.txt](LICENSE.txt)
สามารถนำไปประยุกต์ใช้ในระบบเชิงพาณิชย์และโปรเจกต์ภายในองค์กรได้อย่างอิสระ
