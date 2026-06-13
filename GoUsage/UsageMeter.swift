import Foundation

struct UsageMeter: Identifiable {
    let id = UUID()
    let label: String
    let percentage: Int
    let resetTime: String

    var shortLabel: String {
        switch label {
        case "Rolling Usage": return "Rolling"
        case "Weekly Usage": return "Weekly"
        case "Monthly Usage": return "Monthly"
        default: return label
        }
    }

    var displayLine: String {
        "\(shortLabel.padding(toLength: 8, withPad: " ", startingAt: 0)) \(percentage)%  \(resetTime)"
    }
}
