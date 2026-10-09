# Native Mac services

Apple Vision recognizes Russian and English recipe images locally. `RecipeModelJob` calls the official LiteRT-LM 0.18.0 C API on a background queue with the same schema, Qwen template and source-evidence checks used on Android. The CPU backend uses four threads. Cancellation protects the active C handle from concurrent deletion.

The universal arm64/x86_64 binary is fetched by Swift Package Manager from Google's release, with the upstream SHA-256 checksum pinned in Package.swift. Model weights remain a separately verified download in the application support container; neither the source archive nor the application bundle contains them. Temporary inference caches are removed after each request. No Python or external AI server is required on Mac.

The native window uses NSGlassEffectView on macOS 26+, with NSVisualEffectView on earlier versions. Flutter reserves the titlebar and respects changes to the system Reduce Transparency preference. Native window, sandboxed OCR and login Keychain tests are in RunnerTests.

See the bundled Resources/LiteRT-LM-LICENSE.txt and NOTICE.txt for runtime attribution.
