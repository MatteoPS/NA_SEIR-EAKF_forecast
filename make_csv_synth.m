% loads aggregated forecast metrics and exports
% relative bar data to a CSV

clear; close all; clc;

%% --- 1. Parameters ---

groups_desc_path   = 'Groups-description-pois.xlsx';
metrics_file_path  = 'Forecasts_groups/0128_all_synth_forecast_metrics-pois.mat';
sg_to_plot         = {'sgP'};
out_path           = 'Output/rel_bars_synth.csv';


targets_to_plot        = {'onset100', 'onset150'};
metrics_to_plot        = {'mean_mae', 'mean_wis'};
time_window_to_average = -8:0;
bar_cap                = 1.5;

%% --- 2. Load Data ---
fprintf('Loading metrics from: %s\n', metrics_file_path);
loaded_data = load(metrics_file_path);

fprintf('Loading group descriptions from: %s\n', groups_desc_path);
try
    groups_description = readtable(groups_desc_path);
catch ME
    error('Failed to read %s. Error: %s', groups_desc_path, ME.message);
end

supergroup_names = fieldnames(loaded_data);
fprintf('Found %d supergroup(s).\n', length(supergroup_names));

%% --- 3. Main Loop ---
csv_rows = {};

for sg_i = 1:length(supergroup_names)
    supergroup_name = supergroup_names{sg_i};

    if ~ismember(supergroup_name, sg_to_plot)
        fprintf('Skipping supergroup: %s\n', supergroup_name);
        continue;
    end

    fprintf('Processing supergroup: %s\n', supergroup_name);
    supergroup_struct = loaded_data.(supergroup_name);
    group_names       = fieldnames(supergroup_struct);

    for r = 1:length(targets_to_plot)
        target_to_plot = targets_to_plot{r};
        for c = 1:length(metrics_to_plot)
            metric_to_plot = metrics_to_plot{c};
            for i = 1:length(group_names)
                group_id   = group_names{i};
                group_data = supergroup_struct.(group_id);

                % Baseline lookup
                current_baseline_nickname = get_baseline_for_group(groups_description, group_id);

                baseline_val = NaN;
                if ~isempty(current_baseline_nickname) && isfield(supergroup_struct, current_baseline_nickname)
                    base_data    = supergroup_struct.(current_baseline_nickname).(target_to_plot);
                    [b_vals, ~]  = extract_series_data(base_data, metric_to_plot, time_window_to_average);
                    baseline_val = mean(b_vals, 'omitnan');
                end

                % Current group value
                curr_rel_val   = NaN;
                avg_num_sample = NaN;
                if isfield(group_data, target_to_plot)
                    [g_vals, g_samples] = extract_series_data(group_data.(target_to_plot), metric_to_plot, time_window_to_average);
                    group_val      = mean(g_vals,    'omitnan');
                    avg_num_sample = mean(g_samples, 'omitnan');
                    if ~isnan(baseline_val) && baseline_val ~= 0
                        curr_rel_val = group_val / baseline_val;
                    end
                end

                % Style fields
                try
                    row_idx    = strcmp(groups_description.GroupID, group_id);
                    grow       = groups_description(row_idx, :);
                    strain     = grow.Strain{:};
                    flights    = grow.Flights{:};
                    commuting  = grow.Commuting{:};
                    stochastic = grow.Stochastic{:};
                    label      = grow.Label{:};
                catch
                    strain=''; flights=''; commuting=''; stochastic=''; label=group_id;
                end

                capped = ~isnan(curr_rel_val) && curr_rel_val > bar_cap;

                csv_rows{end+1} = {group_id, label, target_to_plot, metric_to_plot, ...
                    curr_rel_val, avg_num_sample, ...
                    strain, flights, commuting, stochastic, double(capped)};
            end
        end
    end
end

%% --- 4. Write CSV ---
fid = fopen(out_path, 'w');
fprintf(fid, 'group_id,label,target,metric,rel_val,n_samples,strain,flights,commuting,stochastic,capped\n');
for k = 1:length(csv_rows)
    row = csv_rows{k};
    fprintf(fid, '%s,%s,%s,%s,%.6f,%.1f,%s,%s,%s,%s,%d\n', ...
        row{1}, row{2}, row{3}, row{4}, row{5}, row{6}, ...
        row{7}, row{8}, row{9}, row{10}, row{11});
end
fclose(fid);
fprintf('CSV saved to: %s\n', out_path);


%% =========================================================================
%  LOCAL HELPER FUNCTIONS
%  =========================================================================
function baseline_nickname = get_baseline_for_group(groups_description, group_id)
baseline_nickname = '';
try
    label_idx = strcmp(groups_description.GroupID, group_id);
    if any(label_idx)
        baseline_nickname = groups_description(label_idx, :).Baseline{:};
    end
catch ME
    warning('Could not find baseline for GroupID "%s". Error: %s', group_id, ME.message);
end
end

function [series_values, num_samples] = extract_series_data(target_data, metric_to_plot, x_week_range)
series_values = NaN(1, length(x_week_range));
num_samples   = NaN(1, length(x_week_range));
fnames                = fieldnames(target_data);
is_sim_week_plot      = any(startsWith(fnames, 'sim_week_'));
is_pred_horizon_plot  = any(startsWith(fnames, 'pred_in_w'));
for j = 1:length(x_week_range)
    current_week = x_week_range(j);
    bin_name = '';
    if is_sim_week_plot
        if current_week > 0, bin_name = sprintf('sim_week_%d', current_week); end
    elseif is_pred_horizon_plot
        if current_week >= 0
            bin_name = sprintf('pred_in_w%d', current_week);
        elseif current_week == -1
            bin_name = 'pred_past';
        end
    else
        if current_week >= 0
            bin_name = sprintf('week_p%d', current_week);
        else
            bin_name = sprintf('week_m%d', abs(current_week));
        end
    end
    if ~isempty(bin_name) && isfield(target_data, bin_name) && isfield(target_data.(bin_name), metric_to_plot)
        series_values(j) = target_data.(bin_name).(metric_to_plot);
        if isfield(target_data.(bin_name), 'num_samples')
            num_samples(j) = target_data.(bin_name).num_samples;
        end
    end
end
end