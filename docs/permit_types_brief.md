# General vs. Individual NPDES Permits: Concept and Data

**Scope.** How the Clean Water Act's two NPDES permit vehicles differ conceptually, and how that
distinction shows up in the ICIS-NPDES (ECHO) data used in this project.

## 1. The regulatory distinction

An **individual permit** is written for one specific facility. Its effluent limits combine
technology-based limits (national, by industry) with **water-quality-based limits derived from the
specific receiving water**, so two identical dischargers can face different limits. It requires a
full application, is issued for a ~5-year term, and carries facility-specific monitoring and
reporting (DMR) obligations. Individual permits are the norm for larger, more complex dischargers —
municipal treatment plants and major industrial sources.

A **general permit** is a single template permit the permitting authority issues to cover **many
similar, lower-risk dischargers** at once (construction and industrial stormwater, CAFOs, small or
short-lived operations). A facility obtains coverage by filing a **Notice of Intent (NOI)** against
the master permit rather than negotiating its own. Conditions are standardized, monitoring is lighter
or absent, and the relationship is **one-to-many**: one master general permit → hundreds or thousands
of coverages.

The practical trade-off is specificity vs. administrative cost: individual permits are tailored but
resource-intensive; general permits are efficient but coarse.

## 2. How the distinction appears in this dataset

- **Permit-type codes.** `PERMIT_TYPE_CODE` marks the vehicle: `NPD` = individual, `GPC` =
  general-permit covered (plus a master `GPG` and minor types). General-permit records dominate the
  file — roughly **1.37M `GPC` vs. 243k `NPD`** permit records — even though individual permits carry
  most of the regulatory content.

- **Major status tracks the individual vehicle.** "Major" facilities are almost exclusively
  individually permitted: **~97% of major permits are individual** (7,800 of ~8,060). Restricting to
  major *and* individual yields a clean population of **7,710 facilities**.

- **Facility identity.** Individual permits map cleanly to a single physical site with a reliable FRS
  registry ID (`FACILITY_UIN`) and point geocode. General permits frequently **share one generic
  `FACILITY_UIN`** across unrelated sites — e.g., a single North Dakota UIN spans **361 distinct
  general permits** (construction-stormwater projects in different cities). This makes facility-level
  aggregation safe for individual permits but hazardous for general ones.

- **Both at once.** About **10,362 facilities hold both** an individual and a general permit
  (~6,500 as a clean one-individual-plus-one-general pair) — typically an individually permitted
  process discharge plus a general stormwater coverage. The two permits govern *different* discharges,
  not the same one.

- **ID persistence over time.** An individual permit keeps its **same NPDES_ID across ~5-year
  reissuances** (recorded as new versions; 52% of individual permits have >1 version). General-permit
  coverages are often **renumbered** when the master permit is reissued (e.g., an `NDR100000`-cycle
  coverage becomes an `NDR110000`-cycle coverage).

- **Data richness.** Monitoring and enforcement are concentrated on the individual/major side. In
  FY2025 DMR data, **majors appear at 84% coverage vs. 7% for minors**, with ~700 vs. ~266 monitoring
  records per reporting facility. Formal enforcement is likewise concentrated on individual/major
  facilities; general-permit sites show mostly informal actions or none.

## 3. Implication for analysis

For facility-level research, the individual permit is the meaningful unit: one site, stable ID,
dense measurement, trustworthy location. The general permit is an **administrative umbrella, not a
facility**. Filtering to major individual permits (~7,710 facilities) buys a well-defined,
well-measured population — at the cost of external validity, since it excludes the large majority of
permits, which are general, lightly monitored, and lightly enforced.

---
*Figures computed from this project's ICIS-NPDES bulk files (`data/raw/npdes_downloads/`) and the
FY2025 DMR extract; rounded. Reproducible from the permit/facility/enforcement tables.*
