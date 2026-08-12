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

### 🧊 Fridge Tracker
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
- Transaction tracking with income and expense categories
- Cumulative amount entry (add multiple items into one transaction)
- Monthly budget with category breakdown and progress bar
- Stock portfolio with live prices via Yahoo Finance (auto-refresh every 5 min)
- Stock chart with buy/sell markers
- CD (Certificate of Deposit) accounts with maturity countdown
- 6-month spending trends and category comparisons

### 👤 Profile
- Personal info (name, age, height, weight, calorie goal)
- Year Wish List — goals organised by category (Travel, Health, Career, Finance…)
- Progress ring showing how many wishes achieved this year
- Category filter chips, swipe to complete or delete

---

## Tech Stack

| | |
|---|---|
| **Platform** | iOS 17+ |
| **Language** | Swift 5.9 |
| **UI Framework** | SwiftUI |
| **Health Data** | HealthKit |
| **Calendar Data** | EventKit |
| **Stock Prices** | Yahoo Finance (unofficial API) |
| **Storage** | UserDefaults |
| **Notifications** | UserNotifications (CD maturity alerts) |

---

## Screenshots

> Coming soon

---

## Requirements

- iOS 17.0 or later
- iPhone (optimised for iPhone 16/17 Pro)
- Xcode 16+

### Permissions required
- **Apple Health** — steps, sleep, active calories, heart rate, menstrual cycle data
- **Apple Calendar** — read your calendar events to show alongside health data

---

## Setup

1. Clone the repo
2. Open `CalorieSnap.xcodeproj` in Xcode
3. Select your development team in Signing & Capabilities
4. Add the following keys to `Info.plist` if not already present:

```xml
<key>NSHealthShareUsageDescription</key>
<string>Kelly Life reads your health data to show steps, sleep, calories and period tracking.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>Kelly Life may write health data on your behalf.</string>

<key>NSCalendarsFullAccessUsageDescription</key>
<string>Kelly Life shows your calendar events alongside health data.</string>
```

5. Build and run on your device (`Cmd + R`)

---

## Project Structure

```
CalorieSnap/
├── CalendarView.swift      — Calendar, events, period tracker, countdown
├── ContentView.swift       — Dashboard, To-Do, meal log, weight, finance panel
├── FinanceView.swift       — Transactions, stocks, CDs, budget
├── FridgeView.swift        — Fridge/freezer/storage tracker
├── ProfileView.swift       — Profile, year wish list
├── HealthKitManager.swift  — Apple Health integration
└── Info.plist              — App permissions
```

---

## Data Privacy

All data is stored **locally on device** using `UserDefaults`. Nothing is sent to any server. Stock prices are fetched from Yahoo Finance's public endpoint. Apple Health and Calendar data is read-only and never leaves the device.

---

## About

Built as a personal daily companion app for tracking health, food, finances, and life goals.  
Developed with SwiftUI over several months of iterative building.

---

*Made with ❤️ for a healthier, more organised life.*
