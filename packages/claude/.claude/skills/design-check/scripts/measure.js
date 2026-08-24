// 画面の見やすさを「数値で」測る。ブラウザの javascript_tool にそのまま貼る。
//
// 毎回その場で同じ計測コードを書き直していたので束ねた。
// 「見やすくなった気がする」で判断すると外す（8回連続で外した実績がある）ので、
// 直す前と後で同じものを測って比べること。
//
// 幅を変えて測りたいときは、この前に1行足す:
//   const __W = 394;   // スマホ幅
// resize_window は成功を返しても innerWidth が変わらないことがあるため、
// <main> に直接幅を当てて代用する。戻すには __W を渡さずに実行する。
(() => {
  const W = typeof __W !== "undefined" ? __W : null;
  const main = document.querySelector("main");
  if (main) {
    if (W) { main.style.width = main.style.maxWidth = W + "px"; }
    else { main.style.width = main.style.maxWidth = ""; }
  }

  const de = document.documentElement;

  // ⚠️ 出走表は馬を展開すると中に別の table が入る。`thead th` の子孫セレクタだと
  // 入れ子の table のヘッダまで数えて 14→27 になり、colSpan が「ズレている」と
  // 誤検出する（実測で踏んだ）。外側の table だけを見るため `:scope >` で辿る。
  const ownHeaders = (t) => [...t.querySelectorAll(":scope > thead > tr > th")];
  const ownColspans = (t) =>
    [...t.querySelectorAll(":scope > tbody > tr > td[colspan]")]
      .map((td) => Number(td.getAttribute("colspan")));

  // Tailwind が @property で登録する内部変数は初期値が空文字なので、
  // 「未定義」判定に引っかかる（24件出た）。自前のトークンだけ見る。
  const INTERNAL = /^--(tw|default)-/;

  const out = {
    viewport: innerWidth,
    main_width: main ? Math.round(main.getBoundingClientRect().width) : null,

    // A/B: はみ出し。表の中のスクロールは可、ページ全体は不可。
    page_overflow_px: de.scrollWidth - de.clientWidth,
    overflowing: [...document.querySelectorAll("body *")]
      .filter((e) => e.getBoundingClientRect().right > de.clientWidth + 1)
      .slice(0, 8)
      .map((e) => ({
        tag: e.tagName.toLowerCase(),
        cls: (e.className || "").toString().slice(0, 60),
        right: Math.round(e.getBoundingClientRect().right),
        text: (e.textContent || "").trim().slice(0, 24),
      })),

    // D: 日本語のタイポグラフィ。欧文が先頭だと日本語がフォールバックで崩れる。
    // line-height は px で返るので font-size で割って倍率にする（1.7 が基準）。
    body_font: getComputedStyle(document.body).fontFamily.slice(0, 80),
    body_line_height: (() => {
      const s = getComputedStyle(document.body);
      const lh = parseFloat(s.lineHeight), fs = parseFloat(s.fontSize);
      return { px: lh, ratio: fs ? Math.round((lh / fs) * 100) / 100 : null };
    })(),

    // A: 表の列幅と行高。行高が1行だけ突出していたら折り返しが起きている。
    tables: [...document.querySelectorAll("table")]
      .filter((t) => !t.parentElement.closest("table"))   // 入れ子は親側で見る
      .slice(0, 3)
      .map((t) => ({
        header_cells: ownHeaders(t).length,
        colspans: ownColspans(t),          // header_cells と一致していること
        table_width: Math.round(t.getBoundingClientRect().width),
        row_heights: [...t.querySelectorAll(":scope > tbody > tr")]
          .slice(0, 12)
          .map((r) => Math.round(r.getBoundingClientRect().height)),
        col_widths: ownHeaders(t).map((th) => ({
          label: (th.textContent || "").trim().slice(0, 8),
          w: Math.round(th.getBoundingClientRect().width),
          nowrap: getComputedStyle(th).whiteSpace.includes("nowrap"),
        })),
      })),

    // C: 未定義の CSS 変数は透明で描かれて黙って通るので目視では気づけない。
    undefined_vars: (() => {
      const cs = getComputedStyle(de);
      const used = new Set();
      for (const sheet of document.styleSheets) {
        let rules;
        try { rules = sheet.cssRules; } catch { continue; }
        for (const r of rules || []) {
          for (const m of (r.cssText || "").matchAll(/var\((--[\w-]+)/g)) used.add(m[1]);
        }
      }
      for (const e of document.querySelectorAll("[style]")) {
        for (const m of e.getAttribute("style").matchAll(/var\((--[\w-]+)/g)) used.add(m[1]);
      }
      return [...used].filter((v) => !INTERNAL.test(v) && !cs.getPropertyValue(v).trim());
    })(),
  };
  return JSON.stringify(out, null, 1);
})();
