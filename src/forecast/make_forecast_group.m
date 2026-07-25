function make_forecast_group()
%MAKE_FORECAST_GROUP  Aggregate synthetic forecast metrics into scenario groups.
%
%   make_forecast_group()
%
% Bins the per-run metrics in results/forecasts/ by weeks-to-event and
% averages them within the groups defined in config/Groups-description-pois.xlsx.
% Writes results/forecast_groups/all_synth_forecast_metrics-pois.mat.
%
% Run MAKE_FORECAST_METRICS first.
%
% See also MAKE_FORECAST_GROUP_REAL.

paths = setup_paths();

% load into named variables: parfor has to resolve them statically, which it
% cannot do for variables created by a bare `load`
truth_stats = getfield(load(paths.truth_stats, 'truth_stats'), 'truth_stats');
population  = getfield(load(paths.population,  'population'),  'population');

% --- 1. Load Descriptions ---
runs_description = read_runs_table(paths);

opts_groups = detectImportOptions(paths.groups_description);
opts_groups.DataRange = 'A2';
cols_to_standardize = ["Baseline", "Flights", "Commuting", "Strain", "Seed_loc"];
opts_groups = setvartype(opts_groups, cols_to_standardize, 'string');
groups_description = readtable(paths.groups_description, opts_groups);

summary_filename = paths.synth_group_file;
forecasts_dir    = paths.forecasts;   % sliced into the parfor below

supergroup_names = unique(groups_description.SuperGroup, 'stable');

% --- 2. Define Targets & Output ---
all_targets = ["onset100", "onset150"];
metrics_to_collect = ["wis", "mae"];
coverage_to_collect = ["interval_90", "interval_50"];
all_metrics_list = [metrics_to_collect, coverage_to_collect];


% Main Result Structure
all_supergroup_data = struct();

Thrs=2;

% Check if a pool is already running
poolobj = gcp('nocreate');

if isempty(poolobj)
    % Case 1: No pool running. Start one with Thrs workers.
    parpool(Thrs);
else
    % Case 2: A pool is running. Check if it has the right number of workers.
    if poolobj.NumWorkers ~= Thrs
        delete(poolobj); % Shut down the old n-core pool
        parpool(Thrs);      % Start a new Thrs-core pool
    end
end

tic
%% --- Main Loop: SuperGroups (Sequential) ---
for sg_i = 1:length(supergroup_names)
    sg = supergroup_names{sg_i};

    % Get groups in this supergroup
    sg_idx = strcmp(groups_description.SuperGroup, sg);
    sg_groups = groups_description(sg_idx, :);
    num_groups_in_sg = size(sg_groups, 1);

    fprintf('Processing SuperGroup: %s (%d groups) using PARFOR...\n', sg, num_groups_in_sg);

    % Prepare a container to hold results from the workers
    sg_results_cell = cell(num_groups_in_sg, 1);

    %% --- Parallel Loop: Groups (A1, A2...) ---
    parfor g_i = 1:num_groups_in_sg
        %for g_i = 1:num_groups_in_sg

        % Extract group specific props
        group_id = sg_groups.GroupID{g_i};
        group_props = sg_groups(g_i, :);

        % Initialize bins for THIS group only
        group_abs_bins = struct();

        % 1. Find ALL runs belonging to this group
        run_indices = find_run_indices(runs_description, group_props);
        matched_runs = runs_description(run_indices, :);

        if isempty(matched_runs)
            continue;
        end

        %% --- Loop 2: Runs within Group ---
        num_runs_in_group = height(matched_runs);
        for r_i = 1:num_runs_in_group

            % Get Run Details
            run_id = matched_runs.RunIDtext{r_i};
            truth_id = matched_runs.TruthID{r_i};

            % A. Load Forecast File
            [test_forecast_struct, file_found] = load_forecast_struct(forecasts_dir, run_id);

            if ~file_found
                continue;
            end

            % B. Load Truth Data
            truth_match_idx = strcmp({truth_stats.id}, truth_id);
            if ~any(truth_match_idx)
                continue;
            end
            truth_current = truth_stats(truth_match_idx);

            % C. Bin Metrics
            T_weeks = length(test_forecast_struct);
            num_locs = size(truth_current.peak_week, 1);

            % Determine Location Filter
            loc_indices = 1:num_locs;
            loc_label = group_props.Seed_loc(1);

            if ~ismissing(loc_label) && ~isempty(population)
                loc_indices = get_location_indices(loc_label, population, num_locs);
            end

            for t = 1:T_weeks
                % Extract absolute forecast week
                if ~isfield(test_forecast_struct(t), 'forecast_week_abs')
                    warning('Missing forecast_week_abs for t=%d in run %s', t, run_id);
                    continue;
                end
                forecast_week_abs = test_forecast_struct(t).forecast_week_abs;
                % Loop over selected locations
                for i = 1:length(loc_indices)
                    loc = loc_indices(i);

                    % --- parfor fix: Use Integer Indexing for Targets ---
                    for tn_i = 1:length(all_targets)
                        target_name = all_targets(tn_i); % Access by index

                        %[bin_name, weeks_to_event] = get_bin_name(truth_current, target_name, loc, t);
                        [bin_name, weeks_to_event] = get_bin_name(truth_current, target_name, loc, forecast_week_abs);
                        if isnan(weeks_to_event), continue, end

                        metrics_field = sprintf('%s_metrics', target_name);

                        if ~isfield(test_forecast_struct(t), metrics_field)
                            continue;
                        end

                        % Access metrics
                        test_metrics = test_forecast_struct(t).(metrics_field)(loc);

                        % 1. Standard Metrics
                        for m_idx = 1:length(metrics_to_collect)
                            m_name = metrics_to_collect(m_idx);
                            if isfield(test_metrics, m_name)
                                val = test_metrics.(m_name);
                                if ~isnan(val)
                                    group_abs_bins = bin_value(group_abs_bins, target_name, bin_name, m_name, val);
                                end
                            end
                        end

                        % 2. Coverage Metrics
                        for c_idx = 1:length(coverage_to_collect)
                            m_name = coverage_to_collect(c_idx);
                            if isfield(test_metrics, 'coverage') && isfield(test_metrics.coverage, m_name)
                                val = test_metrics.coverage.(m_name);
                                group_abs_bins = bin_value(group_abs_bins, target_name, bin_name, m_name, val);
                            end
                        end
                    end % target loop
                end % loc
            end % weeks (t)
        end % runs (r_i) loop

        %% --- Aggregate Group Data ---
        if ~isempty(fieldnames(group_abs_bins))
            % Store results in a temporary struct
            res_struct = struct();
            res_struct.id = group_id;
            res_struct.data = aggregate_bins(group_abs_bins, all_targets, all_metrics_list);
            sg_results_cell{g_i} = res_struct;
        end

    end % parfor end

    % --- Unpack results ---
    all_supergroup_data.(sg) = struct();
    for k = 1:num_groups_in_sg
        if ~isempty(sg_results_cell{k})
            grp_id = sg_results_cell{k}.id;
            all_supergroup_data.(sg).(grp_id) = sg_results_cell{k}.data;
        end
    end

    clear sg_results_cell;

end % supergroup (sg_i) loop

% --- Final Save ---
fprintf('Saving all supergroup data to %s\n', summary_filename);
save(summary_filename, '-struct', 'all_supergroup_data', '-v7.3');
toc

end

%% --- HELPER FUNCTIONS ---

function [forecast_struct, file_found] = load_forecast_struct(forecasts_dir, run_id)
forecast_struct = [];
file_found = false;

% Pattern match
forecast_files = dir(fullfile(forecasts_dir, ['*_' char(run_id) '_*_fore_res_group.mat']));

if isempty(forecast_files)
    return;
end

% Pick the first match if multiple exist
try
    loaded_data = load(fullfile(forecast_files(1).folder, forecast_files(1).name), 'forecast_struct');
    forecast_struct = loaded_data.forecast_struct;
    file_found = true;
catch
    return;
end
end

function run_indices = find_run_indices(runs_description, group_props)
% Matches Flights, Commuting, Strain, stochastic

% Flights
if ismissing(group_props.Flights(1))
    flights_idx = true(height(runs_description), 1);
else
    flights_idx = strcmp(runs_description.Flights, group_props.Flights(1));
end

% Commuting
if ismissing(group_props.Commuting(1))
    commuting_idx = true(height(runs_description), 1);
else
    commuting_idx = strcmp(runs_description.Commuting, group_props.Commuting(1));
end

% Strain
if ismissing(group_props.Strain(1))
    strain_idx = true(height(runs_description), 1);
else
    strain_idx = strcmp(runs_description.Strain, group_props.Strain(1));
end

run_indices = flights_idx & commuting_idx & strain_idx;
end


function [bin_name, weeks_to_event] = get_bin_name(truth_current, target_name, loc, forecast_week_abs)
    true_event_week = NaN;
    truth_field_name = '';

    if startsWith(target_name, "onset")
        truth_field_name = target_name;
    elseif startsWith(target_name, "peak")
        truth_field_name = 'peak_week';
    end

    if isfield(truth_current, truth_field_name)
        try
            true_event_week = truth_current.(truth_field_name)(loc);
        catch
            true_event_week = NaN;
        end
    end

    if isnan(true_event_week)
        bin_name = '';
        weeks_to_event = NaN;
        return;
    end 

    % weeks_to_event = t - true_event_week; 
    weeks_to_event = forecast_week_abs - true_event_week; 
    
    if weeks_to_event >= 0
        bin_name = sprintf('week_p%d', weeks_to_event);
    else
        bin_name = sprintf('week_m%d', abs(weeks_to_event));
    end
end




function bins = bin_value(bins, target_name, bin_name, m_name, val)
if ~isfield(bins, target_name) || ...
        ~isfield(bins.(target_name), bin_name) || ...
        ~isfield(bins.(target_name).(bin_name), m_name)

    bins.(target_name).(bin_name).(m_name) = [];
end
bins.(target_name).(bin_name).(m_name)(end+1) = val;
end

function summary = aggregate_bins(bins, all_targets, all_metrics)
summary = struct();
if isempty(fieldnames(bins)), return; end

for target_name_cell = all_targets
    target = target_name_cell{:};
    if ~isfield(bins, target), continue; end

    all_binned_weeks = fieldnames(bins.(target));
    for week_i = 1:length(all_binned_weeks)
        bin_name = all_binned_weeks{week_i};

        for metric_name_cell = all_metrics
            m_name = metric_name_cell{:};
            if ~isfield(bins.(target).(bin_name), m_name), continue; end

            raw_values = bins.(target).(bin_name).(m_name);
            if isempty(raw_values), continue; end

            summary.(target).(bin_name).(strcat('mean_', m_name)) = mean(raw_values, 'omitnan');
            summary.(target).(bin_name).(strcat('median_', m_name)) = median(raw_values, 'omitnan');
            summary.(target).(bin_name).num_samples = length(raw_values);
        end
    end
end
end

function loc_indices = get_location_indices(label, population, num_locs)
loc_indices = 1:num_locs;
if isempty(population) || ismissing(label), return; end

pop_median = median(population, 'all', 'omitnan');
switch label
    case "LargePop", loc_indices = find(population > pop_median);
    case "SmallPop", loc_indices = find(population <= pop_median);
    otherwise, loc_indices = 1:num_locs;
end
if iscolumn(loc_indices), loc_indices = loc_indices'; end
end