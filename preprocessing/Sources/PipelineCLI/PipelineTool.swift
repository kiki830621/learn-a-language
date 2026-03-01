import ArgumentParser
import Pipeline

@main
struct PipelineTool: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pipeline",
        abstract: "Preprocessing pipeline for Aozora Bunko literary works",
        subcommands: [Process.self, Batch.self, Index.self, List.self]
    )
}
