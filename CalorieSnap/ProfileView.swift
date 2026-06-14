import SwiftUI
import Combine

// MARK: - User Profile

class UserProfile: ObservableObject {
    @AppStorage("profile_height") var height: Double = 160
    @AppStorage("profile_weight") var weight: Double = 71
    @AppStorage("profile_age") var age: Int = 25
    @AppStorage("profile_gender") var genderRaw: String = "female"
    @AppStorage("profile_activity") var activityRaw: String = "light"
    @AppStorage("profile_goal") var goalRaw: String = "lose05"
    @AppStorage("profile_setup_done") var setupDone: Bool = false

    var gender: Gender {
        get { Gender(rawValue: genderRaw) ?? .female }
        set { genderRaw = newValue.rawValue }
    }

    var activityLevel: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .light }
        set { activityRaw = newValue.rawValue }
    }

    var goal: WeightGoal {
        get { WeightGoal(rawValue: goalRaw) ?? .lose05 }
        set { goalRaw = newValue.rawValue }
    }

    // Mifflin-St Jeor BMR formula
    var bmr: Double {
        if gender == .male {
            return 10 * weight + 6.25 * height - 5 * Double(age) + 5
        } else {
            return 10 * weight + 6.25 * height - 5 * Double(age) - 161
        }
    }

    var tdee: Double {
        bmr * activityLevel.multiplier
    }

    var dailyCalorieGoal: Int {
        Int(tdee + goal.adjustment)
    }

    var bmi: Double {
        let heightM = height / 100
        return weight / (heightM * heightM)
    }

    var bmiCategory: String {
        switch bmi {
        case ..<18.5: return "Underweight"
        case 18.5..<25: return "Normal"
        case 25..<30: return "Overweight"
        default: return "Obese"
        }
    }

    var bmiColor: Color {
        switch bmi {
        case ..<18.5: return .blue
        case 18.5..<25: return .green
        case 25..<30: return .orange
        default: return .red
        }
    }
}

// MARK: - Enums

enum Gender: String, CaseIterable {
    case male = "male"
    case female = "female"

    var label: String {
        switch self {
        case .male: return "Male 男"
        case .female: return "Female 女"
        }
    }
}

enum ActivityLevel: String, CaseIterable {
    case sedentary = "sedentary"
    case light = "light"
    case moderate = "moderate"
    case active = "active"
    case veryActive = "veryActive"

    var label: String {
        switch self {
        case .sedentary: return "Sedentary (desk job, little exercise)"
        case .light: return "Light (exercise 1–3x/week)"
        case .moderate: return "Moderate (exercise 3–5x/week)"
        case .active: return "Active (exercise 6–7x/week)"
        case .veryActive: return "Very Active (physical job + exercise)"
        }
    }

    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }
}

enum WeightGoal: String, CaseIterable {
    case lose15 = "lose15"
    case lose1 = "lose1"
    case lose05 = "lose05"
    case maintain = "maintain"
    case gain05 = "gain05"
    case gain1 = "gain1"

    var label: String {
        switch self {
        case .lose15: return "Lose 1.5 kg/week"
        case .lose1: return "Lose 1 kg/week"
        case .lose05: return "Lose 0.5 kg/week"
        case .maintain: return "Maintain weight"
        case .gain05: return "Gain 0.5 kg/week"
        case .gain1: return "Gain 1 kg/week"
        }
    }

    var adjustment: Double {
        switch self {
        case .lose15: return -825
        case .lose1: return -550
        case .lose05: return -275
        case .maintain: return 0
        case .gain05: return 275
        case .gain1: return 550
        }
    }
}

// MARK: - Profile View

struct ProfileView: View {
    @StateObject private var profile = UserProfile()
    @State private var isEditing = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    // BMI + Calorie summary card
                    VStack(spacing: 16) {
                        HStack(spacing: 24) {
                            VStack(spacing: 6) {
                                Text(String(format: "%.1f", profile.bmi))
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(profile.bmiColor)
                                Text("BMI")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(profile.bmiCategory)
                                    .font(.caption2)
                                    .foregroundColor(profile.bmiColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(profile.bmiColor.opacity(0.15))
                                    .cornerRadius(6)
                            }

                            Divider().frame(height: 60)

                            VStack(spacing: 6) {
                                Text("\(profile.dailyCalorieGoal)")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.green)
                                Text("Daily Goal")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("kcal / day")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        HStack(spacing: 0) {
                            StatPill(label: "BMR", value: "\(Int(profile.bmr))", unit: "kcal", color: .orange)
                            StatPill(label: "TDEE", value: "\(Int(profile.tdee))", unit: "kcal", color: .blue)
                            StatPill(label: "Goal", value: profile.goal.label, unit: "", color: .green)
                        }
                    }
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(16)
                    .padding(.horizontal)

                    // Body stats
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Body Stats")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 0) {
                            ProfileRow(icon: "ruler", label: "Height", value: "\(Int(profile.height)) cm")
                            Divider().padding(.leading, 44)
                            ProfileRow(icon: "scalemass", label: "Weight", value: "\(String(format: "%.1f", profile.weight)) kg")
                            Divider().padding(.leading, 44)
                            ProfileRow(icon: "calendar", label: "Age", value: "\(profile.age) years")
                            Divider().padding(.leading, 44)
                            ProfileRow(icon: "person", label: "Gender", value: profile.gender.label)
                        }
                        .background(.regularMaterial)
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }

                    // Activity & Goal
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Activity & Goal")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 0) {
                            ProfileRow(icon: "figure.walk", label: "Activity", value: profile.activityLevel.label)
                            Divider().padding(.leading, 44)
                            ProfileRow(icon: "target", label: "Goal", value: profile.goal.label)
                        }
                        .background(.regularMaterial)
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }

                    // Calculation breakdown
                    VStack(alignment: .leading, spacing: 10) {
                        Text("How your goal is calculated")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 6) {
                            CalcRow(label: "BMR (base metabolism)", value: "\(Int(profile.bmr)) kcal")
                            CalcRow(label: "× Activity multiplier (\(profile.activityLevel.multiplier))", value: "\(Int(profile.tdee)) kcal")
                            CalcRow(label: "± Goal adjustment", value: "\(Int(profile.goal.adjustment)) kcal")
                            Divider()
                            HStack {
                                Text("Daily calorie goal")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("\(profile.dailyCalorieGoal) kcal")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(16)
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .padding(.top, 16)
            }
            .navigationTitle("My Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { isEditing = true }) {
                        Label("Edit", systemImage: "pencil")
                    }
                }
            }
            .sheet(isPresented: $isEditing) {
                EditProfileView(profile: profile)
            }
        }
    }
}

// MARK: - Profile Row

struct ProfileRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 28)
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

// MARK: - Calc Row

struct CalcRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
                .multilineTextAlignment(.center)
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @ObservedObject var profile: UserProfile
    @Environment(\.dismiss) var dismiss

    @State private var heightStr = ""
    @State private var weightStr = ""
    @State private var ageStr = ""

    var body: some View {
        NavigationView {
            Form {
                Section("Body Measurements") {
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("cm", text: $heightStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("cm").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("kg", text: $weightStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kg").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Age")
                        Spacer()
                        TextField("years", text: $ageStr)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("years").foregroundColor(.secondary)
                    }
                }

                Section("Gender") {
                    Picker("Gender", selection: $profile.gender) {
                        ForEach(Gender.allCases, id: \.self) { g in
                            Text(g.label).tag(g)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Activity Level") {
                    Picker("Activity", selection: $profile.activityLevel) {
                        ForEach(ActivityLevel.allCases, id: \.self) { a in
                            Text(a.label).tag(a)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 140)
                }

                Section("Weight Goal") {
                    Picker("Goal", selection: $profile.goal) {
                        ForEach(WeightGoal.allCases, id: \.self) { g in
                            Text(g.label).tag(g)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 140)
                }

                Section("Your Estimated Daily Goal") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(profile.dailyCalorieGoal) kcal / day")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            Text("BMR \(Int(profile.bmr)) × \(profile.activityLevel.multiplier) \(profile.goal.adjustment >= 0 ? "+" : "")\(Int(profile.goal.adjustment))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if let h = Double(heightStr) { profile.height = h }
                        if let w = Double(weightStr) { profile.weight = w }
                        if let a = Int(ageStr) { profile.age = a }
                        profile.setupDone = true
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                heightStr = "\(Int(profile.height))"
                weightStr = String(format: "%.1f", profile.weight)
                ageStr = "\(profile.age)"
            }
        }
    }
}
