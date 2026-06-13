import Foundation

struct UsageMeter: Identifiable {
    var id: String { label }
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
}
