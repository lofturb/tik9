# -*- coding: utf-8 -*-
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probar import peticion, params_item_detalle

item_id = sys.argv[1] if len(sys.argv) > 1 else "7106594312292453675"
_, cuerpo, _, _ = peticion("/api/item/detail/", params_item_detalle(item_id))
v = json.loads(cuerpo)["itemInfo"]["itemStruct"]["video"]
urls = {"playAddr": v.get("playAddr"), "downloadAddr": v.get("downloadAddr")}
for bi in (v.get("bitrateInfo") or []):
    if (bi.get("CodecType") or "").lower() == "h264":
        u = ((bi.get("PlayAddr") or {}).get("UrlList") or [None])[0]
        if u:
            urls["h264_" + str(bi.get("GearName"))] = u
base = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(base, "urls.json"), "w") as f:
    json.dump(urls, f, indent=1)
print("URLs guardadas en urls.json")
print()
print("playAddr cruda (primeros 700):")
print((v.get("playAddr") or "")[:700])
