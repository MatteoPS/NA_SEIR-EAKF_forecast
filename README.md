# Mobility improves epidemic onset forecast skill in a continental scale disease model

This repository accompanies the manuscript *Mobility improves epidemic onset forecast skill in a continental scale disease model* (Perini M, Yamana TK, Shaman J).

<img width="6000" height="3000" alt="plot_NAR_5070_legend" src="https://github.com/user-attachments/assets/49d70187-a311-4a2c-9bce-b0772fc4a2b3" />

---

## Overview

A stochastic, metapopulation **SEIR model** (Susceptible–Exposed–Infectious Reported–Infectious Unreported) coupled with an **Ensemble Adjustment Kalman Filter (EAKF)** for data assimilation and epidemic forecasting across North America. The model captures both commuting-based and flight-based mobility, and runs ensembles of scenarios driven by synthetic or reported COVID-19 incidence.

---

## Quick start

```matlab
run_pipeline
```

That is the whole thing. `run_pipeline` runs every stage end to end and writes
to `results/`. It works from any current folder — there is no need to `cd` into
the project first, and no paths to edit.

Useful variants:

```matlab
run_pipeline('SimRuns', 1:10)                    % a subset of synthetic runs
run_pipeline('RealRuns', 601:604, 'SimRuns', []) % only the real-incidence runs
run_pipeline('Workers', 8)                       % parallel pool size (default 4)
run_pipeline('Stages', ["metrics" "group" "csv"])% reuse existing model runs
run_pipeline('SeedOffset', 100)                  % a different stochastic realisation
```

Then the manuscript bar plots:

```bash
Rscript src/plotting/plot_rel_bars_synth.R
Rscript src/plotting/plot_rel_bars_real.R
```

---

## Pipeline

| Stage | Function | Reads | Writes |
|---|---|---|---|
| 1. Model + forecasts | `model_forecast_run` | `data/`, `config/Runs-description.xlsx` | `results/model_runs/` |
| 2. Forecast metrics | `make_forecast_metrics`, `make_forecast_metrics_real` | `results/model_runs/` | `results/forecasts/` |
| 3. Group metrics | `make_forecast_group`, `make_forecast_group_real` | `results/forecasts/`, `config/Groups-description-pois.xlsx` | `results/forecast_groups/` |
| 4. Export CSVs | `make_csv_synth`, `make_csv_real` | `results/forecast_groups/` | `results/csv/` |
| 5. Figures (R) | `src/plotting/plot_rel_bars_*.R` | `results/csv/` | `results/figures/` |

Run IDs come from `config/Runs-description.xlsx`: **1–140** are the synthetic
scenarios, **601–604** the real-incidence runs.

Each stage is a plain function, so you can also call any of them on their own:

```matlab
make_forecast_metrics      % just redo stage 2 for the synthetic runs
```

---

## Layout

```
run_pipeline.m         entry point — run this
setup_paths.m          resolves every project path; called by every script

config/                the three spreadsheets that define what gets run
  Runs-description.xlsx      one row per run: RunID, nickname, truth, mobility settings
  Truths-description.xlsx    TruthID -> truth file
  Groups-description-pois.xlsx   how runs are grouped for analysis

data/                  all model inputs (see data/README.md)
  mobility/            commuting network + air travel structures
  incidence/           reported COVID-19 incidence
  rng_seeds/           fixed random draws for reproducibility
  truths/              the 35 synthetic epidemics + their summary statistics
  raw/                 source matrices the mobility structures are built from
  gis/, air_travel/    figure inputs

src/
  model/               the SEIR-EAKF model itself
  forecast/            forecast metrics and their aggregation
  export/              CSV export
  truths/              synthetic truth generation
  preprocessing/       one-off scripts that build the data/ inputs
  plotting/            figure scripts (R) + a MATLAB diagnostic script
  utils/               small shared helpers

results/               everything the pipeline produces (see results/README.md)
docs/                  dataset provenance
```

### Reproducibility

Model runs are deterministic. Each run is seeded with `run_id + SeedOffset`,
which fixes both random streams the model uses — MATLAB's (`rand`, `randi`,
`poissrnd`) and the one inside the `integrate_model` MEX. The same call
therefore produces bit-identical output whenever, and on whichever parallel
worker, it executes. Change `SeedOffset` to draw a different stochastic
realisation.

Synthetic truths are seeded the same way, from the digits of the truth id, so
`make_truth` regenerates a given truth exactly. Regenerating a truth
invalidates the runs already scored against it.

### How paths work

Every script starts with

```matlab
paths = setup_paths();
```

which puts `src/` on the MATLAB path and returns a struct of absolute paths
(`paths.population`, `paths.model_runs`, …) resolved relative to `setup_paths.m`
itself. Scripts therefore run from any working folder, and moving the project
requires no edits.

The R scripts do the equivalent: they locate the project root by walking up from
their own file until they find `run_pipeline.m`, so `Rscript`, `source()` and
RStudio's "Run selection" all work.

---

## `src/model/`

| File | Description |
|---|---|
| `model_forecast_run.m` | Core script. For one `run_id`, loads the inputs, runs the SEIR-EAKF assimilation loop day by day, forecasts every week, and saves to `results/model_runs/`. |
| `integrate_model.cpp` | C++ MEX source: one daily time step of the stochastic SEIR model. Daytime/nighttime transmission, commuting flows via `nl`/`part`/`Cave`, Poisson-sampled transitions S→E→Ir/Iu→R. |
| `integrate_model.mexmaca64` | Pre-compiled MEX binary for Apple Silicon. On any other platform run `build_mex` once. |
| `build_mex.m` | Compiles `integrate_model.cpp` for the current platform. |
| `initialize_para.m` | Builds the parameter ensemble `para`, sampling alpha and beta per location from the `parafit` priors and setting Z, D, mu, theta. |
| `checkbound.m` | Non-negativity and population-size constraints on S, E, Ir, Iu at initialisation. |
| `checkbound_para.m` | Parameter bounds after each EAKF update; out-of-range values are re-inflated or clipped (`flact_checkpara`). |
| `checkbound_yesterday.m` | State bounds relative to the previous day, used after reprobe steps. |

## `src/forecast/`

| File | Description |
|---|---|
| `make_forecast_metrics.m` | Ensemble metrics (WIS, AE, MAE, coverage, bias, peak week, onset week) per location and forecast week, for the synthetic runs. |
| `make_forecast_metrics_real.m` | The same for the real-incidence runs, computed per epidemic wave. |
| `calculate_forecast_metrics.m` | The metric definitions themselves, shared by the two scripts above. |
| `make_forecast_group.m` | Bins the per-run metrics by weeks-to-event and averages them within the groups defined in `Groups-description-pois.xlsx`. |
| `make_forecast_group_real.m` | The same for the four real-incidence runs. |

## `src/truths/`

| File | Description |
|---|---|
| `make_truth.m` | Generates one synthetic epidemic by running the SEIR model forward without assimilation. |
| `make_truth_grouped_files.m` | Bundles every truth into `data/truths/all_truths_struct.mat`. |
| `make_truth_stats_and_histogram.m` | Onset/peak statistics across all truths → `data/truths/all_truths_stats.mat`, plus the summary histograms. |

## `src/preprocessing/`

Run these only if the inputs in `data/` need rebuilding — the repository ships
the results already.

| File | Description |
|---|---|
| `make_parafit.m` | Samples the parameter priors → `data/parafit_vars.mat`. Regenerating changes the priors and hence the results. |
| `build_commutedata.m` | Commuting matrix → `nl`, `part`, `C`, `Cave`. Pass `true` for the zero-commuting variant. |
| `build_flightsflow.m` | Air-travel matrix → `nlp`, `partp`, `P`. |

## `src/utils/`

`setup_paths` aside, these smooth over the spreadsheets: `read_runs_table`
imports `Runs-description.xlsx` consistently, and `find_run_row` finds a RunID
whether the column comes back from Excel as numbers or as text.
`benchmark_run` times a single model run.

---

## Data sources

### Annual air passenger travel
- "Monthly Statistics by Origin - Destination 2016" from AFAC, Gobierno de México available via <https://www.gob.mx/cms/uploads/attachment/file/652389/sase-2016-hitorico-10032017.xlsx>
- "Airline Origin and Destination Survey (DB1B) 2016" form US Bureau of Transportation Statistics available via <https://www.transtats.bts.gov/Tables.asp?QO_VQ=EFI&QO_anzr=Nv4yv0r%FDb4vtv0%FDn0q%FDQr56v0n6v10%FDf748rB%FLQOEO%FM&QO_fu146_anzr=b4vtv0%FDn0q%FDQr56v0n6v10%FDf748rB>
- "Air passenger origin and destination, transborder journeys 2016" from Statistics Canada available via <https://doi.org/10.25318/2310025601-eng>

### Daily work commuting
Developed and already published in [Perini et al. 2025](https://doi.org/10.1016/j.epidem.2025.100818)
- Canadian 2016 census (Statistics Canada): Commuting Flow from Geography of Residence to Geography of Work <https://www12.statcan.gc.ca/census-recensement/2016/dp-pd/dt-td/Rp-eng.cfm?TABID=4&LANG=E&A=R&APATH=3&DETAIL=0&DIM=0&FL=A&FREE=0&GC=0&GL=-1&GID=1354564&GK=0&GRP=1&O=D&PID=111333&PRID=10&PTYPE=109445&S=0&SHOWALL=0&SUB=0&Temporal=2017&THEME=125&VID=0&VNAMEE=&VNAMEF=%20(2017)&D1=0&D2=0&D3=0&D4=0&D5=0&D6=0>
- Canada Frontier Counts (Statistics Canada): Number of vehicles travelling between Canada and the United States <https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=2410000201>
- 5-Year American Community Survey (ACS) (United States Census Bureau) Commuting Flows <https://www.census.gov/data/tables/2015/demo/metro-micro/commuting-flows-2015.html>
- Mexican Intercensal Survey 2015 (National Institute of Statistics and Geography, INEGI) <https://en.www.inegi.org.mx/programas/intercensal/2015/#Microdatos>

### COVID-19 reported cases
- COVID-19 case data from various public sources available via <https://health.google.com/covid-19/open-data/data-sources>

---

## Dependencies

- **MATLAB** with the Parallel Computing Toolbox (for `parfor`)
- **C++ compiler** compatible with MATLAB MEX — only to recompile `integrate_model.cpp`; pre-compiled macOS binaries are included
- **R** for the figure scripts: `ggplot2`, `ggpattern`, `dplyr`, `patchwork`, `cowplot`, `viridis`; plus `sf` for the maps and `reshape2`, `geosphere`, `tidygeocoder` for the air-travel heatmap
- **ImageMagick** (`magick`) — only for the PNG conversion at the end of `plot_maps_NA.R`

## Large files

Model runs, forecast files and grouped metrics are far past GitHub's 100 MB cap
and are not tracked; regenerate them with `run_pipeline` or request a copy. The
CSVs in `results/csv/` and the figures **are** tracked, so the figures can be
reproduced without re-running the model.
