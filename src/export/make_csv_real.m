function make_csv_real()
%MAKE_CSV_REAL  Export grouped real-incidence forecast metrics to a CSV.
%
%   make_csv_real()
%
% Reads results/forecast_groups/all_real_forecast_metrics.mat and writes
% results/csv/rel_bars_real.csv (input for src/plotting/plot_rel_bars_real.R),
% combining fixedbaseline=true and fixedbaseline=false rows.
%
% Fixed settings: group_by_country=false, group_by_wave=false, pois_only=true
%
% Run MAKE_FORECAST_GROUP_REAL first.
%
% See also MAKE_CSV_SYNTH.

paths = setup_paths();

%% --- Parameters ---
metrics_file_path = paths.real_group_file;
out_path          = paths.csv_real;
targets_to_plot   = {'onset50', 'onset100'};
metrics_to_plot   = {'mean_mae', 'mean_wis'};
file_order        = ["nf_p_pois", "f_p_pois", "nf_n_pois", "f_n_pois"];
bar_cap           = 1.5;

%% --- Load & order data ---
fprintf('Loading metrics from: %s\n', metrics_file_path);
loaded_data = load(metrics_file_path);

% Keep only the four expected fields, in order
actual_fields   = fieldnames(loaded_data);
extra_fields    = setdiff(actual_fields, cellstr(file_order));
loaded_data     = rmfield(loaded_data, extra_fields);
present_order   = intersect(file_order, string(fieldnames(loaded_data)), 'stable');
loaded_data     = orderfields(loaded_data, cellstr(present_order));
nicknames       = string(fieldnames(loaded_data));

% Wrap each model in a dummy "all_data" slice (no wave/country grouping)
temp_data = struct();
for nk = 1:length(nicknames)
    temp_data.(nicknames(nk)).all_data = loaded_data.(nicknames(nk));
end
loaded_data = temp_data;

fprintf('Found %d model(s).\n', length(nicknames));

%% --- Define both baseline configurations ---
baseline_configs = { ...
    true,  {-8:-6; -5:-3; -2:0}, {"m8m6"; "m5m3"; "m2p0"}, "m8m6"; ...
    false, {-8:6},                {"all"},                   ""    };
% columns: fixedbaseline | time_windows_to_average | time_windows_names | baseline_name

%% --- Main loop: accumulate rows for both baseline configs ---
csv_rows = {};

for cfg = 1:size(baseline_configs, 1)
    fixedbaseline           = baseline_configs{cfg, 1};
    time_windows_to_average = baseline_configs{cfg, 2};
    time_windows_names      = baseline_configs{cfg, 3};
    baseline_name           = baseline_configs{cfg, 4};

    if fixedbaseline
        bw_idx = find(string(time_windows_names) == baseline_name, 1);
        fixed_baseline_time_window   = time_windows_to_average{bw_idx};
        fixed_baseline_window_label  = baseline_name;
        fprintf('\n--- fixedbaseline=true  (baseline window: %s) ---\n', baseline_name);
    else
        fprintf('\n--- fixedbaseline=false ---\n');
    end

    for r = 1:length(targets_to_plot)
        target_to_plot = targets_to_plot{r};

        for c = 1:length(metrics_to_plot)
            metric_to_plot = metrics_to_plot{c};

            for w_idx = 1:length(time_windows_to_average)
                current_time_window = time_windows_to_average{w_idx};
                current_window_name = time_windows_names{w_idx};

                for nk = 1:length(nicknames)
                    nickname   = nicknames(nk);
                    slice_data = loaded_data.(nickname).all_data;

                    % Baseline nickname: nf_p_pois (no-flight + patch)
                    parts    = split(nickname, "_");
                    parts(1) = "nf";
                    parts(2) = "p";
                    baseline_nickname = join(parts, "_");

                    % Choose time window for baseline denominator
                    if fixedbaseline
                        tw_for_baseline       = fixed_baseline_time_window;
                        baseline_window_label = fixed_baseline_window_label;
                    else
                        tw_for_baseline       = current_time_window;
                        baseline_window_label = current_window_name;
                    end

                    % Compute baseline average
                    baseline_val = NaN;
                    if isfield(loaded_data, baseline_nickname) && ...
                       isfield(loaded_data.(baseline_nickname).all_data, target_to_plot)
                        base_data    = loaded_data.(baseline_nickname).all_data.(target_to_plot);
                        [b_vals, ~]  = extract_series_data(base_data, metric_to_plot, tw_for_baseline);
                        baseline_val = mean(b_vals, 'omitnan');
                    end

                    % Compute model average and relative value
                    curr_rel_val   = NaN;
                    avg_num_sample = NaN;
                    if isfield(slice_data, target_to_plot)
                        [g_vals, g_samples] = extract_series_data( ...
                            slice_data.(target_to_plot), metric_to_plot, current_time_window);
                        group_val      = mean(g_vals,    'omitnan');
                        avg_num_sample = mean(g_samples, 'omitnan');
                        if ~isnan(baseline_val) && baseline_val ~= 0
                            curr_rel_val = group_val / baseline_val;
                        end
                    end

                    % Parse label components
                    [model_label, flights, commuting, stochastic] = parse_model_config_csv(nickname);

                    capped = ~isnan(curr_rel_val) && curr_rel_val > bar_cap;

                    csv_rows{end+1} = { ...
                        char(nickname),            char(model_label), ...
                        target_to_plot,            metric_to_plot, ...
                        char(current_window_name), char(baseline_window_label), ...
                        double(fixedbaseline), ...
                        curr_rel_val,              avg_num_sample, ...
                        char(flights),             char(commuting),  char(stochastic), ...
                        double(capped)};
                end % nickname
            end % window
        end % metric
    end % target
end % baseline config

%% --- Write CSV ---
fid = fopen(out_path, 'w');
fprintf(fid, 'nickname,model_label,target,metric,time_window,baseline_window,fixedbaseline,rel_val,n_samples,flights,commuting,stochastic,capped\n');
for k = 1:length(csv_rows)
    row = csv_rows{k};
    fprintf(fid, '%s,%s,%s,%s,%s,%s,%d,%.6f,%.1f,%s,%s,%s,%d\n', ...
        row{1}, row{2}, row{3}, row{4}, row{5}, row{6}, row{7}, ...
        row{8}, row{9}, row{10}, row{11}, row{12}, row{13});
end
fclose(fid);
fprintf('\nCSV saved to: %s\n', out_path);

end

%% =========================================================================
%  LOCAL HELPER FUNCTIONS
%% =========================================================================

function [series_values, num_samples] = extract_series_data(target_data, metric_to_plot, x_week_range)
series_values = NaN(1, length(x_week_range));
num_samples   = NaN(1, length(x_week_range));
for j = 1:length(x_week_range)
    current_week = x_week_range(j);
    if current_week >= 0
        bin_name = sprintf('week_p%d', current_week);
    else
        bin_name = sprintf('week_m%d', abs(current_week));
    end
    if isfield(target_data, bin_name) && isfield(target_data.(bin_name), metric_to_plot)
        series_values(j) = target_data.(bin_name).(metric_to_plot);
        if isfield(target_data.(bin_name), 'num_samples')
            num_samples(j) = target_data.(bin_name).num_samples;
        end
    end
end
end

function [model_label, flights, commuting, stochastic] = parse_model_config_csv(nickname)
settings  = split(nickname, "_");
flights   = settings(1);   % "nf" or "f"
commuting = settings(2);   % "p"  or "n"
stochastic = "pois";       % always pois in this script

if flights   == "nf", f_lab = "No Flight"; else, f_lab = "Flight"; end
if commuting == "n",  c_lab = "Network";   else, c_lab = "Patch";  end

model_label = strjoin([f_lab, c_lab, "All"], " - ");
end