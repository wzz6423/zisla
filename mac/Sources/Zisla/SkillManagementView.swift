import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

struct SkillManagementView: View {
    @ObservedObject var agent: AIAgentWorkspace

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

            managedSkillsList
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
    private var managedSkillsList: some View {
        if !agent.managedSkills.isEmpty {
            Text("受管 Skills（\(agent.managedSkills.count)）")
                .font(.system(size: 10, weight: .medium))
            ForEach(agent.managedSkills) { skill in
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
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func skillEnabledBinding(_ path: String) -> Binding<Bool> {
        Binding(
            get: { agent.store.state.skills.first { $0.path == path }?.isEnabled ?? false },
            set: { agent.setSkill(path: path, enabled: $0) }
        )
    }
}
