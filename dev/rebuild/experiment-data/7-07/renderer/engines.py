"""The two candidate renderers, each from template + view model to PDF bytes, deterministic by construction."""
import datetime
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def weasy():
    import jinja2.sandbox
    import weasyprint
    env = jinja2.sandbox.SandboxedEnvironment(autoescape=True)
    tpl = env.from_string(open(os.path.join(HERE, "invoice.html.j2"), encoding="utf-8").read())

    def render(data, copy=False):
        html = tpl.render(d=data, copy=copy)
        # no network, no files outside the template's own: the fetcher refuses everything but the fonts directory
        def fetch(url, timeout=10, ssl_context=None, http_headers=None, allowed_protocols=None):
            path = url.removeprefix("file://")
            if not path.startswith(os.path.join(HERE, "fonts") + "/"):
                raise ValueError("refused: " + url)
            return {"file_obj": open(path, "rb"), "mime_type": "font/otf"}
        return weasyprint.HTML(string=html, base_url=HERE + "/", url_fetcher=fetch).write_pdf()
    return render


def typst():
    import typst as t
    compiler = t.Compiler(os.path.join(HERE, "invoice.typ"), font_paths=[os.path.join(HERE, "fonts")],
                          ignore_system_fonts=True)
    ts = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc).timestamp()

    def render(data, copy=False):
        return compiler.compile(format="pdf", sys_inputs={"data": json.dumps(data, ensure_ascii=False),
                                                          "copy": "true" if copy else "false"}, timestamp=int(ts))
    return render


ENGINES = {"weasyprint": weasy, "typst": typst}
