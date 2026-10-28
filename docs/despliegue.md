# Despliegue

No está desplegado. El `Dockerfile` construye el binario nativo y deja el proceso escuchando en el puerto 8080, dentro del contenedor, con los datos en `/data`. No es una configuración de producción.

## Qué hace la imagen

- Ubuntu 24.04, elan, toolchain `v4.35.0`.
- `lake update` y `lake build leanlab-server` con las revisiones fijadas de cairn y uvl.
- Usuario `leanlab` (uid 10001), sin shell de login.
- El proceso escucha en `0.0.0.0:8080` solo dentro de la red del contenedor. En la máquina, el binario sigue en `127.0.0.1` si no se pasa `--host`.

El front Wasm no se compila en la imagen. Si el contexto de build trae `web/dist/`, se copia y el servidor lo sirve. Si no, `GET /` dice que falta el front y el API sigue respondiendo.

## Construir

Hace falta un daemon de Docker. En el entorno donde se escribió el hito 0 no había Docker, así que esta imagen no se ha construido ni ejecutado aquí.

```bash
docker build -t leanlab:dev .
docker run --rm -p 127.0.0.1:8080:8080 -v leanlab-data:/data leanlab:dev
```

El puerto publicado queda en el loopback del host. No abras `0.0.0.0` en una máquina alcanzable desde fuera.

## Lo que falta antes de producción

- Un proxy que termine TLS. El servidor habla HTTP/1.1 en claro.
- Límites de tasa. El hito 0 solo limita el tamaño del cuerpo y de la nota.
- Un usuario y una red aún más estrechos que este contenedor: sin capabilities de más, sistema de ficheros de solo lectura salvo `/data`, y un runtime de aislamiento (gVisor o Firecracker) si el proceso llega a ejecutar algo que no sea este binario. El hito 2 lo escribe con la base de confianza del sandbox; aquí el proceso es el servidor Lean, no un intérprete de código ajeno.
- Copias y supervisión del directorio de datos. cairn hace `fdatasync` por commit en el shard local. Eso no sustituye una copia fuera de la máquina.
- No hay secreto en la imagen. No metas tokens en el contexto de build.
