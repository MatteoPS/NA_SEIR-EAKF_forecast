function run_pipeline(varargin)
%RUN_PIPELINE  Main entry point: run the SEIR-EAKF model and build every output.
%
%   run_pipeline                              % all runs, 4 workers
%   run_pipeline('SimRuns', 1:10)             % a subset of synthetic runs
%   run_pipeline('RealRuns', 601:604)         % only the real-incidence runs
%   run_pipeline('Workers', 8)                % change the parallel pool size
%   run_pipeline('Stages', ["metrics" "group" "csv"])   % skip the model runs
%
% Stages, in order:
%   "model"    model_forecast_run             -> results/model_runs/
%   "metrics"  make_forecast_metrics[_real]   -> results/forecasts/
%   "group"    make_forecast_group[_real]     -> results/forecast_groups/
%   "csv"      make_csv_synth / make_csv_real -> results/csv/
%
% The bar-plot figures are produced separately with R:
%   Rscript src/plotting/plot_rel_bars_synth.R
%   Rscript src/plotting/plot_rel_bars_real.R
%
% Run IDs are defined in config/Runs-description.xlsx (synthetic 1-140,
% real incidence 601-604).

paths = setup_paths();

%% ---- options ------------------------------------------------------------
opts = inputParser;
addParameter(opts, 'SimRuns',  1:140);
addParameter(opts, 'RealRuns', 601:604);
addParameter(opts, 'Workers',  4);
addParameter(opts, 'Stages',   ["model" "metrics" "group" "csv"]);
parse(opts, varargin{:});

sim_runs  = opts.Results.SimRuns;
real_runs = opts.Results.RealRuns;
workers   = opts.Results.Workers;
stages    = string(opts.Results.Stages);

mmdd = datestr(datetime('now'), 'mmdd');   %#ok<DATST> % prefix for output filenames

%% ---- stage 1: model runs + forecasts ------------------------------------
if ismember("model", stages)
    run_ids = [sim_runs real_runs];
    runs_description = read_runs_table(paths);

    nickname = cell(numel(run_ids), 1);
    for k = 1:numel(run_ids)
        nickname{k} = runs_description.nickname{find_run_row(runs_description, run_ids(k))};
    end

    fprintf('\n=== Stage 1/4: model runs (%d runs, %d workers) ===\n', ...
        numel(run_ids), workers);
    start_time = datetime('now');

    if isempty(gcp('nocreate')), parpool(workers); end

    runtime = cell(1, numel(run_ids));   % pre-allocated for parfor slicing
    parfor (k = 1:numel(run_ids), workers)
        loop_start = datetime('now');

        model_forecast_run(run_ids(k), mmdd);

        runtime{k} = format_duration(seconds(datetime('now') - loop_start));
        fprintf('\nCompleted run %d: %s in (%s)\n', run_ids(k), nickname{k}, runtime{k});
    end

    disp(table(run_ids(:), nickname, runtime(:), ...
        'VariableNames', {'RunID', 'nickname', 'runtime'}));
    fprintf('\nTotal model runtime: %s\n', ...
        format_duration(seconds(datetime('now') - start_time)));
end

%% ---- stage 2: forecast metrics, one file per run ------------------------
if ismember("metrics", stages)
    fprintf('\n=== Stage 2/4: forecast metrics ===\n');
    make_forecast_metrics();        % synthetic runs
    make_forecast_metrics_real();   % real-incidence runs
end

%% ---- stage 3: aggregate metrics into groups -----------------------------
if ismember("group", stages)
    fprintf('\n=== Stage 3/4: grouping forecast metrics ===\n');
    make_forecast_group();          % groups defined in Groups-description-pois.xlsx
    make_forecast_group_real();     % the 4 real runs together
end

%% ---- stage 4: analysis-ready CSVs ---------------------------------------
if ismember("csv", stages)
    fprintf('\n=== Stage 4/4: exporting CSVs ===\n');
    make_csv_synth();
    make_csv_real();
end

fprintf('\nDone. Outputs are under %s\n', paths.results);

end

%% -------------------------------------------------------------------------
function str = format_duration(total_seconds)
h = floor(total_seconds / 3600);
m = floor(mod(total_seconds, 3600) / 60);
s = mod(total_seconds, 60);
str = sprintf('%dh %dm %.3fs', h, m, s);
end
