import Foundation

public class ExplorationSummarizer {
    
    // Process raw steps, filter out noise, and build a formatted markdown note
    public static func summarize(steps: [ExplorationStep]) -> String {
        guard !steps.isEmpty else {
            return "# Mindspace Summary\nNo note content captured."
        }
        
        // Define apps classified as context-switching/communication noise
        let noisyApps = ["Slack", "Microsoft Teams", "Mail", "Messages", "Discord", "Telegram"]
        
        // Filter out noise
        let filteredSteps = steps.filter { step in
            let isNoiseApp = noisyApps.contains(step.appName)
            
            // Filter criteria: Keep it if it has selected text, or if it is not a known communication noise app
            if step.selectedText != nil {
                return true
            }
            return !isNoiseApp
        }
        
        var output = ""
        output += "# Mindspace Summary\n"
        output += "Date: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))\n"
        output += "Duration: Captured \(steps.count) events (Filtered down to \(filteredSteps.count) relevant actions)\n\n"
        
        output += "## 📝 Key Takeaways & Research Findings\n"
        
        var citations: [String] = []
        
        if filteredSteps.isEmpty {
            output += "Only context-switching noise was captured during this brief exploration session.\n"
        } else {
            for step in filteredSteps {
                let timeStr = DateFormatter.localizedString(from: step.timestamp, dateStyle: .none, timeStyle: .medium)
                
                // Track source for citations
                let sourceIdentifier: String
                if let url = step.url {
                    sourceIdentifier = "\(step.appName) — [\(step.windowTitle)](\(url))"
                } else {
                    sourceIdentifier = "\(step.appName) — \(step.windowTitle)"
                }
                
                if !citations.contains(sourceIdentifier) {
                    citations.append(sourceIdentifier)
                }
                
                let citationIndex = citations.firstIndex(of: sourceIdentifier)! + 1
                
                output += "### • [\(timeStr)] On \(step.appName) [\(citationIndex)]\n"
                output += "  Active Window: *\(step.windowTitle)*\n"
                
                if let selected = step.selectedText {
                    output += "  > **Highlighted Text**: \"\(selected)\"\n"
                }
                
                if let screenshot = step.screenshotPath {
                    output += "  *Screenshot recorded: \(URL(fileURLWithPath: screenshot).lastPathComponent)*\n"
                }
                if let html = step.htmlPath {
                    output += "  *Chrome HTML archived: \(URL(fileURLWithPath: html).lastPathComponent)*\n"
                }
                if let pageText = step.pageText {
                    let excerpt = pageText
                        .replacingOccurrences(of: "\n", with: " ")
                        .prefix(500)
                    output += "  Browser excerpt: \(excerpt)\n"
                }
                output += "\n"
            }
        }
        
        // Output Citations List
        if !citations.isEmpty {
            output += "## 🌐 Sources & Citations\n"
            for (index, citation) in citations.enumerated() {
                output += "[\(index + 1)] \(citation)\n"
            }
        }
        
        // Context-Switching Noise Filter logs for verification
        let filteredOut = steps.filter { step in
            let isNoiseApp = noisyApps.contains(step.appName)
            return isNoiseApp && step.selectedText == nil
        }
        
        if !filteredOut.isEmpty {
            output += "\n## 🧹 Filtered Noise Logs (Removed by AI Agent)\n"
            for noise in filteredOut {
                output += "• Removed active focus on **\(noise.appName)**: *\(noise.windowTitle)*\n"
            }
        }
        
        return output
    }
}
