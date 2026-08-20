import Testing

@testable import QwenPrime

@Suite("Tool name contract")
struct ToolNameTests {
  @Test("Namespaces construct and recognize stable external tool names")
  func namespaceContract() {
    #expect(ToolNamespace.skill.rawValue == "skill__")
    #expect(ToolNamespace.instructions.rawValue == "instructions__")
    #expect(ToolNamespace.mcp.rawValue == "mcp__")
    #expect(ToolNamespace.workspaceProcess.rawValue == "workspace_process_")

    #expect(ToolName.skill("swift-review") == "skill__swift-review")
    #expect(ToolName.instructions("AGENTS.md") == "instructions__AGENTS.md")
    #expect(ToolName.workspaceInstructions == "instructions__AGENTS.md")
    #expect(
      ToolName.mcp(provider: "local", tool: "add_numbers")
        == "mcp__local__add_numbers"
    )
    #expect(ToolName.workspaceReadTools.contains(ToolName.workspaceReadFile))
    #expect(
      ToolNamespace.workspaceProcess.contains(ToolName.workspaceProcessRun)
    )
    #expect(!ToolNamespace.mcp.contains(ToolName.workspaceReadFile))
  }

  @Test("Workspace semantic sets have one canonical membership contract")
  func workspaceSemanticSets() {
    #expect(
      ToolName.workspaceReadTools == [
        "workspace_find_files",
        "workspace_list_directory",
        "workspace_read_file",
        "workspace_search_text",
      ])
    #expect(
      ToolName.quietWorkspaceReadTools == [
        "workspace_find_files",
        "workspace_list_directory",
        "workspace_read_file",
        "workspace_search_text",
      ])
    #expect(
      ToolName.readOnlyWorkspaceTools == [
        "workspace_find_files",
        "workspace_list_directory",
        "workspace_process_status",
        "workspace_read_file",
        "workspace_search_text",
      ])
    #expect(
      ToolName.workspaceMutationTools == [
        "workspace_apply_changes",
        "workspace_apply_patch",
        "workspace_write_file",
      ])
  }

  @Test("Workspace process names cannot satisfy workspace read classification")
  func workspaceProcessAndReadClassificationAreDisjoint() {
    let processNames = [
      ToolName.workspaceProcessRun,
      ToolName.workspaceProcessStart,
      ToolName.workspaceProcessStatus,
      ToolName.workspaceProcessStop,
      "workspace_process_future_action",
    ]

    for processName in processNames {
      #expect(!ToolName.workspaceReadTools.contains(processName))
      #expect(ToolNamespace.workspaceProcess.contains(processName))
    }
  }
}
