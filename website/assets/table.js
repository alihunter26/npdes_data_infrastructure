// Renders an array-of-objects as a sortable, searchable HTML table.
// rows: [{col: value, ...}, ...] — column order taken from the first row's keys.
function renderDataTable(container, rows, opts) {
  opts = opts || {};
  const searchable = opts.searchable !== false;
  const columns = rows.length ? Object.keys(rows[0]) : [];

  container.innerHTML = "";

  let filtered = rows.slice();
  let sortCol = null;
  let sortDir = 1;

  const controls = document.createElement("div");
  controls.className = "controls";
  let searchInput = null;
  if (searchable) {
    searchInput = document.createElement("input");
    searchInput.type = "search";
    searchInput.placeholder = "Filter rows…";
    controls.appendChild(searchInput);
  }
  const countEl = document.createElement("span");
  countEl.className = "count";
  controls.appendChild(countEl);
  container.appendChild(controls);

  const wrap = document.createElement("div");
  wrap.className = "table-wrap";
  const table = document.createElement("table");
  table.className = "data-table";
  const thead = document.createElement("thead");
  const headRow = document.createElement("tr");
  columns.forEach(col => {
    const th = document.createElement("th");
    th.textContent = col;
    th.addEventListener("click", () => {
      if (sortCol === col) sortDir = -sortDir;
      else { sortCol = col; sortDir = 1; }
      draw();
    });
    headRow.appendChild(th);
  });
  thead.appendChild(headRow);
  const tbody = document.createElement("tbody");
  table.appendChild(thead);
  table.appendChild(tbody);
  wrap.appendChild(table);
  container.appendChild(wrap);

  function isNumericCol(col) {
    return filtered.every(r => {
      const v = r[col];
      return v === null || v === undefined || v === "" || (!isNaN(v) && v !== true && v !== false);
    });
  }

  function cellClass(col, value) {
    if (value === null || value === undefined || value === "") return "empty-val";
    if (!isNaN(value) && value !== "" && typeof value !== "boolean") return "num";
    return "";
  }

  function draw() {
    // filter
    const q = searchInput ? searchInput.value.trim().toLowerCase() : "";
    filtered = rows.filter(r => {
      if (!q) return true;
      return columns.some(c => String(r[c] ?? "").toLowerCase().includes(q));
    });

    // sort
    if (sortCol) {
      const numeric = isNumericCol(sortCol);
      filtered.sort((a, b) => {
        let av = a[sortCol], bv = b[sortCol];
        if (av === null || av === undefined) av = "";
        if (bv === null || bv === undefined) bv = "";
        if (numeric) {
          av = av === "" ? -Infinity : Number(av);
          bv = bv === "" ? -Infinity : Number(bv);
          return (av - bv) * sortDir;
        }
        return String(av).localeCompare(String(bv)) * sortDir;
      });
    }

    // header sort indicators
    Array.from(headRow.children).forEach((th, i) => {
      th.classList.remove("sorted-asc", "sorted-desc");
      if (columns[i] === sortCol) th.classList.add(sortDir === 1 ? "sorted-asc" : "sorted-desc");
    });

    // body
    tbody.innerHTML = "";
    filtered.forEach(r => {
      const tr = document.createElement("tr");
      columns.forEach(col => {
        const td = document.createElement("td");
        const v = r[col];
        td.textContent = (v === null || v === undefined || v === "") ? "—" : v;
        td.className = cellClass(col, v);
        tr.appendChild(td);
      });
      tbody.appendChild(tr);
    });

    countEl.textContent = `${filtered.length.toLocaleString()} of ${rows.length.toLocaleString()} rows`;
  }

  if (searchInput) searchInput.addEventListener("input", draw);
  draw();
}
