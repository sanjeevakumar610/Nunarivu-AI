# நுணரிவு AI — Nunarivu AI

### Offline Tamil AI Tutor for Sri Lankan Students
**Built for students and teachers to learn in Tamil language using AI**

---

## Live Demo & Links

| | |
|---|---|
| 🌐 **Landing Page** | https://nunarivu-ai.web.app |
| 📱 **Download APK** | [app-release.apk](https://github.com/sanjeevakumar610/Nunarivu-AI/releases/download/v1.0.0/app-release.apk) |
| 📓 **Kaggle Notebook** | [Runnable Tamil OCR + Gemma 4 demo](https://github.com/sanjeevakumar610/Nunarivu-AI/blob/main/nunarivu_ai_kaggle_demo.ipynb) |
| 🤖 **AI Model** | [litert-community/gemma-4-E2B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm) |

---

## The Problem

### Problem 1 — Climate Crisis Destroying Education Access

Sri Lanka consistently appears among the **top ten countries at risk of extreme weather events** in the Global Climate Risk Index, ranked **4th most affected globally in 2016**. With 96% of its disasters driven by climate — flooding, landslides, cyclones — the education system is under constant threat.

**Recent Crisis (2024–2026):**

- **2024**: Significant nationwide flooding between May and June disrupted hundreds of thousands of students
- **November 2025**: Cyclone Ditwah severely impacted Sri Lanka's upcountry (Central and Uva provinces), causing widespread landslides and catastrophic damage
  - Over **1,382 schools** were directly affected — highest concentration in the Central, Uva, and Sabaragamuwa provinces
  - Over **1,300 schools** were closed for an extended period, disrupting education for over **550,000 children**
  - As of mid-December 2025, **115 schools in the Central Province alone** could not reopen due to high risk
  - Many students faced transportation difficulties due to landslides blocking hill country roads
  - By January 2026, many upcountry schools were still recovering

> **Critical note**: Thousands of children lost their school bags, exercise books, and stationery — leaving them unable to continue their studies even when schools reopened.

When physical schools are inaccessible, students need a learning tool that works **wherever they are** — without internet, without electricity-dependent infrastructure, without any cost.

---

### Problem 2 — Tamil Students Have No AI Learning Tools

Over **542,344 Tamil-medium students** in Sri Lanka study from government-issued textbooks — and they are completely underserved by every existing AI education product.

- **No reliable internet** — rural and estate areas have little to no connectivity; some areas have no internet connection at all
- **Cannot afford tutoring** — household incomes are often below Rs 30,000/month (~$93–$99 USD); private tutoring, app subscriptions, and even mobile data costs are out of reach
- **No Tamil AI tools exist offline** — every available Tamil-language AI app requires internet, a paid subscription, or collects user data with free tiers that impose limitations or move to paid models later
- **Their textbooks are invisible to software** — Sri Lankan Tamil government textbooks use legacy encoding fonts (Baamini, SHREE-TAM7) that no standard text extractor can read — PyMuPDF, PDFBox, and Syncfusion all return zero readable text

---

## The Solution — Nunarivu AI

A **fully offline** Android app *(Sri Lankan students mostly use Android-based phones)* that runs **Google Gemma 4 E2B IT** directly on the device — no server, no subscription, no internet required after setup.

> *"நுணரிவு" (Nunarivu) means "intelligence" or "wisdom" in Tamil.*

Students access Tamil textbook PDF files in the app library, ask questions using **Tamil Voice Q&A**, and receive accurate spoken answers — all grounded strictly in the textbook page they are reading. The app works fully on a budget Android phone in a village with no internet, during a cyclone, with the phone in airplane mode.

---

## Key Features

### 🤖 On-Device Gemma 4 E2B IT
- Runs **Google Gemma 4 E2B IT** (Instruction Tuned, 2B parameters, Edge variant) via **LiteRT-LM** directly on the Android device
- No API calls, no cloud dependency, no data ever leaves the phone
- Student side-loads the model once — then it's theirs forever

### 📚 Tamil Textbook Library (161 Books)
- Auto-imports all PDFs from the app's external storage folder
- Covers the full Grade 10 and Grade 11 Sri Lankan Tamil-medium curriculum: Maths, Science, History, Tamil Literature, Islam, Christianity, Hinduism, Geography, ICT, Health, Commerce, and more
- Books organised by grade and subject automatically on every launch

### 🔍 Tesseract OCR — The Core Technical Innovation

Sri Lankan Tamil government textbooks are printed using **legacy encoding fonts** (Baamini, SHREE-TAM7, FMAbhaya) with WinAnsiEncoding and no Unicode CMap. Every standard PDF text extractor — including PyMuPDF, PDFBox, and Syncfusion — returns **zero readable text** from these books.

**Our solution**: Render each page to a 2× PNG image using Android's native PdfRenderer, then run **Tesseract OCR** (Tamil + English, LSTM engine, PSM 6) on the image. Results are cached permanently in SQLite so each page is only processed once — instant on every subsequent question.

```
PDF Page → pdfx renders to 1044×1368 PNG → Tesseract tam+eng → Tamil Unicode text → SQLite cache
```

### 🎤 Tamil Voice Q&A
- Tap the mic, ask in spoken Tamil or English
- 6 seconds of silence tolerance — waits patiently for the student to finish thinking
- Uses Android's offline `ta-IN` speech recognition — no internet needed

### 🔄 Four Instant Follow-up Buttons
Every AI answer has four one-tap follow-up buttons — no re-typing needed:

| Button | What it does |
|--------|-------------|
| **தமிழில்** | Re-explains the same answer in simple Tamil |
| **In English** | Re-explains the same answer in simple English |
| **More Examples** | Re-runs inference asking for real-life examples of the concept |
| **Explain More** | Re-runs inference asking for a deeper, step-by-step breakdown |

Each button re-uses the same OCR page text as context — so all follow-up answers remain strictly grounded in the textbook page, never from outside knowledge.

### 📖 Page-Aware Answers — Zero Hallucination Risk
- The model answers **only from the current page's OCR text**
- Hard block on general knowledge — if the answer is not on that page, the app says exactly that in Tamil
- **Safe for exam preparation** — students will not write incorrect answers from AI guesses

### 🔊 Text-to-Speech
- Every AI answer read aloud at one tap — clean audio, no symbols
- Critical for students with reading difficulties or low literacy
- Works offline via Android's built-in TTS engine

### 👤 Multi-Student Profiles
- Multiple student profiles on one device — for siblings or classmates sharing a phone
- Per-profile: name, grade, language preference, learning disability mode, AI persona (Teacher / Friend / Parent)
- Profile delete with confirmation dialog — permanently removes profile and all its chat history
- Each profile switch opens a fresh blank chat window

### ⏰ Study Reminders and Badges
- Daily study alarms with Tamil notification text — "படிக்க நேரம்! / Time to Study!"
- Achievement badges unlocked by question count and study-day streaks
- All progress tracked locally — no account, no cloud, no tracking

---

## Technical Architecture

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
│  BadgeService  │  Reminders     │  DbService (v7)   │
├─────────────────────────────────────────────────────┤
│           Local Storage — 100% on-device             │
│  SQLite v7: profiles · chats · messages · pdfs      │
│             pdf_chunks (OCR cache) · badges         │
│             reminders                               │
└─────────────────────────────────────────────────────┘
          ↕ MethodChannel / EventChannel (JNI)
┌─────────────────────────────────────────────────────┐
│    InferencePlugin.kt — LiteRT-LM C++ Bridge        │
│  Engine (GPU/CPU) · Conversation · AtomicReference  │
└─────────────────────────────────────────────────────┘
```

### Gemma 4 E2B IT — LiteRT-LM Integration

A custom Kotlin JNI bridge (`InferencePlugin.kt`) calls the LiteRT-LM C++ runtime and streams tokens back to Flutter through an `EventChannel`:

```kotlin
// InferencePlugin.kt — streams tokens to Flutter in real time
streamJob = scope.launch {
    prevJob?.join()  // wait for previous job's finally block before creating new session
    conversation = createConversationWithRecovery(engine)
    conversation.sendMessageAsync(prompt).collect { chunk ->
        withContext(Dispatchers.Main) { events.success(chunk.toString()) }
    }
    withContext(Dispatchers.Main) { events.endOfStream() }
}
```

```dart
// ModelService.dart — each token updates the UI as it arrives
Stream<String> inferStream(String prompt) =>
    _streamChannel.receiveBroadcastStream({'prompt': prompt}).cast<String>();
```

**Key implementation details:**
- **Backend**: Adreno 710 GPU via OpenCL, automatic CPU fallback
- **Session management**: `AtomicReference<Conversation?>` tracks the one active native session — LiteRT-LM allows only one `Conversation` at a time globally
- **Recovery**: On `FAILED_PRECONDITION: A session already exists`, the engine reloads (~7–8s) rather than waiting for GC (~30–45s natural recovery). This makes the Tamil / English / More Examples / Explain More buttons reliable immediately after stopping a response.
- **Model format**: `.litertlm` single file — not `.gguf`
- **Performance**: First token ~8–12s; streaming ~4–6 tokens/sec on Adreno 710

### OCR Pipeline

```dart
// OcrService.dart — called once per page, result cached permanently
PDF file
  → Copy to ASCII temp path            // avoids Android PdfRenderer Tamil filename bug
  → pdfx renders page at 2× scale      // 1044 × 1368 px PNG
  → Tesseract OCR (tam+eng, oem=3, psm=6)
  → Store in SQLite pdf_chunks table   // chunk_index = -1 marks OCR entries
  → Memory-cached for instant reuse
```

### Prompt Design — Exam Safety First

```
You are a teacher answering a student's question about their textbook "[title]", page N.
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
- Approximately 3 GB of free storage for the model

### Step 1 — Install the APK
Download `app-release.apk` from [Releases](https://github.com/sanjeevakumar610/Nunarivu-AI/releases) and install it.

### Step 2 — Download the Gemma 4 E2B IT Model
The model is Google's official release on HuggingFace (free, requires a HuggingFace account):

```
https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm
```

Download: `gemma-4-E2B-it-litert-lm.litertlm` (~2.4 GB)

Copy to the device via ADB:
```bash
adb push gemma-4-E2B-it-litert-lm.litertlm \
  /sdcard/Android/data/com.example.nunarivu_ai/files/models/gemma-4-E2B-it-litert-lm.litertlm
```

Or copy manually using a file manager to:
`Internal Storage → Android → data → com.example.nunarivu_ai → files → models`

### Step 3 — Add a Sample Textbook (Optional)
The app works as a general Tamil tutor without textbooks. To test the OCR and page-aware Q&A, place any Tamil PDF into:
```
Android/data/com.example.nunarivu_ai/files/books/Grade 10/Subject Name/book.pdf
```
The app auto-scans and imports it on next launch.

### Step 4 — Try It
1. Open the app → create a student profile
2. **Chat tab** → ask any question in Tamil or English
3. **Library tab** → open a textbook → ask about the page you are reading
4. Tap **தமிழில்**, **In English**, **More Examples**, or **Explain More** for instant follow-ups
5. **Turn on Airplane Mode and ask again** — it still works ✅

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Framework | Flutter 3 / Dart |
| AI Model | Google Gemma 4 E2B IT — LiteRT-LM format |
| Model Runtime | LiteRT-LM C++ via custom Android JNI plugin |
| OCR Engine | Tesseract 4 LSTM — Tamil + English |
| PDF Page Rendering | pdfx (Android native PdfRenderer) |
| PDF Viewer | Syncfusion Flutter PDF Viewer |
| State Management | Flutter Riverpod 2 |
| Local Database | SQLite v7 via sqflite |
| Speech-to-Text | Android offline ta-IN STT |
| Text-to-Speech | flutter_tts |
| Typography | Noto Sans Tamil |
| Notifications | flutter_local_notifications |

---

## Why This Matters

| Challenge | Our Solution |
|-----------|-------------|
| Cyclone/flood disrupts schools | 100% offline app works anywhere on any Android phone |
| No internet in rural and estate Tamil areas | Works after one-time model download — zero connectivity needed |
| Tamil textbook PDFs unreadable by software | Tesseract OCR on rendered page images — page-perfect text extraction |
| No Tamil-language AI tools for students | Full Tamil UI, Tamil STT, Tamil TTS, Tamil answers |
| Exam risk from AI hallucination | Hard block — model reads only from the textbook page, never guesses |
| Cannot afford tutoring (~$93/month salary) | Free, open source, works on any budget Android phone |
| Multiple students sharing one device | Multi-profile with separate history, badges, and settings per student |
| Need same concept explained differently | Four follow-up buttons: Tamil / English / More Examples / Explain More |

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
flutter build apk --release
```

The LiteRT-LM native library (`liblitert_lm_main_jni.so`) is compiled via the NDK and placed in `android/app/src/main/jniLibs/arm64-v8a/`. See `android/app/src/main/kotlin/.../InferencePlugin.kt` for the JNI interface.

---

> *Gemma is a trademark of Google LLC. Nunarivu AI is an independent open-source project and is not affiliated with or endorsed by Google.*
