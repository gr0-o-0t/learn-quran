# UI/UX Design Guidelines (Design) - Learn Quran Offline Mobile App

This document outlines the visual system, style guide, and design tokens for the Flutter mobile application, ensuring a serene, modern, and highly readable user experience.

---

## 1. Color Palette (Serene & Modern)
We use a clean, light-first palette featuring organic green and ivory tones that feel scholarly and peaceful, combined with high-contrast text for reading comfort.

| Token Name | Hex Code | HSL Representation | Purpose |
|---|---|---|---|
| **Primary (Forest Green)** | `#0F5132` | `hsl(152, 69%, 19%)` | Dark brand color, app bar headers, titles |
| **Secondary (Emerald)** | `#198754` | `hsl(152, 69%, 31%)` | Active tabs, button backgrounds, highlights |
| **Background (Soft Ivory)** | `#FDFBF7` | `hsl(40, 43%, 98%)` | Main screen background (easy on diacritics) |
| **Surface (Mint/Ivory Card)** | `#F5F7F4` | `hsl(100, 10%, 96%)` | Inset cards, search bars, list tiles |
| **Text Primary (Charcoal)** | `#2C302E` | `hsl(150, 5%, 18%)` | Primary reading text, translation text |
| **Text Secondary (Muted)** | `#5C6460` | `hsl(150, 4%, 38%)` | Subtitles, verse references, secondary info |
| **Accent Gold (Ayah Marker)** | `#D4AF37` | `hsl(47, 65%, 53%)` | Ayah number rings, active bookmarks, stars |

---

## 2. Typography System
We use a hybrid font pairing optimized for multilingual readability.

### 2.1. Font Families
*   **Arabic Text:** **Amiri** (default serif, classic Naskh style) or **Scheherazade New** (for clean diacritics).
*   **Translation & UI Text:** **Outfit** (modern, geometric sans-serif for titles) and **Inter** (neutral, high-legibility sans-serif for translations and settings).

### 2.2. Font Sizes & Line Heights
*   **Arabic Ayah:** `28sp`, line-height `2.0` (critical to prevent Arabic diacritic symbols from overlap or clipping).
*   **Translation text:** `16sp`, line-height `1.65` (relaxed spacing for reflective, slow reading).
*   **Surah Name / Header:** `24sp` (Outfit Bold), line-height `1.3`.
*   **UI Label / Subtitle:** `14sp` (Inter Medium), line-height `1.4`.

---

## 3. Spacing & Layout Architecture
To foster a calm and meditative atmosphere, we employ a relaxed spatial rhythm.

*   **Screen Margins:** `24dp` horizontal padding for all outer page layouts.
*   **Card Internals:** `20dp` padding inside Ayah and story cards to allow elements to breathe.
*   **Vertical Rhythm:** `16dp` spacing between consecutive items in scroll views.
*   **Card Radius:** `16dp` corner rounding for cards and bottom sheets to give a organic, soft interface feeling.

---

## 4. Interaction & Micro-Animations
*   **Ayah Tap Effect:** A subtle scale-down (`0.98x`) and soft emerald border highlight when tapping an Ayah card to focus on reading/viewing actions.
*   **Audio Highlight:** Active playing Ayah cards transition their background to a very soft mint tint (`#EDF3EE`).
*   **Transitions:**
    *   *Bottom Sheets:* Slide up smoothly using `Curves.easeOutQuart` over `300ms`.
    *   *Route changes:* Fade-through transition pattern rather than sliding, minimizing screen jarring.
*   **Bookmark Toggle:** A soft radial gold glow animation triggers around the star icon when selected.
