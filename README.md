# Kelly Life 🌸

A personal health & lifestyle iOS app built with SwiftUI — designed around one person's daily life.

---

## Features

### 🔥 Today Dashboard
- Calorie ring with live macro tracking (carbs, protein, fat)
- Exercise bonus from Apple Health — goal adjusts automatically based on active calories burned
- Meal logging with calorie/macro input
- Weight trend chart (7-day) with multiple logs per day
- To-Do list with priority levels, due dates and progress ring
- Finance monthly overview and stock portfolio snapshot
- Upcoming events from countdown calendar
- Period tracker status
- Swipe left for quick meal log panel
- Anniversary celebration animation on special days

### 🍄 Energy & Readiness
- Daily energy score from sleep, HRV and resting heart rate (Apple Health)
- Real Readiness and Sleep scores from the **Oura Ring** via the Oura API (OAuth with PKCE)
- Oura ring battery level shown in the energy card
- Animated faceless mushroom companion that changes with your status (energized, steady, tired, short sleep, stressed…)
- 14-day energy strip, sleep stage chart and recent workouts from Apple Health

### 🤖 Kelly AI (on-device Apple Intelligence)
- Runs on Apple's on-device Foundation Models — private, no cloud
- Topics: Recipes, Weight, Health, Training, Money, News, Ask anything
- Meal plans from your saved recipes, with calories totalled by the app
- Training & rest-day week plans built from sleep, readiness and workouts
- Goal-weight plan with app-calculated timeline, milestones and calorie targets
- Answers questions across sleep, energy, HRV, steps, workouts, weight, food, recipes, fridge, cycle, calendar, countdowns, to-dos, wishes, stocks, CDs and spending, with real numbers shown first
- Money snapshot where the app computes every number (stocks vs CDs, top holdings, groups, CD maturities) and the AI only adds observations
- "How are my stocks today?": live index moves (S&P 500, Nasdaq, Dow, TSX), your day's gain/loss per holding, and news for the biggest movers
- Ask about one stock (e.g. "NVDA?") for today's move, your position, gain since buying and recent headlines
- CD maturities with days left and expected interest; spending totals with a month-end forecast
- Follow-up questions remember the topic; general questions get a plain answer without unrelated data
- Latest headlines for the stocks you own

### 🍳 Kitchen — Fridge & Recipes
**Recipes**
- Save recipes from any app's share sheet (share extension) or add them manually
- On-device text recognition (Chinese & English) from screenshots and PDFs
- Long recipes: combine up to 10 screenshots, overlaps and cut-off lines handled automatically
- Understands Xiaohongshu-style recipes: 【section】 headings, emoji step numbers (1️⃣), amounts before or after the name, and app buttons/like counts are ignored
- Title guessed from the post or its best-matching hashtag
- Pick which lines to keep, add a title, note and tags
- Ingredients (grouped by section) with checkboxes, numbered steps and a Tips section (小贴士); edit, favourite or delete anytime

**Fridge**
- Track items across Fridge, Freezer and Storage
- Two tracking modes: **Percentage** (milk, sauce) or **Count** (apples, eggs)
- Overstocked detection (shown in purple)
- Expiry date tracking with colour-coded warnings
- Status badges: Empty · Running Low · Good · Full · Overstocked
- Search across all locations
- Swipe to edit or delete

### 📅 Calendar
- Monthly grid with colour-coded dots for health data, events, period days and countdowns
- Apple Calendar integration — shows all your real calendar events
- Period tracker with cycle length, last period and next estimated date
- Countdown events bar — horizontal scroll with emoji chips and days remaining
- Anniversary events repeat every year with emoji marked on that date
- Celebration full-screen animation with confetti on anniversary days
- Daily health summary (calories/macros) per selected date
- Weight logging per day

### 💰 Finance
**Four ways to add purchases**
1. **Apple Pay, automatic** — a Shortcuts "Transaction" automation runs the app's *Log Purchase* action after every Apple Pay tap; the shop name, amount and card are saved and the category is guessed
2. **Share a statement** — Share a PDF or CSV statement (Amex, Mail, Files…) → Kelly Life → *Import to Finance*; the preview opens next time the app is opened
3. **Import a file** — Finance → + → Import from Bank CSV (PDF or CSV)
4. **By hand** — Finance → + → Add Transaction

**Statement import**
- Reads CSV downloads from most banks and cards (Chase, Amex, Capital One, Citi, BofA, Discover, Apple Card, RBC, TD, Scotiabank…) and PDF statements, including scanned ones
- Preview before importing: pick rows, change categories, swap purchases/refunds
- Skips card payments and purchases already in the app (same day, same amount, matching name)

**Tracking**
- Transaction tracking with income and expense categories
- Choose which week, month or year to view (‹ › or tap the date to jump back)
- Cumulative amount entry (add multiple items into one transaction)
- Monthly budget with category breakdown and progress bar (follows the month you're viewing)
- Stock portfolio with live prices via Yahoo Finance (auto-refresh every 5 min)
- Stock chart with buy/sell markers
- CD (Certificate of Deposit) accounts with maturity countdown
- 6-month spending trends and category comparisons

### 👤 Profile
- Personal info (name, age, height, weight, calorie goal)
- Year Wish List — goals organised by category (Travel, Health, Career, Finance…)
- Progress ring showing how many wishes achieved this year
- Category filter chips, swipe to complete or delete
- **Face ID lock** — offered on first launch, with re-lock timing options
- **Backup & Restore** — automatic daily backup to OneDrive (linked file) or an iCloud Drive folder, plus manual backup and restore

---

## Tech Stack

| | |
|---|---|
| **Platform** | iOS 26+ |
| **Language** | Swift 6 |
| **UI Framework** | SwiftUI |
| **Health Data** | HealthKit |
| **Wearable** | Oura API v2 |
| **AI** | Apple Foundation Models (on-device) |
| **Automation** | App Intents + Shortcuts (Apple Pay "Transaction" trigger) |
| **Statements** | PDFKit + Vision text recognition |
| **Text Recognition** | Vision & VisionKit |
| **Security** | LocalAuthentication (Face ID), Keychain |
| **Calendar Data** | EventKit |
| **Stock Prices** | Yahoo Finance (unofficial API) |
| **Storage** | UserDefaults + App Group (shared with the share extension) |
| **Notifications** | UserNotifications (CD maturity alerts) |

---

## Screenshots

> Coming soon

---

## Requirements

- iOS 26 or later (Kelly AI needs an Apple Intelligence–capable iPhone)
- iPhone (optimised for iPhone 16/17 Pro)
- Xcode 26+

### Permissions required
- **Apple Health** — steps, sleep, active calories, heart rate, HRV, resting heart rate, workouts, menstrual cycle data
- **Face ID** — to lock the app
- **Photos** — to read recipe screenshots
- **Shortcuts** — a personal automation for logging Apple Pay purchases (optional)
- **Apple Calendar** — read your calendar events to show alongside health data

---

## Setup

1. Clone the repo
2. Open `CalorieSnap.xcodeproj` in Xcode
3. Select your development team in Signing & Capabilities
4. Add the App Group `group.com.kelly.kellylife` to both the **CalorieSnap** and **KellyLifeShare** targets
5. Add the URL scheme `kellylife` (for the Oura sign-in redirect)
6. Add the following keys to `Info.plist` if not already present:

```xml
<key>NSHealthShareUsageDescription</key>
<string>Kelly Life reads your health data to show steps, sleep, calories and period tracking.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>Kelly Life may write health data on your behalf.</string>

<key>NSCalendarsFullAccessUsageDescription</key>
<string>Kelly Life shows your calendar events alongside health data.</string>

<key>NSFaceIDUsageDescription</key>
<string>Kelly Life uses Face ID to keep your personal data private.</string>
```

7. To use Oura, register an app at the Oura developer portal and enter its Client ID and Secret in the app
8. Build and run on your device (`Cmd + R`)

### Apple Pay auto-logging (optional)
1. Open **Shortcuts** → tap **+** to make a new shortcut
2. Add the trigger **When Any Card is tapped** (Transaction) and turn off **Notify**
3. Add the action **Log Purchase in Kelly Life** and set:
   - **Amount** → Transaction › Amount
   - **Merchant** → Transaction › Merchant
   - **Card** → Transaction › Card or Pass
4. Each Apple Pay payment is then added to Finance automatically. Card swipes, online card-number purchases and cash still need importing or adding by hand.

> Apple's FinanceKit (direct Wallet access) is only available to finance apps on the App Store, so this app uses the Shortcuts automation instead.

---

## Project Structure

```
CalorieSnap/
├── CalendarView.swift      — Calendar, events, period tracker, countdown
├── ContentView.swift       — Tabs, Dashboard, To-Do, meal log, weight, finance panel
├── EnergyView.swift        — Energy score, readiness, mushroom companion, workouts
├── OuraService.swift       — Oura sign-in, readiness, sleep, ring battery
├── AIAssistantView.swift   — Kelly AI (on-device), money facts, stock news
├── KellyBrain.swift        — Kelly AI question routing and app-calculated facts for every category
├── ReceiptsView.swift      — Kitchen tab, recipes list/detail/editor
├── ReceiptParser.swift     — Recipe model & text parsing (shared with extension)
├── ReceiptStore.swift      — Recipe storage in the App Group (shared)
├── AppLock.swift           — Face ID lock
├── BackupView.swift        — Backup & restore (OneDrive / iCloud Drive)
├── FinanceView.swift       — Transactions, stocks, CDs, budget, week/month/year navigation
├── ImportTransactionsView.swift — Bank statement import (CSV & PDF), shared-statement pickup
├── PurchaseIntent.swift    — "Log Purchase in Kelly Life" Shortcuts action for Apple Pay
├── FridgeView.swift        — Fridge/freezer/storage tracker
├── ProfileView.swift       — Profile, year wish list
├── HealthKitManager.swift  — Apple Health integration
└── Info.plist              — App permissions
KellyLifeShare/
└── ShareViewController.swift — Share extension: saves recipes, hands bank statements to Finance
```

---

## Data Privacy

All data is stored **locally on device**. There's no Kelly Life server. Stock prices and headlines come from Yahoo Finance's public endpoints; Oura data is fetched directly from Oura with your own sign-in, and its tokens are kept in the Keychain. Kelly AI runs entirely on-device. Apple Pay purchases are passed from Shortcuts straight into the app, and imported statements are read on the phone and deleted after import. Backups go only to the OneDrive or iCloud Drive location you choose. Apple Health and Calendar data is read-only.

---

## About

Built as a personal daily companion app for tracking health, food, finances, and life goals.  
Developed with SwiftUI over several months of iterative building.

---

*Made with ❤️ for a healthier, more organised life.*
