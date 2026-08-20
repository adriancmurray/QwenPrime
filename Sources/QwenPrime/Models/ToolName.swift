/// Stable namespaces used by local, workspace, skill, and MCP tool names.
public enum ToolNamespace: String, CaseIterable, Sendable {
  case skill = "skill__"
  case instructions = "instructions__"
  case mcp = "mcp__"
  case workspaceProcess = "workspace_process_"

  public func contains(_ toolName: String) -> Bool {
    toolName.hasPrefix(rawValue)
  }

  public func qualify(_ component: String) -> String {
    rawValue + component
  }
}

/// Canonical names and semantic name sets shared by tool producers and consumers.
public enum ToolName {
  public static let workspaceListDirectory = "workspace_list_directory"
  public static let workspaceReadFile = "workspace_read_file"
  public static let workspaceFindFiles = "workspace_find_files"
  public static let workspaceSearchText = "workspace_search_text"

  public static let workspaceWriteFile = "workspace_write_file"
  public static let workspaceApplyPatch = "workspace_apply_patch"
  public static let workspaceApplyChanges = "workspace_apply_changes"

  public static let workspaceProcessRun = "workspace_process_run"
  public static let workspaceProcessStart = "workspace_process_start"
  public static let workspaceProcessStatus = "workspace_process_status"
  public static let workspaceProcessStop = "workspace_process_stop"

  public static let workspaceInstructions = ToolNamespace.instructions.qualify(
    "AGENTS.md"
  )

  public static let workspaceReadTools: Set<String> = [
    workspaceFindFiles,
    workspaceListDirectory,
    workspaceReadFile,
    workspaceSearchText,
  ]

  public static let quietWorkspaceReadTools = workspaceReadTools

  public static let readOnlyWorkspaceTools: Set<String> =
    workspaceReadTools.union([
      workspaceProcessStatus
    ])

  public static let workspaceMutationTools: Set<String> = [
    workspaceWriteFile,
    workspaceApplyPatch,
    workspaceApplyChanges,
  ]

  public static func skill(_ name: String) -> String {
    ToolNamespace.skill.qualify(name)
  }

  public static func instructions(_ fileName: String) -> String {
    ToolNamespace.instructions.qualify(fileName)
  }

  public static func mcp(provider: String, tool: String) -> String {
    ToolNamespace.mcp.qualify("\(provider)__\(tool)")
  }
}
