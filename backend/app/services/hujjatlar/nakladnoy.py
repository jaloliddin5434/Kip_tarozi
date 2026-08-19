import logging
from pathlib import Path

from playwright.sync_api import sync_playwright

from app.core.config import settings
from app.models.partiya import Partiya

logger = logging.getLogger("nakladnoy")

YUK_JONATUVCHI = '"XAZORASP TEXTIL" MCHJ'


def nakladnoy_raqami_yarat(partiya: Partiya) -> str:
    return f"NK-{partiya.id:06d}"


def _son(qiymat: float | None) -> str:
    return f"{qiymat:.2f}" if qiymat is not None else "—"


def _html_qur(partiya: Partiya, mahsulot_nomi: str, kip_soni: int) -> str:
    sana = partiya.sotuv_sanasi.strftime("%d.%m.%Y") if partiya.sotuv_sanasi else "—"

    return f"""<!doctype html>
<html lang="uz">
<head>
<meta charset="utf-8">
<style>
  body {{ font-family: Arial, "Segoe UI", sans-serif; font-size: 13px; color: #111; margin: 32px; }}
  h1 {{ text-align: center; font-size: 17px; margin: 0 0 6px; }}
  .sana {{ text-align: center; margin-bottom: 24px; color: #333; }}
  table.info {{ width: 100%; margin-bottom: 18px; border-collapse: collapse; }}
  table.info td {{ padding: 4px 0; vertical-align: top; }}
  table.info td.label {{ width: 220px; font-weight: bold; }}
  table.jadval {{ width: 100%; border-collapse: collapse; margin-top: 12px; }}
  table.jadval th, table.jadval td {{ border: 1px solid #333; padding: 8px 6px; text-align: center; font-size: 11.5px; }}
  table.jadval th {{ background: #f0f0f0; }}
  .jami-qator td {{ font-weight: bold; }}
  .imzo-qatori {{ display: flex; justify-content: space-between; margin-top: 70px; }}
  .imzo {{ width: 30%; border-top: 1px solid #333; padding-top: 4px; text-align: center; font-size: 11px; color: #333; }}
</style>
</head>
<body>
  <h1>ТОВАР ТРАНСПОРТ НАКЛАДНОЙ № {partiya.nakladnoy_raqami}</h1>
  <div class="sana">{sana}</div>

  <table class="info">
    <tr><td class="label">Yuk jo'natuvchi:</td><td>{YUK_JONATUVCHI}</td></tr>
    <tr><td class="label">Yuk oluvchi:</td><td>{partiya.xaridor or '—'}</td></tr>
    <tr><td class="label">Dogovor raqami:</td><td>{partiya.dogovor_raqami or '—'}</td></tr>
  </table>

  <table class="jadval">
    <thead>
      <tr>
        <th>Mahsulot nomi</th>
        <th>Marka<br>(partiya raqami)</th>
        <th>Sort</th>
        <th>Soni</th>
        <th>Urama bilan<br>birga vazni (kg)</th>
        <th>Urama (kg)</th>
        <th>Sof og'irlik<br>netto (kg)</th>
        <th>Kondicion<br>vazni (kg)</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>{mahsulot_nomi}</td>
        <td>#{partiya.partiya_raqami}</td>
        <td>{partiya.sort or '—'}</td>
        <td>{kip_soni}</td>
        <td>{_son(partiya.urama_bilan_vazn)}</td>
        <td>{_son(partiya.urama_vazni)}</td>
        <td>{_son(partiya.sof_vazn)}</td>
        <td>{_son(partiya.kondicion_vazni)}</td>
      </tr>
      <tr class="jami-qator">
        <td colspan="6">Jami</td>
        <td>{_son(partiya.sof_vazn)}</td>
        <td>{_son(partiya.kondicion_vazni)}</td>
      </tr>
    </tbody>
  </table>

  <div class="imzo-qatori">
    <div class="imzo">Yuk jo'natuvchi</div>
    <div class="imzo">Yuk oluvchi</div>
    <div class="imzo">Bosh buxgalter</div>
  </div>
</body>
</html>"""


def nakladnoy_pdf_yarat(partiya: Partiya, mahsulot_nomi: str, kip_soni: int) -> str | None:
    """Partiya sotilganda chaqiriladi (nakladnoy_raqami allaqachon o'rnatilgan
    bo'lishi kerak). HTML shablonni Playwright orqali PDF'ga aylantirib,
    STORAGE_PATH/nakladnoy/<nakladnoy_raqami>.pdf'ga yozadi va shu papkaga
    nisbatan yo'lni qaytaradi (bazaga shu saqlanadi — rasm_saqla bilan bir xil
    konvensiya)."""
    if not partiya.nakladnoy_raqami:
        logger.error("nakladnoy_pdf_yarat: partiya #%s uchun nakladnoy_raqami hali o'rnatilmagan", partiya.id)
        return None

    html = _html_qur(partiya, mahsulot_nomi, kip_soni)

    papka = Path(settings.STORAGE_PATH) / "nakladnoy"
    papka.mkdir(parents=True, exist_ok=True)
    yoli = papka / f"{partiya.nakladnoy_raqami}.pdf"

    with sync_playwright() as p:
        brauzer = p.chromium.launch()
        try:
            sahifa = brauzer.new_page()
            sahifa.set_content(html)
            sahifa.pdf(path=str(yoli), format="A4", print_background=True)
        finally:
            brauzer.close()

    logger.info("Nakladnoy PDF yaratildi: partiya #%s -> %s", partiya.partiya_raqami, yoli)
    return str(yoli.relative_to(settings.STORAGE_PATH)).replace("\\", "/")
