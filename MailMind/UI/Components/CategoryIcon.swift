import SwiftUI

struct CategoryIcon: View {
    let name: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(
                LinearGradient(
                    colors: [tintColor, tintColor.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Circle())
    }

    private var lowercased: String {
        name.lowercased()
    }

    private var symbol: String {
        if lowercased.contains("interview") { return "person.2.wave.2.fill" }
        if lowercased.contains("work") || lowercased.contains("office") { return "briefcase.fill" }
        if lowercased.contains("finance") || lowercased.contains("bank") || lowercased.contains("money") { return "dollarsign.circle.fill" }
        if lowercased.contains("news") || lowercased.contains("letter") { return "newspaper.fill" }
        if lowercased.contains("travel") || lowercased.contains("flight") { return "airplane" }
        if lowercased.contains("shop") || lowercased.contains("order") { return "bag.fill" }
        if lowercased.contains("social") { return "person.3.fill" }
        if lowercased.contains("event") || lowercased.contains("calendar") { return "calendar" }
        if lowercased.contains("health") || lowercased.contains("medical") { return "heart.fill" }
        if lowercased.contains("family") || lowercased.contains("home") { return "house.fill" }
        if lowercased.contains("school") || lowercased.contains("class") || lowercased.contains("study") { return "graduationcap.fill" }
        return "tag.fill"
    }

    private var tintColor: Color {
        let palette: [Color] = [
            .indigo,
            .purple,
            .pink,
            .orange,
            Color(red: 0.20, green: 0.65, blue: 0.55),
            .blue,
            .teal,
            Color(red: 0.85, green: 0.45, blue: 0.20),
            Color(red: 0.45, green: 0.30, blue: 0.85)
        ]

        let hash = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[hash % palette.count]
    }
}

#Preview {
    VStack(spacing: 12) {
        CategoryIcon(name: "Interview")
        CategoryIcon(name: "Work")
        CategoryIcon(name: "Finance")
        CategoryIcon(name: "Newsletters")
        CategoryIcon(name: "Travel")
        CategoryIcon(name: "Random Custom")
    }
    .padding()
}
