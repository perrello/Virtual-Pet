//
//  ContentView.swift
//  dynamicpet
//
//  Created by Angelo on 01/09/2025.
//
import SwiftUI

struct ContentView: View {
    @State private var urlText = "https://pets.studioperrello.com/packs/cube/manifest.json"
    @State private var index = PackIndex()
    @State private var isInstalling = false

    var body: some View {
        VStack(spacing: 14) {
            installRow()
            packsList()
            VStack(spacing: 12) {
                Button("Start LA") { PetActivity.start(fps: 1.0, mood: "Test") }
                    .buttonStyle(.borderedProminent)
                Button("Tick") { PetActivity.tick() }
                Button("Test") { writeTestSpriteToAppGroup() }
                Button("End") { PetActivity.end() }
            }
            .padding()
        }
        .padding(.vertical, 20)
        .onAppear { reloadIndex() }
    }
}

private extension ContentView {
    @ViewBuilder
    func installRow() -> some View {
        HStack {
            TextField("Manifest URL", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button(isInstalling ? "Installing…" : "Install") {
                installTapped()
            }
            .disabled(isInstalling)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    func packsList() -> some View {
        List {
            Section("Installed Packs") {
                ForEach(index.installed, id: \.id) { meta in
                    PackRow(
                        meta: meta,
                        isActive: index.activePackId == meta.id,
                        onSetActive: { setActive(meta.id) },
                        onRemove:    { remove(meta.id) }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Actions
    func installTapped() {
        guard let url = URL(string: urlText) else { return }
        isInstalling = true
        Task {
            defer { isInstalling = false }
            do {
                let meta = try await PackManager.install(from: url)
                await PackManager.settle()             // kleine sim-wacht
                reloadIndex()
                PetActivity.start(fps: meta.fps, mood: "Excited")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    PetActivity.tick()
                }
            } catch {
                print("Install failed:", error)
            }
        }
    }

    func setActive(_ id: String) {
        // vind meta in je index
        guard let meta = index.installed.first(where: { $0.id == id }) else { return }
        do {
            try PackManager.activate(meta)
            reloadIndex()                       // UI bijwerken
            // Live Activity updaten/starten met pack fps
            PetActivity.start(fps: meta.fps, mood: "Excited")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                PetActivity.tick()
            }
        } catch {
            print("Activate failed:", error)
        }
    }
    func remove(_ id: String) {
        PackManager.remove(id: id)
        reloadIndex()
        PetActivity.tick()
    }

    func reloadIndex() {
        index = PackManager.list()
    }
}

struct PackRow: View {
    let meta: PackMeta
    let isActive: Bool
    let onSetActive: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(meta.name).font(.headline)
                Text(meta.id).font(.caption2).foregroundStyle(.secondary)
                Text("\(meta.cols)x\(meta.rows) • \(meta.cellW)x\(meta.cellH) px • @\(meta.scale)x • \(String(format: "%.1f", meta.fps)) fps")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Text("Active").font(.caption).foregroundStyle(.green)
            }
            Menu {
                Button("Set Active", action: onSetActive)
                Button("Remove", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

func writeTestSpriteToAppGroup() {
    let base = SharedStore.containerURL
    let dest = base.appendingPathComponent("current-sprite.png")

    // 2880x1440 = 6 x 3 frames van 480x480
    let width = 2880, height = 1440, cell = 480
    let size = CGSize(width: width, height: height)

    UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
    guard let ctx = UIGraphicsGetCurrentContext() else { return }

    // raster van 6x3 kleurblokken
    for r in 0..<3 {
        for c in 0..<6 {
            let hue = CGFloat((r*6+c)) / 18.0
            ctx.setFillColor(UIColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1).cgColor)
            ctx.fill(CGRect(x: c*cell, y: r*cell, width: cell, height: cell))
        }
    }
    // dunne gridlijnen
    ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.2).cgColor)
    ctx.setLineWidth(1)
    for i in 0...6 { ctx.move(to: CGPoint(x: i*cell, y: 0)); ctx.addLine(to: CGPoint(x: i*cell, y: height)) }
    for j in 0...3 { ctx.move(to: CGPoint(x: 0, y: j*cell)); ctx.addLine(to: CGPoint(x: width, y: j*cell)) }
    ctx.strokePath()

    let img = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    guard let png = img?.pngData() else { return }
    try? FileManager.default.removeItem(at: dest)
    try? png.write(to: dest, options: .atomic)

    // Zet cfg in defaults en flush (sim)
    let d = SharedStore.defaults
    d.set([6, 3, 480, 480], forKey: "currentCfg")
    _ = d.synchronize()
    print("APP: wrote test sprite at \(dest.path)")
}
