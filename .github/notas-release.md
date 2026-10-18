Cliente de TikTok ligero y moderno para **iOS 9.3.5 de 32 bits (armv7)**:
iPhone 4S, iPhone 5 y 5C, iPad 2, 3 y 4, iPad mini 1 y iPod touch 5G.

## Qué trae esta versión

* **Feed «Para ti» vertical**, a pantalla completa, con **un vídeo por pantalla**:
  deslizar arriba y abajo cambia de vídeo, un toque lo pausa y lo reanuda.
  El listado se **pagina solo** (pide más vídeos cuando llegas a los últimos).
* **Reproducción directa, sin relay ni PC.** La app firma las peticiones a
  TikTok con el algoritmo web (**X-Gnarly**, portado a C) y reproduce el vídeo
  con la **dirección firmada que ya viene dentro del propio feed**. No hace
  falta ningún servidor encendido.
* **Favoritos**: toca el corazón de un vídeo y se guarda en su pestaña. Desde
  ahí se reproduce **a pantalla completa** o se quita (también deslizando).
* **Compartir** cualquier vídeo con las apps instaladas (enlace + descripción).
* **Ajustes** con lo imprescindible:
  * **Modo de reproducción**: *Automático* (recomendado), *Solo directo* o
    *Solo relay*.
  * **Relay opcional**: dirección y token, con un botón **Probar el relay**.
  * **Cookies de TikTok** (opcionales) y **Probar el feed** y **Olvidar
    dispositivo y cookies**.
  * **Tema**: dos fondos (oscuro y claro) por varios colores de botones.
  * **Cómo funciona**, explicado dentro de la propia app.
* **Interfaz plana, tipografía del sistema e iconos dibujados por código**
  (vectoriales, sin ficheros de imagen). Cero desenfoques y cero animaciones
  caras: todo eso funciona mal en un chip A5.

## Por qué el relay es opcional

Todo el trabajo ocurre **en el propio teléfono**: la app firma aquí el feed y
usa la dirección de vídeo que TikTok ya le ha dado firmada. El CDN de TikTok
sólo exige la cabecera `Referer: https://www.tiktok.com/`, que la app pone.

El **relay** (`relay/servidor.py`, solo biblioteca estándar de Python 3) queda
como **plan B**: sirve si iOS 9 no confía en el certificado del CDN, o si tu
red corta la conexión. Se activa desde Ajustes y **no es obligatorio en ningún
caso**.

## Qué no trae (y por qué)

TikTok **bloquea para clientes que no son la app oficial**: buscar,
comentarios y perfiles devuelven respuestas vacías. Como no se puede fingir lo
que no hay, esas pestañas **no se incluyen**; el feed y los vídeos sí
funcionan. La app lo explica sin rodeos en **Ajustes → Cómo funciona**.

## Cómo instalarlo

1. El dispositivo necesita **jailbreak** y **AppSync Unified** (se instala
   desde Cydia).
2. Copia el `.ipa` adjunto al dispositivo y tócalo desde **Filza** (o usa
   `ipainstaller Tik9.ipa` por SSH).
3. Instala el perfil
   **`certificados/CertificadosModernos.mobileconfig`** del repositorio,
   abriéndolo desde Safari con la dirección del PC en la red local: iOS 9.3.5
   no conoce las autoridades de certificación modernas (Let's Encrypt, Google,
   DigiCert, Amazon…) y, sin ese paso, no hay conexión con TikTok.

El paso a paso completo, la guía de certificados, el **modo relay** y los
problemas frecuentes están en el
[README](https://github.com/lofturb/tik9#readme).

## Comprobar la descarga (opcional)

```powershell
python tools\verificar_ipa.py entrega\Tik9.ipa
```

Debe contestar `armv7`, `minimo 9.0` y `pseudo-firmado`.

---

> Tik9 no es una aplicación oficial de TikTok ni está afiliada a ByteDance.
> Accede al contenido por los mismos servicios web que usa la web de TikTok,
> así que siguen aplicándose las
> [Condiciones de Servicio de TikTok](https://www.tiktok.com/legal/terms-of-service).
> Proyecto educativo y de uso personal.
