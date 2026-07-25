//
//  FoodConfirmSheet.swift
//  caloric
//
//  Review step between the AI analysis and the journal. The model estimates
//  portion sizes — especially from photos, where nothing states the amount —
//  so every item stays editable and removable before the macros are added to
//  the meal.
//

import SwiftUI

struct FoodConfirmSheet: View {

    let language: String
    let accentBlue: Color
    let mealName: String
    @State var items: [FoodItem]
    let onConfirm: ([FoodItem]) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header

                    ForEach($items) { $item in
                        itemCard(item: $item)
                    }

                    if items.isEmpty {
                        Text(language == "de"
                             ? "Keine Positionen übrig. Füge welche hinzu oder brich ab."
                             : "No items left. Add some or cancel.")
                            .font(.poppins(size: 12, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.vertical, 24)
                    }

                    totalCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle(language == "de" ? "Erkannt" : "Detected")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language == "de" ? "Abbrechen" : "Cancel") { dismiss() }
                        .font(.poppins(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language == "de" ? "Übernehmen" : "Add") {
                        onConfirm(items)
                        dismiss()
                    }
                    .font(.poppins(size: 14, weight: .semibold))
                    .foregroundStyle(items.isEmpty ? accentBlue.opacity(0.4) : accentBlue)
                    .disabled(items.isEmpty)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Theme.segTEF.opacity(0.15)).frame(width: 32, height: 32)
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.segTEF)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(mealName)
                    .font(.poppins(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(language == "de"
                     ? "Schätzwerte – prüf die Mengen und korrigier sie bei Bedarf."
                     : "Estimates – check the amounts and correct them if needed.")
                    .font(.poppins(size: 11, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    // MARK: - Item card

    private func itemCard(item: Binding<FoodItem>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("", text: item.name)
                    .font(.poppins(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 8)

                Text("\(Int(item.wrappedValue.kcal.rounded())) kcal")
                    .font(.poppins(size: 12, weight: .medium))
                    .foregroundStyle(.orange)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        items.removeAll { $0.id == item.wrappedValue.id }
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textSecondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                gramField(label: language == "de" ? "Menge" : "Amount",
                          value: item.grams, tint: Theme.textSecondary)
                gramField(label: "Protein", value: item.protein, tint: Theme.segNEAT)
                gramField(label: language == "de" ? "KH" : "Carbs",
                          value: item.carbs, tint: accentBlue)
                gramField(label: language == "de" ? "Fett" : "Fat",
                          value: item.fat, tint: .orange)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.fieldFill)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1))
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func gramField(label: String, value: Binding<Double>, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.poppins(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                TextField("0", text: Binding(
                    get: { value.wrappedValue > 0 ? "\(Int(value.wrappedValue.rounded()))" : "" },
                    set: { value.wrappedValue = Double($0.replacingOccurrences(of: ",", with: ".")) ?? 0 }
                ))
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .font(.poppins(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                Text("g")
                    .font(.poppins(size: 10, weight: .medium))
                    .foregroundStyle(tint.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }

    // MARK: - Total

    private var totalCard: some View {
        let p = Int(items.totalProtein.rounded())
        let c = Int(items.totalCarbs.rounded())
        let f = Int(items.totalFat.rounded())
        let kcal = Int(items.totalKcal.rounded())

        return VStack(spacing: 10) {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text("= \(kcal) kcal \(language == "de" ? "gesamt" : "total")")
                    .font(.poppins(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            HStack(spacing: 8) {
                totalPill(label: "Protein", value: p, color: Theme.segNEAT)
                totalPill(label: language == "de" ? "KH" : "Carbs", value: c, color: accentBlue)
                totalPill(label: language == "de" ? "Fett" : "Fat", value: f, color: .orange)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.fieldFill)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1))
        )
    }

    private func totalPill(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)g")
                .font(.poppins(size: 15, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.poppins(size: 10, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
