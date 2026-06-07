"""Generate 4 simplified GitLab login-showcase skeleton mockups (1280x800).

Same layout skeleton (left sidebar + tanuki logo + project list ghost),
varying only accent intensity / gradient strength / mood.
"""

# Abstract GitLab "tanuki" mark — stylized triangle cluster, not a pixel copy.
def build_logo(c_dark: str, c_mid: str, c_light: str) -> str:
    return f"""<svg width="26" height="24" viewBox="0 0 28 26" aria-hidden="true">
  <polygon points="5,1 2,11 8,11"   fill="{c_dark}"/>
  <polygon points="23,1 26,11 20,11" fill="{c_dark}"/>
  <polygon points="14,1 8,11 20,11"  fill="{c_mid}"/>
  <polygon points="2,11 8,11 14,24"  fill="{c_light}"/>
  <polygon points="26,11 20,11 14,24" fill="{c_light}"/>
  <polygon points="8,11 20,11 14,24"  fill="{c_dark}"/>
</svg>"""


# (name, accent, logo dark/mid/light, gradient-tint rgba, second-accent for dots)
VARIANTS = [
    ("1", "#FC6D26", ("#E24329", "#FC6D26", "#FCA326"), "rgba(252,109,38,0.10)", "#FC6D26"),
    ("2", "#FC6D26", ("#E24329", "#FC6D26", "#FCA326"), "rgba(252,109,38,0.06)", "#FCA326"),
    ("3", "#E24329", ("#C9362A", "#E24329", "#FC6D26"), "rgba(252,109,38,0.17)", "#E24329"),
    ("4", "#FC6D26", ("#E24329", "#FC6D26", "#FCA326"), "rgba(110,73,203,0.11)",  "#6E49CB"),
]

FONT = ('-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,'
        'sans-serif')


def bar(w, h=10, c="#e9eaed", r=6, mb=0, ml=0):
    return (f'<div style="width:{w};height:{h}px;background:{c};border-radius:{r}px;'
            f'margin-bottom:{mb}px;margin-left:{ml}px"></div>')


def nav_item(accent, active=False):
    icon_bg = accent if active else "#e3e4e8"
    txt_w = "60%" if active else f"{50 + (hash(str(accent+str(active)))%30)}%"
    bg = "rgba(0,0,0,0.04)" if active else "transparent"
    return (f'<div style="display:flex;align-items:center;gap:12px;padding:9px 12px;'
            f'border-radius:8px;background:{bg};margin-bottom:4px">'
            f'<div style="width:18px;height:18px;border-radius:5px;background:{icon_bg};'
            f'flex:none"></div>{bar(txt_w,9,"#cfd1d6" if not active else "#9a9ca3")}</div>')


def project_row(accent, second):
    pills = "".join(
        f'<div style="display:flex;align-items:center;gap:6px">'
        f'<div style="width:9px;height:9px;border-radius:50%;background:{second}">'
        f'</div>{bar("26px",8,"#dadce0")}</div>' for _ in range(3))
    return f"""<div style="display:flex;align-items:center;gap:16px;padding:16px 4px;
        border-bottom:1px solid #eef0f2">
      <div style="width:38px;height:38px;border-radius:9px;flex:none;
        background:linear-gradient(135deg,{accent},{second});opacity:.92"></div>
      <div style="flex:1">
        <div style="display:flex;align-items:center;gap:10px;margin-bottom:9px">
          {bar("180px",11,"#c4c6cc")}{bar("46px",10,"#edeef0")}
        </div>
        {bar("72%",8,"#e6e7ea",6,7)}{bar("54%",8,"#eceef0")}
      </div>
      <div style="display:flex;gap:16px;flex:none">{pills}</div>
    </div>"""


def build(name, accent, logo_cols, tint, second):
    logo = build_logo(*logo_cols)
    nav = (nav_item(accent, True)
           + "".join(nav_item(accent) for _ in range(6)))
    rows = "".join(project_row(accent, second) for _ in range(5))
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
*{{margin:0;padding:0;box-sizing:border-box;font-family:{FONT}}}
html,body{{width:1280px;height:800px}}
.canvas{{width:1280px;height:800px;padding:30px;
  background:linear-gradient(135deg,{tint} 0%,#f5f5f7 60%)}}
.app{{width:100%;height:100%;background:#fff;border:1px solid #e0e0e0;
  border-radius:18px;box-shadow:0 8px 24px rgba(0,0,0,0.04);
  display:flex;overflow:hidden}}
.side{{width:236px;flex:none;border-right:1px solid #ededf0;
  background:#fcfcfd;padding:20px 14px;display:flex;flex-direction:column}}
.brand{{display:flex;align-items:center;gap:10px;padding:4px 8px 22px}}
.wordmark{{font-size:19px;font-weight:700;color:#1f1f24;letter-spacing:-.2px}}
.main{{flex:1;padding:30px 38px;display:flex;flex-direction:column}}
.head{{display:flex;align-items:center;justify-content:space-between;
  margin-bottom:22px}}
.title{{font-size:22px;font-weight:700;color:#25252b;letter-spacing:-.3px}}
.search{{width:300px;height:34px;border-radius:9px;background:#f1f2f4;
  border:1px solid #e9eaed}}
.cta{{height:34px;padding:0 18px;border-radius:9px;background:{accent};
  display:flex;align-items:center}}
.cta div{{width:78px;height:10px;border-radius:5px;background:rgba(255,255,255,.85)}}
.avatar{{width:34px;height:34px;border-radius:50%;
  background:linear-gradient(135deg,{accent},{second})}}
</style></head><body>
<div class="canvas"><div class="app">
  <div class="side">
    <div class="brand">{logo}<span class="wordmark">GitLab</span></div>
    {nav}
    <div style="margin-top:auto;display:flex;align-items:center;gap:10px;
      padding:8px;border-top:1px solid #ededf0;padding-top:16px">
      <div class="avatar" style="width:26px;height:26px"></div>
      {bar("60%",9,"#d4d6db")}
    </div>
  </div>
  <div class="main">
    <div class="head">
      <div style="display:flex;align-items:center;gap:16px">
        <span class="title">Projects</span>
        <div class="search"></div>
      </div>
      <div style="display:flex;align-items:center;gap:16px">
        <div class="cta"><div></div></div>
        <div class="avatar"></div>
      </div>
    </div>
    {rows}
  </div>
</div></div>
</body></html>"""


if __name__ == "__main__":
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    for v in VARIANTS:
        name = v[0]
        with open(os.path.join(here, f"mock-{name}.html"), "w") as f:
            f.write(build(*v))
        print(f"wrote mock-{name}.html")
