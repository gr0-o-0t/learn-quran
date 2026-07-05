# Database Schema (Schema) - Learn Quran Offline Mobile App

This project uses **Drift** (SQLite) to manage structured application data. Since SQLite compiles natively on Android and iOS, this schema represents the relational tables compiled into the local database sandbox.

---

## 1. Read-Only Knowledge Base Tables
These tables live in a separate, always-read-only database file (`kb.db`),
distinct from the user-data database below. The app never writes to them.
`kb.db` ships bundled as an app asset by default and can be updated from
Settings (see the knowledge-base-v1 design doc).

### 1.1. `verses`
Stores the Quran text, structural markers, and translations.
*   `id`: `INTEGER` (Primary Key)
*   `surah_number`: `INTEGER` (1-114)
*   `ayah_number`: `INTEGER`
*   `juz_number`: `INTEGER` (1-30)
*   `arabic_text`: `TEXT` (Uthmani script)
*   `english_text`: `TEXT` (Saheeh International)
*   `bangla_text`: `TEXT` (Muhiuddin Khan)

### 1.2. `hadiths`
Stores authentic Hadiths (Sahih al-Bukhari and Sahih Muslim only) for
referencing and the RAG pipeline.
*   `id`: `INTEGER` (Primary Key)
*   `book_name`: `TEXT` ('Sahih al-Bukhari' or 'Sahih Muslim')
*   `hadith_number`: `TEXT`
*   `chapter_title`: `TEXT`
*   `arabic_text`: `TEXT`
*   `english_text`: `TEXT`
*   `bangla_text`: `TEXT`

### 1.3. `tafsirs`
Tafsir Ibn Kathir commentary linked to verses.
*   `id`: `INTEGER` (Primary Key)
*   `surah_number`: `INTEGER` (Foreign Key -> `verses.surah_number`)
*   `ayah_number`: `INTEGER` (Foreign Key -> `verses.ayah_number`)
*   `author`: `TEXT` ('Ibn Kathir')
*   `content_english`: `TEXT`
*   `content_bangla`: `TEXT`

### 1.4. `kb_meta`
Single-row-per-key metadata describing this `kb.db` build.
*   `key`: `TEXT` (Primary Key) — e.g. `'version'`, `'built_at'`, `'embedding_model'`
*   `value`: `TEXT`

Note: Hindi translations/commentary are intentionally not included — no
authentic source was found for Hindi Hadith or Tafsir Ibn Kathir (see the
knowledge-base-v1 design doc's Decision Log). AI-translation-on-demand is a
deferred, separate feature.

---

## 2. Writable User Data Tables
These tables track user progress, logs, and interaction history on the local device storage.

### 2.1. `user_progress`
Tracks the user's reading and memorization milestones.
*   `id`: `INTEGER` (Primary Key, Auto-Increment)
*   `surah_number`: `INTEGER`
*   `ayah_number`: `INTEGER`
*   `last_read_timestamp`: `INTEGER` (Unix Epoch)
*   `is_memorized`: `BOOLEAN` (Default: `FALSE`)
*   `bookmark_folder`: `TEXT` (Nullable, e.g., 'Daily Study', 'Favorites')

### 2.2. `salat_logs`
Logs completed prayers locally (self-reported) to display on the dashboard.
*   `date`: `TEXT` (Primary Key, Format: `YYYY-MM-DD`)
*   `fajr_completed`: `BOOLEAN` (Default: `FALSE`)
*   `dhuhr_completed`: `BOOLEAN` (Default: `FALSE`)
*   `asr_completed`: `BOOLEAN` (Default: `FALSE`)
*   `maghrib_completed`: `BOOLEAN` (Default: `FALSE`)
*   `isha_completed`: `BOOLEAN` (Default: `FALSE`)

### 2.3. `conversations`
Stores chat metadata for the Q&A Agent.
*   `id`: `TEXT` (Primary Key, UUID)
*   `title`: `TEXT` (Generated summary of the conversation)
*   `created_at`: `INTEGER` (Unix Epoch)
*   `last_active`: `INTEGER` (Unix Epoch)

### 2.4. `messages`
Stores actual messages within a conversation.
*   `id`: `TEXT` (Primary Key, UUID)
*   `conversation_id`: `TEXT` (Foreign Key -> `conversations.id` ON DELETE CASCADE)
*   `sender`: `TEXT` ('user' or 'agent')
*   `text_content`: `TEXT`
*   `citations_json`: `TEXT` (Serialized array of sources, e.g., `[{"type": "quran", "surah": 2, "ayah": 153}, {"type": "hadith", "book": "bukhari", "number": "12"}]`)
*   `timestamp`: `INTEGER` (Unix Epoch)

### 2.5. `user_engagement_state`
A key-value table storing local state metrics used by the daily story compiler and agent check-ins.
*   `key`: `TEXT` (Primary Key)
*   `value`: `TEXT` (String or Serialized JSON)
    *   *Examples:*
        *   `key = "last_read_topic"`, `value = "patience"`
        *   `key = "current_streak"`, `value = "5"`
        *   `key = "engagement_score"`, `value = "85"`
        *   `key = "recent_question_sentiment"`, `value = "seeking_comfort"`

---

## 3. Vector Search Table
Lives in `kb.db` alongside the tables in section 1, precomputed at build
time (never generated on-device). Built as a plain table, not a `vec0`
virtual table — `sqlite-vec`'s native extension was found not to load in
the current dev/CI environment, so `RagRepository`'s existing Dart-side
dot-product fallback is the search path this table is built for.

### 3.1. `vec_knowledge_base`
*   `rowid`: `INTEGER` (Primary Key — maps to row ID in `verses`, `hadiths`, or `tafsirs`, using the existing `hadithOffset`/`tafsirOffset` scheme in `RagRepository`)
*   `embedding`: `BLOB` (384-dim float32 vector, English text only, from BGE-small-en-v1.5)
