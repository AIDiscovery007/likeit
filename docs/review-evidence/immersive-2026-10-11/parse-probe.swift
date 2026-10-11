import Foundation
@main struct Probe { static func main() {
for count in [1000, 8000] {
 let input=(0..<count).map { "[00:01]Sentence \($0)" }.joined(separator:"\n")
 let start=ProcessInfo.processInfo.systemUptime
 let lines=parseLRC(input)
 print("\(count) lines, \(input.utf8.count) bytes, \(ProcessInfo.processInfo.systemUptime-start) seconds, outputGroups=\(lines.count)")
}
}}
