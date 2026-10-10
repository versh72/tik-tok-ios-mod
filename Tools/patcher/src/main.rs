/*
 * TikTokRegion — установщик.
 *
 * Что делает программа
 * --------------------
 *   1. Проверяет, что телефон подключён
 *   2. Берёт файл TikTok.ipa
 *   3. Вмещает в него библиотеку
 *   4. Подписывает твоим сертификатом
 *   5. Ставит на телефон
 *
 * Всё в одном окне. Ничего доустанавливать не нужно: подпись и
 * установка делаются встроенными программами, которые лежат рядом.
 *
 * Про данные
 * ----------
 * Программа не ходит в интернет. Она только читает файлы, которые
 * ты сам указал, и запускает программы из своей папки. Исходный код
 * открыт — можешь проверить или собрать сам.
 */

use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, exit};

const DYLIB_NAME: &str = "TikTokRegion.dylib";

fn line() {
    println!();
}

fn say(msg: &str) {
    println!("{}", msg);
}

fn ok(msg: &str) {
    println!("  [готово] {}", msg);
}

fn step(msg: &str) {
    line();
    println!("--- {} ---", msg);
}

fn fail(msg: &str) -> ! {
    line();
    println!("!!  {}", msg);
    line();
    pause();
    exit(1);
}

fn pause() {
    let _ = io::stdout().flush();
    println!();
    println!("Нажми Enter, чтобы закрыть окно.");
    let mut s = String::new();
    let _ = io::stdin().read_line(&mut s);
}

fn exe_dir() -> PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.to_path_buf()))
        .unwrap_or_else(|| PathBuf::from("."))
}

/// Ищет файл рядом с программой или в текущем каталоге.
fn near(name: &str) -> Option<PathBuf> {
    let d = exe_dir().join(name);
    if d.exists() {
        return Some(d);
    }
    let h = PathBuf::from(name);
    if h.exists() {
        return Some(h);
    }
    None
}

/// Ищет файл в подпапке, если он лежит там (например tools\).
fn near_in(sub: &str, name: &str) -> Option<PathBuf> {
    let d = exe_dir().join(sub).join(name);
    if d.exists() {
        return Some(d);
    }
    None
}

fn main() {
    println!();
    println!("=========================================");
    println!("  TikTokRegion — установка на телефон");
    println!("=========================================");

    // ── 1. телефон ────────────────────────────────────────────────────────
    step("Проверяю телефон");

    let device_tool = match near("idevice_id.exe").or_else(|| near_in("tools", "idevice_id.exe")) {
        Some(p) => p,
        None => fail(
            "в папке нет файла idevice_id.exe — он нужен, чтобы увидеть телефон.\n\
             \n\
             Что сделать: установи приложение «Apple Devices» с сайта Apple \
             или iTunes. Само приложение запускать не нужно — нужен только \
             драйвер, который оно ставит.\n\
             \n\
             После установки перезапусти эту программу.",
        ),
    };

    let (out, _) = run(device_tool, &[]);
    // Успех — это строка вида "d3a4...", начинающаяся с 40 нулей при
    // отсутствии устройств. Любой непустой вывод означает, что телефон найден.
    let found = out
        .lines()
        .map(str::trim)
        .find(|l| !l.is_empty() && l.len() >= 40 && !l.chars().all(|c| c == '0'))
        .map(|s| s.to_string());

    match found {
        Some(udid) => ok(&format!("телефон подключён: {}", &udid[..8.min(udid.len())])),
        None => fail(
            "телефон не найден. Проверь три вещи:\n\
             \n\
              1. Телефон подключён кабелем и РАЗБЛОКИРОВАН\n\
              2. На экране нажато «Доверять этому компьютеру»\n\
              3. В Настройки -> Конфиденциальность -> Режим разработчика \
             включён\n\
             \n\
             Если режим разработчика включали недавно, телефон перезагрузился — \
             подключи его заново.",
        ),
    }

    // ── 2. файлы ──────────────────────────────────────────────────────────
    step("Ищу нужные файлы");

    let dylib = match near(DYLIB_NAME) {
        Some(p) => {
            ok(&format!("библиотека: {}", p.display()));
            p
        }
        None => fail(&format!(
            "рядом с программой нет файла {}.\n\
             Скачай архив целиком и распакуй заново.",
            DYLIB_NAME
        )),
    };

    let zsign = match near("zsign.exe").or_else(|| near_in("tools", "zsign.exe")) {
        Some(p) => {
            ok("программа подписи найдена");
            p
        }
        None => fail(
            "в папке программы нет файла zsign.exe. \
             Похоже, архив распакован не полностью.",
        ),
    };

    // Сертификат и профиль нужны, только если нет ad-hoc подписи.
    let p12 = near("certificate.p12");
    let prov = near("profile.mobileprovision");
    let password = read_password();

    match (&p12, &prov) {
        (Some(p), Some(m)) => {
            ok(&format!("сертификат: {}", p.display()));
            ok(&format!("профиль:   {}", m.display()));
        }
        _ => {
            say("");
            say("  Сертификат не найден — подпишу ad-hoc.");
            say("  Так может не принять iOS. Если не запустится,");
            say("  возьми сертификат и профиль и положи их рядом.");
        }
    }

    // ── 3. исходный IPA ───────────────────────────────────────────────────
    step("Ищу файл TikTok.ipa");

    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Ok(rd) = fs::read_dir(exe_dir()) {
        for e in rd.flatten() {
            let p = e.path();
            let name = p.file_name().unwrap_or_default().to_string_lossy();
            if name.eq_ignore_ascii_case("TikTok.ipa") {
                candidates.push(p);
            }
        }
    }

    if candidates.is_empty() {
        fail(
            "файл TikTok.ipa не найден рядом с программой.\n\
             \n\
             Положи его в ту же папку, где лежит эта программа, \
             и запусти снова.\n\
             \n\
             Имя должно быть ровно TikTok.ipa.",
        );
    }
    ok(&format!("файл: {}", candidates[0].display()));

    let input = candidates[0].clone();
    let output = exe_dir().join("TikTok-region.ipa");
    let _ = fs::remove_file(&output);

    // ── 4. подпись и вставка ──────────────────────────────────────────────
    step("Вмещаю библиотеку и подписываю");

    let mut args: Vec<String> = vec![];
    match (&p12, &prov) {
        (Some(p), Some(m)) => {
            args.push("-k".into());
            args.push(p.to_string_lossy().to_string());
            args.push("-m".into());
            args.push(m.to_string_lossy().to_string());
            args.push("-p".into());
            args.push(password.clone());
        }
        _ => args.push("-a".into()),
    }
    args.push("-l".into());
    args.push(dylib.to_string_lossy().to_string());
    args.push("-o".into());
    args.push(output.to_string_lossy().to_string());
    args.push(input.to_string_lossy().to_string());

    let (log, code) = run_owned(zsign, args);

    if code != 0 || !output.exists() {
        println!("{}", log);
        fail("не получилось подписать файл. Скорее всего, IPA зашифрован.");
    }
    ok("подпись сделана");

    // ── 5. установка ──────────────────────────────────────────────────────
    step("Ставлю на телефон");

    let installer = match near("ideviceinstaller.exe")
        .or_else(|| near_in("tools", "ideviceinstaller.exe"))
    {
        Some(p) => p,
        None => fail(
            "в папке программы нет файла ideviceinstaller.exe. \
             Похоже, архив распакован не полностью.",
        ),
    };

    let (log, code) = run_owned(installer, vec!["-i".into(), output.to_string_lossy().to_string()]);

    line();
    if code == 0 {
        println!("  ГОТОВО.");
        line();
        say("Открой TikTok на телефоне.");
        say("Подменённый регион — Япония.");
        say("");
        say("Если что-то пойдёт не так, напиши в консоль:");
        say("  {}", log.trim());
    } else {
        println!("{}", log);
        fail("не получилось поставить на телефон.");
    }

    pause();
}

/// Запускает программу и возвращает (вывод, код возврата).
///
/// Раньше вывод и код возврата брались двумя отдельными запусками:
/// программа выполнялась дважды, а для zsign это означало двойную
/// подпись и лишние секунды.
fn run(program: &Path, args: &[&str]) -> (String, i32) {
    let owned: Vec<String> = args.iter().map(|s| s.to_string()).collect();
    run_owned(program, owned)
}

fn run_owned(program: &Path, args: Vec<String>) -> (String, i32) {
    match Command::new(program).args(&args).output() {
        Ok(o) => {
            let text = format!(
                "{}{}",
                String::from_utf8_lossy(&o.stdout),
                String::from_utf8_lossy(&o.stderr)
            );
            (text, o.status.code().unwrap_or(-1))
        }
        Err(e) => (format!("не удалось запустить: {}", e), -1),
    }
}

/// Спрашивает пароль от сертификата, только если он рядом есть.
fn read_password() -> String {
    if near("password.txt").is_none() {
        return String::new();
    }
    line();
    say("  Найден файл password.txt с паролем от сертификата.");
    let _ = io::stdout().flush();
    let mut s = String::new();
    let _ = io::stdin().read_line(&mut s);
    s.trim().to_string()
}
