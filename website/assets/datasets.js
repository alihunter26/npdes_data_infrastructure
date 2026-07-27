// Registry of datasets shown on the site. Kept separate from the per-dataset
// JSON (data/<key>.json) so the summary/index cards don't need to fetch all
// seven files just to list them.
const DATASETS = [
  {
    key: "npdes",
    name: "ICIS-NPDES Core Tables",
    blurb: "All 15 core ICIS-NPDES bulk tables: facilities, permits, violations (compliance-schedule, permit-schedule, single-event), formal & informal enforcement, inspections, QNCR history, violation–enforcement links, NAICS/SIC, permit components & feature coordinates, and data groups. Each table is its own tab.",
    source: "EPA ICIS-NPDES"
  },
  {
    key: "dmrs",
    name: "Discharge Monitoring Reports (DMRs)",
    blurb: "FY2025 DMR parameter/limit submissions: reported discharge values against permitted limits.",
    source: "EPA ICIS-NPDES"
  },
  {
    key: "attains",
    name: "ATTAINS Water Quality Links",
    blurb: "Links NPDES facilities to ATTAINS assessment units, impairment status, and catchments.",
    source: "EPA ATTAINS"
  },
  {
    key: "limits",
    name: "NPDES Permit Limits",
    blurb: "Numeric discharge limits written into each permit: one row per pollutant limit, at one outfall, for one effective period.",
    source: "EPA ICIS-NPDES"
  },
  {
    key: "master_general_permits",
    name: "Master General Permits",
    blurb: "General permits (e.g. stormwater, CAFO) that individual facilities certify coverage under.",
    source: "EPA ICIS-NPDES"
  },
  {
    key: "outfalls_layer",
    name: "NPDES Outfalls (Spatial Layer)",
    blurb: "One row per permitted discharge point (outfall), with location and permit status.",
    source: "EPA ICIS-NPDES"
  },
  {
    key: "eff_violations_va",
    name: "Effluent Violations — Virginia",
    blurb: "DMR parameter/limit violations for Virginia facilities (NPDES_ID starting with 'VA').",
    source: "EPA ICIS-NPDES"
  },
  {
    key: "eff_violations_ny",
    name: "Effluent Violations — New York",
    blurb: "DMR parameter/limit violations for New York facilities (NPDES_ID starting with 'NY').",
    source: "EPA ICIS-NPDES"
  }
];
