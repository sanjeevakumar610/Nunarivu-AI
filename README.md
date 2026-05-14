# நுணரிவு AI — Nunarivu AI

### Offline Tamil/English AI Tutor for Sri Lankan Students
**Gemma 4 Good Hackathon — Future of Education · Digital Equity & Inclusivity**

---

## The Problem

Over **1 million Tamil-medium students** in Sri Lanka study from government textbooks that exist only as scanned PDF files — printed in legacy Tamil fonts (Baamini, SHREE-TAM7) that **no standard text extractor can read**. These students:

- Have **no reliable internet** in rural and estate areas
- Cannot afford expensive private tutoring
- Have **no AI tool** that speaks their language
- Study from books that are invisible to modern software

Nunarivu AI solves this completely — offline, free, and in their own language.

---

## What is Nunarivu AI?

A **fully offline** Android app that runs **Google Gemma 4 E2B on the device itself** — no server, no subscription, no internet required after setup.

Students open any Grade 10 or Grade 11 Tamil-medium textbook, ask questions in spoken Tamil, and get accurate answers read back aloud — all grounded strictly in the textbook page they are reading.

> *"நுணரிவு" (Nunarivu) means "intelligence" or "wisdom" in Tamil.*

---

## Demo

📱 **Tested on**: Redmi Note 14 — a budget Android phone real students own  
🔇 **Turn on Airplane Mode** — every feature still works

---

## Key Features

### 🤖 On-Device Gemma 4 E2B
- Runs **Google Gemma 4 E2B** via **LiteRT-LM** directly on the Android device
- No API calls, no cloud dependency, no data leaves the phone
- Student side-loads the model once from HuggingFace

### 📚 Tamil Textbook Library (161 Books)
- Auto-imports all PDFs from the app's external storage folder
- Covers Grade 10 and Grade 11 Sri Lankan curriculum: Maths, Science, History, Tamil Literature, Islam, Christianity, Hinduism, Geography, ICT, Health, Commerce, and more
- Books organised by grade and subject automatically

### 🔍 Tesseract OCR — The Core Technical Innovation

Sri Lankan Tamil textbooks use **legacy encoding fonts** (Baamini, SHREE-TAM7, FMAbhaya) with WinAnsiEncoding and no Unicode CMap. Every standard PDF text extractor — including PyMuPDF, PDFBox, and Syncfusion — returns **zero readable text** from these books.

**Our solution**: Render each page to a 2× PNG image using Android's native PdfRenderer, then run **Tesseract OCR** (Tamil + English, LSTM engine, PSM 6) on the image. Results are cached in SQLite so each page is only processed once.

```
PDF Page → pdfx renders to 1044×1368 PNG → Tesseract tam+eng → Tamil Unicode text
```

### 🎤 Tamil Voice Q&A
- Tap the mic, ask in spoken Tamil or English
- 6 seconds of silence tolerance — waits for the student to finish thinking
- Uses Android's offline `ta-IN` speech recognition — no internet needed

### 📖 Page-Aware Answers (No Hallucination)
- The model answers **only from the current page's OCR text**
- Hard block on general knowledge — if the answer is not on the page, the app says exactly that
- Safe for exam preparation — students will not write wrong answers from AI guesses

### 🔊 Text-to-Speech
- Every AI answer can be read aloud at one tap
- Strips markdown symbols before speaking — clean audio
- Students with reading difficulties can listen instead of read

### 🌐 In English / தமிழில் Buttons
Every AI reply has two instant re-explanation buttons:
- **In English** — re-explains the same answer in simple English
- **தமிழில்** — re-explains in simple Tamil  
No retyping — one tap switches the language of the explanation

### 🧠 Topic-Aware Chat Memory
- Remembers last 5 exchanges and stays on the current topic
- Encouragement only on genuinely deep or complex questions — not on every simple reply
- Full conversation history saved per session in local SQLite

### ⏰ Study Reminders and Badges
- Daily study alarms with Tamil notification text
- Achievement badges unlocked by question count and study-day streaks
- All progress tracked locally — no account needed

### 👤 Multi-Student Profiles
- Multiple student profiles on one device (siblings, classmates)
- Per-profile settings: name, grade, language preference, learning disability mode, AI persona (Teacher / Friend / Parent)

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Flutter (Android)                   │
├──────────────┬──────────────────┬───────────────────┤
│  Chat Tab    │   Library Tab    │   Settings Tab    │
│  Gemma 4 Q&A │   161 Books      │  Profile / Badges │
├──────────────┴──────────────────┴───────────────────┤
│                  Services Layer                      │
│  ModelService  │  OcrService    │  SttService       │
│  (LiteRT-LM)   │  (Tesseract)   │  (ta-IN offline)  │
│  PdfService    │  BookSeed      │  TtsService       │
│  BadgeService  │  Reminders     │  DbService        │
├─────────────────────────────────────────────────────┤
│           Local Storage — 100% on-device             │
│  SQLite: profiles, chat history, OCR cache, books   │
│  SharedPreferences: settings, theme, seed flags     │
└─────────────────────────────────────────────────────┘
```

### How Gemma 4 is Integrated

The model runs via a custom JNI bridge (`InferencePlugin.kt`) that calls the LiteRT-LM C++ runtime and streams tokens back to Flutter through an `EventChannel`:

```kotlin
// InferencePlugin.kt
fun inferStream(prompt: String): Unit {
    // Calls LiteRT-LM native library
    // Streams each token to Flutter via EventChannel sink
}
```

```dart
// ModelService.dart
Stream<String> inferStream(String prompt) {
    // Each emitted string is one token
    // UI updates in real time as tokens arrive
}
```

### OCR Pipeline

```dart
// OcrService.dart — called once per page, result cached forever
PDF file
  → Copy to ASCII temp path           // avoids Android PdfRenderer Tamil filename bug
  → pdfx renders page at 2× scale     // 1044 × 1368 px PNG
  → Tesseract OCR (tam+eng, oem=3, psm=6)
  → Store in SQLite pdf_chunks table  // chunk_index = -1 marks OCR entries
  → Memory-cached for instant reuse
```

### Prompt Design (Exam Safety)

```
You are a teacher answering a student's question about their textbook.
Answer STRICTLY using ONLY the page text below.
Do NOT use any outside knowledge.
If the answer cannot be found in the page text, reply ONLY with:
"இந்தப் பக்கத்தில் இந்தத் தகவல் இல்லை · This information is not on this page."

PAGE TEXT (page N):
"""
[Tesseract OCR output]
"""

Question: [student's question]
Answer in Tamil:
```

---

## Setup for Judges

### Requirements
- Android phone running API 24 or higher
- About 3 GB of free storage for the model

### Step 1 — Install the APK
Download `app-debug.apk` from [Releases](https://github.com/sanjeevakumar610/Nunarivu-AI/releases) and install it.

### Step 2 — Download the Gemma 4 model
The model is Google's official release on HuggingFace (free, requires a HuggingFace account):

```
https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm
```

Download the file: `gemma-4-E2B-it-litert-lm.litertlm` (approximately 2.4 GB)

Copy it to the device using ADB:
```bash
adb push gemma-4-E2B-it-litert-lm.litertlm \
  /sdcard/Android/data/com.example.nunarivu_ai/files/models/gemma-4-E2B-it-litert-lm.litertlm
```

Or copy it manually using a file manager to:
```
Internal Storage → Android → data → com.example.nunarivu_ai → files → models
```

### Step 3 — Add a sample textbook (optional)
The app works as a general tutor without textbooks. To test the OCR and page-aware Q&A, place any Tamil PDF into:
```
Android/data/com.example.nunarivu_ai/files/books/Grade 10/Subject Name/book.pdf
```
The app will auto-scan and import it on next launch.

### Step 4 — Create a profile and start
1. Open the app and create a student profile
2. Chat tab → ask any question in Tamil or English
3. Library tab → open a textbook → ask about the page you are reading
4. **Turn on Airplane Mode and ask again — it still works** ✅

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Framework | Flutter 3 / Dart |
| AI Model | Google Gemma 4 E2B — LiteRT-LM |
| Model Runtime | LiteRT-LM C++ via custom JNI plugin |
| OCR Engine | Tesseract 4 LSTM — Tamil + English |
| PDF Page Rendering | pdfx (Android native PdfRenderer) |
| PDF Viewer | Syncfusion Flutter PDF Viewer |
| State Management | Flutter Riverpod 2 |
| Local Database | SQLite via sqflite |
| Speech-to-Text | Android offline ta-IN STT |
| Text-to-Speech | flutter_tts |
| Typography | Noto Sans Tamil |
| Notifications | flutter_local_notifications |

---

## Why This Matters

| Challenge | Our Solution |
|-----------|-------------|
| No internet in rural Sri Lanka | 100% offline after one-time setup |
| Legacy Tamil font PDFs unreadable by software | Tesseract OCR on rendered page images |
| No Tamil-language AI tools for students | Tamil STT + TTS + full Tamil UI |
| Exam risk from AI hallucination | Hard block — model only reads from the page |
| Expensive private tutoring | Free, open source, runs on any budget Android phone |
| Multiple students sharing one device | Multi-profile with separate history and settings |

---

## Hackathon Categories

**Primary**: Future of Education  
**Secondary**: Digital Equity & Inclusivity

This app directly addresses SDG 4 (Quality Education) for Tamil-medium students in Sri Lanka — a community underserved by every existing AI education product.

---

## Privacy

🔒 **Zero data leaves the device. Ever.**

No analytics, no telemetry, no user account, no server calls.  
All chat history, student profiles, OCR text, and usage data is stored exclusively in local SQLite on the student's phone.

---

## Build from Source

```bash
# Prerequisites: Flutter 3.x, Android SDK, NDK r27

git clone https://github.com/sanjeevakumar610/Nunarivu-AI.git
cd Nunarivu-AI
flutter pub get
flutter build apk --debug
```

The LiteRT-LM native library (`liblitert_lm_main_jni.so`) is compiled separately via the NDK and placed in `android/app/src/main/jniLibs/arm64-v8a/`. See `android/app/src/main/kotlin/.../InferencePlugin.kt` for the JNI interface.

---

> *Gemma is a trademark of Google LLC. Nunarivu AI is an independent open-source project and is not affiliated with or endorsed by Google.*
