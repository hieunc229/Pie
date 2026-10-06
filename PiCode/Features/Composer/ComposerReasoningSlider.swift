//
//  ComposerReasoningSlider.swift
//  PiCode
//
//  A compact stepped slider for the reasoning efforts exposed by the current
//  model. The catalog order is preserved because it represents increasing effort.
//

import SwiftUI

struct ComposerReasoningSlider: View {
    let levels: [String]
    let selectedLevel: String?
    let onSelect: (String) -> Void

    @State private var displayedIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            if levels.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: "brain")
                        .foregroundStyle(.tertiary)
                        .frame(width: 16)
                    Text("Reasoning effort unavailable")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 9) {
                    Image(systemName: "brain")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text("Reasoning effort")
                    Spacer(minLength: 8)
                    Text(selectedLevel?.pickerCapitalized ?? "Default")
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geometry in
                    let inset: CGFloat = 8
                    let trackWidth = max(geometry.size.width - inset * 2, 1)
                    let denominator = CGFloat(max(levels.count - 1, 1))
                    let progress = levels.count == 1
                        ? 0.5
                        : CGFloat(displayedIndex) / denominator

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.quaternary)
                            .frame(width: trackWidth, height: 4)
                            .offset(x: inset)

                        Capsule()
                            .fill(Color.accentColor.opacity(0.65))
                            .frame(width: max(progress * trackWidth, 2), height: 4)
                            .offset(x: inset)

                        ForEach(levels.indices, id: \.self) { index in
                            let stopProgress = levels.count == 1
                                ? 0.5
                                : CGFloat(index) / denominator
                            Circle()
                                .fill(index <= displayedIndex ? Color.accentColor : Color(nsColor: .separatorColor))
                                .frame(width: 6, height: 6)
                                .offset(x: inset + stopProgress * trackWidth - 3)
                        }

                        Circle()
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                            .offset(x: inset + progress * trackWidth - 8)

                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        displayedIndex = index(at: value.location.x,
                                                               inset: inset,
                                                               trackWidth: trackWidth)
                                    }
                                    .onEnded { value in
                                        let index = index(at: value.location.x,
                                                          inset: inset,
                                                          trackWidth: trackWidth)
                                        displayedIndex = index
                                        onSelect(levels[index])
                                    }
                            )
                    }
                }
                .frame(height: 18)
                .animation(.easeOut(duration: 0.12), value: displayedIndex)

                HStack(spacing: 0) {
                    ForEach(levels.indices, id: \.self) { index in
                        Text(levels[index].pickerCapitalized)
                            .font(.caption2.weight(index == displayedIndex ? .semibold : .regular))
                            .foregroundStyle(index == displayedIndex ? .primary : .tertiary)
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .onAppear(perform: synchronizeSelection)
        .onChange(of: levels) { _, _ in synchronizeSelection() }
        .onChange(of: selectedLevel) { _, _ in synchronizeSelection() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reasoning effort")
        .accessibilityValue(selectedLevel?.pickerCapitalized ?? "Default")
        .accessibilityAdjustableAction { direction in
            guard !levels.isEmpty else { return }
            let delta = direction == .increment ? 1 : -1
            let index = min(max(displayedIndex + delta, 0), levels.count - 1)
            displayedIndex = index
            onSelect(levels[index])
        }
    }

    private func index(at x: CGFloat, inset: CGFloat, trackWidth: CGFloat) -> Int {
        guard levels.count > 1 else { return 0 }
        let progress = min(max((x - inset) / trackWidth, 0), 1)
        return Int((progress * CGFloat(levels.count - 1)).rounded())
    }

    private func synchronizeSelection() {
        displayedIndex = levels.firstIndex(of: selectedLevel ?? "") ?? 0
    }
}
