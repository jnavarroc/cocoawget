# ROADMAP — Modernización de CocoaWget para macOS Tahoe

Plan de actualización de CocoaWget para que compile, se ejecute y se distribuya en **macOS Tahoe
(macOS 26)** y arquitectura **Apple Silicon (arm64)**.

> **Issues de GitHub:** este roadmap está troceado en issues; ejecuta
> [`scripts/create-github-issues.sh`](scripts/create-github-issues.sh) (requiere `gh` autenticado)
> para crearlas con sus etiquetas de prioridad.

> ### Nota sobre la numeración de versiones
> macOS Tahoe es **macOS 26** (lanzado en septiembre de 2025; Apple saltó de la 15 a la 26 para
> alinear la numeración con el año). **No existe "macOS 18"**: el commit `8974aee` ("Update project
> for macOS 18 compatibility") usa una numeración inexistente; la última versión antes del salto fue
> macOS 15 *Sequoia*. Este roadmap usa la nomenclatura correcta: **macOS 26 Tahoe**.

---

## Diagnóstico de partida

Lo que ya se hizo en el commit `8974aee` (buena base, pero parcial):

- ✅ `ARCHS` pasó de `ARCHS_STANDARD_32_BIT` a `ARCHS_STANDARD`; se eliminó `VALID_ARCHS = "i386 ppc"`
  y `SDKROOT = macosx10.5`.
- ✅ Se sustituyeron APIs de `NSFileManager` eliminadas (`removeFileAtPath:handler:` →
  `removeItemAtPath:error:`, etc.) y `stringWithContentsOfFile:` con codificación explícita.
- ✅ Se modernizaron `NSOpenPanel` (sheet con *completion handler*), `NSModalResponse`,
  `runningApplications` en lugar de `launchedApplications` y el *bridging* de Core Foundation.
- ✅ `MACOSX_DEPLOYMENT_TARGET = 10.13` y `LSMinimumSystemVersion = 10.13` en el Info.plist.

Lo que **sigue bloqueando** la ejecución en macOS Tahoe:

1. 🔴 **El binario `wget` es i386 + ppc** → no arranca en macOS 10.15+. Bloqueante absoluto.
2. 🔴 **Sin firma de código ni notarización** → Gatekeeper bloquea la app.
3. 🟠 **APIs obsoletas/eliminadas** todavía en uso (`NSDrawer`, `NSStringPboardType`,
   `setKeys:triggerChangeNotificationsForDependentKey:`, `NSWorkspace iconForFileType:` /
   `openFile:`, `NSTask -setLaunchPath:`/`-launch`).
4. 🟠 **Conteo manual de referencias (MRC)** y macros de excepción heredadas (`NS_DURING`).
5. 🟠 **Modifica `~/.wgetrc` global** y **controla Safari/Finder por AppleScript** → incompatible
   con *App Sandbox* y sujeto a permisos TCC.
6. 🟡 Vulnerabilidades de *format string* (`NSLog(filename)`), opciones de wget obsoletas
   (`--http-passwd`), proyecto Xcode en formato antiguo (`objectVersion = 45`).

---

## Fase 0 — Línea base y entorno (preparación)

**Objetivo:** poder compilar y diagnosticar en una máquina con macOS Tahoe + Xcode actual.

- [ ] Verificar compilación actual con Xcode reciente; capturar todos los *warnings* de
      deprecación (activar `-Wdeprecated-declarations`).
- [ ] Actualizar el proyecto al formato moderno de Xcode (Xcode propondrá *"Update to recommended
      settings"`*; revisar y aceptar). Subir `objectVersion`.
- [ ] Definir **deployment target** objetivo. Recomendado: **macOS 13 Ventura** como mínimo (cubre
      la base instalada razonable y permite usar APIs modernas), con Tahoe como sistema de pruebas.
- [ ] Añadir un archivo **LICENSE** explícito para el código de CocoaWget y documentar la GPL de
      wget incluida.
- [ ] Crear un esquema de CI opcional (`xcodebuild` en GitHub Actions con *runner* macОС).

**Criterio de salida:** el proyecto abre y compila sin errores (aunque la app aún no descargue).

---

## Fase 1 — Binario `wget` universal y moderno  🔴 *(bloqueante)*

**Objetivo:** sustituir el wget i386/ppc por uno que funcione en Apple Silicon e Intel con TLS
moderno.

- [x] Actualizar [buildwget.sh](buildwget.sh) para compilar una versión **actual de wget**
      (≥ 1.25) en lugar de la 1.15 (2014). *(Hecho: versión configurable, por defecto 1.25.0.)*
- [x] Compilar con **TLS moderno** (OpenSSL) para soportar TLS 1.2/1.3 y HTTPS actual; **enlazar
      estáticamente** OpenSSL para que el binario no dependa de dylibs de Homebrew.
      *(Hecho en `buildwget.sh`: OpenSSL `no-shared`.)*
- [x] Generar un **binario universal** (`arm64` + `x86_64`) con `lipo`, construyendo cada *slice*
      por separado. *(Hecho en `buildwget.sh`.)*
- [x] **Verificar la integridad de las fuentes** antes de compilar (`.sha256` publicado de
      OpenSSL, firma GPG de wget contra el llavero de GNU, o sha256 fijados con `STRICT_VERIFY=1`).
      *(Hecho en `buildwget.sh`.)*
- [x] **Paso opcional para instalar el binario en un `.app`** (`APP_BUNDLE=` o argumento
      posicional), con re‑firma ad-hoc. *(Hecho en `buildwget.sh`.)*
- [ ] **Validar el script en una máquina con macOS** (no se ha podido ejecutar aún): comprobar
      `otool -L wget` (solo `/usr/lib` y `/System`), `file wget` (universal) y una descarga HTTPS
      real. Ajustar dependencias opcionales (libidn2/libpsl) si aparecen.
- [ ] **Decisión de arquitectura** (ver sección *Decisiones*): ¿seguir empaquetando wget,
      detectar/usar un wget de Homebrew, o sustituir el motor por `URLSession`/`libcurl`?
- [ ] Verificar firma del binario (el script firma ad-hoc; debe **re‑firmarse con Developer ID** y
      notarizarse junto con la app).
- [ ] Actualizar la opción obsoleta `--http-passwd` → `--http-password` en
      [DownloadItem.m](DownloadItem.m).

**Criterio de salida:** `file wget` reporta `arm64`/`x86_64`, y una descarga HTTPS real funciona.

---

## Fase 2 — Saneamiento del código (APIs obsoletas y memoria)  🟠

**Objetivo:** eliminar APIs eliminadas/obsoletas y modernizar la gestión de memoria.

- [ ] **Migrar a ARC** (*Automatic Reference Counting*). Quitar `retain`/`release`/`autorelease`/
      `dealloc` manuales en [DownloadItem.m](DownloadItem.m) y [CWArrayController.m](CWArrayController.m).
- [ ] Reemplazar las macros de excepción heredadas `NS_DURING`/`NS_HANDLER`/`NS_ENDHANDLER` por
      `@try/@catch` o por comprobaciones de error.
- [ ] Sustituir `setKeys:triggerChangeNotificationsForDependentKey:` (eliminado) por
      `+keyPathsForValuesAffectingValueForKey:` en `DownloadItem`.
- [ ] `NSStringPboardType` → `NSPasteboardTypeString` en el arrastrar y soltar.
- [ ] `NSTask`: `setLaunchPath:` + `launch` → `executableURL` + `launchAndReturnError:`.
- [ ] `NSWorkspace iconForFileType:` → `iconForContentType:` (UniformTypeIdentifiers / `UTType`).
- [ ] `NSWorkspace openFile:` → `openURL:` / `openApplicationAtURL:configuration:...`.
- [ ] `NSAlert alertWithMessageText:defaultButton:...` (obsoleto) → `NSAlert` con
      `addButtonWithTitle:` y `messageText`/`informativeText`.
- [ ] Corregir **format strings**: `NSLog(filename)`/`NSLog(contents)` →
      `NSLog(@"%@", filename)` (riesgo de seguridad y de *crash*).
- [ ] Revisar el temporizador en `NSEventTrackingRunLoopMode`; usar
      `NSRunLoopCommonModes` o migrar a GCD/`dispatch_source`.

**Criterio de salida:** compilación sin *warnings* de deprecación y sin fugas (Instruments /
*Address Sanitizer*).

---

## Fase 3 — Interfaz de usuario  🟠

**Objetivo:** reemplazar componentes de UI eliminados y adaptar al lenguaje visual de Tahoe.

- [ ] **Eliminar `NSDrawer`** (obsoleto desde 10.13, no funciona como antes): mover el log a un
      `NSSplitView` lateral, un panel inferior colapsable o una hoja/ventana de inspección.
- [ ] Revisar el `MainMenu.xib` en Xcode actual (puede requerir migración del formato de XIB) en
      las tres localizaciones (`English`, `German`, `Japanese`).
- [ ] Adoptar **Auto Layout** si la ventana usa *autoresizing masks* frágiles.
- [ ] Migrar el icono a un **Asset Catalog** (`.xcassets`) con todos los tamaños; opcionalmente
      preparar el icono para el nuevo estilo *Liquid Glass* de Tahoe.
- [ ] Verificar contraste/colores en **modo oscuro** y con el nuevo diseño de macOS 26.
- [ ] (Opcional, mayor esfuerzo) Evaluar una reescritura incremental de vistas a **SwiftUI**.

**Criterio de salida:** UI funcional sin componentes obsoletos, correcta en claro/oscuro en Tahoe.

---

## Fase 4 — Sandbox, permisos y modelo de seguridad  🟠

**Objetivo:** cumplir el modelo de seguridad moderno de macOS.

- [ ] **No reescribir el `~/.wgetrc` global del usuario.** Generar un archivo de configuración
      propio dentro del contenedor de la app y pasarlo a wget con `--config=<ruta>` (evita el
      *backup/restore* invasivo y es compatible con sandbox).
- [ ] Decidir sobre el **App Sandbox**:
  - Si se distribuye por la **Mac App Store** → sandbox **obligatorio**; lanzar un ejecutable
    auxiliar (wget) requiere empaquetarlo como *helper* y revisar restricciones (la MAS suele
    rechazar apps que ejecutan binarios externos arbitrarios).
  - Si se distribuye por **fuera (Developer ID)** → sandbox opcional, pero **Hardened Runtime**
    obligatorio para notarizar.
- [ ] Añadir *entitlements*: `com.apple.security.network.client`, acceso a la carpeta de descargas
      (sandbox o *bookmarks* de seguridad), y `com.apple.security.automation.apple-events` si se
      mantiene el control de Safari/Finder.
- [ ] Añadir cadenas de uso en Info.plist: `NSAppleEventsUsageDescription` (control de Safari para
      el Referer y de Finder para comentarios). Manejar el consentimiento TCC con elegancia
      (la función debe degradar bien si el usuario la deniega).
- [ ] Usar **marcadores con ámbito de seguridad** (*security-scoped bookmarks*) para recordar la
      carpeta de descargas elegida por el usuario.

**Criterio de salida:** la app no toca archivos globales, pide permisos correctamente y funciona
con Hardened Runtime activado.

---

## Fase 5 — Firma, notarización y distribución  🔴 *(bloqueante para distribuir)*

**Objetivo:** que la app pase Gatekeeper en máquinas de usuarios.

- [ ] **Firmar** la app y el binario `wget` empaquetado con un certificado **Developer ID
      Application** (firma anidada del *helper*).
- [ ] Activar **Hardened Runtime**.
- [ ] **Notarizar** con `notarytool` y **grapar** el ticket (`stapler staple`).
- [ ] Empaquetar en `.dmg` o `.pkg` firmado.
- [ ] Verificar en una máquina limpia con `spctl -a -vv` y `codesign --verify --deep --strict`.
- [ ] Actualizar metadatos del bundle: `CFBundleVersion`, `CFBundleShortVersionString`,
      `CFBundleIdentifier` real (no el `${PRODUCT_NAME:identifier}` por defecto),
      `LSMinimumSystemVersion` al objetivo elegido.

**Criterio de salida:** la app instalada desde el `.dmg` arranca sin advertencias de Gatekeeper en
macOS Tahoe.

---

## Fase 6 — Calidad, pruebas y mantenimiento  🟡

- [ ] Pruebas manuales del *parsing* de progreso con el formato de salida de wget actual
      (`--progress=dot:binary`) — verificar que `parseDownloadingProgress:` sigue siendo correcto.
- [ ] Probar: descarga simple HTTPS, reanudación, recursiva, FTP pasivo, proxy, autenticación,
      expansión secuencial de URLs y arrastrar/soltar.
- [ ] Revisar **fugas y *races*** del manejo de `NSPipe`/notificaciones con Instruments.
- [ ] Pruebas en **Apple Silicon e Intel** (universal).
- [ ] Documentar el proceso de *build* reproducible (incluido el de wget) en el README.
- [ ] (Opcional) Tests automatizados de las utilidades puras (`parseURL:`, `expandSequencialURL:`,
      `validateURL:`, construcción de argumentos).

---

## Decisiones a tomar

Estas decisiones afectan al alcance de varias fases; conviene resolverlas pronto.

1. **¿Cómo proveer wget?**
   - **(A)** Seguir empaquetando un wget universal compilado por nosotros *(menos cambios de
     código; más trabajo de build y de firma/notarización del helper)*.
   - **(B)** Sustituir el motor de descarga por **`libcurl`/`URLSession`** nativo *(elimina el
     subproceso y el problema del binario, pero implica reescribir gran parte de `DownloadItem`)*.
   - **(C)** Depender de un wget instalado por el usuario (Homebrew) *(frágil; mala experiencia)*.
   - *Recomendación:* (A) a corto plazo para desbloquear; valorar (B) como objetivo a largo plazo.

2. **¿Canal de distribución?** Mac App Store (sandbox estricto, posible rechazo por el helper) vs.
   **Developer ID + notarización** (recomendado para esta app).

3. **¿Objetivo de despliegue mínimo?** macOS 13 Ventura (recomendado) vs. mantener 10.13.

4. **¿Reescritura a Swift/SwiftUI?** Modernización incremental en Objective‑C (rápido) vs.
   reescritura (mayor inversión, mejor futuro).

---

## Resumen por prioridad

| Prioridad | Fase | Por qué |
|---|---|---|
| 🔴 P0 | Fase 1 (wget universal) | Sin esto la app **no descarga nada** en macOS actual. |
| 🔴 P0 | Fase 5 (firma/notarización) | Sin esto **no se puede distribuir**. |
| 🟠 P1 | Fase 2 (APIs/ARC) | Riesgo de *crashes* y de no compilar en SDKs futuros. |
| 🟠 P1 | Fase 4 (sandbox/permisos) | Comportamiento invasivo e incompatible con macOS moderno. |
| 🟠 P1 | Fase 3 (UI / NSDrawer) | Componentes obsoletos que pueden dejar de funcionar. |
| 🟡 P2 | Fases 0 y 6 | Base de proyecto y aseguramiento de calidad. |
