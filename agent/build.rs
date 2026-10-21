fn main() {
    println!("cargo:rerun-if-changed=../branding/vil-icon.ico");
    println!("cargo:rerun-if-changed=vil.rc");
    if std::env::var("TARGET").unwrap() == "x86_64-pc-windows-gnu" {
        let out = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap()).join("vil-icon.o");
        let tool = std::env::var("WINDRES").unwrap_or_else(|_| "x86_64-w64-mingw32-windres".into());
        let status = std::process::Command::new(tool)
            .args(["-i", "vil.rc", "-O", "coff", "-o"])
            .arg(&out).status().expect("windres is required to embed the ViL executable icon");
        assert!(status.success(), "could not compile ViL icon resource");
        println!("cargo:rustc-link-arg={}", out.display());
    }
}
