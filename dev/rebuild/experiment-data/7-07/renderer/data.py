"""The invoice view model as erp/billing formats it (30 lines; Chinese, Western diacritics and the euro sign)."""


def view_model(n=30):
    lines = [{"no": i + 1, "code": f"P-{i:04d}", "name": f"螺丝 M6×{20 + i} Café Niño Größe €", "quantity": "12",
              "unit": "EA", "unit_price": "1,234.50", "net": "14,814.00", "tax_rate": "13%", "tax": "1,925.82"}
             for i in range(n)]
    return {"invoice": {"number": "INV-SH-2026-000123", "date": "2026年10月23日", "currency": "CNY"},
            "seller": {"name": "上海示例有限公司", "code": "SH"},
            "buyer": {"name": "北京客户股份有限公司 (Société Générale)", "tax_id": "91310000MA1FL0XX0X"},
            "lines": lines,
            "totals": {"net": "444,420.00", "tax": "57,774.60", "gross": "502,194.60",
                       "gross_in_words": "人民币伍拾万贰仟壹佰玖拾肆元陆角整"}}
