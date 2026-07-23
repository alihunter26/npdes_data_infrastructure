# NPDES Permitting

**Introduction.** This brief covers the scope of National Pollutant Discharge Elimination System (NPDES) permitting under
the Clean Water Act (CWA), how a permit is classified within that scope (individual vs.
general, and major vs. minor), and how those classifications show up in the ICIS-NPDES
(ECHO) data this project uses. Also covers the Master General Permits download,
enforcement patterns by permit type, the 2015 Electronic Reporting Rule, and why many projects restrict to major individual permits.

## 1. Scope

NPDES (CWA § 402) requires a permit for the discharge of a pollutant from a **point
source** into waters of the United States. A point source is defined as any discernible, confined and discrete conveyance, including pipes, ditches, and vessels. Several major
discharge categories are not regulated under NPDES:

- **Nonpoint source pollution** — runoff not channeled through a discrete
  conveyance (general agricultural field runoff, most urban/lawn runoff not routed
  through a regulated storm sewer, atmospheric deposition). It is addressed through CWA § 319 nonpoint source management grants, which have no permitting mechanism.
- **Agricultural stormwater and irrigation return flows** — excluded from the statutory
  definition of "point source" itself (CWA § 502(14)), even when somewhat channeled (e.g.
  field drainage). Animal feeding operations are not permitted under NPDES, but facilities designated as concentrated animal feeding operations are permitted.
- **Silvicultural (forestry) nonpoint runoff** — ordinary forestry runoff is excluded,
  though certain forest-road discharges through a discrete conveyance can still count as
  a point source.
- **Dredge-and-fill activities** — regulated under a different CWA provision (§ 404,
  Army Corps of Engineers), not § 402/NPDES.
- **Zero-discharge facilities** — a facility with no discharge to a jurisdictional water
  (pure land application, fully contained operations) has nothing to permit, since
  there's no point-source discharge in the first place.

Contested boundaries:

- **Groundwater** — historically treated as largely outside NPDES, but *County of Maui
  v. Hawaii Wildlife Fund* (2020) held a discharge reaching surface water via groundwater
  can require a permit if it's the "functional equivalent of a direct discharge" — a
  fact-specific test, not a bright line.
- **"Waters of the United States" (WOTUS)** — which water bodies count as jurisdictional
  at all has been repeatedly redefined by rule and litigation across administrations; a
  discharge to a water outside the current WOTUS definition is outside NPDES regardless
  of point-source status.

## 2. Individual vs. General Permits

Within that scope, the CWA provides two vehicles for issuing an NPDES permit.


An **individual permit** is written for one specific facility. Its effluent limits combine
technology-based limits (national, by industry) with **water-quality-based limits derived
from the specific receiving water**, so two identical dischargers can face different
limits. It requires a full, facility-specific application (40 CFR § 122.21) and carries
facility-specific monitoring and reporting (DMR) obligations. Individual permits are for larger, more complex dischargers, such as municipal treatment plants and major
industrial sources.


A **general permit** (40 CFR § 122.28) is a single template permit the permitting
authority issues once to cover **many similar, lower-risk dischargers** at once
(construction and industrial stormwater, CAFOs, small or short-lived operations). A
facility obtains coverage by filing a **Notice of Intent (NOI)** against the master
permit. Under general permits, conditions are standardized and monitoring is lighter or absent; one master general permit can cover hundreds of thousands of individual coverages (§4 below).

**Permit term:** Both permit types are capped at the same
statutory maximum — 40 CFR § 122.46 limits any NPDES permit, individual or general, to a
fixed term not exceeding five years. Reissuing one general permit covers every facility under it at once, so general permits are almost always issued for the full five years, while an individual permit's specific term (and whether it's reissued on time or instead runs on under administrative continuance) depends on that facility's own permitting history.

**Representative general-permit programs:** EPA's Multi-Sector General Permit (MSGP)
covers stormwater discharges from industrial facilities across roughly thirty sectors in
areas where EPA is the permitting authority; the Construction General Permit (CGP) covers
stormwater from construction sites disturbing ≥1 acre with a pathway to a water of the US.
CAFOs are typically covered under state- or EPA-issued general permits as well.


The practical trade-off is specificity vs. administrative cost: individual permits are
tailored but resource-intensive; general permits are efficient but coarse.

## 3. Facility size: major vs. minor

Independent of *how* a permit is issued (§2), every permit also carries a **major/minor**
designation.


EPA's major/minor designation comes from a point-based rating system (originally the
Municipal/Industrial Strategic Initiative rating) that scores factors like discharge flow
volume, toxic-pollutant potential, and the public-health and water-quality impact of the
receiving water. Facilities crossing the point threshold are designated **major**. For municipal treatment plants, facilities with a design flow of roughly ≥ 1 million gallons per day are typically treated as major. In practice, this means closer EPA/state oversight, more frequent inspections, and — per §6 below — the primary population where formal enforcement and SNC tracking concentrate. Major status is re-evaluated over a permit's life and can change between reissuances (hence "ever major," used throughout this brief, rather than a permanent label).

**DMR reporting frequency**is where major/minor status shows up most directly in the data. Major permits typically require **monthly** numeric effluent monitoring and DMR submission across every permitted parameter, since majors carry the facility-specific technology-based and water-quality-based limits described in §2. Minor permits usually specify a much lighter cadence — quarterly, semi-annual, or even annual — and many minor facilities covered under a general permit have no numeric DMR obligation at all, submitting only a periodic certification of best-management-practice compliance rather than measured effluent values. This reporting-frequency gap is the direct mechanical cause of the ~84% vs ~7% DMR coverage split already noted in §4, and it's also why the 2015 Electronic Reporting Rule's phased rollout (§7) treated individual/major data as Phase 1 and general/minor data as Phase 2: there was simply far less minor-facility DMR data to migrate to electronic reporting in the first place.

**Major and minor cut across both permit vehicles, asymmetrically:**

| Vehicle | Total permits | Ever major | Ever minor | % ever major |
|---|---:|---:|---:|---:|
| `NPD` (individual) | 99,940 | 7,800 | 92,140 | 7.8% |
| `GPC` (general) | 1,029,666 | 95 | 1,029,571 | 0.009% |
| Other codes (`UFT`/`IIU`/`APR`/`SIN`/`NGP`/`SNN`) | 64,424 | 167 | 64,257 | 0.26% |

- **Major status is common among individual permits (7.8%) and vanishingly rare among
  general permits (0.009%)** — it's not just that most majors happen to be individual,
  it's that being individually permitted in the first place is strongly associated with
  being major, and the reverse is nearly never true for general-permit coverages.

## 4. Distinction in the dataset

- **Permit-type codes:** `PERMIT_TYPE_CODE` marks the vehicle: `NPD` = individual, `GPC` =
  a facility's coverage under a general permit, `NGP` = the general permit itself (the
  master record, not a covered facility). The remaining codes (`UFT`, `IIU`, `APR`, `SIN`, `SNN`) are minor, low-volume variants (state-issued or non-NPDES-equivalent records).

  | Code | Permits (distinct) | Records (all versions) |
  |---|---:|---:|
  | `GPC` | 1,029,666 | 1,368,680 |
  | `NPD` | 99,940 | 242,678 |
  | `UFT` | 46,360 | 46,360 |
  | `IIU` | 7,315 | 11,105 |
  | `APR` | 5,901 | 16,382 |
  | `SIN` | 3,573 | 6,562 |
  | `NGP` | 1,232 | 2,823 |
  | `SNN` | 41 | 56 |

  *Permits* = distinct `EXTERNAL_PERMIT_NMBR` values (one row per permit); *Records* = raw
  rows in `ICIS_PERMITS.csv` (one row per permit *version* — reissuances and modifications
  each add a row). The gap matters: general-permit coverages (`GPC`) outnumber individual
  permits roughly ten to one on either count, but reissuance behavior differs — **51.9%**
  of individual permits carry more than one version (a permit keeps its `NPDES_ID` across
  ~5-year reissuances), versus **21.8%** of general-permit coverages, which are more often
  **renumbered** when the master permit is reissued (e.g. an `NDR100000`-cycle coverage
  becomes an `NDR110000`-cycle coverage under a new ID) rather than versioned under the
  same one.

- **Facility identity:** Individual permits map cleanly to a single physical site with a
  reliable FRS registry ID (`FACILITY_UIN`) and point geocode. General permits frequently
  **share one generic `FACILITY_UIN`** across unrelated sites. This makes facility-level
  aggregation reliable for individual permits and hazardous for general ones.

- **Multiple permits:** 10,362 `FACILITY_UIN`s hold both an individual (`NPD`) and a
  general (`GPC`) permit — typically an individually permitted process discharge and a
  general stormwater coverage at the same site. The two permits govern different
  discharges, not the same one, so they shouldn't be collapsed into a single
  "one facility, one permit" record.

- **Data richness:** Monitoring and enforcement are concentrated on the individual/major
  side. In FY2025 DMR data, majors appear at ~84% reporting coverage vs. ~7% for minors —
  consistent with general permits' lighter-to-absent numeric monitoring requirements.

## 5. The Master General Permits download

The 2,823 `NGP` master records don't come from the main 15-table ICIS-NPDES bundle
(`npdes_downloads.zip`) — they have their own **separate** download:
`npdes_master_general_permits.zip`, fetched from
`https://echo.epa.gov/files/echodownloads/npdes_master_general_permits.zip`.

- **One row per master permit** (2,823 total, all `PERMIT_TYPE_CODE = "NGP"`) — this
  file is *only* the master templates, not the millions of individual coverages.
- **Extra descriptive fields not needed for a coverage record**— `PERMIT_NAME` (e.g.
  `"Hawaii Master General Permit Noncontact Cooling Waters"`), `ISSUING_AGENCY`,
  `ORIGINAL_ISSUE_DATE`/`ISSUE_DATE`/`EFFECTIVE_DATE`/`EXPIRATION_DATE`, and the same
  `EXTERNAL_PERMIT_NMBR` that appears as the target of `MASTER_EXTERNAL_PERMIT_NMBR`
  on `GPC` records in the main `ICIS_PERMITS.csv`.

- **`MASTER_EXTERNAL_PERMIT_NMBR` is (almost) always blank in this file itself** —
  51 of 2,823 rows are an exception and have it populated, worth a closer look before
  treating "blank = top-level master" as an absolute rule.

## 6. Enforcement patterns by permit type

Formal vs. informal enforcement action records, by permit type and major/minor status
(all years, all actions in the bulk enforcement files; each row is one action record,
not one facility):

| Permit type | Status | Formal | Informal | Total | % Informal |
|---|---|---:|---:|---:|---:|
| Individual | Minor | 42,307 | 351,145 | 393,452 | 89.2% |
| General | Minor | 23,313 | 237,934 | 261,247 | 91.1% |
| Individual | Major | 30,942 | 179,192 | 210,134 | 85.3% |
| Other | Unknown | 12,748 | 27,885 | 40,633 | 68.6% |
| Other | Minor | 1,406 | 24,147 | 25,553 | 94.5% |
| General | Unknown | 513 | 427 | 940 | 45.4% |
| Other | Major | 279 | 526 | 805 | 65.3% |
| General | Major | 59 | 596 | 655 | 91.0% |
| Individual | Unknown | 249 | 125 | 374 | 33.4% |

Pooling across major/minor status, individual permits accrue **603,960** action records
(12.2% formal / 87.8% informal) and general permits **262,842** (9.1% formal / 90.9%
informal). The two permit types look broadly similar in their formal/informal *split*,
but arrive there by different detection pathways:

- **Individual permits** (mostly majors) generate violations chiefly through routine DMR
  review (numeric effluent-limit exceedances) and scheduled inspections. Individual/major
  permittees are also the population to which EPA's **significant noncompliance (SNC)**
  criteria are principally applied: since 1995, EPA policy has defined SNC to include,
  among other triggers, any monthly average effluent limit exceeded by ≥40% (or by ≥20%
  for two or more consecutive months), any limit violated for four or more months in a
  two-consecutive-quarter window, unauthorized bypass/pass-through, and reporting
  violations 30+ days late. These criteria presuppose numeric monthly DMR limits — exactly
  what individual permits carry and general permits typically do not — which is why SNC
  tracking is substantively an individual/major-permit concept rather than a
  general-permit one.
- **General permits** have less routine numeric monitoring, so violations more often
  surface through inspections, failure to file the NOI or other required paperwork, or
  complaints, rather than a DMR exceedance. Consistent with this, the response is more
  often informal (90.9% vs. 87.8% for individual). The Director's authority to revoke
  general-permit coverage and require an individual permit (§2 above; 40 CFR
  § 122.28(b)(3)) is the formal escalation path when a covered facility turns out to
  warrant closer, facility-specific regulation.

## 7. The 2015 NPDES Electronic Reporting Rule

EPA's NPDES Electronic Reporting Rule took effect **December 21, 2015**, replacing
paper-based NPDES reporting with mandatory electronic submission, with the stated goal of
more complete, timely, and nationally consistent compliance data. Implementation was
phased: **Phase 1** (largely individual-permit DMR data) had a compliance deadline of
December 21, 2016; **Phase 2** (general-permit and other remaining data streams) was
originally due December 21, 2020 but was later extended by rule, giving affected programs
up to five additional years. This phased rollout is the mechanism behind the "2016 eRule"
reporting break already flagged in this project's data documentation
(`docs/data_quirks.md`): majors' DMR coverage was already high before the rule, while
minors' and general-permit coverage only began rising as Phase 1, and later Phase 2,
requirements took hold — so pre- and post-2016 (and pre/post-2020+) coverage are not
directly comparable, particularly for general-permit-covered dischargers.

## 8. Implications for analysis

For facility-level research, the individual permit is the meaningful analytical unit: one
physical site, a stable identifier, dense measurement, and a trustworthy location. The
general permit is best understood as an **administrative umbrella, not a facility** — a
single `FACILITY_UIN` or master permit number can span hundreds of unrelated sites, and
monitoring/enforcement data is comparatively sparse. Restricting to major individual
permits, as most academic projects do, produces a well-defined and well-measured population. However, it excludes the large majority of permitted dischargers,
which are general, lightly monitored, and (per §6) usually resolved informally rather than
through the DMR/inspection/SNC pipeline that individual permits generate.

