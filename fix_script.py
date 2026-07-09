import sys

with open("caloric/Onboarding/DashboardView.swift", "r") as f:
    content = f.read()

bad_block = """            .navigationTitle(language == "de" ? "Datum wählen" : "Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: EnergySegmentType.self) { type in
                calculationDetailView(for: type)
            }
            .toolbar {"""

fixed_bad_block = """            .navigationTitle(language == "de" ? "Datum wählen" : "Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {"""

target_block = """            .navigationTitle(language == "de" ? "Aufschlüsselung" : "Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {"""

fixed_target_block = """            .navigationTitle(language == "de" ? "Aufschlüsselung" : "Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: EnergySegmentType.self) { type in
                calculationDetailView(for: type)
            }
            .toolbar {"""

if bad_block in content:
    content = content.replace(bad_block, fixed_bad_block)
else:
    print("bad_block not found")
    
if target_block in content:
    content = content.replace(target_block, fixed_target_block)
else:
    print("target_block not found")

with open("caloric/Onboarding/DashboardView.swift", "w") as f:
    f.write(content)
print("Done")
