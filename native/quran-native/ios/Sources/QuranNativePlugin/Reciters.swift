import Foundation

/// Ayah-by-ayah recitations hosted on everyayah.com (files named SSSAAA.mp3). Same list as Android.
struct Reciter {
    let id: String
    let name: String
    let riwayah: String
    let folder: String
    let approxMb: Int
    var aliases: [String] = []
    /// other hosts, tried in order after everyayah.com: {c} = SSSAAA, {g} = global ayah number
    var backups: [String] = []

    func url(_ code: String) -> URL { URL(string: "https://everyayah.com/data/\(folder)/\(code).mp3")! }

    func sources(_ code: String, _ global: Int) -> [URL] {
        [url(code)] + backups.compactMap { URL(string: $0.replacingOccurrences(of: "{c}", with: code).replacingOccurrences(of: "{g}", with: String(global))) }
    }
}

enum Reciters {
    static let all: [Reciter] = [
        Reciter(id: "yassin", name: "ياسين الجزائري", riwayah: "warsh", folder: "warsh/warsh_yassin_al_jazaery_64kbps", approxMb: 640, backups: ["https://www.everyayah.com/data/warsh/warsh_yassin_al_jazaery_64kbps/{c}.mp3"]),
        Reciter(id: "abdulbasit_warsh", name: "عبد الباسط عبد الصمد", riwayah: "warsh", folder: "warsh/warsh_Abdul_Basit_128kbps", approxMb: 1300, backups: ["https://www.everyayah.com/data/warsh/warsh_Abdul_Basit_128kbps/{c}.mp3"]),
        Reciter(id: "dosary_warsh", name: "إبراهيم الدوسري", riwayah: "warsh", folder: "warsh/warsh_ibrahim_aldosary_128kbps", approxMb: 1200, backups: ["https://www.everyayah.com/data/warsh/warsh_ibrahim_aldosary_128kbps/{c}.mp3"]),
        Reciter(id: "shuraym", name: "سعود الشريم", riwayah: "hafs", folder: "Saood_ash-Shuraym_64kbps", approxMb: 440, aliases: ["Saood_ash-Shuraym_128kbps"], backups: ["https://mirrors.quranicaudio.com/everyayah/Saood_ash-Shuraym_128kbps/{c}.mp3", "https://cdn.islamic.network/quran/audio/64/ar.saoodshuraym/{g}.mp3", "https://verses.quran.com/Shuraym/mp3/{c}.mp3"]),
        Reciter(id: "husary", name: "محمود خليل الحصري", riwayah: "hafs", folder: "Husary_64kbps", approxMb: 650, aliases: ["Husary_128kbps"], backups: ["https://mirrors.quranicaudio.com/everyayah/Husary_64kbps/{c}.mp3", "https://cdn.islamic.network/quran/audio/64/ar.husary/{g}.mp3"]),
        Reciter(id: "husary_muallim", name: "الحصري (المعلّم)", riwayah: "hafs", folder: "Husary_Muallim_128kbps", approxMb: 1500, backups: ["https://mirrors.quranicaudio.com/everyayah/Husary_Muallim_128kbps/{c}.mp3"]),
        Reciter(id: "minshawy", name: "محمد صديق المنشاوي", riwayah: "hafs", folder: "Minshawy_Murattal_128kbps", approxMb: 1100, backups: ["https://mirrors.quranicaudio.com/everyayah/Minshawy_Murattal_128kbps/{c}.mp3", "https://cdn.islamic.network/quran/audio/128/ar.minshawi/{g}.mp3", "https://verses.quran.com/Minshawi/Murattal/mp3/{c}.mp3"]),
        Reciter(id: "alafasy", name: "مشاري العفاسي", riwayah: "hafs", folder: "Alafasy_64kbps", approxMb: 520, aliases: ["Alafasy_128kbps"], backups: ["https://mirrors.quranicaudio.com/everyayah/Alafasy_128kbps/{c}.mp3", "https://cdn.islamic.network/quran/audio/64/ar.alafasy/{g}.mp3", "https://verses.quran.com/Alafasy/mp3/{c}.mp3"]),
        Reciter(id: "abdulbasit", name: "عبد الباسط عبد الصمد", riwayah: "hafs", folder: "Abdul_Basit_Murattal_64kbps", approxMb: 600, aliases: ["Abdul_Basit_Murattal_192kbps"], backups: ["https://mirrors.quranicaudio.com/everyayah/Abdul_Basit_Murattal_64kbps/{c}.mp3", "https://cdn.islamic.network/quran/audio/64/ar.abdulbasitmurattal/{g}.mp3", "https://verses.quran.com/AbdulBaset/Murattal/mp3/{c}.mp3"]),
        Reciter(id: "sudais", name: "عبد الرحمن السديس", riwayah: "hafs", folder: "Abdurrahmaan_As-Sudais_64kbps", approxMb: 420, backups: ["https://mirrors.quranicaudio.com/everyayah/Abdurrahmaan_As-Sudais_192kbps/{c}.mp3", "https://cdn.islamic.network/quran/audio/64/ar.abdurrahmaansudais/{g}.mp3", "https://verses.quran.com/Sudais/mp3/{c}.mp3"]),
        Reciter(id: "maher", name: "ماهر المعيقلي", riwayah: "hafs", folder: "Maher_AlMuaiqly_64kbps", approxMb: 450, backups: ["https://mirrors.quranicaudio.com/everyayah/Maher_AlMuaiqly_64kbps/{c}.mp3", "https://cdn.islamic.network/quran/audio/64/ar.mahermuaiqly/{g}.mp3"]),
    ]

    static func byId(_ id: String?) -> Reciter? { all.first { $0.id == id } }
}

/// Number of ayahs per surah (Hafs count, as used for the everyayah file names).
enum QuranMeta {
    static let ayahCounts: [Int] = [
        0, 7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128, 111, 110, 98, 135,
        112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73, 54, 45, 83, 182, 88, 75, 85,
        54, 53, 89, 59, 37, 35, 38, 29, 18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13,
        14, 11, 11, 18, 12, 12, 30, 52, 52, 44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42,
        29, 19, 36, 25, 22, 17, 19, 26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11,
        11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4, 5, 6
    ]
    static func code(_ s: Int, _ a: Int) -> String { String(format: "%03d%03d", s, a) }
    static func global(_ s: Int, _ a: Int) -> Int { (1..<max(1, s)).reduce(a) { $0 + ayahCounts[$1] } }
}
