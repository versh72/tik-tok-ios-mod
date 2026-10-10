/*
 * tiktok-region-installer — вставка библиотеки в перепакованный IPA.
 *
 * Зачем нужна эта программа
 * -------------------------
 * Обычно установка требует связки из нескольких инструментов: Rust,
 * insert_dylib, плюс понимание, куда класть файлы. Пользователю это
 * не нужно. Здесь одна программа, которая делает всё: проверяет IPA,
 * вставляет библиотеку и собирает готовый файл обратно.
 *
 * Что она НЕ делает
 * -----------------
 * Не подписывает и не устанавливает на телефон. Подпись требует Apple ID
 * владельца, и её делает Sideloadly или AltStore. Ключ хранится у
 * человека, а не в программе.
 *
 * Требование к исходному IPA: он должен быть расшифрован. Из App Store
 * файл приходит зашифрованным, и после вставки библиотеки приложение
 * не запустится. Это проверяется здесь же, до того как что-то испорчено.
 */

use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, exit};

const DYLIB_NAME: &str = "TikTokRegion.dylib";

fn say(msg: &str) {
    println!("{}", msg);
}

fn step(msg: &str) {
    println!();
    println!("==> {}", msg);
}

fn fail(msg: &str) -> ! {
    println!();
    println!("ОШИБКА: {}", msg);
    exit(1);
}

/// Ищет файл в текущем каталоге и в каталоге программы.
fn find_file(name: &str) -> Option<PathBuf> {
    if let Ok(p) = std::env::current_exe() {
        if let Some(dir) = p.parent() {
            let candidate = dir.join(name);
            if candidate.exists() {
                return Some(candidate);
            }
        }
    }
    let here = PathBuf::from(name);
    if here.exists() {
        return Some(here);
    }
    None
}

fn usage() -> ! {
    println!();
    println!("TikTokRegion — установщик библиотеки в перепакованный IPA");
    println!();
    println!("Запуск:");
    println!("  tiktok-region-installer.exe путь\\к\\TikTok.ipa");
    println!();
    println!("Программа создаст рядом с исходным файлом");
    println!("TikTok-region.ipa — его и нужно подписать и поставить на телефон.");
    println!();
    exit(1);
}

fn main() {
    println!("TikTokRegion 1.0.0");
    println!("Вставка библиотеки в перепакованный TikTok.ipa");

    let args: Vec<String> = std::env::args().collect();
    if args.len() != 2 {
        usage();
    }

    let ipa = PathBuf::from(&args[1]);
    if !ipa.exists() {
        fail(&format!("файл не найден: {}", ipa.display()));
    }

    // ── библиотека ────────────────────────────────────────────────────────
    step("Проверяю наличие библиотеки");
    let dylib = match find_file(DYLIB_NAME) {
        Some(p) => {
            println!("  найдена: {}", p.display());
            p
        }
        None => fail(&format!(
            "рядом с программой должен лежать файл {}. Скачать его можно \
             со страницы релизов на GitHub.",
            DYLIB_NAME
        )),
    };

    // ── инструмент вставки ────────────────────────────────────────────────
    step("Проверяю встроенный инструмент");
    let insert = match find_file("insert-dylib.exe").or_else(|| find_file("insert-dylib")) {
        Some(p) => p,
        None => fail(
            "не найден insert-dylib рядом с программой. Вероятно, архив \
             распакован не полностью — скачай его заново целиком.",
        ),
    };
    println!("  найден: {}", insert.display());

    // ── расшифровка ───────────────────────────────────────────────────────
    step("Проверяю, что IPA расшифрован");
    match check_decrypted(&ipa) {
        Ok(()) => println!("  расшифрован — можно вставлять"),
        Err(why) => fail(&why),
    }

    // ── работа ────────────────────────────────────────────────────────────
    step("Вставляю библиотеку");
    let out = ipa.with_file_name("TikTok-region.ipa");
    if out.exists() {
        let _ = fs::remove_file(&out);
    }

    let status = Command::new(&insert)
        .arg(&dylib)
        .arg(&ipa)
        .arg(&out)
        .arg("--all-yes")
        .status();

    match status {
        Ok(s) if s.success() => println!("  готово"),
        Ok(s) => fail(&format!("insert-dylib завершился с кодом {}", s)),
        Err(e) => fail(&format!("не удалось запустить insert-dylib: {}", e)),
    }

    if !out.exists() {
        fail("insert-dylib отработал, но файл не появился");
    }

    // ── результат ─────────────────────────────────────────────────────────
    let size = fs::metadata(&out).map(|m| m.len()).unwrap_or(0);
    println!();
    println!("Готово: {}", out.display());
    println!("Размер: {:.1} МБ", size as f64 / 1_048_576.0);
    println!();
    println!("Что дальше:");
    println!("  Файл нужно подписать — он не запустится без подписи.");
    println!("  Сделать это можно Sideloadly или AltStore, оба работают");
    println!("  на Windows и бесплатны:");
    println!("    1. Скачать Sideloadly: sideloadly.io");
    println!("    2. Перетащить сюда TikTok-region.ipa");
    println!("    3. Выбрать свой Apple ID, нажать Start");
    println!("    4. На iPhone включить Режим разработчика");
    println!("       (Настройки -> Конфиденциальность -> Режим разработчика)");
    println!();
    println!("  Подпись бесплатная и живёт 7 дней. Потом подписать заново.");
    println!();

    // Небольшая пауза, чтобы вывод успел показаться в консоли,
    // запущенной двойным щелчком.
    let _ = io::stdout().flush();
    std::thread::sleep(std::time::Duration::from_millis(1500));
}

/// Ищет в бинарнике приложения признак шифрования Mach-O.
///
/// LC_ENCRYPTION_INFO (0x21) содержит cryptid. Значение не равно нулю —
/// код зашифрован. Такой файл после вставки библиотеки не запустится:
/// расшифровщик iOS не совпадёт с новой подписью.
fn check_decrypted(ipa: &Path) -> Result<(), String> {
    let file = fs::File::open(ipa)
        .map_err(|e| format!("не удалось открыть IPA: {}", e))?;
    let mut archive = zip::ZipArchive::new(file)
        .map_err(|e| format!("это не ZIP или IPA повреждён: {}", e))?;

    // Ищем главный бинарник приложения.
    let mut names: Vec<String> = archive.file_names().map(|s| s.to_string()).collect();
    names.sort();

    let target = names
        .iter()
        .find(|n| {
            n.starts_with("Payload/")
                && !n.contains('/')
                .then_some(false)
                .unwrap_or_else(|| n.matches('/').count() == 2)
                && !n.ends_with(".plist")
                && !n.ends_with(".dylib")
                && !n.ends_with(".nib")
        })
        .cloned();

    let target = match target {
        Some(t) => t,
        None => return Err("в архиве не нашёлся главный бинарник приложения".into()),
    };

    println!("  бинарник: {}", target);

    let mut entry = archive
        .by_name(&target)
        .map_err(|e| format!("не удалось прочитать бинарник: {}", e))?;

    // Хватает первых мегабайта: заголовок команд загрузки в начале.
    let cap = entry.size().min(1 << 21);
    let mut head = vec![0u8; cap as usize];
    entry
        .read(&mut head)
        .map_err(|e| format!("бинарник не читается: {}", e))?;

    match find_cryptid(&head) {
        Some(0) => Ok(()),
        Some(v) => Err(format!(
            "IPA зашифрован (cryptid = {}). Из App Store файл приходит \
             зашифрованным. Нужен расшифрованный IPA: после вставки \
             библиотеки приложение не запустится.",
            v
        )),
        None => Ok(()),
    }
}

/// Ищет LC_ENCRYPTION_INFO (0x21) и возвращает cryptid.
///
/// Смещения взяты с реального бинарника, а не по памяти:
/// заголовок Mach-O 64-битный (magic 0xfeedfacf) занимает 32 байта,
/// и команды загрузки начинаются сразу за ним. Для 32-битного
/// (magic 0xfeedface) заголовок короче на 4 байта.
fn find_cryptid(head: &[u8]) -> Option<u32> {
    if head.len() < 32 {
        return None;
    }

    let magic = u32::from_le_bytes([head[0], head[1], head[2], head[3]]);
    let start = match magic {
        0xfeedfacf => 32usize, // 64-битный
        0xfeedface => 28usize, // 32-битный
        _ => return None,
    };

    let ncmds = u32::from_le_bytes([
        head[16],
        head[17],
        head[18],
        head[19],
    ]) as usize;

    let mut off = start;
    // Граница: не выходим за прочитанный кусок и не доверяем ncmds вслепую.
    let limit = head.len();

    for _ in 0..ncmds {
        if off + 12 > limit {
            return None;
        }
        let cmd = u32::from_le_bytes([head[off], head[off + 1], head[off + 2], head[off + 3]]);
        let size = u32::from_le_bytes([
            head[off + 4],
            head[off + 5],
            head[off + 6],
            head[off + 7],
        ]) as usize;

        if size < 8 {
            return None;
        }

        // LC_ENCRYPTION_INFO: cmd, cmdsize, cryptoff, cryptsize, cryptid
        if cmd == 0x21 {
            return Some(u32::from_le_bytes([
                head[off + 8],
                head[off + 9],
                head[off + 10],
                head[off + 11],
            ]));
        }

        off += size;
    }
    None
}

use std::io::Read;
