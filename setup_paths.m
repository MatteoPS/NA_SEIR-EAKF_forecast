function paths = setup_paths()
%SETUP_PATHS  Put the project on the MATLAB path and return every project path.
%
%   paths = setup_paths()
%
% Every script in this project starts with this call. It does two things:
%
%   1. Adds src/ (and all its subfolders) to the MATLAB search path, so the
%      model, forecast and plotting functions can be called from anywhere.
%   2. Returns a struct of ABSOLUTE paths to every input file and output
%      folder, resolved relative to this file's own location.
%
% Because the paths are absolute and anchored to setup_paths.m, scripts work
% from any current folder.
%
% Output folders under results/ are created on demand.
%
% See also RUN_PIPELINE.

root = fileparts(mfilename('fullpath'));

%% ---- MATLAB search path -------------------------------------------------
% (idempotent: addpath on an already-present folder is a no-op)
addpath(root);
addpath(genpath(fullfile(root, 'src')));

%% ---- folders ------------------------------------------------------------
paths           = struct();
paths.root      = root;
paths.config    = fullfile(root, 'config');
paths.data      = fullfile(root, 'data');
paths.results   = fullfile(root, 'results');
paths.docs      = fullfile(root, 'docs');

paths.truths          = fullfile(paths.data, 'truths');
paths.raw             = fullfile(paths.data, 'raw');
paths.gis             = fullfile(paths.data, 'gis');
paths.air_travel      = fullfile(paths.data, 'air_travel');

paths.model_runs      = fullfile(paths.results, 'model_runs');
paths.forecasts       = fullfile(paths.results, 'forecasts');
paths.forecast_groups = fullfile(paths.results, 'forecast_groups');
paths.csv             = fullfile(paths.results, 'csv');
paths.figures         = fullfile(paths.results, 'figures');

%% ---- configuration tables (config/) -------------------------------------
paths.runs_description   = fullfile(paths.config, 'Runs-description.xlsx');
paths.truths_description = fullfile(paths.config, 'Truths-description.xlsx');
paths.groups_description = fullfile(paths.config, 'Groups-description-pois.xlsx');

%% ---- model input data (data/) -------------------------------------------
paths.population        = fullfile(paths.data, 'population.mat');
paths.statecodes        = fullfile(paths.data, 'statecodes.mat');
paths.statecodes_csv    = fullfile(paths.data, 'statecodes.csv');
paths.parafit_vars      = fullfile(paths.data, 'parafit_vars.mat');

paths.commutedata       = fullfile(paths.data, 'mobility', 'commutedata.mat');
paths.commutedata_zeros = fullfile(paths.data, 'mobility', 'commutedata_ZEROS.mat');
paths.flightsflow       = fullfile(paths.data, 'mobility', 'flightsflow.mat');

paths.incidence_real    = fullfile(paths.data, 'incidence', 'dailyincidence_real.csv');

paths.fix_para          = fullfile(paths.data, 'rng_seeds', 'fix_para.mat');
paths.fix_rand_matrix   = fullfile(paths.data, 'rng_seeds', 'fix_rand_matrix.mat');
paths.fix_randi_reprobe = fullfile(paths.data, 'rng_seeds', 'fix_randi_reprobe.mat');

% truth summaries (produced by src/truths/)
paths.truth_struct      = fullfile(paths.truths, 'all_truths_struct.mat');
paths.truth_stats       = fullfile(paths.truths, 'all_truths_stats.mat');
paths.real_stats        = fullfile(paths.truths, 'real_stats.mat');

% raw matrices used to rebuild the mobility structures (src/preprocessing/)
paths.raw_commuting_matrix = fullfile(paths.raw, 'final_commuting_matrix_Oct2023.csv');
paths.raw_air_flow_matrix  = fullfile(paths.raw, 'Matrix-air-flow-sep04.csv');

%% ---- pipeline output files ----------------------------------------------
paths.synth_group_file = fullfile(paths.forecast_groups, 'all_synth_forecast_metrics-pois.mat');
paths.real_group_file  = fullfile(paths.forecast_groups, 'all_real_forecast_metrics.mat');
paths.csv_synth        = fullfile(paths.csv, 'rel_bars_synth.csv');
paths.csv_real         = fullfile(paths.csv, 'rel_bars_real.csv');

%% ---- make sure the output folders exist ---------------------------------
out_dirs = {paths.model_runs, paths.forecasts, paths.forecast_groups, ...
            paths.csv, paths.figures};
for k = 1:numel(out_dirs)
    if ~isfolder(out_dirs{k})
        % [~,~] swallows the "already exists" warning if two parallel
        % workers race to create the same folder
        [~, ~] = mkdir(out_dirs{k});
    end
end

end
