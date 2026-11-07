import Foundation
import llama

struct GenStats {
    var promptN = 0          // tokens du prompt complet
    var reused = 0           // tokens déjà présents dans le cache KV (non retraités)
    var genN = 0
    var ttft = 0.0
    var genTps = 0.0
    var promptTps = 0.0      // vitesse sur les tokens réellement traités
    var reachedTokenLimit = false
    var interrupted = false  // erreur de décodage en cours de génération
}

struct EngineError: LocalizedError {
    let msg: String
    var errorDescription: String? { msg }
}

/// Moteur llama.cpp. Toutes les opérations de modèle/génération doivent être
/// séquentielles : VM empêche le changement de modèle pendant une génération.
final class Engine: @unchecked Sendable {
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var vocab: OpaquePointer?
    private var messages: [(String, String)] = []
    private var nBatch = 256
    /// Tokens actuellement présents dans le cache KV (séquence 0), dans l'ordre.
    private var cached: [llama_token] = []
    private var pieceBuffer = [CChar](repeating: 0, count: 128)

    private let cancelLock = NSLock()
    private var cancelRequested = false

    private(set) var nPast = 0
    private(set) var nCtx = 0
    private(set) var info = "—"
    /// Vrai si des couches ont été confiées au GPU Metal.
    private(set) var gpuActive = false
    /// Message d'information du dernier chargement (ex. repli sur CPU).
    private(set) var notice = ""
    /// Nombre de messages anciens retirés du prompt au dernier tour (contexte plein).
    private(set) var trimmed = 0
    /// Vrai si le modèle de chat contient des balises <think> (modèles à réflexion).
    private(set) var thinkTemplate = false
    var loaded: Bool { ctx != nil && model != nil && vocab != nil }

    var cancel: Bool {
        get {
            cancelLock.lock()
            defer { cancelLock.unlock() }
            return cancelRequested
        }
        set {
            cancelLock.lock()
            cancelRequested = newValue
            cancelLock.unlock()
        }
    }

    init() {
        llama_backend_init()
    }

    // MARK: - Chargement

    @discardableResult
    func load(path: String, cfg: Cfg, mmap: Bool = true) -> Bool {
        unload()
        // Cette version du XCFramework n'expose pas use_mmap dans
        // llama_model_params ; l'argument est conservé pour l'interface VM.
        _ = mmap
        notice = ""

        var layers = max(0, cfg.gpuLayers)
        if layers > 0 && !llama_supports_gpu_offload() {
            layers = 0
            notice = "Metal indisponible : CPU utilisé"
        }
        if tryLoad(path: path, cfg: cfg, layers: layers) {
            gpuActive = layers > 0
            return true
        }
        // Repli automatique : si le GPU fait échouer le chargement, on retente sur CPU.
        if layers > 0 {
            notice = "GPU refusé : rechargé sur CPU"
            if tryLoad(path: path, cfg: cfg, layers: 0) {
                gpuActive = false
                return true
            }
        }
        return false
    }

    private func tryLoad(path: String, cfg: Cfg, layers: Int) -> Bool {
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = Int32(layers)

        let loadedModel: OpaquePointer? = path.withCString { cPath in
            llama_model_load_from_file(cPath, modelParams)
        }
        guard let loadedModel else { return false }

        guard let loadedVocab = llama_model_get_vocab(loadedModel) else {
            llama_model_free(loadedModel)
            return false
        }

        var contextParams = llama_context_default_params()
        let contextSize = max(512, cfg.nCtx)
        let batchSize = max(32, min(cfg.nBatch, contextSize))
        contextParams.n_ctx = UInt32(contextSize)
        contextParams.n_batch = UInt32(batchSize)
        contextParams.n_ubatch = UInt32(max(32, min(cfg.nUBatch, batchSize)))
        let threadCount = max(1, min(cfg.threads, ProcessInfo.processInfo.activeProcessorCount))
        contextParams.n_threads = Int32(threadCount)
        contextParams.n_threads_batch = Int32(threadCount)
        applyAdvanced(&contextParams, cfg: cfg)

        guard let loadedContext = llama_init_from_model(loadedModel, contextParams) else {
            llama_model_free(loadedModel)
            return false
        }

        model = loadedModel
        vocab = loadedVocab
        ctx = loadedContext
        nBatch = batchSize
        nCtx = Int(llama_n_ctx(loadedContext))
        nPast = 0
        cached = []
        let templateText = llama_model_chat_template(loadedModel, nil).map { String(cString: $0) } ?? ""
        thinkTemplate = templateText.contains("<think>")
        info = String(
            format: "%.1fB · %.2f Go · %@",
            Double(llama_model_n_params(loadedModel)) / 1_000_000_000,
            Double(llama_model_size(loadedModel)) / 1_000_000_000,
            layers > 0 ? "Metal" : "CPU"
        )
        return true
    }

    /// Réglages avancés du contexte. Isolés ici : si une version du XCFramework
    /// renomme un champ (flash_attn_type, type_k, type_v), c'est le seul endroit à corriger.
    private func applyAdvanced(_ params: inout llama_context_params, cfg: Cfg) {
        switch cfg.flashAttn {
        case 1: params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED
        case 2: params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED
        default: params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO
        }
        if cfg.kvQuant == 1 {
            // Cache K/V en q8_0 : ~2x moins de RAM. Le cache V quantifié exige Flash Attention.
            params.type_k = GGML_TYPE_Q8_0
            params.type_v = GGML_TYPE_Q8_0
            params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED
        }
    }

    /// Ajuste le nombre de threads à chaud (protection thermique / économie d'énergie).
    func setThreads(_ count: Int) {
        guard let context = ctx else { return }
        let n = Int32(max(1, count))
        llama_set_n_threads(context, n, n)
    }

    func unload() {
        if let context = ctx { llama_free(context) }
        if let loadedModel = model { llama_model_free(loadedModel) }
        ctx = nil
        model = nil
        vocab = nil
        messages.removeAll(keepingCapacity: false)
        cached = []
        nPast = 0
        nCtx = 0
        gpuActive = false
        thinkTemplate = false
        info = "—"
    }

    /// Recharge l'historique visible dans l'application. Le cache KV est CONSERVÉ :
    /// au prochain tour, seul le préfixe identique est réutilisé, le reste est retraité.
    func restore(system: String, history: [Msg]) {
        messages = (system.isEmpty ? [] : [("system", system)])
            + history.map { ($0.role, $0.text) }
    }

    /// Vide le cache KV (benchmark, état incertain après une erreur).
    func resetCache() {
        if let context = ctx {
            llama_memory_clear(llama_get_memory(context), true)
        }
        cached = []
        nPast = 0
    }

    // MARK: - Génération

    /// Désactive la réflexion en pré-remplissant un bloc <think> vide
    /// (format attendu par Qwen 3 / 3.5, DeepSeek R1 et modèles similaires).
    static func closeThinking(_ prompt: String) -> String {
        if prompt.hasSuffix("</think>\n\n") { return prompt }
        if prompt.hasSuffix("<think>\n") { return prompt + "\n</think>\n\n" }
        if prompt.hasSuffix("<think>") { return prompt + "\n\n</think>\n\n" }
        return prompt + "<think>\n\n</think>\n\n"
    }

    func generate(user: String, cfg: Cfg, noThink: Bool = false, onToken: (String) -> Void) throws -> GenStats {
        guard let context = ctx, let vocabulary = vocab, model != nil else {
            throw EngineError(msg: "Aucun modèle chargé")
        }

        cancel = false
        messages.append(("user", user))
        trimmed = 0

        // Place réservée à la réponse : si le prompt est trop long, on retire les
        // plus anciens tours (le prompt système et le dernier message restent).
        let reserve = min(max(64, cfg.maxTokens), max(64, nCtx / 2))
        var tokens: [llama_token] = []
        while true {
            var prompt = format(messages, addAssistantPrefix: true)
            guard !prompt.isEmpty else {
                messages.removeLast()
                throw EngineError(msg: "Impossible de formater le prompt du modèle")
            }
            if noThink && thinkTemplate { prompt = Engine.closeThinking(prompt) }
            tokens = tokenize(prompt, addSpecial: true)
            guard !tokens.isEmpty else {
                messages.removeLast()
                throw EngineError(msg: "Échec de la tokenisation du prompt")
            }
            if tokens.count + reserve < nCtx { break }

            let first = messages.first?.0 == "system" ? 1 : 0
            let removable = messages.count - first - 1   // tout sauf le dernier message
            if removable >= 1 {
                let n = min(2, removable)
                messages.removeSubrange(first..<(first + n))
                trimmed += n
            } else {
                messages.removeLast()
                throw EngineError(msg: "Message trop long pour le contexte (\(nCtx) tokens) : augmente le contexte ou raccourcis le message")
            }
        }

        // Réutilisation du cache KV : on ne retraite que ce qui change.
        let memory = llama_get_memory(context)
        var common = 0
        let limit = min(cached.count, tokens.count - 1)   // au moins 1 token à décoder
        while common < limit && cached[common] == tokens[common] { common += 1 }
        if common < cached.count {
            if common == 0 || !llama_memory_seq_rm(memory, 0, Int32(common), -1) {
                // Retrait partiel impossible (ex. modèles à état récurrent) : on repart de zéro.
                llama_memory_clear(memory, true)
                common = 0
                cached = []
            } else {
                cached.removeSubrange(common...)
            }
        }
        nPast = cached.count

        var samplerParams = llama_sampler_chain_default_params()
        samplerParams.no_perf = true
        guard let sampler = llama_sampler_chain_init(samplerParams) else {
            messages.removeLast()
            throw EngineError(msg: "Impossible d'initialiser l'échantillonneur")
        }
        defer { llama_sampler_free(sampler) }

        if cfg.temp <= 0 {
            guard let greedy = llama_sampler_init_greedy() else {
                messages.removeLast()
                throw EngineError(msg: "Échantillonneur greedy indisponible")
            }
            llama_sampler_chain_add(sampler, greedy)
        } else {
            let topK = llama_sampler_init_top_k(Int32(max(1, cfg.topK)))
            let topP = llama_sampler_init_top_p(Float(cfg.topP), 1)
            let minP = llama_sampler_init_min_p(Float(cfg.minP), 1)
            let temperature = llama_sampler_init_temp(Float(cfg.temp))
            let distribution = llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max))

            guard let topK, let topP, let minP, let temperature, let distribution else {
                messages.removeLast()
                throw EngineError(msg: "Impossible de configurer l'échantillonnage")
            }
            // Pénalité de répétition : ignorée à 1.0 (neutre) pour économiser du calcul.
            if cfg.repeatPen != 1.0 {
                guard let penalty = llama_sampler_init_penalties(
                    llama_vocab_n_tokens(vocabulary), 64, Float(cfg.repeatPen), 0, 0
                ) else {
                    messages.removeLast()
                    throw EngineError(msg: "Impossible de configurer la pénalité de répétition")
                }
                llama_sampler_chain_add(sampler, penalty)
            }
            llama_sampler_chain_add(sampler, topK)
            llama_sampler_chain_add(sampler, topP)
            llama_sampler_chain_add(sampler, minP)
            llama_sampler_chain_add(sampler, temperature)
            llama_sampler_chain_add(sampler, distribution)
        }

        var stats = GenStats()
        stats.promptN = tokens.count
        stats.reused = common
        let newTokens = Array(tokens[common...])
        let promptStart = Date()
        guard decode(newTokens) else {
            // État du cache incertain : on le vide pour repartir proprement.
            resetCache()
            messages.removeLast()
            throw EngineError(msg: "Échec du décodage du prompt (mémoire ou contexte insuffisant)")
        }
        let generationStart = Date()
        stats.promptTps = Double(newTokens.count) / max(generationStart.timeIntervalSince(promptStart), 0.001)

        var output = ""
        var pendingBytes: [UInt8] = []
        let tokenLimit = max(1, cfg.maxTokens)
        var endedByEOG = false

        while stats.genN < tokenLimit && nPast < nCtx && !cancel {
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocabulary, token) {
                endedByEOG = true
                // On inscrit le jeton de fin dans le cache : il correspond à celui que le
                // template ajoutera à l'historique, ce qui permet de réutiliser tout le cache.
                if nPast < nCtx { _ = decode([token]) }
                break
            }

            pendingBytes.append(contentsOf: piece(token, vocabulary: vocabulary))
            if let text = String(bytes: pendingBytes, encoding: .utf8) {
                output += text
                onToken(text)
                pendingBytes.removeAll(keepingCapacity: true)
            }

            guard decode([token]) else {
                stats.interrupted = true
                resetCache()
                break
            }
            stats.genN += 1
            if stats.genN == 1 {
                stats.ttft = Date().timeIntervalSince(promptStart)
            }
        }
        _ = endedByEOG

        if !pendingBytes.isEmpty {
            let tail = String(decoding: pendingBytes, as: UTF8.self)
            output += tail
            onToken(tail)
        }

        stats.reachedTokenLimit = stats.genN >= tokenLimit && !cancel
        stats.genTps = Double(stats.genN) / max(Date().timeIntervalSince(generationStart), 0.001)
        messages.append(("assistant", output))
        return stats
    }

    // MARK: - llama.cpp helpers

    /// Décode des tokens par paquets et tient à jour la liste des tokens en cache.
    private func decode(_ tokens: [llama_token]) -> Bool {
        guard let context = ctx, !tokens.isEmpty else { return false }
        var offset = 0

        while offset < tokens.count {
            let count = min(nBatch, tokens.count - offset)
            var chunk = Array(tokens[offset..<(offset + count)])
            let result = chunk.withUnsafeMutableBufferPointer { buffer -> Int32 in
                guard let base = buffer.baseAddress else { return -1 }
                return llama_decode(context, llama_batch_get_one(base, Int32(count)))
            }
            guard result == 0 else { return false }
            cached.append(contentsOf: chunk)
            nPast = cached.count
            offset += count
        }
        return true
    }

    private func tokenize(_ text: String, addSpecial: Bool) -> [llama_token] {
        guard let vocabulary = vocab else { return [] }
        let byteCount = text.utf8.count
        guard byteCount <= Int(Int32.max) - 16 else { return [] }

        var capacity = max(32, byteCount + 16)
        for _ in 0..<3 {
            var tokens = [llama_token](repeating: 0, count: capacity)
            let count = text.withCString { cText in
                tokens.withUnsafeMutableBufferPointer { buffer in
                    guard let base = buffer.baseAddress else { return Int32(-1) }
                    return llama_tokenize(
                        vocabulary, cText, Int32(byteCount), base,
                        Int32(capacity), addSpecial, true
                    )
                }
            }
            if count >= 0 { return Array(tokens.prefix(Int(count))) }
            if count == Int32.min { return [] }
            capacity = Int(-count) + 8
        }
        return []
    }

    private func piece(_ token: llama_token, vocabulary: OpaquePointer) -> [UInt8] {
        var count = pieceBuffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
            guard let base = pointer.baseAddress else { return 0 }
            return llama_token_to_piece(vocabulary, token, base, Int32(pointer.count), 0, false)
        }
        if count < 0 {
            pieceBuffer = [CChar](repeating: 0, count: Int(-count) + 8)
            count = pieceBuffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
                guard let base = pointer.baseAddress else { return 0 }
                return llama_token_to_piece(vocabulary, token, base, Int32(pointer.count), 0, false)
            }
        }
        guard count > 0 else { return [] }
        return pieceBuffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }
    }

    private func format(_ sourceMessages: [(String, String)], addAssistantPrefix: Bool) -> String {
        guard let loadedModel = model else { return "" }

        let allocated = sourceMessages.map { role, content in
            let rolePointer = role.withCString { strdup($0)! }
            let contentPointer = content.withCString { strdup($0)! }
            return (rolePointer, contentPointer)
        }
        defer {
            allocated.forEach { role, content in
                free(role)
                free(content)
            }
        }

        let chat = allocated.map { role, content in
            llama_chat_message(role: UnsafePointer(role), content: UnsafePointer(content))
        }

        let template = llama_model_chat_template(loadedModel, nil)
            .map { String(cString: $0) } ?? "chatml"

        func apply(_ templateName: String) -> String? {
            let messageBytes = sourceMessages.reduce(0) { $0 + $1.1.utf8.count }
            var capacity = max(4096, messageBytes * 2 + 512)

            for _ in 0..<3 {
                var output = [CChar](repeating: 0, count: capacity)
                let written = templateName.withCString { cTemplate in
                    chat.withUnsafeBufferPointer { chatBuffer in
                        output.withUnsafeMutableBufferPointer { outputBuffer in
                            llama_chat_apply_template(
                                cTemplate,
                                chatBuffer.baseAddress,
                                chatBuffer.count,
                                addAssistantPrefix,
                                outputBuffer.baseAddress,
                                Int32(capacity)
                            )
                        }
                    }
                }

                if written >= 0 && Int(written) < capacity {
                    return String(decoding: output.prefix(Int(written)).map {
                        UInt8(bitPattern: $0)
                    }, as: UTF8.self)
                }
                if written > 0 {
                    capacity = Int(written) + 1
                } else {
                    return nil
                }
            }
            return nil
        }

        if let formatted = apply(template) { return formatted }
        if template != "chatml", let formatted = apply("chatml") { return formatted }

        // Dernier recours pour les modèles sans template reconnu.
        var fallback = ""
        for (role, content) in sourceMessages {
            fallback += "### \(role.uppercased())\n\(content)\n\n"
        }
        if addAssistantPrefix { fallback += "### ASSISTANT\n" }
        return fallback
    }
}
