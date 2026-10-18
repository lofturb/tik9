# -*- coding: utf-8 -*-
"""
Localiza la URL del webmssdk que sirve TikTok (la que pone los parametros de
firma y el msToken) leyendo el JSON 'tiktok-environment' de una pagina real.
"""

import json
import os
import re
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36")


def get(url, limite=5_000_000):
    req = urllib.request.Request(url, headers={
        "User-Agent": UA, "Accept": "text/html,*/*",
        "Accept-Language": "en-US,en;q=0.9", "Referer": "https://www.tiktok.com/"})
    with urllib.request.urlopen(req, timeout=45) as r:
        return r.read(limite).decode("utf-8", "replace")


def main():
    page = get("https://www.tiktok.com/@tiktok/video/7106594312292453675")
    print("pagina: %d bytes" % len(page))

    # 1) JSON de entorno
    m = re.search(r'<script id="tiktok-environment" type="application/json">(.*?)</script>', page, re.S)
    if m:
        env = json.loads(m.group(1))
        print("tiktok-environment:")
        print(json.dumps(env, indent=1)[:1500])
    else:
        print("no hay tiktok-environment")

    # 2) cualquier URL de sdk / mssdk / webmssdk
    print("\nURLs candidatas de SDK:")
    vistos = set()
    for u in re.findall(r'https?://[^"\'\\\s<>]+', page):
        if re.search(r'(webmssdk|mssdk|sdk\.js|sign|verify)', u, re.I) and u not in vistos:
            vistos.add(u)
            print(" ", u)

    # 3) todas las de .js del propio tiktok
    print("\nscripts .js en la pagina (hasta 25):")
    for u in re.findall(r'src="(https?://[^"]+\.js[^"]*)"', page)[:25]:
        print(" ", u)


if __name__ == "__main__":
    main()
