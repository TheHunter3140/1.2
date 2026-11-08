import SwiftUI
import UIKit
import os
import Darwin
import PDFKit
import Metal

struct Msg: Identifiable, Codable {
    var id = UUID()
    var role: String
    var text: String
    var thinkSeconds: Double? = nil
    var stat: String? = nil
    var needsContinuation: Bool? = nil
}

struct ModelEntry: Identifiable, Codable {
    var id = UUID(); var name: String; var bookmark: Data; var sizeMB: Int
    var mmproj: Data? = nil; var mmprojName: String? = nil
    var relPath: String? = nil      // chemin relatif dans Documents (modèles du dossier Pal)
    var mmprojRel: String? = nil
    var archInfo: String? = nil     // description donnée par le moteur après vérification
    var compatible: Bool? = nil     // nil = pas encore vérifié
}

enum PerfProfile: String, CaseIterable, Identifiable {
    case eco, balanced, performance, ultra, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .eco: return "Éco"
        case .balanced: return "Équilibré"
        case .performance: return "Max"
        case .ultra: return "Ultra"
        case .custom: return "Perso"
        }
    }
    var icon: String {
        switch self {
        case .eco: return "leaf.fill"
        case .balanced: return "scale.3d"
        case .performance: return "bolt.fill"
        case .ultra: return "flame.fill"
        case .custom: return "slider.horizontal.3"
        }
    }
    var detail: String {
        switch self {
        case .eco: return "Consommation réduite : 2 threads, contexte court, cache K/V compact, priorité basse, CPU."
        case .balanced: return "Contexte 2048, batch 512, GPU Metal automatique si l'appareil le permet."
        case .performance: return "Contexte 4096, plus de mémoire. Utilise le GPU Metal seulement si l'appareil est éligible."
        case .ultra: return "Réglages extrêmes : forte consommation de RAM, risque de fermeture de l'app sur un appareil à mémoire limitée."
        case .custom: return "Réglages personnalisés."
        }
    }

    func apply(_ cfg: inout Cfg) {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        switch self {
        case .eco:
            cfg.nCtx = 1024; cfg.nBatch = 128; cfg.nUBatch = 128; cfg.threads = min(2, cores)
            cfg.gpuLayers = 0; cfg.maxTokens = 256; cfg.flashAttn = 0; cfg.kvQuant = 1
        case .balanced:
            cfg.nCtx = 2048; cfg.nBatch = 512; cfg.nUBatch = 512; cfg.threads = Sys.defaultThreads
            cfg.gpuLayers = Sys.gpuCapable ? 99 : 0; cfg.maxTokens = 512; cfg.flashAttn = 0; cfg.kvQuant = 0
        case .performance:
            cfg.nCtx = 4096; cfg.nBatch = 512; cfg.nUBatch = 512; cfg.threads = Sys.defaultThreads
            cfg.gpuLayers = Sys.gpuCapable ? 99 : 0; cfg.maxTokens = 1024; cfg.flashAttn = 0; cfg.kvQuant = 0
        case .ultra:
            cfg.nCtx = 8192; cfg.nBatch = 1024; cfg.nUBatch = 512; cfg.threads = max(2, cores)
            cfg.gpuLayers = Sys.gpuCapable ? 99 : 0; cfg.maxTokens = 2048; cfg.flashAttn = 0; cfg.kvQuant = 1
        case .custom:
            break
        }
    }

    /// Réglages Max/Ultra de la version 1.1.0 (GPU forcé) : migrés vers ceux de la version 1.2.
    static func v110Match(_ c: Cfg) -> PerfProfile? {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        if c.nCtx == 4096 && c.nBatch == 512 && c.nUBatch == 512 && c.threads == Sys.defaultThreads
            && c.gpuLayers == 99 && c.maxTokens == 1024 && c.flashAttn == 0 && c.kvQuant == 1 {
            return .performance
        }
        if c.nCtx == 8192 && c.nBatch == 1024 && c.nUBatch == 512 && c.threads == max(2, cores)
            && c.gpuLayers == 99 && c.maxTokens == 2048 && c.flashAttn == 0 && c.kvQuant == 1 {
            return .ultra
        }
        return nil
    }

    /// Anciens profils (≤ 1.0.5) : sert à migrer une installation existante vers les nouveaux réglages.
    static func legacyMatch(_ c: Cfg) -> PerfProfile? {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let table: [(PerfProfile, Int, Int, Int, Int, Int)] = [
            (.eco, 768, 64, min(2, cores), 0, 192),
            (.balanced, 1024, 128, min(3, cores), 0, 256),
            (.performance, 2048, 256, max(2, min(4, cores - 1)), 99, 512),
            (.ultra, 8192, 512, max(2, cores), 99, 1024),
        ]
        for (profile, ctx, batch, threads, gpu, maxTok) in table
        where c.nCtx == ctx && c.nBatch == batch && c.threads == threads && c.gpuLayers == gpu && c.maxTokens == maxTok {
            return profile
        }
        return nil
    }

    static func detect(_ cfg: Cfg) -> PerfProfile {
        for profile in [PerfProfile.eco, .balanced, .performance, .ultra] {
            var probe = cfg
            profile.apply(&probe)
            if probe.nCtx == cfg.nCtx && probe.nBatch == cfg.nBatch && probe.threads == cfg.threads
                && probe.gpuLayers == cfg.gpuLayers && probe.maxTokens == cfg.maxTokens
                && probe.nUBatch == cfg.nUBatch && probe.flashAttn == cfg.flashAttn && probe.kvQuant == cfg.kvQuant {
                return profile
            }
        }
        return .custom
    }
}

struct Cfg: Codable {
    var temp = 0.7, topP = 0.9, minP = 0.05, repeatPen = 1.1
    var topK = 40, nCtx = 2048, nBatch = 512, nUBatch = 512, threads = Sys.defaultThreads
    var gpuLayers = Sys.gpuCapable ? 99 : 0, maxTokens = 512
    var flashAttn = 0          // 0 auto, 1 activée, 2 désactivée
    var kvQuant = 0            // 0 précis (f16), 1 compact (q8_0)
    static let legacyDefaultSystem = "Tu es un assistant concis et précis. Réponds dans la langue de l'utilisateur."
    var system = ""            // vide par défaut
    var theme = 0, fontSize = 12.0, accR = 0.004, accG = 0.78, accB = 0.99
    var haptics = true, keepAwake = true

    enum CodingKeys: String, CodingKey {
        case temp, topP, minP, repeatPen, topK, nCtx, nBatch, nUBatch, threads, gpuLayers, maxTokens
        case flashAttn, kvQuant, system, theme, fontSize, accR, accG, accB, haptics, keepAwake
    }

    init() {}

    /// Décodage tolérant : les anciens réglages enregistrés restent valides.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Cfg()
        temp = try c.decodeIfPresent(Double.self, forKey: .temp) ?? d.temp
        topP = try c.decodeIfPresent(Double.self, forKey: .topP) ?? d.topP
        minP = try c.decodeIfPresent(Double.self, forKey: .minP) ?? d.minP
        repeatPen = try c.decodeIfPresent(Double.self, forKey: .repeatPen) ?? d.repeatPen
        topK = try c.decodeIfPresent(Int.self, forKey: .topK) ?? d.topK
        nCtx = try c.decodeIfPresent(Int.self, forKey: .nCtx) ?? d.nCtx
        nBatch = try c.decodeIfPresent(Int.self, forKey: .nBatch) ?? d.nBatch
        nUBatch = try c.decodeIfPresent(Int.self, forKey: .nUBatch) ?? d.nUBatch
        threads = try c.decodeIfPresent(Int.self, forKey: .threads) ?? d.threads
        gpuLayers = try c.decodeIfPresent(Int.self, forKey: .gpuLayers) ?? d.gpuLayers
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? d.maxTokens
        flashAttn = try c.decodeIfPresent(Int.self, forKey: .flashAttn) ?? d.flashAttn
        kvQuant = try c.decodeIfPresent(Int.self, forKey: .kvQuant) ?? d.kvQuant
        system = try c.decodeIfPresent(String.self, forKey: .system) ?? d.system
        theme = try c.decodeIfPresent(Int.self, forKey: .theme) ?? d.theme
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        accR = try c.decodeIfPresent(Double.self, forKey: .accR) ?? d.accR
        accG = try c.decodeIfPresent(Double.self, forKey: .accG) ?? d.accG
        accB = try c.decodeIfPresent(Double.self, forKey: .accB) ?? d.accB
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? d.haptics
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? d.keepAwake
    }

    var accent: Color { Color(red: accR, green: accG, blue: accB) }
    var scheme: ColorScheme? { theme == 1 ? .light : theme == 2 ? .dark : nil }
    mutating func setAccent(_ c: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        accR = r; accG = g; accB = b
    }
}

enum Sys {
    /// Threads par défaut : assez pour le prefill sans surchauffer.
    static var defaultThreads: Int { max(2, min(4, ProcessInfo.processInfo.activeProcessorCount - 2)) }

    /// GPU Metal utilisable : appareil réel, iOS 18+ et GPU famille Apple7 (A14 ou plus récent).
    static var gpuCapable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard #available(iOS 18.0, *) else { return false }
        return MTLCreateSystemDefaultDevice()?.supportsFamily(.apple7) ?? false
        #endif
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return r == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
    static func availMB() -> Double { Double(os_proc_available_memory()) / 1_048_576 }
    static var thermal: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "ok"
        case .fair: return "tiède"
        case .serious: return "chaud"
        case .critical: return "critique"
        @unknown default: return "?"
        }
    }
    static var battery: String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let l = UIDevice.current.batteryLevel
        if l < 0 { return "—" }
        return "\(Int(l * 100)) %" + (UIDevice.current.batteryState == .charging ? " ⚡︎" : "")
    }
    static var disk: String {
        String(format: "%.1f Go", Double(freeDiskBytes()) / 1e9)
    }
    static func freeDiskBytes() -> Int64 {
        let v = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

@MainActor final class VM: ObservableObject {
    let engine = Engine()
    let speaker = Speaker()
    @Published var cfg = Cfg() { didSet { if let d = try? JSONEncoder().encode(cfg) { UD.set(d, forKey: "cfg") } } }
    @Published var prefs = Prefs() { didSet { if let d = try? JSONEncoder().encode(prefs) { UD.set(d, forKey: "prefs") } } }
    @Published var models: [ModelEntry] = []
    @Published var skills: [PalSkill] = PalSkill.defaults
    @Published var conversations: [Conversation] = []
    @Published var currentChatID = UUID()
    @Published var currentID: UUID?
    @Published var messages: [Msg] = []
    @Published var streaming: String?
    @Published var input = ""
    @Published var status = "Aucun modèle"
    @Published var stats = GenStats()
    @Published var loading = false
    @Published var benchmark = ""
    @Published var requestModelPicker = false
    @Published var personas: [Persona] = Persona.defaults
    private var genStart = Date()
    private var thinkEnd: Date?
    private var memWarn = false
    private var pendingSend = false
    private var pendingSignature = ""
    private var lastLoadPath = ""
    private var loadedSignature = ""
    private var idleTask: Task<Void, Never>?
    var generating: Bool { streaming != nil }
    private var scoped: URL?
    let UD = UserDefaults.standard

    init() {
        PalFolders.prepare()
        if let d = UD.data(forKey: "cfg"), let c = try? JSONDecoder().decode(Cfg.self, from: d) {
            cfg = c
            let version = UD.integer(forKey: "perfVersion")
            // Migrations : anciens profils (≤ 1.0.5) puis Max/Ultra de la 1.1.0 (GPU forcé).
            if version < 2, let legacy = PerfProfile.legacyMatch(c) {
                legacy.apply(&cfg)
            } else if version < 3, let current = PerfProfile.v110Match(c) {
                current.apply(&cfg)
            }
            // Prompt système : seule l'ancienne phrase par défaut est retirée, un texte personnalisé est conservé.
            if version < 3 && cfg.system == Cfg.legacyDefaultSystem { cfg.system = "" }
        }
        if let d = UD.data(forKey: "prefs"), let p = try? JSONDecoder().decode(Prefs.self, from: d) { prefs = p }
        if UD.integer(forKey: "perfVersion") < 3 {
            prefs.liteStream = true    // conserve le mode léger de la 1.1.0 pour éviter le rendu riche à chaque token
            // Les observateurs ne s'exécutent pas dans init : on enregistre explicitement.
            if let d = try? JSONEncoder().encode(cfg) { UD.set(d, forKey: "cfg") }
            if let d = try? JSONEncoder().encode(prefs) { UD.set(d, forKey: "prefs") }
        }
        UD.set(3, forKey: "perfVersion")
        if let d = UD.data(forKey: "models"), let m = try? JSONDecoder().decode([ModelEntry].self, from: d) { models = m }
        if let d = UD.data(forKey: "skills"), let saved = try? JSONDecoder().decode([PalSkill].self, from: d) { skills = saved }
        if let d = UD.data(forKey: "personas"), let saved = try? JSONDecoder().decode([Persona].self, from: d), !saved.isEmpty { personas = saved }
        loadConversations()
        scanLibrary()
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.generating else { return }
                self.unloadModel(reason: "Déchargé (mémoire faible)")
            }
        }
        chooseLaunchModel()
        bindDownloadCallback()
        if DownloadManager.hasActiveItems { attachDownloads() }
    }

    var currentName: String { models.first { $0.id == currentID }?.name ?? "Pal" }
    var currentModelSizeMB: Int { models.first { $0.id == currentID }?.sizeMB ?? 0 }

    var fontDesign: Font.Design {
        switch prefs.fontDesign {
        case 1: return .rounded
        case 2: return .serif
        case 3: return .monospaced
        default: return .default
        }
    }

    /// Vrai si le modèle courant produit une phase de réflexion (DeepSeek R1, Qwen3, QwQ…).
    var modelThinks: Bool {
        let name = currentName.lowercased()
        return ["r1", "think", "qwq", "qwen3", "reason"].contains { name.contains($0) }
    }

    // MARK: personnages (prompts système nommés)

    var currentPersona: Persona? {
        guard let id = conversations.first(where: { $0.id == currentChatID })?.personaID else { return nil }
        return personas.first { $0.id == id }
    }

    private func savePersonas() {
        if let d = try? JSONEncoder().encode(personas) { UD.set(d, forKey: "personas") }
    }

    func savePersona(_ persona: Persona) {
        let name = persona.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = persona.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !prompt.isEmpty else { return }
        var updated = persona
        updated.name = String(name.prefix(40))
        updated.prompt = String(prompt.prefix(4000))
        if let index = personas.firstIndex(where: { $0.id == persona.id }) {
            personas[index] = updated
        } else {
            personas.append(updated)
        }
        savePersonas()
        engine.restore(system: effectiveSystemPrompt, history: messages)
    }

    func deletePersona(_ id: String) {
        personas.removeAll { $0.id == id && !$0.builtIn }
        for index in conversations.indices where conversations[index].personaID == id {
            conversations[index].personaID = nil
        }
        savePersonas()
        saveConversations()
    }

    func setPersona(_ id: String?) {
        guard let index = conversations.firstIndex(where: { $0.id == currentChatID }) else { return }
        conversations[index].personaID = id
        saveConversations()
        engine.restore(system: effectiveSystemPrompt, history: messages)
    }
    func saveModels() { if let d = try? JSONEncoder().encode(models) { UD.set(d, forKey: "models") } }
    func saveSkills() { if let d = try? JSONEncoder().encode(skills) { UD.set(d, forKey: "skills") } }

    // MARK: conversations

    private static func makeTitle(_ msgs: [Msg]) -> String {
        guard let first = msgs.first(where: { $0.role == "user" }) else { return "Nouvelle discussion" }
        let line = first.text.components(separatedBy: .newlines).first ?? first.text
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Nouvelle discussion" : String(t.prefix(44))
    }

    private func loadConversations() {
        if let d = try? Data(contentsOf: PalStore.conversationsURL),
           let list = try? JSONDecoder().decode([Conversation].self, from: d), !list.isEmpty {
            conversations = list
        } else if let d = try? Data(contentsOf: PalStore.legacyChatURL),
                  let old = try? JSONDecoder().decode([Msg].self, from: d), !old.isEmpty {
            var c = Conversation()
            c.messages = old
            c.title = VM.makeTitle(old)
            conversations = [c]
        } else {
            conversations = [Conversation()]
        }
        let latest = conversations.max(by: { $0.updated < $1.updated }) ?? conversations[0]
        currentChatID = latest.id
        messages = latest.messages
    }

    private func syncCurrent() {
        guard let i = conversations.firstIndex(where: { $0.id == currentChatID }) else { return }
        let changed = conversations[i].messages.count != messages.count
            || conversations[i].messages.last?.text != messages.last?.text
        conversations[i].messages = messages
        if conversations[i].title == "Nouvelle discussion" {
            conversations[i].title = VM.makeTitle(messages)
        }
        if changed { conversations[i].updated = Date() }
    }

    func saveConversations() {
        syncCurrent()
        if let d = try? JSONEncoder().encode(conversations) {
            try? d.write(to: PalStore.conversationsURL, options: .atomic)
        }
    }

    private func saveChat() { saveConversations() }

    private func newChatModel() -> ModelEntry? {
        guard let id = prefs.newChatModelID else { return nil }
        return models.first { $0.id.uuidString == id }
    }

    /// Change le modèle courant sans le charger : il se chargera au prochain envoi.
    private func applyChatModel(_ id: UUID?) {
        guard !generating, !loading, let id, id != currentID,
              let entry = models.first(where: { $0.id == id }) else { return }
        if engine.loaded { unloadModel(reason: "Déchargé") }
        currentID = id
        UD.set(id.uuidString, forKey: "last")
        status = "\(entry.name) · se charge à l'envoi"
    }

    func newChat() {
        guard !generating, !loading else { return }
        speaker.stop()
        if !messages.isEmpty {
            saveConversations()
            var chat = Conversation()
            chat.modelID = newChatModel()?.id ?? currentID
            conversations.insert(chat, at: 0)
            currentChatID = chat.id
            messages = []
            saveConversations()
        }
        if let target = newChatModel() { applyChatModel(target.id) }
        engine.restore(system: effectiveSystemPrompt, history: [])
    }

    func openChat(_ id: UUID) {
        guard !generating, !loading, id != currentChatID,
              let target = conversations.first(where: { $0.id == id }) else { return }
        speaker.stop()
        saveConversations()
        currentChatID = id
        messages = target.messages
        applyChatModel(target.modelID)
        engine.restore(system: effectiveSystemPrompt, history: messages)
    }

    func deleteChat(_ id: UUID) {
        guard !generating, !loading else { return }
        conversations.removeAll { $0.id == id }
        if conversations.isEmpty { conversations = [Conversation()] }
        if id == currentChatID {
            let next = conversations.max(by: { $0.updated < $1.updated }) ?? conversations[0]
            currentChatID = next.id
            messages = next.messages
            applyChatModel(next.modelID)
            engine.restore(system: effectiveSystemPrompt, history: messages)
        }
        saveConversations()
    }

    func archiveCurrentChat() {
        setArchived(currentChatID, true)
    }

    func setArchived(_ id: UUID, _ archived: Bool) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].archived = archived
        conversations[i].updated = Date()
        saveConversations()
    }

    enum ConversationExport: Equatable { case txt, markdown }

    func exportFileURL(for id: UUID, format: ConversationExport) -> URL {
        let chat = conversations.first(where: { $0.id == id }) ?? Conversation(id: id, messages: messages)
        let ext = format == .markdown ? "md" : "txt"
        let safe = chat.title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).\(ext)")
        var body = format == .markdown ? "# \(chat.title)\n\n" : "\(chat.title)\n\n"
        if let model = models.first(where: { $0.id == chat.modelID }) { body += "Modèle : \(model.name)\n\n" }
        for message in chat.messages {
            let author = message.role == "user" ? "Vous" : "Pal"
            body += format == .markdown ? "## \(author)\n\n\(message.text)\n\n---\n\n" : "\(author) :\n\(message.text)\n\n"
        }
        do { try body.write(to: url, atomically: true, encoding: .utf8) }
        catch { status = "Export impossible : \(error.localizedDescription)" }
        return url
    }

    func renameChat(_ id: UUID, _ title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].title = String(clean.prefix(60))
        saveConversations()
    }

    // MARK: prompt système et compétences

    var effectiveSystemPrompt: String {
        let base = currentPersona?.prompt ?? cfg.system
        let enabled = skills.filter(\.enabled)
        guard !enabled.isEmpty else { return base }
        let skillText = enabled.map { skill in
            "SKILL: \(skill.name)\n\(skill.instructions)"
        }.joined(separator: "\n\n")
        // Limite la surcharge de contexte sur les appareils à mémoire réduite.
        let bounded = String(skillText.prefix(9000))
        return base + "\n\nCompétences activées (instructions de l'utilisateur) :\n" +
            bounded + "\n\nApplique ces compétences si elles sont pertinentes. Ne prétends pas avoir exécuté une action ou consulté une source si ce n'est pas le cas."
    }

    func setSkillEnabled(_ id: String, enabled: Bool) {
        guard let index = skills.firstIndex(where: { $0.id == id }) else { return }
        skills[index].enabled = enabled
        saveSkills()
    }

    func importSkill(_ url: URL) {
        let scopedAccess = url.startAccessingSecurityScopedResource()
        defer { if scopedAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count <= 64 * 1024,
              let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Skill invalide : fichier UTF-8 requis, 64 Ko maximum"
            return
        }
        let firstHeading = text.components(separatedBy: .newlines)
            .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("# ") })
        let name = firstHeading.map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            ?? url.deletingPathExtension().lastPathComponent
        let skill = PalSkill(
            id: UUID().uuidString,
            name: String(name.prefix(60)),
            description: "Compétence importée",
            instructions: String(text.prefix(12000)),
            enabled: true,
            isBuiltIn: false
        )
        skills.append(skill)
        saveSkills()
        status = "Compétence ajoutée : \(skill.name)"
    }

    func addSkill(name: String, description: String, instructions: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanInstructions.isEmpty,
              cleanInstructions.utf8.count <= 12_000 else {
            status = "Nom et instructions requis (12 Ko maximum)"
            return
        }
        skills.append(PalSkill(
            id: UUID().uuidString,
            name: String(cleanName.prefix(60)),
            description: String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180)),
            instructions: cleanInstructions,
            enabled: true,
            isBuiltIn: false
        ))
        saveSkills()
        status = "Compétence créée : " + cleanName
    }

    func deleteSkill(_ id: String) {
        skills.removeAll { $0.id == id && !$0.isBuiltIn }
        saveSkills()
    }

    func importDocument(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let ext = url.pathExtension.lowercased()
            var extracted = ""
            if ext == "pdf" {
                guard let pdf = PDFDocument(url: url) else { throw EngineError(msg: "PDF illisible") }
                extracted = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n\n")
            } else if ["txt", "md", "csv", "json", "html", "xml"].contains(ext) {
                extracted = try String(contentsOf: url, encoding: .utf8)
            } else if ["rtf", "doc", "docx"].contains(ext) {
                let attributed = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
                extracted = attributed.string
            } else {
                throw EngineError(msg: "Format non pris en charge")
            }
            let limit = max(4000, min(cfg.nCtx * 4, 60000))
            if extracted.count > limit { extracted = String(extracted.prefix(limit)) + "\n\n[Document tronqué pour respecter la limite de contexte.]" }
            guard !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw EngineError(msg: "Aucun texte extractible dans ce document") }
            input = "Lis et analyse ce document (\(url.lastPathComponent)) :\n\n\(extracted)"
            status = "Document importé : \(url.lastPathComponent)"
        } catch { status = "Import impossible : \(error.localizedDescription)" }
    }

    func insertResearchContext(_ context: String) {
        input = context
    }

    private func tap() { if cfg.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() } }

    // MARK: Hugging Face

    var hfToken: String { Keychain.get("hf-token") ?? "" }

    func setHFToken(_ token: String) {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if Keychain.set(clean, for: "hf-token") {
            status = clean.isEmpty ? "Jeton Hugging Face supprimé" : "Jeton Hugging Face enregistré dans le trousseau iOS"
        } else {
            status = "Échec de l'enregistrement sécurisé du jeton Hugging Face"
        }
        objectWillChange.send()
    }

    /// Branche le rappel de fin de téléchargement dès le lancement (sans activer la session réseau).
    private func bindDownloadCallback() {
        DownloadManager.shared.onFinished = { [weak self] url in
            Task { @MainActor in self?.downloadFinished(url) }
        }
    }

    func attachDownloads() {
        bindDownloadCallback()
        DownloadManager.shared.activate()
    }

    private func downloadFinished(_ url: URL) {
        scanLibrary()
        let name = url.deletingPathExtension().lastPathComponent
        let fileName = url.lastPathComponent
        // Un téléchargement terminé n'est pas un modèle installé : le moteur le vérifie d'abord.
        if let entry = models.first(where: { ($0.relPath ?? "").hasSuffix(fileName) }) {
            status = "Téléchargé : " + name + " · vérification…"
            verifyModel(entry)
        } else {
            status = "Téléchargé : " + name + " (absent de la liste : analyse le dossier Pal)"
        }
    }

    /// Demande au moteur si le GGUF du dossier Pal est reconnu (sans charger les poids).
    func verifyModel(_ entry: ModelEntry) {
        guard let rel = entry.relPath else { return }
        let path = PalFolders.url(forRelative: rel).path
        let id = entry.id, name = entry.name
        status = "Vérification de " + name + "…"
        Task.detached(priority: .utility) {
            let result = ModelValidator.check(path: path)
            await self.storeCheck(result, id: id, name: name)
        }
    }

    private func storeCheck(_ result: ModelCheck, id: UUID, name: String) {
        if let index = models.firstIndex(where: { $0.id == id }) {
            models[index].archInfo = result.ok ? result.desc : nil
            models[index].compatible = result.ok
            saveModels()
        }
        if result.ok {
            status = "Modèle reconnu : " + name + " · " + result.desc + " · contexte d'entraînement " + String(result.ctxTrain)
        } else {
            status = "⚠︎ " + name + " : non reconnu par le moteur (architecture ou format non pris en charge par cette version de Pal)"
        }
    }

    private func explainLoadFailure(_ result: ModelCheck) {
        guard !engine.loaded, !loading else { return }
        if result.ok {
            status = "Échec du chargement : le modèle est reconnu (" + result.desc + ") mais n'a pas pu être chargé. Mémoire insuffisante probable : essaie un contexte plus court ou le profil Éco."
        } else {
            status = "Échec du chargement : modèle non reconnu par le moteur (architecture ou format non pris en charge par cette version de Pal)."
        }
    }

    func useDownloaded(_ filename: String) {
        scanLibrary()
        if let entry = models.first(where: { $0.relPath == "Models/" + filename || $0.relPath == filename }) {
            select(entry)
        }
    }

    // MARK: modèles (dossier Pal, ou lus en place via signet)

    private func bookmark(_ url: URL) -> (Data, Int)? {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path + "/"
        let isAppOwned = url.standardizedFileURL.path.hasPrefix(home)
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }
        // Ne jamais mémoriser un chemin externe si iOS n'a pas accordé le scope.
        guard didStartAccess || isAppOwned else { return nil }
        guard let data = try? url.bookmarkData() else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return (data, size / 1_048_576)
    }

    @discardableResult
    func addModel(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "gguf" else {
            status = "Choisis un fichier .gguf (fichier reçu : \(url.lastPathComponent))"
            return false
        }
        guard let result = bookmark(url) else {
            status = "Impossible d'enregistrer l'accès au fichier"
            return false
        }
        let entry = ModelEntry(
            name: url.deletingPathExtension().lastPathComponent,
            bookmark: result.0,
            sizeMB: result.1
        )
        models.append(entry)
        saveModels()
        select(entry)
        return true
    }

    /// Plan B : copie le GGUF dans Documents/Models (dossier de Pal) puis le détecte.
    @discardableResult
    func importModelCopy(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "gguf" else {
            status = "Choisis un fichier .gguf (fichier reçu : \(url.lastPathComponent))"
            return false
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: PalFolders.models, withIntermediateDirectories: true)
            let dest = PalFolders.models.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: url, to: dest)
            scanLibrary()
            if let rel = PalFolders.relativePath(of: dest),
               let entry = models.first(where: { $0.relPath == rel }) {
                select(entry)
                return true
            }
            return false
        } catch {
            status = "Copie impossible : \(error.localizedDescription)"
            return false
        }
    }

    func addMMProj(_ url: URL, to id: UUID) {
        guard url.pathExtension.lowercased() == "gguf",
              let result = bookmark(url),
              let index = models.firstIndex(where: { $0.id == id }) else {
            status = "Fichier mmproj inaccessible ou invalide"
            return
        }
        models[index].mmproj = result.0
        models[index].mmprojName = url.lastPathComponent
        saveModels()
        status = "mmproj associé (analyse d'image à implémenter)"
    }

    /// Remplace le signet d'un modèle sans copier le fichier dans le conteneur Pal.
    func relinkModel(_ url: URL, id: UUID) {
        guard url.pathExtension.lowercased() == "gguf",
              let result = bookmark(url),
              let index = models.firstIndex(where: { $0.id == id }) else {
            status = "Impossible de relier ce fichier GGUF"
            return
        }
        let wasCurrent = currentID == id
        models[index].bookmark = result.0
        models[index].sizeMB = result.1
        models[index].name = url.deletingPathExtension().lastPathComponent
        saveModels()
        status = "Fichier relié sans copie"
        if wasCurrent { select(models[index]) }
    }

    /// Texte Markdown exportable depuis la feuille de partage iOS.
    var exportedMarkdown: String {
        var output = "# Conversation avec Pal\n\n"
        if let entry = models.first(where: { $0.id == currentID }) {
            output += "_Modèle : \(entry.name)_\n\n"
        }
        for message in messages {
            output += "## \(message.role == "user" ? "Vous" : "Pal")\n\n\(message.text)\n\n---\n\n"
        }
        return output
    }

    // MARK: performance

    private func signature() -> String {
        "\(cfg.nCtx)/\(cfg.nBatch)/\(cfg.nUBatch)/\(cfg.gpuLayers)/\(cfg.flashAttn)/\(cfg.kvQuant)/\(prefs.mmap)"
    }

    var needsReload: Bool {
        engine.loaded && !loadedSignature.isEmpty && loadedSignature != signature()
    }

    func applyProfile(_ profile: PerfProfile) {
        guard !loading, !generating else { return }
        if profile == .custom {
            if let data = UD.data(forKey: "pal.customProfile"), let saved = try? JSONDecoder().decode(Cfg.self, from: data) { cfg = saved }
            return
        }
        if PerfProfile.detect(cfg) == .custom, let data = try? JSONEncoder().encode(cfg) {
            UD.set(data, forKey: "pal.customProfile")
        }
        var updated = cfg
        profile.apply(&updated)
        cfg = updated
    }

    func resetPerformance() {
        let defaults = Cfg()
        cfg.nCtx = defaults.nCtx; cfg.nBatch = defaults.nBatch; cfg.threads = defaults.threads
        cfg.gpuLayers = defaults.gpuLayers; cfg.maxTokens = defaults.maxTokens
        cfg.nUBatch = defaults.nUBatch; cfg.flashAttn = defaults.flashAttn; cfg.kvQuant = defaults.kvQuant
        UD.removeObject(forKey: "pal.customProfile")
    }

    private func effectiveThreads() -> Int {
        var n = max(1, min(cfg.threads, ProcessInfo.processInfo.activeProcessorCount))
        guard prefs.thermalGuard else { return n }
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: n = max(1, n / 2)
        default: break   // « tiède » (.fair) est normal sous charge : on ne bride plus
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { n = max(1, n - 1) }
        return n
    }

    // MARK: modèle par défaut, déchargement automatique

    func setLaunchModel(_ entry: ModelEntry) {
        prefs.launchMode = 2
        prefs.launchModelID = entry.id.uuidString
    }

    func setNewChatModel(_ entry: ModelEntry?) {
        prefs.newChatModelID = entry?.id.uuidString
    }

    private func chooseLaunchModel() {
        var candidate: ModelEntry?
        if prefs.launchMode == 2 {
            candidate = models.first { $0.id.uuidString == prefs.launchModelID }
        }
        if candidate == nil, let chatModel = conversations.first(where: { $0.id == currentChatID })?.modelID {
            candidate = models.first { $0.id == chatModel }
        }
        if candidate == nil, let saved = UD.string(forKey: "last") {
            candidate = models.first { $0.id.uuidString == saved }
        }
        guard let chosen = candidate else { return }
        if prefs.launchMode == 0 {
            currentID = chosen.id
            status = "\(chosen.name) · se charge à l'envoi"
        } else {
            select(chosen, assign: false)
        }
    }

    func unloadModel(reason: String = "Déchargé") {
        guard !generating, !loading else { return }
        idleTask?.cancel()
        engine.unload()
        scoped?.stopAccessingSecurityScopedResource()
        scoped = nil
        loadedSignature = ""
        status = "\(reason) · se recharge à l'envoi"
        objectWillChange.send()
    }

    private func scheduleIdleUnload() {
        idleTask?.cancel()
        let minutes = prefs.autoUnloadMinutes
        guard minutes > 0, engine.loaded else { return }
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.unloadModel(reason: "Déchargé (inactif)")
        }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            scanLibrary()
        case .background:
            if prefs.unloadInBackground && !generating && !loading && engine.loaded {
                unloadModel(reason: "Déchargé (arrière-plan)")
            }
        default:
            break
        }
    }

    func remove(_ entry: ModelEntry) {
        guard !generating, !loading else {
            status = "Arrête la génération avant de supprimer le modèle"
            return
        }
        if entry.id == currentID {
            guard engine.unload() else {
                status = "Impossible de décharger le modèle pour le moment"
                return
            }
            scoped?.stopAccessingSecurityScopedResource()
            scoped = nil
            currentID = nil
            status = "Aucun modèle"
        }
        models.removeAll { $0.id == entry.id }
        saveModels()
    }

    /// Supprime le fichier d'un modèle du dossier Pal (libère l'espace).
    func deleteModelFile(_ entry: ModelEntry) {
        if entry.id == currentID {
            unloadModel(reason: "Déchargé")
            currentID = nil
            status = "Aucun modèle"
        }
        if let rel = entry.relPath {
            try? FileManager.default.removeItem(at: PalFolders.url(forRelative: rel))
        }
        models.removeAll { $0.id == entry.id }
        saveModels()
    }

    func select(_ entry: ModelEntry, assign: Bool = true) {
        guard !generating, !loading else { return }
        idleTask?.cancel()
        let url: URL
        var didStartAccess = false
        var stale = false

        if let rel = entry.relPath {
            url = PalFolders.url(forRelative: rel)
        } else {
            guard let resolved = try? URL(
                resolvingBookmarkData: entry.bookmark,
                bookmarkDataIsStale: &stale
            ) else {
                status = "Signet invalide : réimporte le fichier GGUF"
                pendingSend = false
                return
            }
            url = resolved
            didStartAccess = resolved.startAccessingSecurityScopedResource()
            let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path + "/"
            let isAppOwned = resolved.standardizedFileURL.path.hasPrefix(home)
            guard didStartAccess || isAppOwned else {
                status = "iOS n'a pas accordé l'accès au fichier : réimporte-le depuis Fichiers"
                pendingSend = false
                return
            }
        }

        // iCloud Drive : un fichier non téléchargé est demandé au système au lieu d'échouer sans explication.
        if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
           values.isUbiquitousItem == true,
           let state = values.ubiquitousItemDownloadingStatus, state != .current {
            _ = try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
            status = "Fichier iCloud pas encore téléchargé : téléchargement demandé, réessaie dans un instant"
            pendingSend = false
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            let requested = (try? FileManager.default.startDownloadingUbiquitousItem(at: url)) != nil
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
            status = requested
                ? "Fichier absent ou iCloud pas encore téléchargé : téléchargement demandé, réessaie dans un instant"
                : "Fichier introuvable ou non téléchargé dans Fichiers"
            pendingSend = false
            return
        }

        scoped?.stopAccessingSecurityScopedResource()
        scoped = didStartAccess ? url : nil

        if stale, let refreshed = try? url.bookmarkData() {
            if let index = models.firstIndex(where: { $0.id == entry.id }) {
                models[index].bookmark = refreshed
                saveModels()
            }
        }

        currentID = entry.id
        if assign, let i = conversations.firstIndex(where: { $0.id == currentChatID }) {
            conversations[i].modelID = entry.id
            saveConversations()
        }
        UD.set(entry.id.uuidString, forKey: "last")
        status = "Chargement…"
        loading = true
        pendingSignature = signature()

        memWarn = !engine.loaded && Double(entry.sizeMB) * 1.1 > Sys.availMB()
        let config = cfg
        let useMmap = prefs.mmap
        let modelEngine = engine
        let modelPath = url.path
        lastLoadPath = modelPath
        Task.detached(priority: .userInitiated) {
            let success = modelEngine.load(path: modelPath, cfg: config, mmap: useMmap)
            await self.loaded(success)
        }
    }

    func reload() {
        if let entry = models.first(where: { $0.id == currentID }) {
            select(entry, assign: false)
        }
    }

    private func loaded(_ success: Bool) {
        loading = false
        if success {
            loadedSignature = pendingSignature
            engine.restore(system: effectiveSystemPrompt, history: messages)
            status = "\(engine.info) · prêt" + (memWarn ? " · ⚠︎ RAM juste" : "")
                + (engine.notice.isEmpty ? "" : " · \(engine.notice)")
            scheduleIdleUnload()
            if pendingSend {
                pendingSend = false
                send()
            }
        } else {
            pendingSend = false
            status = "Échec du chargement : analyse du fichier en cours…"
            let path = lastLoadPath
            if path.isEmpty {
                status = "Échec du chargement : fichier inaccessible"
            } else {
                Task.detached(priority: .utility) {
                    let result = ModelValidator.check(path: path)
                    await self.explainLoadFailure(result)
                }
            }
        }
    }

    // MARK: chat

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !generating, !loading else { return }

        // Modèle déchargé : on le recharge automatiquement puis on envoie.
        if !engine.loaded {
            guard let entry = models.first(where: { $0.id == currentID }) ?? models.first else {
                status = "Ajoute d'abord un modèle"
                requestModelPicker = true
                return
            }
            pendingSend = true
            select(entry, assign: currentID == nil)
            if !loading { pendingSend = false }
            return
        }

        idleTask?.cancel()
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        input = ""; engine.restore(system: effectiveSystemPrompt, history: messages); messages.append(Msg(role: "user", text: text)); streaming = ""; tap()
        speaker.stop()
        genStart = Date()
        thinkEnd = nil
        UIApplication.shared.isIdleTimerDisabled = cfg.keepAwake
        let c = cfg, e = engine, threadCount = effectiveThreads()
        // Réflexion désactivée : bloc <think> vide pré-rempli par le moteur (le texte de l'utilisateur n'est jamais modifié).
        let noThink = !prefs.reasoningEnabled
        // Mode Éco : priorité de tâche basse et rafraîchissement moins fréquent.
        let eco = PerfProfile.detect(cfg) == .eco
        let priority: TaskPriority = eco ? .utility : .medium
        let uiInterval: Double = eco ? 0.15 : 0.08
        e.prepareGeneration()
        Task.detached(priority: priority) {
            e.setThreads(threadCount)
            var acc = "", last = Date()
            do {
                let st = try e.generate(user: text, cfg: c, noThink: noThink) { p in
                    acc += p
                    if Date().timeIntervalSince(last) > uiInterval {
                        last = Date(); let snap = acc
                        Task { @MainActor in
                            if self.streaming != nil {
                                self.streaming = snap
                                if self.thinkEnd == nil && snap.contains("</think>") { self.thinkEnd = Date() }
                            }
                        }
                    }
                }
                await self.finish(acc, st, nil)
            } catch { await self.finish(acc, nil, (error as? EngineError)?.msg ?? "Erreur") }
        }
    }

    private func finish(_ text: String, _ st: GenStats?, _ err: String?) {
        if let st {
            stats = st
            if thinkEnd == nil && text.contains("</think>") { thinkEnd = Date() }
            let seconds = thinkEnd.map { $0.timeIntervalSince(genStart) }
            let perToken = st.genTps > 0 ? 1000 / st.genTps : 0
            var line = String(format: "%.0f ms/token · %.1f tokens/s · 1er token %.2f s (post-prefill %.2f s)", perToken, st.genTps, st.ttft, st.firstTokenAfterPrefill)
            line += String(format: " · format %.0f ms · tokenize %.0f ms · prefill %.2f s · decode %.2f s", st.formatSeconds * 1000, st.tokenizeSeconds * 1000, st.prefillSeconds, st.decodeSeconds)
            if st.reused > 0 { line += " · cache \(st.reused)/\(st.promptN) tok" }
            if engine.trimmed > 0 { line += " · \(engine.trimmed) ancien(s) message(s) retiré(s)" }
            if !(st.cancelled && text.isEmpty) {
                messages.append(Msg(role: "assistant", text: text, thinkSeconds: seconds, stat: line, needsContinuation: st.reachedTokenLimit))
            } else {
                engine.restore(system: effectiveSystemPrompt, history: messages)
            }
        }
        if let err {
            status = err
            engine.restore(system: effectiveSystemPrompt, history: messages)
        } else if st != nil {
            status = "\(engine.info) · prêt"
            if st?.cancelled == true { status += " · arrêt demandé" }
            else if st?.interrupted == true { status += " · ⚠︎ génération interrompue (mémoire ou contexte)" }
            else if engine.trimmed > 0 { status += " · contexte plein : anciens messages retirés du prompt" }
        }
        streaming = nil; saveChat(); tap()
        UIApplication.shared.isIdleTimerDisabled = false
        scheduleIdleUnload()
        if st != nil, err == nil, prefs.ttsAuto, !text.isEmpty {
            speaker.speak(text, voiceID: prefs.ttsVoice, rate: prefs.ttsRate)
        }
    }

    func stop() { engine.cancel = true }

    func continueGeneration() {
        guard !generating, !loading, messages.last?.role == "assistant" else { return }
        input = "Continue exactement à partir du dernier mot, sans répéter le texte déjà produit."
        send()
    }

    func regenerate() {
        guard !generating, messages.count >= 2, messages.last?.role == "assistant" else { return }
        messages.removeLast()
        input = messages.removeLast().text
        engine.restore(system: effectiveSystemPrompt, history: messages)
        send()
    }

    /// Modifier le dernier message utilisateur : il revient dans le champ de saisie.
    func editLast() {
        guard !generating, !loading, let i = messages.lastIndex(where: { $0.role == "user" }) else { return }
        input = messages[i].text
        messages.removeSubrange(i...)
        saveChat()
        engine.restore(system: effectiveSystemPrompt, history: messages)
    }

    /// Benchmark contrôlé : 1 échauffement ignoré, puis 3 mesures à cache KV froid.
    /// La médiane réduit l'influence d'une variation ponctuelle du planificateur iOS.
    func runBenchmark() {
        guard !generating, !loading, engine.loaded else { return }
        loading = true
        benchmark = "Benchmark en cours… (1 échauffement + 3 mesures)"
        var c = cfg; c.temp = 0; c.maxTokens = 64
        // Nombre de threads réellement appliqué = celui affiché dans le résultat (reproductible, sans bridage thermique).
        c.threads = max(1, min(c.threads, ProcessInfo.processInfo.activeProcessorCount))
        let e = engine, saved = messages, sys = effectiveSystemPrompt
        Task.detached(priority: .userInitiated) {
            e.setThreads(c.threads)
            let prompt = "Explique en quelques phrases comment fonctionne un moteur à explosion."
            var measured: [GenStats] = []
            do {
                // Échauffement : charge les chemins de code, mais ne compte pas.
                e.resetCache()
                e.restore(system: "", history: [])
                e.prepareGeneration()
                _ = try e.generate(user: prompt, cfg: c) { _ in }

                // Chaque échantillon repart d'un cache KV vide et d'un historique vide.
                for _ in 0..<3 {
                    e.resetCache()
                    e.restore(system: "", history: [])
                    e.prepareGeneration()
                    measured.append(try e.generate(user: prompt, cfg: c) { _ in })
                }
            } catch {
                measured.removeAll()
            }
            await self.finishBenchmark(measured.isEmpty ? nil : measured, saved, sys, c)
        }
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func finishBenchmark(_ samples: [GenStats]?, _ saved: [Msg], _ sys: String, _ c: Cfg) {
        engine.resetCache()
        engine.restore(system: sys, history: saved)
        loading = false
        guard let samples, !samples.isEmpty else {
            benchmark = "Benchmark échoué"
            return
        }
        var r = samples[0]
        r.ttft = median(samples.map(\.ttft))
        r.firstTokenAfterPrefill = median(samples.map(\.firstTokenAfterPrefill))
        r.formatSeconds = median(samples.map(\.formatSeconds))
        r.tokenizeSeconds = median(samples.map(\.tokenizeSeconds))
        r.prefillSeconds = median(samples.map(\.prefillSeconds))
        r.decodeSeconds = median(samples.map(\.decodeSeconds))
        r.promptTps = median(samples.map(\.promptTps))
        r.genTps = median(samples.map(\.genTps))

        let cache = c.kvQuant == 1 ? "Q8" : "F16"
        let backend = engine.gpuActive ? "Metal" : "CPU"
        benchmark = String(format: "Médiane 3 runs · pp %.1f t/s · tg %.1f t/s · TTFT %.2f s (post %.2f s) · format %.0f ms · tokenize %.0f ms · prefill %.2f s · decode %.2f s · %@ %dT · batch %d/%d · ctx %d · K/V %@ · RAM %.0f Mo", r.promptTps, r.genTps, r.ttft, r.firstTokenAfterPrefill, r.formatSeconds * 1000, r.tokenizeSeconds * 1000, r.prefillSeconds, r.decodeSeconds, backend, c.threads, c.nBatch, c.nUBatch, c.nCtx, cache, Sys.footprintMB())
        Advisor.recordBenchmark(model: currentName, gpu: engine.gpuActive, cfg: c, tg: r.genTps, pp: r.promptTps)
    }
}
