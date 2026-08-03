# results/forecast_groups/

Forecast metrics aggregated over the scenario groups defined in
`config/Groups-description-pois.xlsx`. These are the files the manuscript's
numbers come from.

| file | written by | covers |
|---|---|---|
| `all_synth_forecast_metrics-pois.mat` | `make_forecast_group.m` | the 140 synthetic runs |
| `all_real_forecast_metrics.mat` | `make_forecast_group_real.m` | the 4 real-incidence runs |

Aggregating weeks −8:0 and dividing by the `nf_p` baseline reproduces
`results/csv/rel_bars_synth.csv` (80 rows) and `rel_bars_real.csv` (64 rows) to
within 5e-07.

## Provenance

These are the originals behind the submitted manuscript, generated in January
2026 (the real file carries a later build date because it was aggregated in
April, from the same January forecasts). A `_det` deterministic variant of every
run exists but is not part of the manuscript — the published results are the
`pois` set throughout.

## Scope of reproducibility

Everything **downstream of the model runs** regenerates exactly: forecasts →
groups → CSVs → figures.

The model runs themselves **cannot** be re-derived. `integrate_model` seeds its
Poisson engine from a one-second wall clock, so those trajectories were never
addressable by any seed — see the Reproducibility section of the top-level
README. The `.mat` files under `results/model_runs/` are the only copy.
