import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

struct SkillManagementView: View {
    @ObservedObject var agent: AIAgentWorkspace
    @State private var pendingUninstallSkill: AgentSkill?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skills")
                        .font(.system(size: 11, weight: .semibold))
                    Text("统一存储并同步到已启用的 CLI")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    agent.synchronizeManagedSkills()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .help("立即同步 Skills")
            }

            skillLibraryRow

            VStack(alignment: .leading, spacing: 5) {
                Text("同步方式")
                    .font(.system(size: 10, weight: .medium))
                Picker("同步方式", selection: syncModeBinding) {
                    ForEach(AgentSkillSyncMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text(agent.store.state.skillSyncConfiguration.mode.detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("同步目标")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.bottom, 4)
                ForEach(AgentSkillSyncDestination.allCases, id: \.self) { destination in
                    destinationRow(destination)
                    if destination != AgentSkillSyncDestination.allCases.last {
                        Divider()
                    }
                }
            }
            .padding(7)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            skillsList
        }
        .alert(
            "卸载 Skill？",
            isPresented: Binding(
                get: { pendingUninstallSkill != nil },
                set: { if !$0 { pendingUninstallSkill = nil } }
            ),
            presenting: pendingUninstallSkill
        ) { skill in
            Button("卸载", role: .destructive) {
                pendingUninstallSkill = nil
                uninstallSkill(skill)
            }
            Button("取消", role: .cancel) {
                pendingUninstallSkill = nil
            }
        } message: { _ in
            Text("普通 Skill 会移到废纸篓；由 npm、pnpm、yarn、bun 或 Homebrew 全局安装的 Skill 会调用对应包管理器卸载。")
        }
    }

    private var skillLibraryRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "folder.badge.gearshape")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("受管库")
                    .font(.system(size: 10, weight: .medium))
                Text(agent.managedSkillsDirectory.path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button {
                guard let directory = agent.ensureManagedSkillsDirectory() else { return }
                NSWorkspace.shared.activateFileViewerSelecting([directory])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("在访达中打开受管库")
        }
        .padding(7)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var syncModeBinding: Binding<AgentSkillSyncMode> {
        Binding(
            get: { agent.store.state.skillSyncConfiguration.mode },
            set: { agent.updateManagedSkillSyncMode($0) }
        )
    }

    private func destinationRow(_ destination: AgentSkillSyncDestination) -> some View {
        HStack(spacing: 7) {
            Toggle("", isOn: Binding(
                get: { agent.store.state.skillSyncConfiguration.enabledDestinations.contains(destination) },
                set: { agent.setManagedSkillDestination(destination, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            VStack(alignment: .leading, spacing: 1) {
                Text(destination.displayName)
                    .font(.system(size: 10, weight: .medium))
                Text(agent.managedSkillDestinationDirectory(for: destination).path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var skillsList: some View {
        if !agent.store.state.skills.isEmpty {
            Text("已发现 Skills（\(agent.store.state.skills.count)）")
                .font(.system(size: 10, weight: .medium))
            ForEach(agent.store.state.skills) { skill in
                HStack(spacing: 7) {
                    Toggle("", isOn: skillEnabledBinding(skill.path))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    Text(skill.name)
                        .font(.system(size: 10))
                    Spacer(minLength: 0)
                    Text(skill.path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        pendingUninstallSkill = skill
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("卸载 Skill")
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func uninstallSkill(_ skill: AgentSkill) {
        Task {
            _ = await agent.uninstallSkill(path: skill.path)
        }
    }

    private func skillEnabledBinding(_ path: String) -> Binding<Bool> {
        Binding(
            get: { agent.store.state.skills.first { $0.path == path }?.isEnabled ?? false },
            set: { agent.setSkill(path: path, enabled: $0) }
        )
    }
}
