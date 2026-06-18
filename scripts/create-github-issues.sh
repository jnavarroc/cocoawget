#!/bin/bash
#
# create-github-issues.sh — Crea en GitHub las issues que trocean el ROADMAP.md
# de modernización de CocoaWget a macOS Tahoe (macOS 26).
#
# Requisitos:
#   - GitHub CLI instalado y autenticado:  gh auth login
#       (macOS:  brew install gh   |   Windows:  winget install GitHub.cli)
#   - Ejecutarse dentro del repositorio (usa el remoto 'origin' por defecto).
#
# Uso:
#   ./scripts/create-github-issues.sh           # crea etiquetas e issues
#   DRY_RUN=1 ./scripts/create-github-issues.sh  # solo muestra lo que haría
#
set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"

command -v gh >/dev/null 2>&1 || { echo "Error: falta 'gh' (GitHub CLI). Instálalo y ejecuta 'gh auth login'." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Error: 'gh' no está autenticado. Ejecuta 'gh auth login'." >&2; exit 1; }

run() { if [ "$DRY_RUN" = "1" ]; then echo "[dry-run] $*"; else "$@"; fi; }

# --------------------------------------------------------------------------- #
# Etiquetas (idempotente: si ya existen, no falla)
# --------------------------------------------------------------------------- #
ensure_label() {  # ensure_label <nombre> <color> <descripcion>
    if [ "$DRY_RUN" = "1" ]; then echo "[dry-run] gh label create '$1'"; return; fi
    gh label create "$1" --color "$2" --description "$3" 2>/dev/null \
        || gh label edit "$1" --color "$2" --description "$3" 2>/dev/null \
        || true
}

ensure_label "P0-bloqueante"  "B60205" "Bloquea ejecución o distribución en macOS actual"
ensure_label "P1-alta"        "D93F0B" "Riesgo alto: crashes, APIs eliminadas, seguridad"
ensure_label "P2-media"       "FBCA04" "Base de proyecto y aseguramiento de calidad"
ensure_label "macos-tahoe"    "0E8A16" "Modernización a macOS Tahoe (macOS 26)"

# --------------------------------------------------------------------------- #
# Issues (una por fase del ROADMAP, + decisiones)
# --------------------------------------------------------------------------- #
create_issue() {  # create_issue <titulo> <etiquetas-csv> <cuerpo>
    local title="$1" labels="$2" body="$3"
    echo "==> Creando issue: $title"
    run gh issue create --title "$title" --label "$labels" --body "$body"
}

create_issue \
"Fase 0 — Línea base y entorno (preparación)" \
"P2-media,macos-tahoe" \
"$(cat <<'EOF'
Preparar el proyecto para compilarse y diagnosticarse en macOS Tahoe + Xcode actual.

- [ ] Compilar con Xcode reciente y capturar todos los *warnings* de deprecación (`-Wdeprecated-declarations`).
- [ ] Actualizar el proyecto al formato moderno de Xcode ("Update to recommended settings"); subir `objectVersion`.
- [ ] Definir deployment target objetivo (recomendado: macOS 13 Ventura; Tahoe como sistema de pruebas).
- [x] Añadir LICENSE explícito y documentar la GPL de wget incluida.
- [ ] Crear esquema de CI opcional (`xcodebuild` en GitHub Actions con runner macOS).

**Criterio de salida:** el proyecto abre y compila sin errores.

Ref: ROADMAP.md → Fase 0.
EOF
)"

create_issue \
"Fase 1 — Binario wget universal y moderno (BLOQUEANTE)" \
"P0-bloqueante,macos-tahoe" \
"$(cat <<'EOF'
Sustituir el wget i386/ppc (no arranca en macOS 10.15+) por uno universal y con TLS moderno.

- [x] `buildwget.sh`: compilar wget ≥ 1.25 (configurable, por defecto 1.25.0).
- [x] `buildwget.sh`: TLS moderno con OpenSSL enlazado estáticamente (sin dylibs de Homebrew).
- [x] `buildwget.sh`: binario universal arm64 + x86_64 con `lipo`.
- [x] `buildwget.sh`: verificación de integridad de fuentes (.sha256 de OpenSSL, firma GPG de wget, `STRICT_VERIFY`).
- [x] `buildwget.sh`: instalación opcional en el `.app` (`APP_BUNDLE=` / argumento posicional).
- [ ] **Validar el script en una máquina macOS**: `otool -L wget` (solo /usr/lib y /System), `file wget` (universal) y una descarga HTTPS real. Ajustar libidn2/libpsl si aparecen.
- [ ] Decisión de arquitectura (ver issue de Decisiones): empaquetar wget vs. libcurl/URLSession.
- [ ] Re-firmar el binario con Developer ID y notarizarlo junto con la app.
- [ ] `--http-passwd` → `--http-password` en DownloadItem.m.

**Criterio de salida:** `file wget` reporta arm64/x86_64 y una descarga HTTPS real funciona.

Ref: ROADMAP.md → Fase 1.
EOF
)"

create_issue \
"Fase 2 — Saneamiento del código (APIs obsoletas y ARC)" \
"P1-alta,macos-tahoe" \
"$(cat <<'EOF'
Eliminar APIs eliminadas/obsoletas y modernizar la gestión de memoria.

- [ ] Migrar a ARC (quitar retain/release/autorelease/dealloc manuales en DownloadItem.m y CWArrayController.m).
- [ ] Reemplazar NS_DURING/NS_HANDLER/NS_ENDHANDLER por @try/@catch o comprobaciones de error.
- [ ] `setKeys:triggerChangeNotificationsForDependentKey:` → `+keyPathsForValuesAffectingValueForKey:`.
- [ ] `NSStringPboardType` → `NSPasteboardTypeString`.
- [ ] NSTask: `setLaunchPath:`+`launch` → `executableURL`+`launchAndReturnError:`.
- [ ] `NSWorkspace iconForFileType:` → `iconForContentType:` (UTType).
- [ ] `NSWorkspace openFile:` → `openURL:` / `openApplicationAtURL:configuration:`.
- [ ] `NSAlert alertWithMessageText:...` (obsoleto) → NSAlert con `addButtonWithTitle:`.
- [ ] Corregir format strings: `NSLog(filename)` → `NSLog(@"%@", filename)`.
- [ ] Revisar el timer en `NSEventTrackingRunLoopMode` (usar `NSRunLoopCommonModes` o GCD).

**Criterio de salida:** compila sin warnings de deprecación y sin fugas (Instruments/ASan).

Ref: ROADMAP.md → Fase 2.
EOF
)"

create_issue \
"Fase 3 — Interfaz de usuario (eliminar NSDrawer, diseño Tahoe)" \
"P1-alta,macos-tahoe" \
"$(cat <<'EOF'
Reemplazar componentes de UI eliminados y adaptar al lenguaje visual de Tahoe.

- [ ] Eliminar `NSDrawer` (obsoleto): mover el log a `NSSplitView`, panel colapsable o sheet.
- [ ] Revisar `MainMenu.xib` en Xcode actual en las 3 localizaciones (English, German, Japanese).
- [ ] Adoptar Auto Layout si hay autoresizing masks frágiles.
- [ ] Migrar el icono a un Asset Catalog (.xcassets); preparar estilo Liquid Glass de Tahoe.
- [ ] Verificar contraste/colores en modo oscuro y con el diseño de macOS 26.
- [ ] (Opcional) Evaluar reescritura incremental de vistas a SwiftUI.

**Criterio de salida:** UI funcional sin componentes obsoletos, correcta en claro/oscuro en Tahoe.

Ref: ROADMAP.md → Fase 3.
EOF
)"

create_issue \
"Fase 4 — Sandbox, permisos y modelo de seguridad" \
"P1-alta,macos-tahoe" \
"$(cat <<'EOF'
Cumplir el modelo de seguridad moderno de macOS.

- [ ] No reescribir el `~/.wgetrc` global: generar config propia y pasarla con `--config=<ruta>`.
- [ ] Decidir sobre App Sandbox (Mac App Store obligatorio / Developer ID opcional pero con Hardened Runtime).
- [ ] Entitlements: `com.apple.security.network.client`, acceso a carpeta de descargas, Apple Events si se mantiene el control de Safari/Finder.
- [ ] Info.plist: `NSAppleEventsUsageDescription`; manejar consentimiento TCC con degradación elegante.
- [ ] Usar security-scoped bookmarks para recordar la carpeta de descargas.

**Criterio de salida:** la app no toca archivos globales, pide permisos correctamente y funciona con Hardened Runtime.

Ref: ROADMAP.md → Fase 4.
EOF
)"

create_issue \
"Fase 5 — Firma, notarización y distribución (BLOQUEANTE para distribuir)" \
"P0-bloqueante,macos-tahoe" \
"$(cat <<'EOF'
Que la app pase Gatekeeper en máquinas de usuarios.

- [ ] Firmar la app y el binario wget empaquetado con Developer ID Application (firma anidada del helper).
- [ ] Activar Hardened Runtime.
- [ ] Notarizar con `notarytool` y grapar el ticket (`stapler staple`).
- [ ] Empaquetar en .dmg o .pkg firmado.
- [ ] Verificar en máquina limpia: `spctl -a -vv` y `codesign --verify --deep --strict`.
- [ ] Actualizar metadatos: `CFBundleVersion`, `CFBundleShortVersionString`, `CFBundleIdentifier` real, `LSMinimumSystemVersion`.

**Criterio de salida:** la app instalada desde el .dmg arranca sin advertencias de Gatekeeper en Tahoe.

Ref: ROADMAP.md → Fase 5.
EOF
)"

create_issue \
"Fase 6 — Calidad, pruebas y mantenimiento" \
"P2-media,macos-tahoe" \
"$(cat <<'EOF'
Aseguramiento de calidad de la modernización.

- [ ] Verificar el parsing de progreso con la salida de wget actual (`--progress=dot:binary` → `parseDownloadingProgress:`).
- [ ] Probar: HTTPS simple, reanudación, recursiva, FTP pasivo, proxy, autenticación, expansión secuencial de URLs, drag&drop.
- [ ] Revisar fugas y races del manejo de NSPipe/notificaciones (Instruments).
- [ ] Probar en Apple Silicon e Intel.
- [ ] Documentar build reproducible (incluido wget) en el README.
- [ ] (Opcional) Tests de utilidades puras (parseURL:, expandSequencialURL:, validateURL:, getArgument).

Ref: ROADMAP.md → Fase 6.
EOF
)"

create_issue \
"Decisiones de arquitectura y distribución" \
"P1-alta,macos-tahoe" \
"$(cat <<'EOF'
Decisiones transversales que afectan al alcance de varias fases.

- [ ] **¿Cómo proveer wget?** (A) empaquetar wget universal propio · (B) sustituir motor por libcurl/URLSession · (C) depender de wget de Homebrew. Recomendación: (A) a corto plazo, valorar (B) a largo.
- [ ] **¿Canal de distribución?** Mac App Store (sandbox estricto) vs. Developer ID + notarización (recomendado).
- [ ] **¿Deployment target mínimo?** macOS 13 Ventura (recomendado) vs. mantener 10.13.
- [ ] **¿Reescritura a Swift/SwiftUI?** Modernización incremental en Objective-C vs. reescritura.

Ref: ROADMAP.md → Decisiones a tomar.
EOF
)"

echo "==> Hecho."
