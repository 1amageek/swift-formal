import Darwin
import FormalCLI
import Foundation

@main
struct SwiftFormalCommand {
    static func main() async {
        let result = await FormalCommand().run(arguments: Array(CommandLine.arguments.dropFirst()))
        do {
            try FileHandle.standardOutput.write(contentsOf: Data(result.standardOutput.utf8))
            try FileHandle.standardError.write(contentsOf: Data(result.standardError.utf8))
        } catch {
            fputs("swift-formal: cannot write command output: \(error)\n", stderr)
            exit(7)
        }
        exit(result.exitCode)
    }
}
