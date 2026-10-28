# vlab

Servicio en Lean 4 (toolchain `v4.35.0`, la misma que [cairn](https://github.com/kidandcat/cairn) y [uvl](https://github.com/kidandcat/uvl)). El proceso habla HTTP/1.1 con `Std.Http.Server`, guarda en un `ShardSet` de cairn y sirve un front compilado con uvl a WebAssembly.

El repositorio es público: [kidandcat/vlab](https://github.com/kidandcat/vlab). No lleva secretos. No hay despliegue a producción: hay un `Dockerfile` y [docs/despliegue.md](docs/despliegue.md).

## Hitos

| Hito | Qué es | Estado |
| --- | --- | --- |
| 0 | Esqueleto: servidor, cairn, front uvl | este árbol |
| 1 | Laboratorio de funciones | pendiente |
| 3 | Sandbox Wasm verificado | este árbol |

El mini SO RISC-V queda descartado: no forma parte de este repositorio. El modelo de amenazas del sandbox está en [docs/modelo-de-amenazas.md](docs/modelo-de-amenazas.md). El informe del hito 3 está en [docs/hito-3.md](docs/hito-3.md). Lo que no se promete está en [docs/siguientes-pasos.md](docs/siguientes-pasos.md).

El informe del hito 0 está en [docs/hito-0.md](docs/hito-0.md).

## Dependencias fijadas

| Paquete | Revisión |
| --- | --- |
| cairn | `543684716dde412bb803702efdf6e6406f435c9d` |
| uvl | `ff2f323df25f2e260c19a28d220c3bf507b033df` |

`lake-manifest.json` repite esas revisiones. Un solo shard (`Epoch.single`): un documento es una clave y cairn rechaza un lote que cruce shards.

## Ejecutar en local

Hace falta `elan` con `leanprover/lean4:v4.35.0`.

```bash
lake update
lake build
lake test
bash scripts/e2e.sh
```

El binario es `.lake/build/bin/vlab-server`.

```bash
.lake/build/bin/vlab-server --data data --host 127.0.0.1 --port 8080 --static web/dist
```

El host por defecto es el loopback. `--host` solo acepta una IPv4. Cada nota es un commit de cairn con `sync` antes de la respuesta.

Sin el front compilado, `GET /` responde en texto que falta `web/build.sh`. El API funciona igual:

```bash
curl -s http://127.0.0.1:8080/health
curl -s -X POST http://127.0.0.1:8080/api/notes \
  -H 'Content-Type: application/json' \
  --data '{"text":"hola"}'
curl -s http://127.0.0.1:8080/api/notes
```

El cuerpo de una nota es un objeto con un solo campo `text` (como mucho 4000 caracteres). El cuerpo HTTP no pasa de 64 KiB. La lista devuelve como mucho 50 notas, de la más antigua a la más nueva.

Un sandbox se crea con un texto de concesión, no con JSON:

```bash
curl -s -X POST http://127.0.0.1:8080/api/sandboxes --data $'fuel 1000\nmemory 131072\ncalls 4\nfs-read\n'
curl -s -X POST http://127.0.0.1:8080/api/sandboxes/ID/exec --data 'example add'
curl -s http://127.0.0.1:8080/api/sandboxes/ID/audit
curl -s -X DELETE http://127.0.0.1:8080/api/sandboxes/ID
```

`example` es `add`, `oob`, `loop` o `host`. `wasm HEX` manda un módulo propio, en hexadecimal, de como mucho 16 KiB.

## Front

Hace falta Emscripten 6.0.12 (`emcc` en el `PATH`), el mismo que usa uvl.

```bash
web/build.sh
node web/smoke-node.cjs web/dist
REQUIRE_FRONT=1 bash scripts/e2e.sh
```

`web/build.sh` está adaptado de `web/build.sh` de uvl en la revisión fijada. El runtime de Lean e `Init` se compilan a Wasm una vez y quedan en `.lake/build/wasm`. La salida es `web/dist/` (`index.html`, `uvl.js`, `uvl.wasm`, `uvl-web.js`).

Abre `http://127.0.0.1:8080/` con el servidor en marcha. El lienzo uvl ejecuta el intérprete en los botones `oob`, `bucle` y `denegar`. El panel de al lado crea sandboxes en el servidor.

## Qué guarda cairn

Un directorio, un fichero `shard-0.cairn`.

- La colección `notes`: id `Ulid`, versión, texto.
- La colección `sandboxes` y las claves `spec:<id>` / `alive:<id>`.
- La colección `aud-<id>`: una línea por intento de host. No se borra al destruir el sandbox.
- La clave `meta:boots`: cuántas veces se ha abierto el directorio.
- El directorio `sandboxes/<id>/`: ficheros del sandbox. Se borra al destruirlo.

Al abrir, el generador de ids se siembra con el mayor id ya guardado, para no emitir uno que ordene antes. Si la colección pasa de 100000 páginas de 64, el proceso se niega a arrancar en vez de adivinar.
