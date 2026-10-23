#let d = json(bytes(sys.inputs.data))
#let copy = sys.inputs.at("copy", default: "false") == "true"
#set document(title: "Invoice " + d.invoice.number)
#set page(paper: "a4", margin: (x: 15mm, y: 18mm), footer: context align(right, text(8pt, counter(page).display("1 / 1", both: true))))
#set text(font: "Noto Sans CJK SC", size: 9pt, lang: "zh")
#if copy { place(top + right, text(fill: rgb("#c00"), weight: "bold", "副本 COPY")) }
#align(center, text(16pt, weight: "bold", "销售发票 Invoice"))
#v(4mm)
#grid(columns: (1fr, 1fr),
  [号码 #d.invoice.number \ 日期 #d.invoice.date \ 币种 #d.invoice.currency],
  [销售方 #d.seller.name \ 购买方 #d.buyer.name \ 税号 #d.buyer.tax_id])
#v(4mm)
#table(columns: (auto, auto, 1fr, auto, auto, auto, auto, auto, auto), stroke: 0.5pt + rgb("#444"),
  align: (x, y) => if x in (3, 5, 6, 7, 8) { right } else { left },
  table.header(..("#", "代码", "名称", "数量", "单位", "单价", "金额", "税率", "税额").map(h => table.cell(fill: rgb("#eee"), strong(h)))),
  ..d.lines.map(l => (str(l.no), l.code, l.name, l.quantity, l.unit, l.unit_price, l.net, l.tax_rate, l.tax)).flatten(),
  table.cell(colspan: 6, strong("合计 Total")), strong(d.totals.net), [], strong(d.totals.tax),
  table.cell(colspan: 6, strong("价税合计 " + d.totals.gross_in_words)), table.cell(colspan: 3, align: right, strong(d.totals.gross)),
)
