import SwiftUI
import UIKit
import AVFoundation

struct SettingsTab: View {
    @State private var showSkills = false
    @State private var showResearch = false

    var body: some View {
        NavigationStack {
            List {
                Section("Général") {
                    NavigationLink { SettingsDetail(kind: .appearance) } label: {
                        Label("Apparence et texte", systemImage: "paintpalette")
                    }
                    NavigationLink { SettingsDetail(kind: .voice) } label: {
                        Label("Voix", systemImage: "speaker.wave.2")
                    }
                    NavigationLink { SettingsDetail(kind: .prompt) } label: {
                        Label("Prompt système", systemImage: "text.quote")
                    }
                }
                Section("Modèle") {
                    NavigationLink { SettingsDetail(kind: .performance) } label: {
                        Label("Performance", systemImage: "bolt")
                    }
                    NavigationLink { SettingsDetail(kind: .memory) } label: {
                        Label("Modèles et mémoire", systemImage: "memorychip")
                    }
                    NavigationLink { SettingsDetail(kind: .sampling) } label: {
                        Label("Paramètres du modèle", systemImage: "slider.horizontal.3")
                    }
                }
                Section("Outils") {
                    Button { showSkills = true } label: {
                        Label("Compétences", systemImage: "sparkles")
                    }
                    Button { showResearch = true } label: {
                        Label("Recherche Web", systemImage: "globe")
                    }
                    NavigationLink { DownloadsView() } label: {
                        Label("Hugging Face", systemImage: "arrow.down.circle")
                    }
                }
                Section("Plus") {
                    NavigationLink { SettingsDetail(kind: .data) } label: {
                        Label("Données et confidentialité", systemImage: "lock")
                    }
                }
                Section("À propos") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—") · build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Réglages")
            .sheet(isPresented: $showSkills) { SkillsView() }
            .sheet(isPresented: $showResearch) { ResearchView() }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
        }
    }
}

struct SettingsDetail: View {
    enum Kind { case appearance, voice, prompt, performance, memory, sampling, data }

    let kind: Kind
    @EnvironmentObject private var vm: VM
    @Environment(\.dismiss) private var dismiss
    @State private var voices: [AVSpeechSynthesisVoice] = []

    private let presets: [(String, String)] = [
        ("Concis", "Tu es un assistant concis et précis. Réponds dans la langue de l'utilisateur."),
        ("Maths", "Tu es un tuteur de mathématiques rigoureux. Donne la formule exacte puis le raisonnement étape par étape, sans inventer."),
        ("Traducteur", "Tu es un traducteur FR↔EN. Traduis fidèlement, sans commentaire."),
        ("Code", "Tu es un expert Python, HTML, CSS et JavaScript. Donne du code correct, commenté et court.")
    ]

    var body: some View {
        Form { content }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { voices = Speaker.voices() }
    }

    private var title: String {
        switch kind {
        case .appearance: return "Apparence et texte"
        case .voice: return "Voix"
        case .prompt: return "Prompt système"
        case .performance: return "Performance"
        case .memory: return "Modèles et mémoire"
        case .sampling: return "Paramètres du modèle"
        case .data: return "Données"
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .appearance: appearanceSection
        case .voice: voiceSection
        case .prompt: promptSection
        case .performance:
            perfSection
            adviceSection
        case .memory: modelsMemorySection
        case .sampling: samplingSection
        case .data: dataSection
        }
    }

    // MARK: apparence

    private var fontDesignBinding: Binding<Int> {
        Binding(get: { vm.prefs.fontDesign }, set: { vm.prefs.fontDesign = $0 })
    }

    private var appearanceSection: some View {
        Group {
            Section("Thème") {
                Picker("Thème", selection: $vm.cfg.theme) {
                    Text("Auto").tag(0)
                    Text("Clair").tag(1)
                    Text("Sombre").tag(2)
                }
                .pickerStyle(.segmented)
                ColorPicker(
                    "Couleur d'accent",
                    selection: Binding(get: { vm.cfg.accent }, set: { vm.cfg.setAccent($0) })
                )
            }
            Section {
                Picker("Police", selection: fontDesignBinding) {
                    Text("Système").tag(0)
                    Text("Arrondie").tag(1)
                    Text("Serif").tag(2)
                    Text("Mono").tag(3)
                }
                .pickerStyle(.segmented)
                HStack { sliderRow("Taille des messages", $vm.cfg.fontSize, 12...26, 1); resetButton { vm.cfg.fontSize = Cfg().fontSize } }
                HStack { sliderRow("Taille générale de l'interface", $vm.prefs.interfaceFontScale, 0.85...1.35, 0.05); resetButton { vm.prefs.interfaceFontScale = Prefs().interfaceFontScale } }
                Text("Aperçu : le discriminant vaut b² − 4ac. Voici un texte pour vérifier la lisibilité.")
                    .font(.system(size: vm.cfg.fontSize, design: vm.fontDesign))
                    .padding(.vertical, 4)
            } header: {
                Text("Texte des messages")
            }
            Section("Bulles des discussions") {
                Picker("Style", selection: $vm.prefs.bubbleMode) {
                    Text("Sans bulle").tag(0); Text("Discret").tag(1); Text("Coloré").tag(2)
                }.pickerStyle(.segmented)
                Picker("Couleur", selection: $vm.prefs.bubbleColor) {
                    Text("Système").tag(0); Text("Accent").tag(1); Text("Vert").tag(2); Text("Violet").tag(3)
                }
                HStack { Spacer(); resetButton { vm.prefs.bubbleMode = 1; vm.prefs.bubbleColor = 0 } }
            }
            Section {
                Picker("Réflexion", selection: $vm.prefs.thinkDisplay) {
                    Text("Repliée").tag(0)
                    Text("Visible").tag(1)
                    Text("Masquée").tag(2)
                }
                .pickerStyle(.segmented)
                Toggle("Retour haptique", isOn: $vm.cfg.haptics)
                Toggle("Écran allumé pendant la génération", isOn: $vm.cfg.keepAwake)
                Toggle("Autoriser la réflexion des modèles", isOn: $vm.prefs.reasoningEnabled)
                Button("Réinitialiser l'apparence", role: .destructive) {
                    let d = Cfg(); vm.cfg.theme = d.theme; vm.cfg.fontSize = d.fontSize; vm.cfg.accR = d.accR; vm.cfg.accG = d.accG; vm.cfg.accB = d.accB
                    let p = Prefs(); vm.prefs.fontDesign = p.fontDesign; vm.prefs.interfaceFontScale = p.interfaceFontScale; vm.prefs.bubbleMode = 1; vm.prefs.bubbleColor = 0
                    vm.prefs.thinkDisplay = 0; vm.cfg.haptics = true; vm.cfg.keepAwake = true; vm.prefs.reasoningEnabled = true
                }
            } header: {
                Text("Comportement")
            } footer: {
                Text("La réflexion concerne les modèles comme DeepSeek R1 qui « pensent » avant de répondre.")
            }
        }
    }

    // MARK: performance

    private var gpuBinding: Binding<Bool> {
        Binding(get: { vm.cfg.gpuLayers > 0 }, set: { vm.cfg.gpuLayers = $0 ? 99 : 0 })
    }

    private func profileCard(_ profile: PerfProfile) -> some View {
        let selected = PerfProfile.detect(vm.cfg) == profile
        return Button {
            vm.applyProfile(profile)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: profile.icon).font(.title3)
                Text(profile.title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                selected ? vm.cfg.accent.opacity(0.18) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? vm.cfg.accent : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var ramRow: some View {
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576
        let used = Sys.footprintMB()
        return VStack(alignment: .leading, spacing: 4) {
            Text(String(format: "RAM : %.0f Mo utilisés sur %.0f Mo · disponible pour l'app ≈ %.0f Mo", used, total, Sys.availMB()))
                .font(.caption)
            ProgressView(value: min(used, total), total: total)
        }
    }

    private var adviceSection: some View {
        Section {
            ForEach(Advisor.advice(modelName: vm.currentName, modelSizeMB: vm.currentModelSizeMB, cfg: vm.cfg)) { item in
                Label(item.text, systemImage: item.level == 1 ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.footnote)
            }
        } header: {
            Text("Recommandations")
        } footer: {
            Text("Calculées d'après l'état réel de l'appareil et tes benchmarks. Elles ne modifient aucun réglage.")
        }
    }

    private var perfSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(PerfProfile.allCases) { profile in profileCard(profile).frame(width: 76) } }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            .listRowBackground(Color.clear)

            Text(PerfProfile.detect(vm.cfg).detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack { Toggle(isOn: gpuBinding) { Label("GPU Metal", systemImage: "cpu") }; resetButton { vm.cfg.gpuLayers = Cfg().gpuLayers } }
            HStack { Toggle("Lecture mmap", isOn: $vm.prefs.mmap); resetButton { vm.prefs.mmap = true } }
            HStack { Toggle("Protection thermique et batterie", isOn: $vm.prefs.thermalGuard); resetButton { vm.prefs.thermalGuard = true } }
            HStack { Stepper(value: $vm.cfg.nCtx, in: 256...65536, step: 256) { Label("Contexte : \(vm.cfg.nCtx) tokens", systemImage: "text.alignleft") }; resetButton { vm.cfg.nCtx = Cfg().nCtx } }
            HStack { Stepper(value: $vm.cfg.nBatch, in: 32...2048, step: 32) { Label("Batch : \(vm.cfg.nBatch)", systemImage: "square.stack.3d.up") }; resetButton { vm.cfg.nBatch = Cfg().nBatch } }
            HStack { Stepper(value: $vm.cfg.threads, in: 1...8) { Label("Threads : \(vm.cfg.threads)", systemImage: "square.grid.3x3") }; resetButton { vm.cfg.threads = Cfg().threads } }
            HStack { Stepper(value: $vm.cfg.batchThreads, in: 1...8) { Label("Threads préremplissage : \(vm.cfg.batchThreads)", systemImage: "square.stack.3d.up") }; resetButton { vm.cfg.batchThreads = Cfg().batchThreads } }
            Text("Les threads de génération et de préremplissage sont appliqués séparément par llama.cpp. La garde réduit ces valeurs uniquement si l'état thermique iOS est sérieux/critique ou si le mode économie d'énergie est actif.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Stepper(value: $vm.cfg.maxTokens, in: 64...2048, step: 64) { Label("Réponse max : \(vm.cfg.maxTokens) tokens", systemImage: "text.badge.checkmark") }; resetButton { vm.cfg.maxTokens = Cfg().maxTokens } }
            HStack { Stepper(value: $vm.cfg.nUBatch, in: 32...1024, step: 32) { Label("Micro-batch : \(vm.cfg.nUBatch)", systemImage: "square.stack") }; resetButton { vm.cfg.nUBatch = Cfg().nUBatch } }
            HStack {
                Picker(selection: $vm.cfg.flashAttn) {
                    Text("Auto").tag(0); Text("Activée").tag(1); Text("Désactivée").tag(2)
                } label: { Label("Flash Attention", systemImage: "bolt.horizontal") }
                resetButton { vm.cfg.flashAttn = Cfg().flashAttn }
            }
            HStack {
                Picker(selection: $vm.cfg.kvQuant) {
                    Text("Précis (f16)").tag(0); Text("Compact (q8)").tag(1)
                } label: { Label("Cache K/V", systemImage: "memorychip") }
                resetButton { vm.cfg.kvQuant = Cfg().kvQuant }
            }
            HStack { Toggle(isOn: $vm.prefs.liteStream) { Label("Affichage fluide pendant la génération", systemImage: "text.alignleft") }; resetButton { vm.prefs.liteStream = Prefs().liteStream } }
            if !Sys.gpuCapable {
                Text("Le GPU Metal n'est pas activé par défaut sur cet appareil (iOS 18+ et GPU de génération A14 ou plus récente requis). Tu peux le forcer ; si le chargement échoue, Pal retombe sur le CPU. Compare toujours avec le benchmark.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ramRow
            Button("Réinitialiser les réglages de performance", role: .destructive) { vm.resetPerformance() }

            if vm.needsReload {
                Button {
                    vm.reload()
                    dismiss()
                } label: {
                    Label("Appliquer et recharger le modèle", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        } footer: {
            Text("Ultra dépasse Max et peut faire fermer Pal par iOS sur un appareil à mémoire limitée. Les valeurs personnalisées sont conservées dans Perso. Contexte, GPU, micro-batch, Flash Attention et cache K/V demandent de recharger le modèle ; une valeur de contexte trop élevée peut échouer selon le modèle et la RAM disponible.")
        }
    }

    // MARK: modèles et mémoire

    private var launchModelBinding: Binding<String> {
        Binding(get: { vm.prefs.launchModelID ?? "" }, set: { vm.prefs.launchModelID = $0.isEmpty ? nil : $0 })
    }

    private var newChatBinding: Binding<String> {
        Binding(get: { vm.prefs.newChatModelID ?? "" }, set: { vm.prefs.newChatModelID = $0.isEmpty ? nil : $0 })
    }

    private var modelsMemorySection: some View {
        Section {
            Picker("Au lancement de l'app", selection: $vm.prefs.launchMode) {
                Text("Ne rien charger (à la demande)").tag(0)
                Text("Recharger le dernier modèle").tag(1)
                Text("Toujours charger le modèle choisi").tag(2)
            }
            if vm.prefs.launchMode == 2 {
                Picker("Modèle de lancement", selection: launchModelBinding) {
                    Text("—").tag("")
                    ForEach(vm.models) { model in
                        Text(model.name).tag(model.id.uuidString)
                    }
                }
            }
            Picker("Nouvelles discussions", selection: newChatBinding) {
                Text("Modèle actuel").tag("")
                ForEach(vm.models) { model in
                    Text(model.name).tag(model.id.uuidString)
                }
            }
            Picker("Décharger si inactif", selection: $vm.prefs.autoUnloadMinutes) {
                Text("Jamais").tag(0)
                Text("1 min").tag(1)
                Text("5 min").tag(5)
                Text("10 min").tag(10)
                Text("30 min").tag(30)
                Text("60 min").tag(60)
            }
            Toggle("Décharger en arrière-plan", isOn: $vm.prefs.unloadInBackground)
            Button("Réinitialiser les préférences de chargement") {
                vm.prefs.launchMode = 0; vm.prefs.launchModelID = nil; vm.prefs.newChatModelID = nil
                vm.prefs.autoUnloadMinutes = 10; vm.prefs.unloadInBackground = true
            }
            Button {
                vm.unloadModel()
            } label: {
                Label("Décharger le modèle maintenant", systemImage: "eject")
            }
            .disabled(!vm.engine.loaded || vm.generating || vm.loading)
        } footer: {
            Text("Chaque discussion garde son modèle. Un modèle déchargé libère la RAM et se recharge tout seul à l'envoi du prochain message.")
        }
    }

    // MARK: voix

    private var voiceBinding: Binding<String> {
        Binding(get: { vm.prefs.ttsVoice ?? "" }, set: { vm.prefs.ttsVoice = $0.isEmpty ? nil : $0 })
    }

    private var voiceSection: some View {
        Section {
            Toggle("Lire les réponses automatiquement", isOn: $vm.prefs.ttsAuto)
            Picker("Voix", selection: voiceBinding) {
                Text("Automatique").tag("")
                ForEach(voices, id: \.identifier) { voice in
                    Text("\(voice.name) · \(voice.language) · \(Speaker.qualityLabel(voice))").tag(voice.identifier)
                }
            }
            HStack { VStack(alignment: .leading) {
                Text(String(format: "Vitesse : %.2f", vm.prefs.ttsRate)).font(.subheadline)
                Slider(value: $vm.prefs.ttsRate, in: 0.3...0.6, step: 0.01)
            }; resetButton { vm.prefs.ttsRate = 0.5; vm.prefs.ttsVoice = nil } }
            Button {
                vm.speaker.speak("Bonjour, je suis Pal. Voici ma voix.", voiceID: vm.prefs.ttsVoice, rate: vm.prefs.ttsRate)
            } label: {
                Label("Tester la voix", systemImage: "speaker.wave.2")
            }
        } footer: {
            Text("Pour de meilleures voix : Réglages iOS › Accessibilité › Contenu énoncé › Voix.")
        }
    }

    // MARK: prompt, échantillonnage, données

    private var promptSection: some View {
        Section {
            TextEditor(text: $vm.cfg.system)
                .frame(minHeight: 120)
            Menu("Préréglages") {
                ForEach(presets, id: \.0) { preset in Button(preset.0) { vm.cfg.system = preset.1 } }
            }
            Button("Réinitialiser le prompt système", role: .destructive) { vm.cfg.system = Cfg().system }
        } footer: {
            Text("Utilisé quand la discussion n'a pas de personnage. Il s'applique au prochain message.")
        }
    }

    private var samplingSection: some View {
        Section("Échantillonnage") {
            HStack { sliderRow("temperature", $vm.cfg.temp, 0...2, 0.05); resetButton { vm.cfg.temp = Cfg().temp } }
            HStack { sliderRow("top_p", $vm.cfg.topP, 0...1, 0.05); resetButton { vm.cfg.topP = Cfg().topP } }
            HStack { sliderRow("min_p", $vm.cfg.minP, 0...0.5, 0.01); resetButton { vm.cfg.minP = Cfg().minP } }
            HStack { sliderRow("repeat_penalty", $vm.cfg.repeatPen, 1...1.5, 0.01); resetButton { vm.cfg.repeatPen = Cfg().repeatPen } }
            HStack { Stepper("top_k : \(vm.cfg.topK)", value: $vm.cfg.topK, in: 1...200); resetButton { vm.cfg.topK = Cfg().topK } }
            Button("Réinitialiser l'échantillonnage", role: .destructive) {
                let d = Cfg(); vm.cfg.temp = d.temp; vm.cfg.topP = d.topP; vm.cfg.minP = d.minP; vm.cfg.repeatPen = d.repeatPen; vm.cfg.topK = d.topK
            }
        }
    }

    private var dataSection: some View {
        Section {
            Text("Les conversations restent stockées localement sur l'iPhone. Les modèles du dossier Pal sont lus sur place ; ceux choisis via le sélecteur sont lus à leur emplacement d'origine. Aucune copie n'est faite sans ton accord.")
                .font(.caption)
            Button("Supprimer la discussion actuelle", role: .destructive) {
                vm.deleteChat(vm.currentChatID)
            }
            .disabled(vm.generating || vm.loading || vm.messages.isEmpty)
        }
    }

    private func resetButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "arrow.uturn.backward.circle") }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("Réinitialiser ce paramètre")
    }

    private func sliderRow(
        _ name: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        _ step: Double
    ) -> some View {
        VStack(alignment: .leading) {
            Text("\(name) : \(String(format: "%.2f", value.wrappedValue))")
                .font(.subheadline)
            Slider(value: value, in: range, step: step)
        }
    }
}
