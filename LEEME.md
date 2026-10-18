# Tik9 — por dónde empezar

Cliente de **TikTok** para **iOS 9.3.5 de 32 bits (armv7)**, en la misma línea
que Tube9.

> Este fichero es solo un recordatorio. La documentación de verdad es:

| Fichero | Qué contiene |
|---|---|
| **[`README.md`](README.md)** | El manual para quien usa la app: qué hace, cómo se instala, certificados, relay opcional y problemas frecuentes. |
| **[`PROCESO.md`](PROCESO.md)** | El manual del proceso de compilación: Theos + GitHub Actions, el SDK 9.3, la trampa de `liblaunch.tbd` y cómo se publica el `.ipa`. |
| **[`HALLAZGOS.md`](HALLAZGOS.md)** | El registro técnico de qué se comprobó contra TikTok, con lo medido: firma X-Gnarly en C, reproducción directa, qué está bloqueado. |

## Lo importante, en tres líneas

* **La reproducción es directa y autónoma.** La app firma sus peticiones con el
  algoritmo web de TikTok (**X-Gnarly**) portado a C, y reproduce el vídeo con
  la dirección firmada que ya viene dentro del feed. **Sin PC y sin relay.**
* **El relay es opcional**: solo un plan B por HTTP plano si iOS 9 no confía en
  el certificado del CDN o la red corta la conexión.
* **Buscar, comentarios y perfiles no se incluyen**: TikTok los bloquea para
  clientes que no son la app oficial. El feed y los vídeos sí funcionan.
