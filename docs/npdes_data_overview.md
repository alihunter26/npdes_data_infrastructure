# NPDES Data Documentation

## Overview

The EPA's NPDES data downloads through ECHO provide records from ICIS covering
facilities, permits, inspections, enforcement actions, violations, and quarterly
noncompliance history. The national dataset is split into two files — the first
covering general compliance and enforcement information, and the second containing
effluent violations. Discharge monitoring reports are available separately, both by
jurisdiction and by fiscal year going back to before 2009.

Notably, the downloads do **not** include the specific pollutant limits written into
each permit or water quality data from receiving waterways. Those require separate
tools within ECHO.

## Definitions

- **NPDES** — National Pollutant Discharge Elimination System
- **DMR** — Discharge Monitoring Report
- **ICIS** — Integrated Compliance Information System (the EPA database the downloads are drawn from)
- **ECHO** — Enforcement and Compliance History Online (the public-facing portal for the data)
- **NAICS** — North American Industry Classification System (the modern industry-code system)
- **SIC** — Standard Industrial Classification (the older industry-code system)
- **RNC** — Reportable Noncompliance
- **EFF** — Effluent (used here for the effluent-violations file)

---

## ICIS-NPDES National Dataset (Part 1)

15 CSV files drawn from ICIS covering the core components of the NPDES program,
including facility and permit records, four types of violations, inspection and
enforcement actions, industry classifications, spatial coordinates, and a quarterly
noncompliance history going back to the 1970s.

### Facility & Permit Information
- **ICIS_FACILITIES** — core registry of every regulated facility, with location and basic info
- **ICIS_PERMITS** — detailed permit records, including status, flow, receiving water body, and key dates
- **NPDES_PERM_COMPONENTS** — describes the individual components that make up each permit
- **NPDES_DATA_GROUPS** — categorizes permits by type; useful for filtering

### Spatial Data
- **NPDES_PERM_FEATURE_COORDS** — geographic coordinates for specific discharge points and outfalls

### Industry Classification
- **NPDES_NAICS** — links permits to industry type using the modern NAICS system
- **NPDES_SICS** — links permits to industry type using the older SIC system

### Violations
- **NPDES_CS_VIOLATIONS** — failures to meet compliance schedule deadlines
- **NPDES_PS_VIOLATIONS** — failures to meet permit schedule milestones (mostly administrative)
- **NPDES_SE_VIOLATIONS** — discrete one-off violation events, like spills or bypasses
- **NPDES_QNCR_HISTORY** — quarterly noncompliance records going back decades; best for trend analysis

### Enforcement
- **NPDES_FORMAL_ENFORCEMENT_ACTIONS** — serious legal actions, such as court orders and penalties
- **NPDES_INFORMAL_ENFORCEMENT_ACTIONS** — lower-level actions, such as warning letters and notices of violation
- **NPDES_VIOLATION_ENFORCEMENTS** — bridge table linking violations to enforcement actions

### Compliance Monitoring
- **NPDES_INSPECTIONS** — logs all facility inspections, who conducted them, and the outcome

---

## ICIS-NPDES National Dataset (Part 2 — Effluent Violations)

One large (~15 GB) file containing every instance where a facility's discharge
monitoring report (DMR) showed a pollutant reading that exceeded its permitted limit.

**Each row:** a single parameter violation — one pollutant, at one discharge point,
during one monitoring period.

Effluent violations are generated automatically and continuously: every month, every
permitted facility submits a DMR, and every measurement is checked against its limit.
With around 50,000 active NPDES facilities, this produces a very large file.

**Total entries: 46,361,587**

| Violation Code | n | Description |
|---|---:|---|
| **D80** | 22,176,683 | The facility failed to submit required monitoring data for a given parameter |
| **D90** | 20,771,765 | The facility failed to submit monitoring data for a parameter that has a specific numeric limit in its permit |
| **E90** | 3,413,139 | The facility reported a discharge measurement that exceeded the limit set in its permit |

**Most violations come from missing data**, not from measured exceedances — the two
non-reporting codes (D80 and D90) together account for the large majority of rows.

**Note:** the `EXCEEDENCE_PCT` variable name is misspelled in the source data (it should
read "exceedance").

---

## Master General Permits

Permits covering entire categories of similar facilities rather than a single site.
- **Ex.** stormwater, agricultural, drinking water

**Important info:** facility type, permit, issuing agency.

**Missing info:** geographic/location data, and the bodies of water affected.

---

## ICIS-NPDES Discharge Points — NPDES_OUTFALLS_LAYER

A pre-joined, analysis-ready file that combines facility information, permit details,
compliance status, and geographic coordinates into a single flat table. It contains the
same data found in the master ICIS-NPDES files, but joined together and extended with
geographic coordinates (though not much water or policy data).

**Each row:** one permitted discharge point — a specific physical location where a
facility is authorized to release water — combined with a snapshot of that facility's
current permit and compliance status.

Note that the spatial data describes each **discharge point**, not the facility as a
whole. The file is a snapshot representative of the time of download: it has no dates and
is **not** time-series data.

**Missing info:** detailed information on the violations themselves.

---

## National Permit Limit Dataset — NPDES_LIMITS

The numeric discharge limits written into each permit.

**Each row:** one specific limit, for one pollutant, at one discharge point, under one
permit, during one time period.

**Important info:** pollutant parameter, numeric limit value, unit of measurement, limit
type (daily maximum vs. monthly average), monitoring frequency, effective date range, and
seasonal applicability by month.

**Missing info:** the reported discharge (i.e., what the facility actually measured).

---

## DMR Data — NPDES_DMRS_FY2025

Every self-reported discharge measurement in fiscal year 2025.

**Each row:** a reported measurement for one pollutant, at one discharge point, during
one monitoring period, paired with the corresponding permit limit.

**Important info:** the reported measurement value, the permit limit it's compared
against, the statistical basis of the measurement (maximum, average, etc.), the
monitoring period, and the outfall.

**Missing info:** facility names/locations, and type of industry.

### NPDES Monitoring Data

A per-facility report showing the legal limits on what a facility can release into the
water, what it actually measured, and whether it stayed within bounds. This is the permit
limit and DMR data joined together for a specific facility.

- Organized by outfall — the monitoring location, i.e., the physical point where the facility releases water
- Selected by facility (NPDES ID) and date range
- Each file (per location) has multiple outfall points
- Columns are the type of pollutant
- Includes statistical information (whether a value is a maximum, an average, etc.)

**Missing info:** data before 2007, and enforcement actions.

---

## Violations (Glossary)

- **Compliance Schedule Violation** — a facility failed to meet a specific deadline or
  milestone that was negotiated with the regulatory agency and written into a *separate*
  schedule outlining the steps the facility must take to come into full compliance with
  its permit.

- **Permit Schedule Violation** — a facility failed to meet a deadline or milestone that
  was built directly into the terms of the *permit itself*, rather than outlined in a
  separate compliance agreement.

- **Single Event Violation** — a facility committed a discrete, one-time violation of its
  permit conditions, such as an accidental spill, an unauthorized discharge, or a bypass
  of its treatment system.

- **Reportable Noncompliance (RNC)** — a violation serious enough that the EPA or state
  agency is required to formally track and report it. The facility has crossed a threshold
  of noncompliance that triggers regulatory attention and potential enforcement.

- **Effluent Violation** — a facility discharged a pollutant into a waterway at a
  concentration or volume that exceeded the numeric limits set in its permit, meaning the
  water leaving the facility was dirtier than the law allows.
