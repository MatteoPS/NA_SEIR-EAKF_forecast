# results/

Everything the pipeline produces. Created automatically by `setup_paths.m`.

| Folder | Written by | Contents |
|---|---|---|
| `model_runs/` | `model_forecast_run.m` | One `<mmdd>_<nickname>.mat` per run: posterior state variables, ensemble forecasts, Kalman gain records, run metadata. |
| `forecasts/` | `make_forecast_metrics[_real].m` | One `*_fore_res_group.mat` (synthetic) or `*_fore_real_stats.mat` (real) per run: per-location, per-week forecast metrics. |
| `forecast_groups/` | `make_forecast_group[_real].m` | `all_synth_forecast_metrics-pois.mat` and `all_real_forecast_metrics.mat`: metrics aggregated over scenario groups. |
| `csv/` | `make_csv_synth.m`, `make_csv_real.m` | `rel_bars_synth.csv`, `rel_bars_real.csv`: the analysis-ready tables used for the figures and for the numbers reported in the manuscript. |
| `csv/` | `src/plotting/export_fan_data.m` | `fan_truth_*.csv`, `fan_forecast_*.csv`: observed trajectories and forecast-ensemble quantiles for the fan plots. |
| `figures/` | `src/plotting/*.R` | Manuscript figures (PDF + PNG). |

#### Please note

The `.mat` files under `model_runs/`, `forecasts/` and `forecast_groups/` are
too large for GitHub's 100 MB upload cap, so they are not tracked (see
`.gitignore`). They are the outputs the manuscript was written from; ask the
authors for a copy. Re-running `run_pipeline` reproduces the findings but not
these files — the model is not bit-reproducible (see the top-level README).

`csv/fan_forecast_*.csv` run to tens of MB and are not tracked either; rebuild
them with `src/plotting/export_fan_data.m`.

The remaining CSVs and all figures **are** tracked, so every figure can be
redrawn without re-running the model.
