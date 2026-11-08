import Foundation
import UIKit
import llama

/// Résultat de la vérification d'un fichier GGUF par le moteur (vocabulaire et métadonnées seulement).
struct ModelCheck {
    var ok: Bool
    var desc: String      // ex. « llama 1B Q4_K - Medium »
    var ctxTrain: Int
}

/// Demande au moteur lui-même si un GGUF est reconnu, sans charger les poids.
enum ModelValidator {
    static func check(path: String) -> ModelCheck {
        var params = llama_model_default_params()
        params.vocab_only = true
        params.n_gpu_layers = 0
        let loaded: OpaquePointer? = path.withCString { cPath in
            llama_model_load_from_file(cPath, params)
        }
        guard let model = loaded else {
            return ModelCheck(ok: false, desc: "", ctxTrain: 0)
        }
        defer { llama_model_free(model) }
        var buffer = [CChar](repeating: 0, count: 256)
        _ = buffer.withUnsafeMutableBufferPointer { pointer in
            llama_model_desc(model, pointer.baseAddress, pointer.count)
        }
        let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return ModelCheck(
            ok: true,
            desc: String(decoding: bytes, as: UTF8.self),
            ctxTrain: Int(llama_model_n_ctx_train(model))
        )
    }
}

struct Advice: Identifiable {
    let id: String
    let level: Int        // 0 information, 1 avertissement
    let text: String

    init(level: Int, text: String) {
        self.id = text
        self.level = level
        self.text = text
    }
}

/// Lit l'état réel de l'appareil et des mesures passées pour produire des recommandations neutres.
enum Advisor {
    static var totalRAMMB: Double { Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576 }

    /// Lit une capacité du processeur (nil si le système ne la déclare pas).
    static func cpuFeature(_ name: String) -> Bool? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value != 0
    }

    static var cpuSummary: String {
        func mark(_ value: Bool?) -> String {
            guard let value else { return "?" }
            return value ? "oui" : "non"
        }
        let dot = mark(cpuFeature("hw.optional.arm.FEAT_DotProd"))
        let i8 = mark(cpuFeature("hw.optional.arm.FEAT_I8MM"))
        return "dotprod \(dot) · i8mm \(i8)"
    }

    // MARK: mesures conservées

    private static let benchKey = "palBenchmarks"

    private static func benchName(_ model: String, _ gpu: Bool) -> String {
        model + "|" + (gpu ? "gpu" : "cpu")
    }

    /// Conserve la dernière mesure d'un modèle. Le nombre de threads et le contexte du test
    /// sont mémorisés en 3e et 4e valeurs ; les anciennes entrées à 2 valeurs restent lisibles.
    static func recordBenchmark(model: String, gpu: Bool, cfg: Cfg, tg: Double, pp: Double) {
        guard tg > 0, !model.isEmpty else { return }
        var all = (UserDefaults.standard.dictionary(forKey: benchKey) as? [String: [Double]]) ?? [:]
        all[benchName(model, gpu)] = [tg, pp, Double(cfg.threads), Double(cfg.nCtx)]
        UserDefaults.standard.set(all, forKey: benchKey)
    }

    static func benchmark(model: String, gpu: Bool) -> (tg: Double, pp: Double)? {
        let all = (UserDefaults.standard.dictionary(forKey: benchKey) as? [String: [Double]]) ?? [:]
        guard let values = all[benchName(model, gpu)], values.count >= 2 else { return nil }
        return (values[0], values[1])
    }

    // MARK: recommandations

    static func advice(modelName: String, modelSizeMB: Int, cfg: Cfg) -> [Advice] {
        var list: [Advice] = []
        let avail = Sys.availMB()

        if modelSizeMB > 0 && Double(modelSizeMB) / max(totalRAMMB, 1) > 0.55 {
            list.append(Advice(level: 1, text: "Modèle volumineux par rapport à la mémoire de l'appareil : risque de lenteur ou de fermeture de l'app. Un contexte plus court réduit ce risque."))
        }
        if avail > 0 && avail < 400 {
            list.append(Advice(level: 1, text: String(format: "Mémoire disponible faible (%.0f Mo) : ferme d'autres apps ou réduis le contexte.", avail)))
        }
        if cfg.gpuLayers > 0 && !Sys.gpuCapable {
            list.append(Advice(level: 1, text: "Le GPU est activé alors que cet appareil n'est pas éligible par défaut : les performances peuvent baisser. Compare avec le benchmark en CPU."))
        }
        if let cpu = benchmark(model: modelName, gpu: false), let gpu = benchmark(model: modelName, gpu: true) {
            if gpu.tg < cpu.tg * 0.8 {
                list.append(Advice(level: 1, text: String(format: "Mesures enregistrées : le CPU génère plus vite que le GPU pour ce modèle (%.1f contre %.1f t/s).", cpu.tg, gpu.tg)))
            } else if gpu.tg > cpu.tg * 1.2 {
                list.append(Advice(level: 0, text: String(format: "Mesures enregistrées : le GPU génère plus vite que le CPU pour ce modèle (%.1f contre %.1f t/s).", gpu.tg, cpu.tg)))
            }
        }
        if cfg.nCtx > 4096 && totalRAMMB < 4500 {
            list.append(Advice(level: 1, text: "Un contexte supérieur à 4096 tokens est exigeant pour cette quantité de mémoire."))
        }
        if Sys.freeDiskBytes() < 1_500_000_000 {
            list.append(Advice(level: 1, text: "Espace de stockage faible : les téléchargements de modèles risquent d'échouer."))
        }
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal == .serious || thermal == .critical {
            list.append(Advice(level: 1, text: "L'appareil est chaud : iOS et Pal réduisent la vitesse. Laisse-le refroidir."))
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            list.append(Advice(level: 0, text: "Le mode économie d'énergie d'iOS est actif : il peut limiter les performances."))
        }
        if list.isEmpty {
            list.append(Advice(level: 0, text: "Aucun problème détecté avec les réglages et l'état actuel de l'appareil."))
        }
        return list
    }
}
