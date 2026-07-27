// Renders the year-coverage cross-tab: one row per (file, variable), one column
// per year, cell = observation count. Mirrors the heatmap in the source workbook:
// each row is colored independently, bucketed into 5 quantile tiers (R's
// quantile(..., type = 1), matching summarize_year_coverage.R exactly).
const YC_GRADIENT = ["#FFFFCC", "#C2E699", "#78C679", "#31A354", "#006837"];

// R's quantile(x, probs, type = 1): x_{ceil(n*p)} for p in (0,1], x_1 for p = 0.
function quantileType1(sortedVals, p) {
  const n = sortedVals.length;
  if (p <= 0) return sortedVals[0];
  const idx = Math.min(n, Math.ceil(n * p));
  return sortedVals[idx - 1];
}

function rowBuckets(counts, years) {
  const nonzero = years.map(y => counts[y]).filter(v => v !== undefined && v > 0).sort((a, b) => a - b);
  const buckets = {};
  if (nonzero.length === 0) return buckets;
  const breaks = [];
  for (let i = 0; i <= 5; i++) breaks.push(quantileType1(nonzero, i / 5));
  years.forEach(y => {
    const v = counts[y];
    if (v === undefined || v <= 0) return;
    let b = 5;
    for (let i = 1; i <= 5; i++) { if (v <= breaks[i]) { b = i; break; } }
    buckets[y] = b;
  });
  return buckets;
}

function renderYearCoverageTable(container, data) {
  const years = data.years;
  const rows = data.rows;

  container.innerHTML = "";

  const controls = document.createElement("div");
  controls.className = "controls";
  const searchInput = document.createElement("input");
  searchInput.type = "search";
  searchInput.placeholder = "Filter by file or variable…";
  controls.appendChild(searchInput);
  const countEl = document.createElement("span");
  countEl.className = "count";
  controls.appendChild(countEl);
  container.appendChild(controls);

  const wrap = document.createElement("div");
  wrap.className = "table-wrap yc-wrap";
  const table = document.createElement("table");
  table.className = "data-table yc-table";

  const thead = document.createElement("thead");
  const headRow = document.createElement("tr");
  ["File", "Variable"].forEach(h => {
    const th = document.createElement("th");
    th.textContent = h;
    th.className = "yc-sticky";
    headRow.appendChild(th);
  });
  years.forEach(y => {
    const th = document.createElement("th");
    th.textContent = y;
    headRow.appendChild(th);
  });
  thead.appendChild(headRow);
  table.appendChild(thead);

  const tbody = document.createElement("tbody");
  table.appendChild(tbody);
  wrap.appendChild(table);
  container.appendChild(wrap);

  function draw() {
    const q = searchInput.value.trim().toLowerCase();
    const filtered = rows.filter(r => !q || r.file.toLowerCase().includes(q) || r.variable.toLowerCase().includes(q));

    tbody.innerHTML = "";
    let lastFile = null;
    let fileCellRef = null;
    let fileRunLength = 0;

    filtered.forEach((r, i) => {
      const buckets = rowBuckets(r.counts, years);
      const tr = document.createElement("tr");

      if (r.file !== lastFile) {
        const td = document.createElement("td");
        td.textContent = r.file;
        td.className = "yc-sticky yc-file";
        tr.appendChild(td);
        fileCellRef = td;
        fileRunLength = 1;
        lastFile = r.file;
      } else {
        fileRunLength++;
        fileCellRef.rowSpan = fileRunLength;
      }

      const varTd = document.createElement("td");
      varTd.textContent = r.variable;
      varTd.className = "yc-sticky yc-var";
      tr.appendChild(varTd);

      years.forEach(y => {
        const td = document.createElement("td");
        const v = r.counts[y];
        if (v !== undefined && v > 0) {
          td.textContent = v.toLocaleString();
          td.className = "num";
          td.style.background = YC_GRADIENT[buckets[y] - 1];
          if (buckets[y] >= 4) td.style.color = "#fff";
        }
        tr.appendChild(td);
      });

      tbody.appendChild(tr);
    });

    countEl.textContent = `${filtered.length.toLocaleString()} of ${rows.length.toLocaleString()} rows`;
  }

  searchInput.addEventListener("input", draw);
  draw();
}
