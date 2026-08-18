import Foundation
import Testing
import QwenPrimeCommandProtocol
import QwenPrimeHarnessProtocol
@testable import QwenPrime

@Suite("Workspace task registry")
struct WorkspaceTaskRegistryTests {
    @Test("Registry is the single closed catalog for supported tasks")
    func closedCatalog() {
        #expect(WorkspaceTaskRegistry.descriptors.map(\.id) == [
            "swift_build",
            "swift_test"
        ])
        #expect(WorkspaceTaskRegistry.descriptors.map(\.supportsFilter) == [false, true])
    }

    @Test("Registry maps tool input to a fixed proposal")
    func mapsToolInput() throws {
        let proposal = try WorkspaceTaskRegistry.proposal(
            taskID: "swift_test",
            filter: "RegistryTests",
            workingDirectory: "Fixture"
        )

        #expect(proposal.command == "swift")
        #expect(proposal.arguments == ["test", "--filter", "RegistryTests"])
        #expect(proposal.workingDirectory == "Fixture")
    }

    @Test("Registry maps approved proposals to harness operations")
    func mapsApprovedProposal() throws {
        let invocation = try WorkspaceTaskRegistry.harnessInvocation(
            for: WorkspaceCommandProposal(
                command: "swift",
                arguments: ["build"],
                workingDirectory: ""
            )
        )

        #expect(invocation.operation == .swiftBuild)
        #expect(invocation.filter == nil)
    }

    @Test("Build filters are rejected by the registry")
    func buildRejectsFilter() {
        #expect(throws: Error.self) {
            try WorkspaceTaskRegistry.proposal(
                taskID: "swift_build",
                filter: "NotAllowed",
                workingDirectory: ""
            )
        }
    }

    @Test("Package discovery reports exact manifests as task working directories")
    func discoversPackages() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "Package.swift", content: "// root\n")
            try fixture.createFile(at: "Nested/Package.swift", content: "// nested\n")
            try fixture.createFile(at: "Nested/Package.swift.backup", content: "// backup\n")
            try fixture.createFile(at: ".build/Ignored/Package.swift", content: "// ignored\n")
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            let catalog = try await WorkspaceTaskRegistry.catalog(in: service)

            #expect(catalog.tasks == WorkspaceTaskRegistry.descriptors)
            #expect(catalog.swiftPackages == ["", "Nested"])
            #expect(!catalog.isTruncated)
        }
    }
}
