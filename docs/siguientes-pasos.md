# Siguientes pasos

Esto no está hecho y este hito no lo promete. Está aquí para que el diseño no se lea como si ya estuviera.

## Lenguaje huésped

- WASI, para que un módulo compilado de forma ordinaria encuentre ficheros y reloj con los nombres que ya usa el ecosistema. Hoy las herramientas son cuatro funciones del módulo `vlab`, no WASI.
- Cargar Python o JavaScript ya compilados a Wasm (por ejemplo CPython o un intérprete pequeño). Hoy solo corre el subconjunto que el parser acepta.
- Floats, SIMD y llamadas indirectas. El intérprete rechaza esos opcodes. Sin llamadas indirectas no hay un vtable ni un `call_indirect` de un runtime de lenguaje.

## Red

`net_send` no abre un socket. Responde con el `body` guardado en la concesión. Un paso posterior, si se hace, sería un conectador que solo marca destinos ya concedidos y que vive fuera del teorema, detrás del mismo aislamiento de proceso.

## Aislamiento del servidor

Correr `vlab-server` dentro de Firecracker o gVisor, como proceso sin privilegios, con el directorio de datos como único volumen. El modelo de amenazas lo cuenta como una capa que hoy no existe. No convierte el teorema en una prueba sobre el kernel.

## Agentes

El sandbox está orientado a eso: concesión explícita, cuota, directorio propio, registro. No hay un agente, ni un modelo, ni un planificador de herramientas. Un agente futuro sería un cliente de `POST /api/sandboxes` y de `POST /api/sandboxes/<id>/exec`, no un permiso nuevo escondido en el intérprete.
